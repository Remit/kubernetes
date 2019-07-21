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

package cm

import (
	"fmt"
	"strings"
	"sync"
	"time"
	"os"
	"strconv"
	"sort"

	"k8s.io/klog"

	"k8s.io/apimachinery/pkg/util/wait"

	units "github.com/docker/go-units"
	cgroupfs "github.com/opencontainers/runc/libcontainer/cgroups/fs"
	"k8s.io/api/core/v1"
	utilfeature "k8s.io/apiserver/pkg/util/feature"
	"k8s.io/kubernetes/pkg/api/v1/resource"
	v1qos "k8s.io/kubernetes/pkg/apis/core/v1/helper/qos"
	kubefeatures "k8s.io/kubernetes/pkg/features"
	cmutil "k8s.io/kubernetes/pkg/kubelet/cm/util"
	utilfs "k8s.io/kubernetes/pkg/util/filesystem"
	"k8s.io/kubernetes/pkg/kubelet/cm/cpuset"
)

const (
	// how often the qos cgroup manager will perform periodic update
	// of the qos level cgroup resource constraints
	periodicQOSCgroupUpdateInterval = 1 * time.Minute
)

type QOSContainerManager interface {
	Start(func() v1.ResourceList, ActivePodsFunc) error
	GetQOSContainersInfo() QOSContainersInfo
	UpdateCgroups() error
}

type qosContainerManagerImpl struct {
	sync.Mutex
	nodeInfo           *v1.Node
	qosContainersInfo  QOSContainersInfo
	subsystems         *CgroupSubsystems
	cgroupManager      CgroupManager
	activePods         ActivePodsFunc
	getNodeAllocatable func() v1.ResourceList
	cgroupRoot         CgroupName
	qosReserved        map[v1.ResourceName]int64
	topoNUMA					 *cmutil.NUMATopology
}

func NewQOSContainerManager(subsystems *CgroupSubsystems, cgroupRoot CgroupName, nodeConfig NodeConfig, cgroupManager CgroupManager, topoNUMA *cmutil.NUMATopology) (QOSContainerManager, error) {
	if !nodeConfig.CgroupsPerQOS {
		return &qosContainerManagerNoop{
			cgroupRoot: cgroupRoot,
		}, nil
	}

	return &qosContainerManagerImpl{
		subsystems:    subsystems,
		cgroupManager: cgroupManager,
		cgroupRoot:    cgroupRoot,
		qosReserved:   nodeConfig.QOSReserved,
		topoNUMA:			 topoNUMA,
	}, nil
}

func (m *qosContainerManagerImpl) GetQOSContainersInfo() QOSContainersInfo {
	return m.qosContainersInfo
}

func (m *qosContainerManagerImpl) Start(getNodeAllocatable func() v1.ResourceList, activePods ActivePodsFunc) error {
	cm := m.cgroupManager
	rootContainer := m.cgroupRoot
	if !cm.Exists(rootContainer) {
		return fmt.Errorf("root container %v doesn't exist", rootContainer)
	}

	// Top level for Qos containers are created only for Burstable
	// and Best Effort classes
	qosClasses := map[v1.PodQOSClass]CgroupName{
		v1.PodQOSBurstable:  NewCgroupName(rootContainer, strings.ToLower(string(v1.PodQOSBurstable))),
		v1.PodQOSBestEffort: NewCgroupName(rootContainer, strings.ToLower(string(v1.PodQOSBestEffort))),
	}

	// Create containers for both qos classes
	for qosClass, containerName := range qosClasses {
		resourceParameters := &ResourceConfig{}
		// the BestEffort QoS class has a statically configured minShares value
		if qosClass == v1.PodQOSBestEffort {
			minShares := uint64(MinShares)
			resourceParameters.CpuShares = &minShares
		}

		// containerConfig object stores the cgroup specifications
		containerConfig := &CgroupConfig{
			Name:               containerName,
			ResourceParameters: resourceParameters,
		}

		// for each enumerated huge page size, the qos tiers are unbounded
		m.setHugePagesUnbounded(containerConfig)

		// check if it exists
		if !cm.Exists(containerName) {
			if err := cm.Create(containerConfig); err != nil {
				return fmt.Errorf("failed to create top level %v QOS cgroup : %v", qosClass, err)
			}
		} else {
			// to ensure we actually have the right state, we update the config on startup
			if err := cm.Update(containerConfig); err != nil {
				return fmt.Errorf("failed to update top level %v QOS cgroup : %v", qosClass, err)
			}
		}
	}
	// Store the top level qos container names
	m.qosContainersInfo = QOSContainersInfo{
		Guaranteed: rootContainer,
		Burstable:  qosClasses[v1.PodQOSBurstable],
		BestEffort: qosClasses[v1.PodQOSBestEffort],
	}
	m.getNodeAllocatable = getNodeAllocatable
	m.activePods = activePods

	// update qos cgroup tiers on startup and in periodic intervals
	// to ensure desired state is in sync with actual state.
	go wait.Until(func() {
		err := m.UpdateCgroups()
		if err != nil {
			klog.Warningf("[ContainerManager] Failed to reserve QoS requests: %v", err)
		}
	}, periodicQOSCgroupUpdateInterval, wait.NeverStop)

	return nil
}

// setHugePagesUnbounded ensures hugetlb is effectively unbounded
func (m *qosContainerManagerImpl) setHugePagesUnbounded(cgroupConfig *CgroupConfig) error {
	hugePageLimit := map[int64]int64{}
	for _, pageSize := range cgroupfs.HugePageSizes {
		pageSizeBytes, err := units.RAMInBytes(pageSize)
		if err != nil {
			return err
		}
		hugePageLimit[pageSizeBytes] = int64(1 << 62)
	}
	cgroupConfig.ResourceParameters.HugePageLimit = hugePageLimit
	return nil
}

func (m *qosContainerManagerImpl) setHugePagesConfig(configs map[v1.PodQOSClass]*CgroupConfig) error {
	for _, v := range configs {
		if err := m.setHugePagesUnbounded(v); err != nil {
			return err
		}
	}
	return nil
}

func (m *qosContainerManagerImpl) setCPUCgroupConfig(configs map[v1.PodQOSClass]*CgroupConfig) error {
	pods := m.activePods()
	burstablePodCPURequest := int64(0)
	for i := range pods {
		pod := pods[i]
		qosClass := v1qos.GetPodQOS(pod)
		if qosClass != v1.PodQOSBurstable {
			// we only care about the burstable qos tier
			continue
		}
		req, _ := resource.PodRequestsAndLimits(pod)
		if request, found := req[v1.ResourceCPU]; found {
			burstablePodCPURequest += request.MilliValue()
		}
	}

	// make sure best effort is always 2 shares
	bestEffortCPUShares := uint64(MinShares)
	configs[v1.PodQOSBestEffort].ResourceParameters.CpuShares = &bestEffortCPUShares

	// set burstable shares based on current observe state
	burstableCPUShares := MilliCPUToShares(burstablePodCPURequest)
	configs[v1.PodQOSBurstable].ResourceParameters.CpuShares = &burstableCPUShares
	return nil
}

// Augmentation starts:
func filterFileInfo(aa []os.FileInfo, test func(os.FileInfo) bool) (ret []os.FileInfo) {
  for _, a := range aa {
    if test(a) {
      ret = append(ret, a)
    }
  }

  return
}

func filterString(aa []string, test func(string) bool) (ret []string) {
  for _, a := range aa {
    if test(a) {
      ret = append(ret, a)
    }
  }

  return
}

func (m *qosContainerManagerImpl) setCPUSetsCgroupConfig(configs map[string]*CgroupConfig) error {
	// TODO: ask for mem??? like in  setMemoryReserve ?
	// TODO: add default case: no NUMA -> nils
	pods := m.activePods()
	fs := utilfs.DefaultFs{}

	// For each pod...
	for i := range pods {
		// Getting the settings for the given pod...
		pod := pods[i]
		podNamespace := pod.Namespace

		// Checking if we can apply the algorithm to the current pod
		numaAware := false
		if val, ok := pod.Labels["numapolicy"]; ok {
			if val == "numaaware" {
				numaAware = true
			}
		}

		// Following, we exclude service pods of Kubernetes from our adjustments
		// by considering the namespace
		if numaAware  && (podNamespace != "kube-system") {
			rootContainer := m.cgroupRoot

			// Checking if we need to prioritize placing of threads on NUMA nodes where their stack is
			stackBound := false
			if val, ok := pod.Labels["stackbound"]; ok {
				if val == "true" {
					stackBound = true
				}
			}

			// Preparations depending on QoS class
			cgroupKubepodsDir := "/sys/fs/cgroup/cpu/kubepods/"
			podUID := string(pod.UID)
			qosClass := v1qos.GetPodQOS(pod)
			if qosClass == v1.PodQOSBurstable {
				cgroupKubepodsDir = cgroupKubepodsDir + "burstable/"
				klog.V(2).Infof("[Container Manager | Augmentation II] setCPUSetsCgroupConfig: pod %s is in class v1.PodQOSBurstable, continuing to work in %s", podUID, cgroupKubepodsDir)
			} else if qosClass == v1.PodQOSBestEffort {
				cgroupKubepodsDir = cgroupKubepodsDir + "besteffort/"
				klog.V(2).Infof("[Container Manager | Augmentation II] setCPUSetsCgroupConfig: pod %s is in class v1.PodQOSBestEffort, continuing to work in %s", podUID, cgroupKubepodsDir)
			} else {
				klog.V(2).Infof("[Container Manager | Augmentation II] setCPUSetsCgroupConfig: pod %s in some other QoS class, returning...", podUID)
				return nil
			}

			// Getting pod folder of format kubepods/[burstable|besteffort]/pod*
			cgroupPodDirContents, err := fs.ReadDir(cgroupKubepodsDir)

			if err != nil {
				return err
			}

			filterByPodUID := func(fileInfoEntry os.FileInfo) bool {
				rawName := fileInfoEntry.Name()
				return strings.Contains(rawName, podUID)
			}

			cgroupPodSubdirs := filterFileInfo(cgroupPodDirContents, filterByPodUID)

			// Cheking if the pod was already created
			if len(cgroupPodSubdirs) > 0 {
				// pods are unique...
				podFSName := cgroupPodSubdirs[0].Name()
				cgroupContainersDir := cgroupKubepodsDir + podFSName + "/"

				klog.V(2).Infof("[Container Manager | Augmentation II] setCPUSetsCgroupConfig: pod %s has its settings in %s folder of Cgroups", podUID, cgroupContainersDir)

				// For each pod's container...
				for _, containerStatus := range pod.Status.ContainerStatuses {
					// 1. Extract IDs of containers of each pod
					preferredNUMAnodesByContainer := []int{}
					containerIDRaw := containerStatus.ContainerID
					prefixLen := len("docker://")
					containerID := containerIDRaw[ prefixLen : ]

					// 2. Getting task IDs for the container based on container id
				  cgroupContainersDirContents, err := fs.ReadDir(cgroupContainersDir)

					if err != nil {
						return err
					}

					filterByContainerID := func(fileInfoEntry os.FileInfo) bool {
				    rawName := fileInfoEntry.Name()
				    return strings.Contains(rawName, containerID)
				  }

				  cgroupContainersSubdirs := filterFileInfo(cgroupContainersDirContents, filterByContainerID)

					for _, cgroupContainersSubdir := range cgroupContainersSubdirs {
						rawName := cgroupContainersSubdir.Name()
						tasksFileName := cgroupContainersDir + rawName + "/tasks"

						tasksBytesRaw, err := fs.ReadFile(tasksFileName)
						if err != nil {
							return err
						}

						tasksStringRaw := string(tasksBytesRaw)
						taskIDs := strings.Split(tasksStringRaw, "\n")

						// For each container's task...
						for _, taskID := range taskIDs {
							// 3. Check if the task is already bound to some NUMA node
							statusFileName := "/proc/" + taskID + "/status"
							statusBytesRaw, err := fs.ReadFile(statusFileName)
							if err != nil {
								return err
							}

							statusStringRaw := string(statusBytesRaw)
							statusStrings := strings.Split(statusStringRaw, "\n")
							statusString := statusStrings[4]

							if !strings.Contains(statusString, "Ngid") {
								for _, statusString = range statusStrings {
		    					if strings.Contains(statusString, "Ngid") {
		        				break
		    					}
								}
							}

							numaStatStr := statusString[ (len(statusString) - 1) :]
							numaStat, err := strconv.Atoi(numaStatStr)
							if err != nil {
								numaStat = 0
							}

							// If the task is not yet bound to the NUMA node...
							if numaStat == 0 {
								klog.V(2).Infof("[Container Manager | Augmentation II] setCPUSetsCgroupConfig: task %s of container %s of pod %s is not yet bound to any NUMA node. Binding...", taskID, containerID, podUID)

								// 4. Find appropriate cpuset to run the task based on locality and (if enabled) stack placement
								if stackBound {
									// 5.a. Look up NUMA memory node where the process cache is, and push process to run closer to its cache
									// -> cache/memory locality [has to be set explicitly through pod label]
									// Reference: https://linux.die.net/man/5/numa_maps
									numaMapsFileName := "/proc/" + taskID + "/numa_maps"
									numaMapsBytesRaw, err := fs.ReadFile(numaMapsFileName)
									if err != nil {
										return err
									}

									numaMapsStringRaw := string(numaMapsBytesRaw)
									numaMaps := strings.Split(numaMapsStringRaw, "\n")

									filterByStackAffiliation := func(numaMap string) bool {
								    return strings.Contains(numaMap, "stack")
								  }

								  numaMapsAffiliatedWithStack := filterString(numaMaps, filterByStackAffiliation)

									// Identifying how many mem pages were allocated for stack of the given task at each NUMA node
									stackPagesOnNUMANodes := make(map[int]int)
									for _, numaMapStackString := range numaMapsAffiliatedWithStack {
										numaMapStackComponents := strings.Split(numaMapStackString, " ")

										for i := 0; i < m.topoNUMA.NumNodes; i++ {
											filterKey := "N" + strconv.Itoa(i) + "="

											filterByNUMANode := func(component string) bool {
										    return strings.Contains(component, filterKey)
										  }

											numaMapStackComponentsForNode := filterString(numaMapStackComponents, filterByNUMANode)
											numStackPagesOnNUMANode := 0
											if len(numaMapStackComponentsForNode) > 0 {
												numaMapStackComponentForNode := numaMapStackComponentsForNode[0]
												numStackPagesOnNUMANode, err = strconv.Atoi(strings.Split(numaMapStackComponentForNode, "=")[1])

												if err != nil {
													return err
												}
											}

											klog.V(2).Infof("[Container Manager | Augmentation II] setCPUSetsCgroupConfig: for task %s of container %s of pod %s %d stack pages were allocated on NUMA node #%d", taskID, containerID, podUID, numStackPagesOnNUMANode, i)
											stackPagesOnNUMANodes[i] = stackPagesOnNUMANodes[i] + numStackPagesOnNUMANode
										}
									}

									var pages []int
									for _, val := range stackPagesOnNUMANodes {
					    			pages = append(pages, val)
									}

									sort.Sort(sort.Reverse(sort.IntSlice(pages)))
									pagesMax := pages[0]
									preferredNUMAnodeByPagesOfStack := 0
									for key, val := range stackPagesOnNUMANodes {
										if(val == pagesMax) {
											preferredNUMAnodeByPagesOfStack = key
											break
										}
									}

									klog.V(2).Infof("[Container Manager | Augmentation II] setCPUSetsCgroupConfig: for task %s of container %s of pod %s NUMA node #%d was identified as preferred node by stack location", taskID, containerID, podUID, preferredNUMAnodeByPagesOfStack)
									preferredNUMAnodesByContainer = append(preferredNUMAnodesByContainer, preferredNUMAnodeByPagesOfStack)
									// TODO: consider checking possibility of migration in cpuset???
								} else {
									// 5.b. Get ID of the CPU where the task was last executed and fix memory to be in the same NUMA node
									// (in case of tasks scattered across NUMA nodes we determine the NUMA node where most tasks are running)
									// -> process locality [default]
									statFileName := "/proc/" + taskID + "/stat"
									statBytesRaw, err := fs.ReadFile(statFileName)
									if err != nil {
										return err
									}

									statStringRaw := string(statBytesRaw)
									statsForProc := strings.Split(statStringRaw, " ")
									cpuIDLastExecutedOn, err := strconv.Atoi(statsForProc[38])
									if err != nil {
										return err
									}

									klog.V(2).Infof("[Container Manager | Augmentation II] setCPUSetsCgroupConfig: for task %s of container %s of pod %s got CPU where it last run: %d", taskID, containerID, podUID, cpuIDLastExecutedOn)

									singleCPUcpuset := cpuset.NewCPUSet(cpuIDLastExecutedOn)
									preferredNUMAnodesByContainer = append(preferredNUMAnodesByContainer, m.topoNUMA.GetNUMANodeIDbyCPU(singleCPUcpuset))
								}
							}
						}
					}

					// 6. Determine the most often NUMA node desired by the container among preferredNUMAnodesByContainer
					// and assign the corresponding cpuset.
					// TODO: take into account migration to other NUMA nodes (matrix)! Original NUMA node?
					occurencies := make(map[int]int)
					for _ , preferredNUMAnode :=  range preferredNUMAnodesByContainer {
							occurencies[preferredNUMAnode] = occurencies[preferredNUMAnode] + 1
					}

					var occs []int
					for _, val := range occurencies {
	    			occs = append(occs, val)
					}

					sort.Sort(sort.Reverse(sort.IntSlice(occs)))
					occsMax := occs[0]
					preferredNUMAnode := 0
					for key, val := range occurencies {
						if(val == occsMax) {
							preferredNUMAnode = key
							break
						}
					}

					preferredCpuset := m.topoNUMA.GetCPUSetByNodeID(preferredNUMAnode)

					// 7. Update cpusets for the QoS class of the pod
					cpusetCPUsStr := preferredCpuset.String()
					cpusetMemsStr := preferredCpuset.Memstring()

					klog.V(2).Infof("[Container Manager | Augmentation II] setCPUSetsCgroupConfig: updating configs for cpusets for container %s of pod %s", containerID, podUID)

					// Note that the root cgroup is 'kubepods', hence all the modifications have to come after it ->
					// libcontainer deals with cgroup subsystems through resources, so we don't have to mention them
					// in the name of the cgroup.
					cgroupNameForContainer := NewCgroupName(rootContainer, strings.ToLower(string(qosClass)), podUID, containerID)
					curContainerConfig := CgroupConfig{
							Name:               cgroupNameForContainer,
							ResourceParameters: &ResourceConfig{
								CpusetCpus: &cpusetCPUsStr,
								CpusetMems: &cpusetMemsStr,
							},
					}
					configs[containerID] = &curContainerConfig
				}
			}
		}
	}

	return nil
}
// Augmentation ends

// setMemoryReserve sums the memory limits of all pods in a QOS class,
// calculates QOS class memory limits, and set those limits in the
// CgroupConfig for each QOS class.
func (m *qosContainerManagerImpl) setMemoryReserve(configs map[v1.PodQOSClass]*CgroupConfig, percentReserve int64) {
	qosMemoryRequests := map[v1.PodQOSClass]int64{
		v1.PodQOSGuaranteed: 0,
		v1.PodQOSBurstable:  0,
	}

	// Sum the pod limits for pods in each QOS class
	pods := m.activePods()
	for _, pod := range pods {
		podMemoryRequest := int64(0)
		qosClass := v1qos.GetPodQOS(pod)
		if qosClass == v1.PodQOSBestEffort {
			// limits are not set for Best Effort pods
			continue
		}
		req, _ := resource.PodRequestsAndLimits(pod)
		if request, found := req[v1.ResourceMemory]; found {
			podMemoryRequest += request.Value()
		}
		qosMemoryRequests[qosClass] += podMemoryRequest
	}

	resources := m.getNodeAllocatable()
	allocatableResource, ok := resources[v1.ResourceMemory]
	if !ok {
		klog.V(2).Infof("[Container Manager] Allocatable memory value could not be determined.  Not setting QOS memory limts.")
		return
	}
	allocatable := allocatableResource.Value()
	if allocatable == 0 {
		klog.V(2).Infof("[Container Manager] Memory allocatable reported as 0, might be in standalone mode.  Not setting QOS memory limts.")
		return
	}

	for qos, limits := range qosMemoryRequests {
		klog.V(2).Infof("[Container Manager] %s pod requests total %d bytes (reserve %d%%)", qos, limits, percentReserve)
	}

	// Calculate QOS memory limits
	burstableLimit := allocatable - (qosMemoryRequests[v1.PodQOSGuaranteed] * percentReserve / 100)
	bestEffortLimit := burstableLimit - (qosMemoryRequests[v1.PodQOSBurstable] * percentReserve / 100)
	configs[v1.PodQOSBurstable].ResourceParameters.Memory = &burstableLimit
	configs[v1.PodQOSBestEffort].ResourceParameters.Memory = &bestEffortLimit
}

// retrySetMemoryReserve checks for any QoS cgroups over the limit
// that was attempted to be set in the first Update() and adjusts
// their memory limit to the usage to prevent further growth.
func (m *qosContainerManagerImpl) retrySetMemoryReserve(configs map[v1.PodQOSClass]*CgroupConfig, percentReserve int64) {
	// Unreclaimable memory usage may already exceeded the desired limit
	// Attempt to set the limit near the current usage to put pressure
	// on the cgroup and prevent further growth.
	for qos, config := range configs {
		stats, err := m.cgroupManager.GetResourceStats(config.Name)
		if err != nil {
			klog.V(2).Infof("[Container Manager] %v", err)
			return
		}
		usage := stats.MemoryStats.Usage

		// Because there is no good way to determine of the original Update()
		// on the memory resource was successful, we determine failure of the
		// first attempt by checking if the usage is above the limit we attempt
		// to set.  If it is, we assume the first attempt to set the limit failed
		// and try again setting the limit to the usage.  Otherwise we leave
		// the CgroupConfig as is.
		if configs[qos].ResourceParameters.Memory != nil && usage > *configs[qos].ResourceParameters.Memory {
			configs[qos].ResourceParameters.Memory = &usage
		}
	}
}

func (m *qosContainerManagerImpl) UpdateCgroups() error {
	m.Lock()
	defer m.Unlock()

	qosConfigs := map[v1.PodQOSClass]*CgroupConfig{
		v1.PodQOSBurstable: {
			Name:               m.qosContainersInfo.Burstable,
			ResourceParameters: &ResourceConfig{},
		},
		v1.PodQOSBestEffort: {
			Name:               m.qosContainersInfo.BestEffort,
			ResourceParameters: &ResourceConfig{},
		},
	}

	// Augmentation begins:
	// Special structure for per container configuration
	containerQoSConfigs := map[string]*CgroupConfig{}
	// Augmentation ends

	// update the qos level cgroup settings for cpu shares
	if err := m.setCPUCgroupConfig(qosConfigs); err != nil {
		return err
	}

	// update the qos level cgroup settings for huge pages (ensure they remain unbounded)
	if err := m.setHugePagesConfig(qosConfigs); err != nil {
		return err
	}

	// Augmentation start:
	// update the co-location of task's memory and CPUs for NUMA architecture
	if err := m.setCPUSetsCgroupConfig(containerQoSConfigs); err != nil {
		return err
	}
	// Augmentation ends

	if utilfeature.DefaultFeatureGate.Enabled(kubefeatures.QOSReserved) {
		for resource, percentReserve := range m.qosReserved {
			switch resource {
			case v1.ResourceMemory:
				m.setMemoryReserve(qosConfigs, percentReserve)
			}
		}

		updateSuccess := true
		for _, config := range qosConfigs {
			err := m.cgroupManager.Update(config)
			if err != nil {
				updateSuccess = false
			}
		}
		if updateSuccess {
			klog.V(4).Infof("[ContainerManager]: Updated QoS cgroup configuration")
			return nil
		}

		// If the resource can adjust the ResourceConfig to increase likelihood of
		// success, call the adjustment function here.  Otherwise, the Update() will
		// be called again with the same values.
		for resource, percentReserve := range m.qosReserved {
			switch resource {
			case v1.ResourceMemory:
				m.retrySetMemoryReserve(qosConfigs, percentReserve)
			}
		}
	}

	for _, config := range qosConfigs {
		err := m.cgroupManager.Update(config)
		if err != nil {
			klog.Errorf("[ContainerManager]: Failed to update QoS cgroup configuration")
			return err
		}
	}

	klog.V(4).Infof("[ContainerManager]: Updated QoS cgroup configuration")

	// Augmentation starts:
	for _, config := range containerQoSConfigs {
		err := m.cgroupManager.Update(config)
		if err != nil {
			klog.Errorf("[ContainerManager]: Failed to update container Burtstable/BestEffort cgroup configuration")
			return err
		}
	}

	klog.V(4).Infof("[ContainerManager]: Updated containers Burtstable/BestEffort cgroup configuration")
	// Augmentation ends

	return nil
}

type qosContainerManagerNoop struct {
	cgroupRoot CgroupName
}

var _ QOSContainerManager = &qosContainerManagerNoop{}

func (m *qosContainerManagerNoop) GetQOSContainersInfo() QOSContainersInfo {
	return QOSContainersInfo{}
}

func (m *qosContainerManagerNoop) Start(_ func() v1.ResourceList, _ ActivePodsFunc) error {
	return nil
}

func (m *qosContainerManagerNoop) UpdateCgroups() error {
	return nil
}
