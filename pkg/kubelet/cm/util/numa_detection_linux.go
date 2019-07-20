/*
Copyright 2016 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package util

import (
  "os"
  "strings"
  "strconv"

  "k8s.io/klog"

  utilfs "k8s.io/kubernetes/pkg/util/filesystem"
  "k8s.io/kubernetes/pkg/kubelet/cm/cpuset"
)

func filter(aa []os.FileInfo, test func(os.FileInfo) bool) (ret []os.FileInfo) {
  for _, a := range aa {
    if test(a) {
      ret = append(ret, a)
    }
  }

  return
}

// NUMANodeInfo contains details about a particular node
type NUMANodeInfo struct {
	CPUs []int
	Mems []int
}

// NUMADetails contains a map from NUMA node ID to
// the CPU ids and memory nodes ids of the same node
type NUMADetails map[int]NUMANodeInfo

// NUMATopology contains details of NUMA architecture
type NUMATopology struct {
	NumNodes		int
	NUMADetails	NUMADetails
}

// GetNUMANodeIDbyCPU returns the ID of the NUMA node for the given cpuset with CPUs
func (t NUMATopology) GetNUMANodeIDbyCPU(cpus cpuset.CPUSet) int {
  for i, nodeInfo := range t.NUMADetails {
    nodeCPUs := nodeInfo.CPUs
    for _, nodeCPUID := range nodeCPUs {
      if cpus.Contains(nodeCPUID) {
        return i, nil
      }
    }
  }

  klog.Errorf("Given cpuset %v is not present in the NUMA topology", cpus)
  return -1
}

// GetCPUSetByNodeID returns the cpuset with CPU ids and mem nodes ids for the given NUMA node
func (t NUMATopology) GetCPUSetByNodeID(nodeID int) cpuset.CPUSet {
  if nodeID < t.NumNodes && nodeID >= 0 {
    CPUsIDs := NUMADetails[nodeID].CPUs
    numaCpuset := cpuset.NewCPUSetFromSlice(CPUsIDs)
    memIDs := []int{nodeID}
    memsCpuset := cpuset.NewCPUSetWithMem(memIDs)
    numaCpusetWithMem := numaCpuset.Union(memsCpuset)

    return numaCpusetWithMem
  } else {
    klog.Errorf("The given NUMA node ID %d is out of bounds", nodeID)
    return cpuset.NewCPUSet()
  }
}

// GetColocatedCPUs returns the slice of CPUs IDs
// which are on the same NUMA node as cpus
// func (t NUMATopology) GetColocatedCPUs(cpus cpuset.CPUSet) []int {
//   cpusIDs := []int{}
//   addCPUs := make([]bool, len(t.NUMADetails))
//
//   for i, nodeInfo := range t.NUMADetails {
//     nodeCPUs := nodeInfo.CPUs
//     for _, nodeCPUID := range nodeCPUs {
//       if cpus.Contains(nodeCPUID) {
//         addCPUs[i] = true
//         break
//       }
//     }
//   }
//
//   for i, addCPUCheck := range addCPUs {
//     if addCPUCheck {
//       cpusIDs = t.NUMADetails[i].CPUs
//     }
//   }
//
//   return cpusIDs
// }

// MemsForCPUs returns the slice of memory nodes IDs
// which are on the same NUMA node as cpus
// TODO: consider returning cpuset.CPUSet -> usage needs to be modified too
func (t NUMATopology) MemsForCPUs(cpus cpuset.CPUSet) []int {
  memnodesIDs := []int{}
  addMems := make([]bool, len(t.NUMADetails))

  for i, nodeInfo := range t.NUMADetails {
    nodeCPUs := nodeInfo.CPUs
    for _, nodeCPUID := range nodeCPUs {
      if cpus.Contains(nodeCPUID) {
        addMems[i] = true
        break
      }
    }
  }

  for i, addMemCheck := range addMems {
    if addMemCheck {
      memnodesIDs = t.NUMADetails[i].Mems
    }
  }

	return memnodesIDs
}

// GetNUMANodeSubnodes gets ids of resource subnodes for the given NUMA node
func GetNUMANodeSubnodes(nodeID int, resourceName string) ([]int, error) {
  fs := utilfs.DefaultFs{}
  nodeDir := "/sys/devices/system/node/node" + strconv.Itoa(nodeID) + "/"
  nodeDirContents, err := fs.ReadDir(nodeDir)

  if err != nil {
    klog.Errorf("could not read the contents of directory %s for the resource %s",
      nodeDir, resourceName)
		return nil, err
	}

  filterByResource := func(fileInfoEntry os.FileInfo) bool {
    rawName := fileInfoEntry.Name()
    return strings.Contains(rawName, resourceName)
  }

  resNodesNames := filter(nodeDirContents, filterByResource)

  subnodesIDs := []int{}
  prefixLen := len(resourceName)
  for _, resNodeNameFI := range resNodesNames {
    resNodeName := resNodeNameFI.Name()
    rawID := resNodeName[prefixLen : ]

    // Taking into account other folders with overlapping names e.g. cpumap and cpulist
    if resID, err := strconv.Atoi(rawID); err == nil {
		    subnodesIDs = append(subnodesIDs, resID)
	  }
  }

  return subnodesIDs, nil
}

// GetNUMANodeCPUs gets the CPUs on the given NUMA node
func GetNUMANodeCPUs(nodeID int) ([]int, error) {
  nodeCPUs, err := GetNUMANodeSubnodes(nodeID, "cpu")

  if err != nil {
		return nil, err
	}

  return nodeCPUs, nil
}

// GetNUMATopology gets the NUMA topology of the host
// accessing /sys/devices/system/node/nodeX dirs
func GetNUMATopology() (*NUMATopology, error) {
  fs := utilfs.DefaultFs{}
  nodeStrPrefix := "node"
  dirForNodes := "/sys/devices/system/node/"
  nodeDirContents, err := fs.ReadDir(dirForNodes)

  if err != nil {
    klog.Errorf("could not read the contents of directory %s",
      dirForNodes)
		return nil, err
	}

  filterByName := func(fileInfoEntry os.FileInfo) bool {
    rawName := fileInfoEntry.Name()
    return strings.Contains(rawName, nodeStrPrefix)
  }

  nodesNames := filter(nodeDirContents, filterByName)
  numaDetails := make(NUMADetails)
  prefixLen := len(nodeStrPrefix)
  for _, nodeNameFI := range nodesNames {
    nodeName := nodeNameFI.Name()
    rawID := nodeName[prefixLen : ]

    if nodeID, err := strconv.Atoi(rawID); err == nil {

        nodeCPUs, err := GetNUMANodeCPUs(nodeID)

        if err != nil {
          return nil, err
        }

        // cpuset.mems has the granularity of NUMA nodes and not memory blocks
        nodeMems := []int{nodeID}

        numaDetails[nodeID] = NUMANodeInfo{
          CPUs:   nodeCPUs,
          Mems:   nodeMems,
        }
    }
  }

  numNUMANodes := len(nodesNames)

  return &NUMATopology{
		NumNodes:    numNUMANodes,
		NUMADetails: numaDetails,
	}, nil
}
