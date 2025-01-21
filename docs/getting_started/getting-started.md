# Getting started

## Install ansible

Install Ansible according to [Ansible installation guide](/docs/ansible/ansible.md#installing-ansible).

## Building your own inventory

Ansible inventory can be stored in 3 formats: YAML, JSON, or INI-like. See the [Ansible documentation on building your
inventory](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html), and [details on the inventory
structure expected by Kubespray](/docs/ansible/inventory.md).

```ShellSession
<your-favorite-editor> inventory/mycluster/inventory.ini

# Review and change parameters under ``inventory/mycluster/group_vars``
<your-favorite-editor> inventory/mycluster/group_vars/all.yml # for every node, including etcd
<your-favorite-editor> inventory/mycluster/group_vars/k8s_cluster.yml # for every node in the cluster (not etcd when it's separate)
<your-favorite-editor> inventory/mycluster/group_vars/kube_control_plane.yml # for the control plane
<your-favorite-editor> inventory/myclsuter/group_vars/kube_node.yml # for worker nodes
```

## Installing the cluster

```ShellSession
ansible-playbook -i inventory/mycluster/ cluster.yml -b -v \
  --private-key=~/.ssh/private_key
```

### Adding nodes

You may want to add worker, control plane or etcd nodes to your existing cluster. This can be done by re-running the `cluster.yml` playbook, or you can target the bare minimum needed to get kubelet installed on the worker and talking to your control planes. This is especially helpful when doing something like autoscaling your clusters.

- Add the new worker node to your inventory in the appropriate group (or utilize a [dynamic inventory](https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html)).
- Run the ansible-playbook command, substituting `cluster.yml` for `scale.yml`:

```ShellSession
ansible-playbook -i inventory/mycluster/hosts.yml scale.yml -b -v \
  --private-key=~/.ssh/private_key
```

### Remove nodes

You may want to remove **control plane**, **worker**, or **etcd** nodes from your
existing cluster. This can be done by re-running the `remove-node.yml`
playbook. First, all specified nodes will be drained, then stop some
kubernetes services and delete some certificates,
and finally execute the kubectl command to delete these nodes.
This can be combined with the add node function. This is generally helpful
when doing something like autoscaling your clusters. Of course, if a node
is not working, you can remove the node and install it again.

Use `--extra-vars "node=<nodename>,<nodename2>"` to select the node(s) you want to delete.

```ShellSession
ansible-playbook -i inventory/mycluster/hosts.yml remove-node.yml -b -v \
--private-key=~/.ssh/private_key \
--extra-vars "node=nodename,nodename2"
```

If a node is completely unreachable by ssh, add `--extra-vars reset_nodes=false`
to skip the node reset step. If one node is unavailable, but others you wish
to remove are able to connect via SSH, you could set `reset_nodes=false` as a host
var in inventory.

## Connecting to Kubernetes

By default, Kubespray configures kube_control_plane hosts with insecure access to
kube-apiserver via port 8080. A kubeconfig file is not necessary in this case,
because kubectl will use <http://localhost:8080> to connect. The kubeconfig files
generated will point to localhost (on kube_control_planes) and kube_node hosts will
connect either to a localhost nginx proxy or to a loadbalancer if configured.
More details on this process are in the [HA guide](/docs/operations/ha-mode.md).

Kubespray permits connecting to the cluster remotely on any IP of any
kube_control_plane host on port 6443 by default. However, this requires
authentication. One can get a kubeconfig from kube_control_plane hosts
(see [below](#accessing-kubernetes-api)).

For more information on kubeconfig and accessing a Kubernetes cluster, refer to
the Kubernetes [documentation](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/).

## Accessing Kubernetes Dashboard

Supported version is kubernetes-dashboard v2.0.x :

- Login option : token/kubeconfig by default
- Deployed by default in "kube-system" namespace, can be overridden with `dashboard_namespace: kubernetes-dashboard` in inventory,
- Only serves over https

Access is described in [dashboard docs](https://github.com/kubernetes/dashboard/tree/master/docs/user/accessing-dashboard). With kubespray's default deployment in kube-system namespace, instead of kubernetes-dashboard :

- Proxy URL is <http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#/login>
- kubectl commands must be run with "-n kube-system"

Accessing through Ingress is highly recommended. For proxy access, please note that proxy must listen to [localhost](https://github.com/kubernetes/dashboard/issues/692#issuecomment-220492484) (`proxy  --address="x.x.x.x"` will not work)

For token authentication, guide to create Service Account is provided in [dashboard sample user](https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md) doc. Still take care of default namespace.

Access can also by achieved via ssh tunnel on a control plane :

```bash
# localhost:8081 will be sent to control-plane-1's own localhost:8081
ssh -L8001:localhost:8001 user@control-plane-1
sudo -i
kubectl proxy
```

## Accessing Kubernetes API

The main client of Kubernetes is `kubectl`. It is installed on each kube_control_plane
host and can optionally be configured on your ansible host by setting
`kubectl_localhost: true` and `kubeconfig_localhost: true` in the configuration:

- If `kubectl_localhost` enabled, `kubectl` will download onto `/usr/local/bin/` and setup with bash completion. A helper script `inventory/mycluster/artifacts/kubectl.sh` also created for setup with below `admin.conf`.
- If `kubeconfig_localhost` enabled `admin.conf` will appear in the `inventory/mycluster/artifacts/` directory after deployment.
- The location where these files are downloaded to can be configured via the `artifacts_dir` variable.

NOTE: The controller host name in the admin.conf file might be a private IP. If so, change it to use the controller's public IP or the cluster's load balancer.

You can see a list of nodes by running the following commands:

```ShellSession
cd inventory/mycluster/artifacts
./kubectl.sh get nodes
```

If desired, copy admin.conf to ~/.kube/config.

## Setting up your first cluster

[Setting up your first cluster](/docs/getting_started/setting-up-your-first-cluster.md) is an
 applied step-by-step guide for setting up your first cluster with Kubespray.
