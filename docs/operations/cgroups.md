# cgroups

To avoid resource contention between containers and host daemons in Kubernetes,
the kubelet components can use cgroups to limit resource usage.

## Node Allocatable

Node Allocatable is calculated by subtracting from the node capacity:

- kube-reserved reservations
- system-reserved reservations
- hard eviction thresholds

You can set those reservations:

```yaml
kube_memory_reserved: 256Mi
kube_cpu_reserved: 100m
kube_ephemeral_storage_reserved: 2Gi
kube_pid_reserved: "1000"

# System daemons (sshd, network manager, ...)
system_memory_reserved: 512Mi
system_cpu_reserved: 500m
system_ephemeral_storage_reserved: 2Gi
system_pid_reserved: "1000"
```

By default, the kubelet will enforce Node Allocatable for pods, which means
pods will be evicted when resource usage excess Allocatable.

You can optionnaly enforce the reservations for kube-reserved and
system-reserved, but proceed with caution (see [the kubernetes
guidelines](https://kubernetes.io/docs/tasks/administer-cluster/reserve-compute-resources/#general-guidelines)).

```yaml
enforce_allocatable_pods: true # default
enforce_allocatable_kube_reserved: true
enforce_allocatable_system_reseverd: true
```

You can learn more in the [official kubernetes documentation](https://kubernetes.io/docs/tasks/administer-cluster/reserve-compute-resources/).
