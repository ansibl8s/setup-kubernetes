# Kubernetes on Exoscale with Terraform

Provision a Kubernetes cluster on [Exoscale](https://www.exoscale.com/) using Terraform and Kubespray

## Overview

The setup looks like following

```text
                           Kubernetes cluster
                        +-----------------------+
+---------------+       |   +--------------+    |
|               |       |   | +--------------+  |
| API server LB +---------> | |              |  |
|               |       |   | | Master/etcd  |  |
+---------------+       |   | | node(s)      |  |
                        |   +-+              |  |
                        |     +--------------+  |
                        |           ^           |
                        |           |           |
                        |           v           |
+---------------+       |   +--------------+    |
|               |       |   | +--------------+  |
|  Ingress LB   +---------> | |              |  |
|               |       |   | |    Worker    |  |
+---------------+       |   | |    node(s)   |  |
                        |   +-+              |  |
                        |     +--------------+  |
                        +-----------------------+
```

## Requirements

* Terraform 0.13.0 or newer (0.12 also works if you modify the provider block to include version and remove all `versions.tf` files)

## Quickstart

NOTE: *Assumes you are at the root of the kubespray repo*

Copy the sample inventory for your cluster and copy the default terraform variables.

```bash
CLUSTER=my-exoscale-cluster
cp contrib/terraform/exoscale/default.tfvars inventory/$CLUSTER/
cd inventory/$CLUSTER
```

Edit `default.tfvars` to match your setup. You MUST, at the very least, change `ssh_public_keys`.

```bash
# Ensure $EDITOR points to your favorite editor, e.g., vim, emacs, VS Code, etc.
$EDITOR default.tfvars
```

For authentication you can use the credentials file `~/.cloudstack.ini` or `./cloudstack.ini`.
The file should look like something like this:

```ini
[cloudstack]
key = <API key>
secret = <API secret>
```

Follow the [Exoscale IAM Quick-start](https://community.exoscale.com/documentation/iam/quick-start/) to learn how to generate API keys.

### Encrypted credentials

To have the credentials encrypted at rest, you can use [sops](https://github.com/mozilla/sops) and only decrypt the credentials at runtime.

```bash
cat << EOF > cloudstack.ini
[cloudstack]
key =
secret =
EOF
sops --encrypt --in-place --pgp <PGP key fingerprint> cloudstack.ini
sops cloudstack.ini
```

Run terraform to create the infrastructure

```bash
terraform init ../../contrib/terraform/exoscale
terraform apply -var-file default.tfvars ../../contrib/terraform/exoscale
```

If your cloudstack credentials file is encrypted using sops, run the following:

```bash
terraform init ../../contrib/terraform/exoscale
sops exec-file -no-fifo cloudstack.ini 'CLOUDSTACK_CONFIG={} terraform apply -var-file default.tfvars ../../contrib/terraform/exoscale'
```

You should now have a inventory file named `inventory.ini` that you can use with kubespray.
You can now copy your inventory file and use it with kubespray to set up a cluster.
You can type `terraform output` to find out the IP addresses of the nodes, as well as control-plane and data-plane load-balancer.

It is a good idea to check that you have basic SSH connectivity to the nodes. You can do that by:

```bash
ansible -i inventory.ini -m ping all
```

Example to use this with the default sample inventory:

```bash
ansible-playbook -i inventory.ini ../../cluster.yml -b -v
```

## Teardown

The Kubernetes cluster cannot create any load-balancers or disks, hence, teardown is as simple as Terraform destroy:

```bash
terraform destroy -var-file default.tfvars ../../contrib/terraform/exoscale
```

## Variables

### Required

* `ssh_public_keys`: List of public SSH keys to install on all machines
* `zone`: The zone where to run the cluster
* `machines`: Machines to provision. Key of this object will be used as the name of the machine
  * `node_type`: The role of this node *(master|worker)*
  * `size`: The size to use
  * `boot_disk`: The boot disk to use
    * `image_name`: Name of the image
    * `root_partition_size`: Size *(in GB)* for the root partition
    * `ceph_partition_size`: Size *(in GB)* for the partition for rook to use as ceph storage. *(Set to 0 to disable)*
    * `node_local_partition_size`: Size *(in GB)* for the partition for node-local-storage. *(Set to 0 to disable)*
* `ssh_whitelist`: List of IP ranges (CIDR) that will be allowed to ssh to the nodes
* `api_server_whitelist`: List of IP ranges (CIDR) that will be allowed to connect to the API server
* `nodeport_whitelist`: List of IP ranges (CIDR) that will be allowed to connect to the kubernetes nodes on port 30000-32767 (kubernetes nodeports)

### Optional

* `prefix`: Prefix to use for all resources, required to be unique for all clusters in the same project *(Defaults to `default`)*

An example variables file can be found `default.tfvars`

## Known limitations

### Only single disk

Since Exoscale doesn't support additional disks to be mounted onto an instance, this script has the ability to create partitions for [Rook](https://rook.io/) and [node-local-storage](https://kubernetes.io/docs/concepts/storage/volumes/#local).

### No Kubernetes API

The current solution doesn't use the [Exoscale Kubernetes cloud controller](https://github.com/exoscale/exoscale-cloud-controller-manager).
This means that we need to set up a HTTP(S) loadbalancer in front of all workers and set the Ingress controller to DaemonSet mode.
