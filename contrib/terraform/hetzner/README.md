# Kubernetes on Hetzner with Terraform

Provision a Kubernetes cluster on [Hetzner](https://www.hetzner.com/cloud) using Terraform and Kubespray

## Overview

The setup looks like following

```text
   Kubernetes cluster
+--------------------------+
|      +--------------+    |
|      | +--------------+  |
| -->  | |              |  |
|      | | Master/etcd  |  |
|      | | node(s)      |  |
|      +-+              |  |
|        +--------------+  |
|              ^           |
|              |           |
|              v           |
|      +--------------+    |
|      | +--------------+  |
| -->  | |              |  |
|      | |    Worker    |  |
|      | |    node(s)   |  |
|      +-+              |  |
|        +--------------+  |
+--------------------------+
```

The nodes uses a private network for node to node communication and a public interface for all external communication.

## Requirements

* Terraform 0.14.0 or newer

## Quickstart

NOTE: Assumes you are at the root of the kubespray repo.

For authentication in your cluster you can use the environment variables.

```bash
export HCLOUD_TOKEN=api-token
```

Copy the cluster configuration file.

```bash
CLUSTER=my-hetzner-cluster
cp contrib/terraform/hetzner/default.tfvars inventory/$CLUSTER/
cd inventory/$CLUSTER
```

Edit `default.tfvars` to match your requirement.

Flatcar Container Linux instead of the basic Hetzner Images.

```bash
cd ../../contrib/terraform/hetzner
```

Edit `main.tf` and reactivate the module `source = "./modules/kubernetes-cluster-flatcar"`and
comment out the `#source = "./modules/kubernetes-cluster"`.

activate `ssh_private_key_path = var.ssh_private_key_path`. The VM boots into
Rescue-Mode with the selected image of the `var.machines` but installs Flatcar instead.

Run Terraform to create the infrastructure.

```bash
cd ./kubespray
terraform -chdir=./contrib/terraform/hetzner/ init
terraform -chdir=./contrib/terraform/hetzner/ apply --var-file=../../../inventory/$CLUSTER/default.tfvars
```

You should now have a inventory file named `inventory.ini` that you can use with kubespray.
You can use the inventory file with kubespray to set up a cluster.

It is a good idea to check that you have basic SSH connectivity to the nodes. You can do that by:

```bash
ansible -i inventory.ini -m ping all
```

You can setup Kubernetes with kubespray using the generated inventory:

```bash
ansible-playbook -i inventory.ini ../../cluster.yml -b -v
```

## Cloud controller

For better support with the cloud you can install the [hcloud cloud controller](https://github.com/hetznercloud/hcloud-cloud-controller-manager) and [CSI driver](https://github.com/hetznercloud/csi-driver).

Please read the instructions in both repos on how to install it.

## Teardown

You can teardown your infrastructure using the following Terraform command:

```bash
terraform destroy --var-file default.tfvars ../../contrib/terraform/hetzner
```

## Variables

* `prefix`: Prefix to add to all resources, if set to "" don't set any prefix
* `ssh_public_keys`: List of public SSH keys to install on all machines
* `zone`: The zone where to run the cluster
* `network_zone`: the network zone where the cluster is running
* `machines`: Machines to provision. Key of this object will be used as the name of the machine
  * `node_type`: The role of this node *(master|worker)*
  * `size`: Size of the VM
  * `image`: The image to use for the VM
* `ssh_whitelist`: List of IP ranges (CIDR) that will be allowed to ssh to the nodes
* `api_server_whitelist`: List of IP ranges (CIDR) that will be allowed to connect to the API server
* `nodeport_whitelist`: List of IP ranges (CIDR) that will be allowed to connect to the kubernetes nodes on port 30000-32767 (kubernetes nodeports)
* `ingress_whitelist`: List of IP ranges (CIDR) that will be allowed to connect to kubernetes workers on port 80 and 443
