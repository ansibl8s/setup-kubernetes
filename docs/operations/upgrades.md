# Upgrading Kubernetes in Kubespray

Kubespray handles upgrades the same way it handles initial deployment. That is to
say that each component is laid down in a fixed order.

You can also individually control versions of components by explicitly defining their
versions. Here are all version vars for each component:

* docker_version
* docker_containerd_version (relevant when `container_manager` == `docker`)
* containerd_version (relevant when `container_manager` == `containerd`)
* kube_version
* etcd_version
* calico_version
* calico_cni_version
* weave_version
* flannel_version
* kubedns_version

> **Warning**
> [Attempting to upgrade from an older release straight to the latest release is unsupported and likely to break something](https://github.com/kubernetes-sigs/kubespray/issues/3849#issuecomment-451386515)

See [Multiple Upgrades](#multiple-upgrades) for how to upgrade from older Kubespray release to the latest release

## Unsafe upgrade example

If you wanted to upgrade just kube_version from v1.18.10 to v1.19.7, you could
deploy the following way:

```ShellSession
ansible-playbook cluster.yml -i <inventory_path>/hosts.ini -e kube_version=v1.18.10 -e upgrade_cluster_setup=true
```

And then repeat with v1.19.7 as kube_version:

```ShellSession
ansible-playbook cluster.yml -i <inventory_path>/hosts.ini -e kube_version=v1.19.7 -e upgrade_cluster_setup=true
```

The var ```-e upgrade_cluster_setup=true``` is needed to be set in order to migrate the deploys of e.g kube-apiserver inside the cluster immediately which is usually only done in the graceful upgrade. (Refer to [#4139](https://github.com/kubernetes-sigs/kubespray/issues/4139) and [#4736](https://github.com/kubernetes-sigs/kubespray/issues/4736))

## Graceful upgrade

Kubespray also supports cordon, drain and uncordoning of nodes when performing
a cluster upgrade. There is a separate playbook used for this purpose. It is
important to note that upgrade-cluster.yml can only be used for upgrading an
existing cluster. That means there must be at least 1 kube_control_plane already
deployed.

```ShellSession
ansible-playbook upgrade-cluster.yml -b -i <inventory_path>/hosts.ini -e kube_version=v1.19.7
```

After a successful upgrade, the Server Version should be updated:

```ShellSession
$ kubectl version
Client Version: version.Info{Major:"1", Minor:"19", GitVersion:"v1.19.7", GitCommit:"1dd5338295409edcfff11505e7bb246f0d325d15", GitTreeState:"clean", BuildDate:"2021-01-13T13:23:52Z", GoVersion:"go1.15.5", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"19", GitVersion:"v1.19.7", GitCommit:"1dd5338295409edcfff11505e7bb246f0d325d15", GitTreeState:"clean", BuildDate:"2021-01-13T13:15:20Z", GoVersion:"go1.15.5", Compiler:"gc", Platform:"linux/amd64"}
```

You can control how many nodes are upgraded at the same time by modifying the ansible variable named `serial`, as explained [here](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_strategies.html#setting-the-batch-size-with-serial). If you don't set this variable, it will upgrade the cluster nodes in batches of  20% of the available nodes. Setting `serial=1` would mean upgrade one node at a time.

```ShellSession
ansible-playbook upgrade-cluster.yml -b -i <inventory_path>/hosts.ini -e kube_version=v1.20.7 -e "serial=1"
```

### Pausing the upgrade

If you want to manually control the upgrade procedure, you can set some variables to pause the upgrade playbook. Pausing *before* upgrading each upgrade may be useful for inspecting pods running on that node, or performing manual actions on the node:

* `upgrade_node_confirm: true` - This will pause the playbook execution prior to upgrading each node. The play will resume when manually approved by typing "yes" at the terminal.
* `upgrade_node_pause_seconds: 60` - This will pause the playbook execution for 60 seconds prior to upgrading each node. The play will resume automatically after 60 seconds.

Pausing *after* upgrading each node may be useful for rebooting the node to apply kernel updates, or testing the still-cordoned node:

* `upgrade_node_post_upgrade_confirm: true` - This will pause the playbook execution after upgrading each node, but before the node is uncordoned. The play will resume when manually approved by typing "yes" at the terminal.
* `upgrade_node_post_upgrade_pause_seconds: 60` - This will pause the playbook execution for 60 seconds after upgrading each node, but before the node is uncordoned. The play will resume automatically after 60 seconds.

## Node-based upgrade

If you don't want to upgrade all nodes in one run, you can use `--limit` [patterns](https://docs.ansible.com/ansible/latest/user_guide/intro_patterns.html#patterns-and-ansible-playbook-flags).

Before using `--limit` run playbook `facts.yml` without the limit to refresh facts cache for all nodes:

```ShellSession
ansible-playbook facts.yml -b -i <inventory_path>/hosts.ini
```

After this upgrade control plane and etcd groups [#5147](https://github.com/kubernetes-sigs/kubespray/issues/5147):

```ShellSession
ansible-playbook upgrade-cluster.yml -b -i <inventory_path>/hosts.ini -e kube_version=v1.20.7 --limit "kube_control_plane:etcd"
```

Now you can upgrade other nodes in any order and quantity:

```ShellSession
ansible-playbook upgrade-cluster.yml -b -i <inventory_path>/hosts.ini -e kube_version=v1.20.7 --limit "node4:node6:node7:node12"
ansible-playbook upgrade-cluster.yml -b -i <inventory_path>/hosts.ini -e kube_version=v1.20.7 --limit "node5*"
```

## Multiple upgrades

> **Warning**
> [Do not skip minor releases (patches releases are ok) when upgrading--upgrade by one tag at a
> time.](https://github.com/kubernetes-sigs/kubespray/issues/3849#issuecomment-451386515)

For instances, given the tag list:

```console
$ git tag
v2.20.0
v2.21.0
v2.22.0
v2.22.1
v2.23.0
v2.23.1
v2.23.2
v2.24.0
...
```

v2.22.0 -> v2.23.2 -> v2.24.0 : ✓
v.22.0 -> v2.24.0 : ✕

Assuming you don't explicitly define a kubernetes version in your k8s_cluster.yml, you simply check out the next tag and run the upgrade-cluster.yml playbook

* If you do define kubernetes version in your inventory (e.g. group_vars/k8s_cluster.yml) then either make sure to update it before running upgrade-cluster, or specify the new version you're upgrading to: `ansible-playbook -i inventory/mycluster/hosts.ini -b upgrade-cluster.yml -e kube_version=v1.11.3`

  Otherwise, the upgrade will leave your cluster at the same k8s version defined in your inventory vars.

The below example shows taking a cluster that was set up for v2.6.0 up to v2.10.0

```ShellSession
$ kubectl get node
NAME      STATUS    ROLES         AGE       VERSION
apollo    Ready     master,node   1h        v1.10.4
boomer    Ready     master,node   42m       v1.10.4
caprica   Ready     master,node   42m       v1.10.4

$ git describe --tags
v2.6.0

$ git tag
...
v2.6.0
v2.7.0
v2.8.0
v2.8.1
v2.8.2
...

$ git checkout v2.7.0
Previous HEAD position was 8b3ce6e4 bump upgrade tests to v2.5.0 commit (#3087)
HEAD is now at 05dabb7e Fix Bionic networking restart error #3430 (#3431)

# NOTE: May need to `pip3 install -r requirements.txt` when upgrading.

ansible-playbook -i inventory/mycluster/hosts.ini -b upgrade-cluster.yml

...

$ kubectl get node
NAME      STATUS    ROLES         AGE       VERSION
apollo    Ready     master,node   1h        v1.11.3
boomer    Ready     master,node   1h        v1.11.3
caprica   Ready     master,node   1h        v1.11.3

$ git checkout v2.8.0
Previous HEAD position was 05dabb7e Fix Bionic networking restart error #3430 (#3431)
HEAD is now at 9051aa52 Fix ubuntu-contiv test failed (#3808)
```

> **Note**
> Review changes between the sample inventory and your inventory when upgrading versions.

Some deprecations between versions that mean you can't just upgrade straight from 2.7.0 to 2.8.0 if you started with the sample inventory.

In this case, I set "kubeadm_enabled" to false, knowing that it is deprecated and removed by 2.9.0, to delay converting the cluster to kubeadm as long as I could.

```ShellSession
$ ansible-playbook -i inventory/mycluster/hosts.ini -b upgrade-cluster.yml
...
    "msg": "DEPRECATION: non-kubeadm deployment is deprecated from v2.9. Will be removed in next release."
...
Are you sure you want to deploy cluster using the deprecated non-kubeadm mode. (output is hidden):
yes
...

$ kubectl get node
NAME      STATUS   ROLES         AGE    VERSION
apollo    Ready    master,node   114m   v1.12.3
boomer    Ready    master,node   114m   v1.12.3
caprica   Ready    master,node   114m   v1.12.3

$ git checkout v2.8.1
Previous HEAD position was 9051aa52 Fix ubuntu-contiv test failed (#3808)
HEAD is now at 2ac1c756 More Feature/2.8 backports for 2.8.1 (#3911)

$ ansible-playbook -i inventory/mycluster/hosts.ini -b upgrade-cluster.yml
...
    "msg": "DEPRECATION: non-kubeadm deployment is deprecated from v2.9. Will be removed in next release."
...
Are you sure you want to deploy cluster using the deprecated non-kubeadm mode. (output is hidden):
yes
...

$ kubectl get node
NAME      STATUS   ROLES         AGE     VERSION
apollo    Ready    master,node   2h36m   v1.12.4
boomer    Ready    master,node   2h36m   v1.12.4
caprica   Ready    master,node   2h36m   v1.12.4

$ git checkout v2.8.2
Previous HEAD position was 2ac1c756 More Feature/2.8 backports for 2.8.1 (#3911)
HEAD is now at 4167807f Upgrade to 1.12.5 (#4066)

$ ansible-playbook -i inventory/mycluster/hosts.ini -b upgrade-cluster.yml
...
    "msg": "DEPRECATION: non-kubeadm deployment is deprecated from v2.9. Will be removed in next release."
...
Are you sure you want to deploy cluster using the deprecated non-kubeadm mode. (output is hidden):
yes
...

$ kubectl get node
NAME      STATUS   ROLES         AGE    VERSION
apollo    Ready    master,node   3h3m   v1.12.5
boomer    Ready    master,node   3h3m   v1.12.5
caprica   Ready    master,node   3h3m   v1.12.5

$ git checkout v2.8.3
Previous HEAD position was 4167807f Upgrade to 1.12.5 (#4066)
HEAD is now at ea41fc5e backport cve-2019-5736 to release-2.8 (#4234)

$ ansible-playbook -i inventory/mycluster/hosts.ini -b upgrade-cluster.yml
...
    "msg": "DEPRECATION: non-kubeadm deployment is deprecated from v2.9. Will be removed in next release."
...
Are you sure you want to deploy cluster using the deprecated non-kubeadm mode. (output is hidden):
yes
...

$ kubectl get node
NAME      STATUS   ROLES         AGE     VERSION
apollo    Ready    master,node   5h18m   v1.12.5
boomer    Ready    master,node   5h18m   v1.12.5
caprica   Ready    master,node   5h18m   v1.12.5

$ git checkout v2.8.4
Previous HEAD position was ea41fc5e backport cve-2019-5736 to release-2.8 (#4234)
HEAD is now at 3901480b go to k8s 1.12.7 (#4400)

$ ansible-playbook -i inventory/mycluster/hosts.ini -b upgrade-cluster.yml
...
    "msg": "DEPRECATION: non-kubeadm deployment is deprecated from v2.9. Will be removed in next release."
...
Are you sure you want to deploy cluster using the deprecated non-kubeadm mode. (output is hidden):
yes
...

$ kubectl get node
NAME      STATUS   ROLES         AGE     VERSION
apollo    Ready    master,node   5h37m   v1.12.7
boomer    Ready    master,node   5h37m   v1.12.7
caprica   Ready    master,node   5h37m   v1.12.7

$ git checkout v2.8.5
Previous HEAD position was 3901480b go to k8s 1.12.7 (#4400)
HEAD is now at 6f97687d Release 2.8 robust san handling (#4478)

$ ansible-playbook -i inventory/mycluster/hosts.ini -b upgrade-cluster.yml
...
    "msg": "DEPRECATION: non-kubeadm deployment is deprecated from v2.9. Will be removed in next release."
...
Are you sure you want to deploy cluster using the deprecated non-kubeadm mode. (output is hidden):
yes
...

$ kubectl get node
NAME      STATUS   ROLES         AGE     VERSION
apollo    Ready    master,node   5h45m   v1.12.7
boomer    Ready    master,node   5h45m   v1.12.7
caprica   Ready    master,node   5h45m   v1.12.7

$ git checkout v2.9.0
Previous HEAD position was 6f97687d Release 2.8 robust san handling (#4478)
HEAD is now at a4e65c7c Upgrade to Ansible >2.7.0 (#4471)
```

> **Warning**
> IMPORTANT: Some variable formats changed in the k8s_cluster.yml between 2.8.5 and 2.9.0

If you do not keep your inventory copy up to date, **your upgrade will fail** and your first master will be left non-functional until fixed and re-run.

It is at this point the cluster was upgraded from non-kubeadm to kubeadm as per the deprecation warning.

```ShellSession
ansible-playbook -i inventory/mycluster/hosts.ini -b upgrade-cluster.yml

...

$ kubectl get node
NAME      STATUS   ROLES         AGE     VERSION
apollo    Ready    master,node   6h54m   v1.13.5
boomer    Ready    master,node   6h55m   v1.13.5
caprica   Ready    master,node   6h54m   v1.13.5

# Watch out: 2.10.0 is hiding between 2.1.2 and 2.2.0

$ git tag
...
v2.1.0
v2.1.1
v2.1.2
v2.10.0
v2.2.0
...

$ git checkout v2.10.0
Previous HEAD position was a4e65c7c Upgrade to Ansible >2.7.0 (#4471)
HEAD is now at dcd9c950 Add etcd role dependency on kube user to avoid etcd role failure when running scale.yml with a fresh node. (#3240) (#4479)

ansible-playbook -i inventory/mycluster/hosts.ini -b upgrade-cluster.yml

...

$ kubectl get node
NAME      STATUS   ROLES         AGE     VERSION
apollo    Ready    master,node   7h40m   v1.14.1
boomer    Ready    master,node   7h40m   v1.14.1
caprica   Ready    master,node   7h40m   v1.14.1


```

## Upgrading to v2.19

`etcd_kubeadm_enabled` is being deprecated at v2.19. The same functionality is achievable by setting `etcd_deployment_type` to `kubeadm`.
Deploying etcd using kubeadm is experimental and is only available for either new or deployments where `etcd_kubeadm_enabled` was set to `true` while deploying the cluster.

From 2.19 and onward `etcd_deployment_type` variable will be placed in `group_vars/all/etcd.yml` instead of `group_vars/etcd.yml`, due to scope issues.
The placement of the variable is only important for `etcd_deployment_type: kubeadm` right now. However, since this might change in future updates, it is recommended to move the variable.

Upgrading is straightforward; no changes are required if `etcd_kubeadm_enabled` was not set to `true` when deploying.

If you have a cluster where `etcd` was deployed using `kubeadm`, you will need to remove `etcd_kubeadm_enabled` the variable. Then move `etcd_deployment_type` variable from `group_vars/etcd.yml` to `group_vars/all/etcd.yml` due to scope issues and set `etcd_deployment_type` to `kubeadm`.

## Upgrade order

As mentioned above, components are upgraded in the order in which they were
installed in the Ansible playbook. The order of component installation is as
follows:

* Docker
* Containerd
* etcd
* kubelet and kube-proxy
* network_plugin (such as Calico or Weave)
* kube-apiserver, kube-scheduler, and kube-controller-manager
* Add-ons (such as KubeDNS)

### Component-based upgrades

A deployer may want to upgrade specific components in order to minimize risk
or save time. This strategy is not covered by CI as of this writing, so it is
not guaranteed to work.

These commands are useful only for upgrading fully-deployed, healthy, existing
hosts. This will definitely not work for undeployed or partially deployed
hosts.

Upgrade docker:

```ShellSession
ansible-playbook -b -i <inventory_path>/hosts.ini cluster.yml --tags=docker
```

Upgrade etcd:

```ShellSession
ansible-playbook -b -i <inventory_path>/hosts.ini cluster.yml --tags=etcd
```

Upgrade etcd without rotating etcd certs:

```ShellSession
ansible-playbook -b -i <inventory_path>/hosts.ini cluster.yml --tags=etcd --limit=etcd --skip-tags=etcd-secrets
```

Upgrade kubelet:

```ShellSession
ansible-playbook -b -i <inventory_path>/hosts.ini cluster.yml --tags=node --skip-tags=k8s-gen-certs
```

Upgrade Kubernetes master components:

```ShellSession
ansible-playbook -b -i <inventory_path>/hosts.ini cluster.yml --tags=master
```

Upgrade network plugins:

```ShellSession
ansible-playbook -b -i <inventory_path>/hosts.ini cluster.yml --tags=network
```

Upgrade all add-ons:

```ShellSession
ansible-playbook -b -i <inventory_path>/hosts.ini cluster.yml --tags=apps
```

Upgrade just helm (assuming `helm_enabled` is true):

```ShellSession
ansible-playbook -b -i <inventory_path>/hosts.ini cluster.yml --tags=helm
```

## Migrate from Docker to Containerd

Please note that **migrating container engines is not officially supported by Kubespray**. While this procedure can be used to migrate your cluster, it applies to one particular scenario and will likely evolve over time. At the moment, they are intended as an additional resource to provide insight into how these steps can be officially integrated into the Kubespray playbooks.

As of Kubespray 2.18.0, containerd is already the default container engine. If you have the chance, it is advisable and safer to reset and redeploy the entire cluster with a new container engine.

* [Migrating from Docker to Containerd](/docs/upgrades/migrate_docker2containerd.md)

## System upgrade

If you want to upgrade the APT or YUM packages while the nodes are cordoned, you can use:

```ShellSession
ansible-playbook upgrade-cluster.yml -b -i <inventory_path>/hosts.ini -e system_upgrade=true
```

Nodes will be rebooted when there are package upgrades (`system_upgrade_reboot: on-upgrade`).
This can be changed to `always` or `never`.

Note: Downloads will happen twice unless `system_upgrade_reboot` is `never`.
