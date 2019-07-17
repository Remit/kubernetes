/*
Copyright 2017 The Kubernetes Authors.

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

package cpumanager

import (
	"fmt"
	"sort"

	"k8s.io/klog"

	"k8s.io/kubernetes/pkg/kubelet/cm/cpumanager/topology"
	"k8s.io/kubernetes/pkg/kubelet/cm/cpuset"
	cmutil "k8s.io/kubernetes/pkg/kubelet/cm/util"
)

type cpuAccumulator struct {
	topo          *topology.CPUTopology
	details       topology.CPUDetails
	numCPUsNeeded int
	result        cpuset.CPUSet
	topoNUMA			*cmutil.NUMATopology
}

func newCPUAccumulator(topo *topology.CPUTopology, availableCPUs cpuset.CPUSet, numCPUs int, topoNUMA *cmutil.NUMATopology) *cpuAccumulator {
	return &cpuAccumulator{
		topo:          topo,
		details:       topo.CPUDetails.KeepOnly(availableCPUs),
		numCPUsNeeded: numCPUs,
		result:        cpuset.NewCPUSet(),
		topoNUMA:			 topoNUMA,
	}
}

func (a *cpuAccumulator) take(cpus cpuset.CPUSet, numaAware bool) {
	// Augmentation begins:
	associatedMems := []int{0} // Default case for K8s system pods
	if numaAware {
		// 1) find mem ids from same node
		associatedMems = a.topoNUMA.MemsForCPUs(cpus)
	}

	// 2) add mem ids as memelements to cpus
	addedMemCpuset := cpuset.NewCPUSetWithMem(associatedMems)
	cpusetCloned := cpus.Union(addedMemCpuset)
	klog.V(4).Infof("[cpumanager | Augmentation TEST] updateContainerCPUSet: memory string is %s", cpusetCloned.Memstring())

	a.result = a.result.Union(cpusetCloned)
	// Augmentation ends
	//a.result = a.result.Union(cpus)
	a.details = a.details.KeepOnly(a.details.CPUs().Difference(a.result))
	a.numCPUsNeeded -= cpus.Size()
}

// Returns true if the supplied socket is fully available in `topoDetails`.
func (a *cpuAccumulator) isSocketFree(socketID int) bool {
	return a.details.CPUsInSocket(socketID).Size() == a.topo.CPUsPerSocket()
}

// Returns true if the supplied core is fully available in `topoDetails`.
func (a *cpuAccumulator) isCoreFree(coreID int) bool {
	return a.details.CPUsInCore(coreID).Size() == a.topo.CPUsPerCore()
}

// Returns free socket IDs as a slice sorted by:
// - socket ID, ascending.
func (a *cpuAccumulator) freeSockets() []int {
	return a.details.Sockets().Filter(a.isSocketFree).ToSlice()
}

// Returns core IDs as a slice sorted by:
// - the number of whole available cores on the socket, ascending
// - socket ID, ascending
// - core ID, ascending
func (a *cpuAccumulator) freeCores(socketID int) []int {
	socketIDs := a.details.Sockets().ToSliceNoSort()

	// Augmentation starts: search for free cores is conducted only for the given socket
	intInSlice := func(a int, aa []int) bool {
		for _, b := range aa {
			if b == a {
				return true
			}
		}
		return false
	}

	if (socketID > -1) && (intInSlice(socketID, socketIDs)) {
		socketIDs = []int{socketID}
	}
	// Augmentation ends

	sort.Slice(socketIDs,
		func(i, j int) bool {
			iCores := a.details.CoresInSocket(socketIDs[i]).Filter(a.isCoreFree)
			jCores := a.details.CoresInSocket(socketIDs[j]).Filter(a.isCoreFree)
			return iCores.Size() < jCores.Size() || socketIDs[i] < socketIDs[j]
		})

	coreIDs := []int{}
	for _, s := range socketIDs {
		coreIDs = append(coreIDs, a.details.CoresInSocket(s).Filter(a.isCoreFree).ToSlice()...)
	}
	return coreIDs
}

// Returns CPU IDs as a slice sorted by:
// - socket affinity with result
// - number of CPUs available on the same socket
// - number of CPUs available on the same core
// - socket ID.
// - core ID.
func (a *cpuAccumulator) freeCPUs(socketID int) []int {
	result := []int{}
	cores := a.details.Cores().ToSlice()

	// Augmentation starts: search for free CPUs is conducted only for the cores
	// that are on chip in the given socket
	filter := func(aa []int, test func(int) bool) (ret []int) {
		for _, a := range aa {
			if test(a) {
				ret = append(ret, a)
			}
		}

		return
	}

	filterBySocketID := func(core int) bool {
		CPUs := a.topo.CPUDetails.CPUsInCore(core).ToSlice()
		curSocketID := a.topo.CPUDetails[CPUs[0]].SocketID
		return curSocketID == socketID
	}

	if socketID > -1 {
		cores = filter(cores, filterBySocketID)
	}
	// Augmentation ends

	sort.Slice(
		cores,
		func(i, j int) bool {
			iCore := cores[i]
			jCore := cores[j]

			iCPUs := a.topo.CPUDetails.CPUsInCore(iCore).ToSlice()
			jCPUs := a.topo.CPUDetails.CPUsInCore(jCore).ToSlice()

			iSocket := a.topo.CPUDetails[iCPUs[0]].SocketID
			jSocket := a.topo.CPUDetails[jCPUs[0]].SocketID

			// Compute the number of CPUs in the result reside on the same socket
			// as each core.
			iSocketColoScore := a.topo.CPUDetails.CPUsInSocket(iSocket).Intersection(a.result).Size()
			jSocketColoScore := a.topo.CPUDetails.CPUsInSocket(jSocket).Intersection(a.result).Size()

			// Compute the number of available CPUs available on the same socket
			// as each core.
			iSocketFreeScore := a.details.CPUsInSocket(iSocket).Size()
			jSocketFreeScore := a.details.CPUsInSocket(jSocket).Size()

			// Compute the number of available CPUs on each core.
			iCoreFreeScore := a.details.CPUsInCore(iCore).Size()
			jCoreFreeScore := a.details.CPUsInCore(jCore).Size()

			return iSocketColoScore > jSocketColoScore ||
				iSocketFreeScore < jSocketFreeScore ||
				iCoreFreeScore < jCoreFreeScore ||
				iSocket < jSocket ||
				iCore < jCore
		})

	// For each core, append sorted CPU IDs to result.
	for _, core := range cores {
		result = append(result, a.details.CPUsInCore(core).ToSlice()...)
	}
	return result
}

func (a *cpuAccumulator) needs(n int) bool {
	return a.numCPUsNeeded >= n
}

func (a *cpuAccumulator) needsLT(n int) bool {
	return a.numCPUsNeeded < n
}

func (a *cpuAccumulator) isSatisfied() bool {
	return a.numCPUsNeeded < 1
}

func (a *cpuAccumulator) isFailed() bool {
	return a.numCPUsNeeded > a.details.CPUs().Size()
}

func takeByTopology(topo *topology.CPUTopology, availableCPUs cpuset.CPUSet, numCPUs int, separateSockets bool, numaAware bool, topoNUMA *cmutil.NUMATopology) (cpuset.CPUSet, error) {
	// TODO: check if the new arguments can be made by default
	acc := newCPUAccumulator(topo, availableCPUs, numCPUs, topoNUMA)
	if acc.isSatisfied() {
		return acc.result, nil
	}
	if acc.isFailed() {
		return cpuset.NewCPUSet(), fmt.Errorf("not enough cpus available to satisfy request")
	}

	// Algorithm: topology-aware best-fit augmented with distribution of containers
	// over sockets if needed.

	// 0. Ask for free sockets and allocate free cores/CPUs
	// only from given socket if the container can fit
	// into the socket -> otherwise continue as is with static policy.
	if separateSockets && acc.needsLT(acc.topo.CPUsPerSocket()) {
		freeS := acc.freeSockets()
		s := freeS[0] // Get first free socket -> TODO: if there is a necessity to select the socket closest to I/O, then this should be changed
		klog.V(4).Infof("[cpumanager-augmentation] takeByTopology: claiming whole or part of socket for pinned allocation [%d]", s)
		// a) acquire whole socket if needed
		if acc.needs(acc.topo.CPUsPerSocket()) {
			acc.take(acc.details.CPUsInSocket(s), numaAware)
			if acc.isSatisfied() {
				return acc.result, nil
			}
		}

		// b) acquire whole cores if needed
		if acc.needs(acc.topo.CPUsPerCore()) {
			for _, c := range acc.freeCores(s) {
				acc.take(acc.details.CPUsInCore(c), numaAware)
				if acc.isSatisfied() {
					return acc.result, nil
				}
			}
		}

		// c) acquire single threads if needed
		// TODO: acc.freeCPUs() should be augmented too to get cores only from the particular socket
		for _, c := range acc.freeCPUs(s) {
			if acc.needs(1) {
				acc.take(cpuset.NewCPUSet(c), numaAware)
			}
			if acc.isSatisfied() {
				return acc.result, nil
			}
		}
	}

	// 1. Acquire whole sockets, if available and the container requires at
	//    least a socket's-worth of CPUs.
	if acc.needs(acc.topo.CPUsPerSocket()) {
		for _, s := range acc.freeSockets() {
			klog.V(4).Infof("[cpumanager] takeByTopology: claiming socket [%d]", s)
			acc.take(acc.details.CPUsInSocket(s), numaAware)
			if acc.isSatisfied() {
				return acc.result, nil
			}
			if !acc.needs(acc.topo.CPUsPerSocket()) {
				break
			}
		}
	}

	// 2. Acquire whole cores, if available and the container requires at least
	//    a core's-worth of CPUs.
	if acc.needs(acc.topo.CPUsPerCore()) {
		for _, c := range acc.freeCores(-1) {
			klog.V(4).Infof("[cpumanager] takeByTopology: claiming core [%d]", c)
			acc.take(acc.details.CPUsInCore(c), numaAware)
			if acc.isSatisfied() {
				return acc.result, nil
			}
			if !acc.needs(acc.topo.CPUsPerCore()) {
				break
			}
		}
	}

	// 3. Acquire single threads, preferring to fill partially-allocated cores
	//    on the same sockets as the whole cores we have already taken in this
	//    allocation.
	for _, c := range acc.freeCPUs(-1) {
		klog.V(4).Infof("[cpumanager] takeByTopology: claiming CPU [%d]", c)
		if acc.needs(1) {
			acc.take(cpuset.NewCPUSet(c), numaAware)
		}
		if acc.isSatisfied() {
			return acc.result, nil
		}
	}

	return cpuset.NewCPUSet(), fmt.Errorf("failed to allocate cpus")
}
