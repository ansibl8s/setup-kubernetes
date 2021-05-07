Kubernetes on ionos with Terraform
Provision a Kubernetes cluster on ionos using Terraform and Kubespray

Overview
The setup looks like following

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
Requirements
Terraform 0.13.0 or newer
Quickstart
NOTE: Assumes you are at the root of the kubespray repo.

For authentication in your cluster you can use the environment variables.

export IONOS_USERNAME=”<put your IONOS username here>”
export IONOS_PASSWORD=”<put your IONOS password here>”

To allow API access to your ionos account, you need to allow API connections by visiting Account-page in your ionos Hub.


Run Terraform to create the infrastructure.

terraform init ../../contrib/terraform/ionos
terraform apply ../../contrib/terraform/ionos/

You should now have a inventory file named inventory.ini that you can use with kubespray. You can use the inventory file with kubespray to set up a cluster.

It is a good idea to check that you have basic SSH connectivity to the nodes. You can do that by:

ansible -i inventory.ini -m ping all

You can setup Kubernetes with kubespray using the generated inventory:

ansible-playbook -i inventory.ini ../../cluster.yml -b -v

Teardown
You can teardown your infrastructure using the following Terraform command:

terraform destroy ../../contrib/terraform/ionos/
      
Variables


ssh_public_keys: One or more public SSH keys to install on all machines.Define the path of the ssh public key
location: The zone where the cluster will be created. 
machines: Machines to provision. Contain the list of machines composing the cluster. Key of this object will be used as the name of the machine.
node_type: The role of this node (master|worker, in Kubespray and hence in this guide called “master” due to legacy naming of the control plane -- is likely to change in the future).
cpu: number of CPU cores.
mem: memory size in MB.
disk_size: The size of the storage in GB.
