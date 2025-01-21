# Migrating from Docker to Containerd

❗MAKE SURE YOU READ BEFORE PROCEEDING❗

**Migrating container engines is not officially supported by Kubespray**. The following procedure covers one particular scenario and involves manual steps, along with multiple runs of `cluster.yml`. It provides no guarantees that it will actually work or that any further action is needed.  Please, consider these instructions as experimental guidelines. While they can be used to migrate your cluster, they will likely evolve over time. At the moment, they are intended as an additional resource to provide insight into how these steps can be officially integrated into the Kubespray playbooks.

As of Kubespray 2.18.0, containerd is already the default container engine. If you have the chance, it is still advisable and safer to reset and redeploy the entire cluster with a new container engine.

Input and feedback are always appreciated.

## Tested environment

Nodes: Ubuntu 18.04 LTS\
Cloud Provider: None (baremetal or VMs)\
Kubernetes version: 1.21.5\
Kubespray version: 2.18.0

## Important considerations

If you require minimum downtime, nodes need to be cordoned and drained before being processed, one by one. If you wish to run `cluster.yml` only once and get it all done in one swoop, downtime will be significantly higher. Docker will need to be manually removed from all nodes before the playbook runs (see [#8431](https://github.com/kubernetes-sigs/kubespray/issues/8431)). For minimum downtime, the following steps will be executed multiple times, once for each node.

Processing nodes one by one also means you will not be able to update any other cluster configuration using Kubespray before this procedure is finished and the cluster is fully migrated.

Everything done here requires full root access to every node.

## Migration steps

Before you begin, adjust your inventory:

```yaml
# Filename: k8s_cluster/k8s-cluster.yml
resolvconf_mode: host_resolvconf
container_manager: containerd

# Filename: etcd.yml
etcd_deployment_type: host
```

### 1) Pick one or more nodes for processing

It is still unclear how the order might affect this procedure. So, to be sure, it might be best to start with the control plane and etcd nodes all together, followed by each worker node individually.

### 2) Cordon and drain the node

... because, downtime.

### 3) Stop docker and kubelet daemons

```commandline
service kubelet stop
service docker stop
```

### 4) Uninstall docker + dependencies

```commandline
apt-get remove -y --allow-change-held-packages containerd.io docker-ce docker-ce-cli docker-ce-rootless-extras
```

In some cases, there might a `pigz` missing dependency. Some image layers need this to be extracted.

```shell
apt-get install pigz
```

### 5) Run `cluster.yml` playbook with `--limit`

```commandline
ansible-playbook -i <inventory_path>/hosts.ini cluster.yml --limit=NODENAME
```

This effectively reinstalls containerd and seems to place all config files in the right place. When this completes, kubelet will immediately pick up the new container engine and start spinning up DaemonSets and kube-system Pods.

Optionally, if you feel confident, you can remove `/var/lib/docker` anytime after this step.

```commandline
rm -fr /var/lib/docker
```

You can watch new containers using `crictl`.

```commandline
crictl ps -a
```

### 6) Replace the cri-socket node annotation

Node annotations need to be adjusted. Kubespray will not do this, but a simple kubectl is enough.

```commandline
kubectl annotate node NODENAME --overwrite kubeadm.alpha.kubernetes.io/cri-socket=/var/run/containerd/containerd.sock
```

The annotation is required by kubeadm to follow through future cluster upgrades.

### 7) Reboot the node

Reboot, just to make sure everything restarts fresh before the node is uncordoned.

## After thoughts

If your cluster runs a log aggregator, like fluentd+Graylog, you will likely need to adjust collection filters and parsers. While docker generates Json logs, containerd has its own space delimited format. Example:

```text
2020-01-10T18:10:40.01576219Z stdout F application log message...
```
