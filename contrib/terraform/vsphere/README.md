# Kubernetes on vSphere with Terraform

Provision a Kubernetes cluster on [vSphere](https://www.vmware.com/products/vsphere.html) using Terraform and Kubespray.

## Overview

The setup looks like following.

```text
   Kubernetes cluster
+-----------------------+
|   +--------------+    |
|   | +--------------+  |
|   | |              |  |
|   | | Master/etcd  |  |
|   | | node(s)      |  |
|   +-+              |  |
|     +--------------+  |
|           ^           |
|           |           |
|           v           |
|   +--------------+    |
|   | +--------------+  |
|   | |              |  |
|   | |    Worker    |  |
|   | |    node(s)   |  |
|   +-+              |  |
|     +--------------+  |
+-----------------------+
```

## Warning

This setup assumes that the DHCP is disabled in the vSphere cluster and IP addresses have to be provided in the configuration file.

## Requirements

* Terraform 0.13.0 or newer (0.12 also works if you modify the provider block to include version and remove all `versions.tf` files)

## Quickstart

NOTE: *Assumes you are at the root of the kubespray repo*

Copy the sample inventory for your cluster and copy the default terraform variables.

```bash
CLUSTER=my-vsphere-cluster
cp contrib/terraform/vsphere/default.tfvars inventory/$CLUSTER/
cd inventory/$CLUSTER
```

Edit `default.tfvars` to match your setup. You MUST set values specific for you network and vSphere cluster.

```bash
# Ensure $EDITOR points to your favorite editor, e.g., vim, emacs, VS Code, etc.
$EDITOR default.tfvars
```

For authentication in your vSphere cluster you can use the environment variables.

```bash
export TF_VAR_vsphere_user=username
export TF_VAR_vsphere_password=password
```

Run Terraform to create the infrastructure.

```bash
terraform init ../../contrib/terraform/vsphere
terraform apply \
    -var-file default.tfvars \
    -state=tfstate-$CLUSTER.tfstate \
    ../../contrib/terraform/vsphere
```

You should now have a inventory file named `inventory.ini` that you can use with kubespray.
You can now copy your inventory file and use it with kubespray to set up a cluster.
You can type `terraform output` to find out the IP addresses of the nodes.

It is a good idea to check that you have basic SSH connectivity to the nodes. You can do that by:

```bash
ansible -i inventory.ini -m ping all
```

Example to use this with the default sample inventory:

```bash
ansible-playbook -i inventory.ini ../../cluster.yml -b -v
```

## Variables

### Required

* `machines`: Machines to provision. Key of this object will be used as the name of the machine
  * `node_type`: The role of this node *(master|worker)*
  * `ip`: The IP address of the machine
  * `netmask`: The netmask to use (to be used on the right hand side in CIDR notation, e.g., `24`)
* `network`: The name of the network to attach the machines to
* `gateway`: The IP address of the network gateway
* `vsphere_datacenter`: The identifier of vSphere data center
* `vsphere_compute_cluster`: The identifier of vSphere compute cluster
* `vsphere_datastore`: The identifier of vSphere data store
* `vsphere_server`: This is the vCenter server name or address for vSphere API operations.
* `ssh_public_keys`: List of public SSH keys to install on all machines
* `template_name`: The name of a base image (the OVF template be defined in vSphere beforehand)

### Optional

* `folder`: Name of the folder to put all machines in (default: `""`)
* `prefix`: Prefix to use for all resources, required to be unique for all clusters in the same project (default: `"k8s"`)
* `inventory_file`: Name of the generated inventory file for Kubespray to use in the Ansible step (default: `inventory.ini`)
* `dns_primary`: The IP address of primary DNS server (default: `8.8.4.4`)
* `dns_secondary`: The IP address of secondary DNS server (default: `8.8.8.8`)
* `firmware`: Firmware to use (default: `bios`)
* `hardware_version`: The version of the hardware (default: `15`)
* `master_cores`: The number of CPU cores for the master nodes (default: 4)
* `master_memory`: The amount of RAM for the master nodes in MB (default: 4096)
* `master_disk_size`: The amount of disk space for the master nodes in GB (default: 20)
* `worker_cores`: The number of CPU cores for the worker nodes (default: 16)
* `worker_memory`: The amount of RAM for the worker nodes in MB (default: 8192)
* `worker_disk_size`: The amount of disk space for the worker nodes in GB (default: 100)
* `vapp`: Boolean to set the template type to vapp. (Default: false)
* `interface_name`: Name of the interface to configure. (Default: ens192)

An example variables file can be found `default.tfvars`
