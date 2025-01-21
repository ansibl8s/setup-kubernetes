# Deploying a Kubespray Kubernetes Cluster with GlusterFS

You can either deploy using Ansible on its own by supplying your own inventory file or by using Terraform to create the VMs and then providing a dynamic inventory to Ansible. The following two sections are self-contained, you don't need to go through one to use the other. So, if you want to provision with Terraform, you can skip the **Using an Ansible inventory** section, and if you want to provision with a pre-built ansible inventory, you can neglect the **Using Terraform and Ansible**  section.

## Using an Ansible inventory

In the same directory of this ReadMe file you should find a file named `inventory.example` which contains an example setup. Please note that, additionally to the Kubernetes nodes/masters, we define a set of machines for GlusterFS and we add them to the group `[gfs-cluster]`, which in turn is added to the larger `[network-storage]` group as a child group.

Change that file to reflect your local setup (adding more machines or removing them and setting the adequate ip numbers), and save it to your Ansible inventory. Then execute change to the kubespray root folder, and execute (supposing that the machines are all using ubuntu):

```shell
ansible-playbook -b --become-user=root -i <inventory_path>/k8s_gfs_inventory --user=ubuntu ./cluster.yml
```

This will provision your Kubernetes cluster. Then, to provision and configure the GlusterFS cluster, from the same directory execute:

```shell
ansible-playbook -b --become-user=root -i <inventory_path>/k8s_gfs_inventory --user=ubuntu ./contrib/network-storage/glusterfs/glusterfs.yml
```

If your machines are not using Ubuntu, you need to change the `--user=ubuntu` to the correct user. Alternatively, if your Kubernetes machines are using one OS and your GlusterFS a different one, you can instead specify the `ansible_ssh_user=<correct-user>` variable in the inventory file that you just created, for each machine/VM:

```shell
k8s-master-1 ansible_ssh_host=192.168.0.147 ip=192.168.0.147 ansible_ssh_user=core
k8s-master-node-1 ansible_ssh_host=192.168.0.148 ip=192.168.0.148 ansible_ssh_user=core
k8s-master-node-2 ansible_ssh_host=192.168.0.146 ip=192.168.0.146 ansible_ssh_user=core
```

## Using Terraform and Ansible

First step is to fill in a `my-kubespray-gluster-cluster.tfvars` file with the specification desired for your cluster. An example with all required variables would look like:

```ini
cluster_name = "cluster1"
number_of_k8s_masters = "1"
number_of_k8s_masters_no_floating_ip = "2"
number_of_k8s_nodes_no_floating_ip = "0"
number_of_k8s_nodes = "0"
public_key_path = "~/.ssh/my-desired-key.pub"
image = "Ubuntu 16.04"
ssh_user = "ubuntu"
flavor_k8s_node = "node-flavor-id-in-your-openstack"
flavor_k8s_master = "master-flavor-id-in-your-openstack"
network_name = "k8s-network"
floatingip_pool = "net_external"

# GlusterFS variables
flavor_gfs_node = "gluster-flavor-id-in-your-openstack"
image_gfs = "Ubuntu 16.04"
number_of_gfs_nodes_no_floating_ip = "3"
gfs_volume_size_in_gb = "50"
ssh_user_gfs = "ubuntu"
```

As explained in the general terraform/openstack guide, you need to source your OpenStack credentials file, add your ssh-key to the ssh-agent and setup environment variables for terraform:

```shell
$ source ~/.stackrc
$ eval $(ssh-agent -s)
$ ssh-add ~/.ssh/my-desired-key
$ echo Setting up Terraform creds && \
  export TF_VAR_username=${OS_USERNAME} && \
  export TF_VAR_password=${OS_PASSWORD} && \
  export TF_VAR_tenant=${OS_TENANT_NAME} && \
  export TF_VAR_auth_url=${OS_AUTH_URL}
```

Then, standing on the kubespray directory (root base of the Git checkout), issue the following terraform command to create the VMs for the cluster:

```shell
terraform apply -state=contrib/terraform/openstack/terraform.tfstate -var-file=my-kubespray-gluster-cluster.tfvars contrib/terraform/openstack
```

This will create both your Kubernetes and Gluster VMs. Make sure that the ansible file `contrib/terraform/openstack/group_vars/all.yml` includes any ansible variable that you want to setup (like, for instance, the type of machine for bootstrapping).

Then, provision your Kubernetes (kubespray) cluster with the following ansible call:

```shell
ansible-playbook -b --become-user=root -i contrib/terraform/openstack/hosts ./cluster.yml
```

Finally, provision the glusterfs nodes and add the Persistent Volume setup for GlusterFS in Kubernetes through the following ansible call:

```shell
ansible-playbook -b --become-user=root -i contrib/terraform/openstack/hosts ./contrib/network-storage/glusterfs/glusterfs.yml
```

If you need to destroy the cluster, you can run:

```shell
terraform destroy -state=contrib/terraform/openstack/terraform.tfstate -var-file=my-kubespray-gluster-cluster.tfvars contrib/terraform/openstack
```
