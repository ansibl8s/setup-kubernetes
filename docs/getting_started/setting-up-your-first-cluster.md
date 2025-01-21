# Setting up your first cluster with Kubespray

This tutorial walks you through the detailed steps for setting up Kubernetes
with [Kubespray](https://kubespray.io/).

The guide is inspired on the tutorial [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way), with the
difference that here we want to showcase how to spin up a Kubernetes cluster
in a more managed fashion with Kubespray.

## Target Audience

The target audience for this tutorial is someone looking for a
hands-on guide to get started with Kubespray.

## Cluster Details

* [kubespray](https://github.com/kubernetes-sigs/kubespray)
* [kubernetes](https://github.com/kubernetes/kubernetes)

## Prerequisites

* Google Cloud Platform: This tutorial leverages the [Google Cloud Platform](https://cloud.google.com/) to streamline provisioning of the compute infrastructure required to bootstrap a Kubernetes cluster from the ground up. [Sign up](https://cloud.google.com/free/) for $300 in free credits.
* Google Cloud Platform SDK: Follow the Google Cloud SDK [documentation](https://cloud.google.com/sdk/) to install and configure the `gcloud` command
 line utility. Make sure to set a default compute region and compute zone.
* The [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) command line utility is used to interact with the Kubernetes
 API Server.
* Linux or Mac environment with Python 3

## Provisioning Compute Resources

Kubernetes requires a set of machines to host the Kubernetes control plane and the worker nodes where containers are ultimately run. In this lab you will provision the compute resources required for running a secure and highly available Kubernetes cluster across a single [compute zone](https://cloud.google.com/compute/docs/regions-zones/regions-zones).

### Networking

The Kubernetes [networking model](https://kubernetes.io/docs/concepts/cluster-administration/networking/#kubernetes-model) assumes a flat network in which containers and nodes can communicate with each other. In cases where this is not desired [network policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) can limit how groups of containers are allowed to communicate with each other and external network endpoints.

> Setting up network policies is out of scope for this tutorial.

#### Virtual Private Cloud Network

In this section a dedicated [Virtual Private Cloud](https://cloud.google.com/compute/docs/networks-and-firewalls#networks) (VPC) network will be setup to host the Kubernetes cluster.

Create the `kubernetes-the-kubespray-way` custom VPC network:

```ShellSession
gcloud compute networks create kubernetes-the-kubespray-way --subnet-mode custom
```

A [subnet](https://cloud.google.com/compute/docs/vpc/#vpc_networks_and_subnets) must be provisioned with an IP address range large enough to assign a private IP address to each node in the Kubernetes cluster.

Create the `kubernetes` subnet in the `kubernetes-the-kubespray-way` VPC network:

```ShellSession
gcloud compute networks subnets create kubernetes \
  --network kubernetes-the-kubespray-way \
  --range 10.240.0.0/24
 ```

> The `10.240.0.0/24` IP address range can host up to 254 compute instances.

#### Firewall Rules

Create a firewall rule that allows internal communication across all protocols.
It is important to note that the vxlan protocol has to be allowed in order for
the calico (see later) networking plugin to work.

```ShellSession
gcloud compute firewall-rules create kubernetes-the-kubespray-way-allow-internal \
  --allow tcp,udp,icmp,vxlan \
  --network kubernetes-the-kubespray-way \
  --source-ranges 10.240.0.0/24
```

Create a firewall rule that allows external SSH, ICMP, and HTTPS:

```ShellSession
gcloud compute firewall-rules create kubernetes-the-kubespray-way-allow-external \
  --allow tcp:80,tcp:6443,tcp:443,tcp:22,icmp \
  --network kubernetes-the-kubespray-way \
  --source-ranges 0.0.0.0/0
```

It is not feasible to restrict the firewall to a specific IP address from
where you are accessing the cluster as the nodes also communicate over the public internet and would otherwise run into
this firewall. Technically you could limit the firewall to the (fixed) IP
addresses of the cluster nodes and the remote IP addresses for accessing the
cluster.

### Compute Instances

The compute instances in this lab will be provisioned using [Ubuntu Server](https://www.ubuntu.com/server) 18.04.
Each compute instance will be provisioned with a fixed private IP address and
 a public IP address (that can be fixed - see [guide](https://cloud.google.com/compute/docs/ip-addresses/reserve-static-external-ip-address)).
Using fixed public IP addresses has the advantage that our cluster node
configuration does not need to be updated with new public IP addresses every
time the machines are shut down and later on restarted.

Create three compute instances which will host the Kubernetes control plane:

```ShellSession
for i in 0 1 2; do
  gcloud compute instances create controller-${i} \
    --async \
    --boot-disk-size 200GB \
    --can-ip-forward \
    --image-family ubuntu-1804-lts \
    --image-project ubuntu-os-cloud \
    --machine-type e2-standard-2 \
    --private-network-ip 10.240.0.1${i} \
    --scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
    --subnet kubernetes \
    --tags kubernetes-the-kubespray-way,controller
done
```

> Do not forget to fix the IP addresses if you plan on re-using the cluster
after temporarily shutting down the VMs - see [guide](https://cloud.google.com/compute/docs/ip-addresses/reserve-static-external-ip-address)

Create three compute instances which will host the Kubernetes worker nodes:

```ShellSession
for i in 0 1 2; do
  gcloud compute instances create worker-${i} \
    --async \
    --boot-disk-size 200GB \
    --can-ip-forward \
    --image-family ubuntu-1804-lts \
    --image-project ubuntu-os-cloud \
    --machine-type e2-standard-2 \
    --private-network-ip 10.240.0.2${i} \
    --scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
    --subnet kubernetes \
    --tags kubernetes-the-kubespray-way,worker
done
```

> Do not forget to fix the IP addresses if you plan on re-using the cluster
after temporarily shutting down the VMs - see [guide](https://cloud.google.com/compute/docs/ip-addresses/reserve-static-external-ip-address)

List the compute instances in your default compute zone:

```ShellSession
gcloud compute instances list --filter="tags.items=kubernetes-the-kubespray-way"
```

> Output

```ShellSession
NAME          ZONE        MACHINE_TYPE   PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP    STATUS
controller-0  us-west1-c  e2-standard-2               10.240.0.10  XX.XX.XX.XXX   RUNNING
controller-1  us-west1-c  e2-standard-2               10.240.0.11  XX.XXX.XXX.XX  RUNNING
controller-2  us-west1-c  e2-standard-2               10.240.0.12  XX.XXX.XX.XXX  RUNNING
worker-0      us-west1-c  e2-standard-2               10.240.0.20  XX.XX.XXX.XXX  RUNNING
worker-1      us-west1-c  e2-standard-2               10.240.0.21  XX.XX.XX.XXX   RUNNING
worker-2      us-west1-c  e2-standard-2               10.240.0.22  XX.XXX.XX.XX   RUNNING
```

### Configuring SSH Access

Kubespray is relying on SSH to configure the controller and worker instances.

Test SSH access to the `controller-0` compute instance:

```ShellSession
IP_CONTROLLER_0=$(gcloud compute instances list  --filter="tags.items=kubernetes-the-kubespray-way AND name:controller-0" --format="value(EXTERNAL_IP)")
USERNAME=$(whoami)
ssh $USERNAME@$IP_CONTROLLER_0
```

If this is your first time connecting to a compute instance SSH keys will be
generated for you. In this case you will need to enter a passphrase at the
prompt to continue.

> If you get a 'Remote host identification changed!' warning, you probably
already connected to that IP address in the past with another host key. You
can remove the old host key by running `ssh-keygen -R $IP_CONTROLLER_0`

Please repeat this procedure for all the controller and worker nodes, to
ensure that SSH access is properly functioning for all nodes.

## Set-up Kubespray

The following set of instruction is based on the [Quick Start](https://github.com/kubernetes-sigs/kubespray) but slightly altered for our
set-up.

As Ansible is a python application, we will create a fresh virtual
environment to install the dependencies for the Kubespray playbook:

```ShellSession
python3 -m venv venv
source venv/bin/activate
```

Next, we will git clone the Kubespray code into our working directory:

```ShellSession
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
git checkout release-2.17
```

Now we need to install the dependencies for Ansible to run the Kubespray
playbook:

```ShellSession
pip install -r requirements.txt
```

Create your Ansible inventory file with ip given by gcloud:

```ShellSession
gcloud compute instances list --filter="tags.items=kubernetes-the-kubespray-way"
```

Create the `inventory/mycluster/inventory.ini` file with the following content:

```ini
[kube_control_plane]
controller-0 ip=<ip of controller-0> # add respective ip for each node in the inventory
controller-1
controller-2

[kube_node]
worker-0
worker-1
worker-2
```

In order to be able to access the Kubernetes API server from outside the VPC network, we'll need to add the ip from all
three controller nodes to `supplementary_addresses_in_ssl_keys`. You can place this variable in
`inventory/mycluster/group_vars/kube_control_plane.yml` (apply to all hosts in the `kube_control_plane` group).

```yml
supplementary_addresses_in_ssl_keys:
- <ip-0>
- <ip-1>
- <ip-2>
```

Kubespray also offers to easily enable popular kubernetes add-ons.
Let's enable the metrics server as this is a crucial monitoring element for the kubernetes cluster.
`metrics_server_enabled`.

```yml
metrics_server_enabled: true
```

Now we will deploy the configuration:

```ShellSession
ansible-playbook -i inventory/mycluster/ -u $USERNAME -b -v --private-key=~/.ssh/id_rsa cluster.yml
```

Ansible will now execute the playbook, this can take up to 20 minutes.

## Access the kubernetes cluster

We will leverage a kubeconfig file from one of the controller nodes to access
 the cluster as administrator from our local workstation.

> In this simplified set-up, we did not include a load balancer that usually sits on top of the three controller nodes for a high available API server endpoint. In this simplified tutorial we connect directly to one of the three controllers.

First, we need to edit the permission of the kubeconfig file on one of the
controller nodes:

```ShellSession
ssh $USERNAME@$IP_CONTROLLER_0
USERNAME=$(whoami)
sudo chown -R $USERNAME:$USERNAME /etc/kubernetes/admin.conf
exit
```

Now we will copy over the kubeconfig file:

```ShellSession
scp $USERNAME@$IP_CONTROLLER_0:/etc/kubernetes/admin.conf kubespray-do.conf
```

This kubeconfig file uses the internal IP address of the controller node to
access the API server. This kubeconfig file will thus not work of from
outside the VPC network. We will need to change the API server IP address
to the controller node his external IP address. The external IP address will be
accepted in the
TLS negotiation as we added the controllers external IP addresses in the SSL
certificate configuration.
Open the file and modify the server IP address from the local IP to the
external IP address of controller-0, as stored in $IP_CONTROLLER_0.

> Example

```ShellSession
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: XXX
    server: https://35.205.205.80:6443
  name: cluster.local
...
```

Now, we load the configuration for `kubectl`:

```ShellSession
export KUBECONFIG=$PWD/kubespray-do.conf
```

We should be all set to communicate with our cluster from our local workstation:

```ShellSession
kubectl get nodes
```

> Output

```ShellSession
NAME           STATUS   ROLES    AGE   VERSION
controller-0   Ready    master   47m   v1.17.9
controller-1   Ready    master   46m   v1.17.9
controller-2   Ready    master   46m   v1.17.9
worker-0       Ready    <none>   45m   v1.17.9
worker-1       Ready    <none>   45m   v1.17.9
worker-2       Ready    <none>   45m   v1.17.9
```

## Smoke tests

### Metrics

Verify if the metrics server addon was correctly installed and works:

```ShellSession
kubectl top nodes
```

> Output

```ShellSession
NAME           CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
controller-0   191m         10%    1956Mi          26%
controller-1   190m         10%    1828Mi          24%
controller-2   182m         10%    1839Mi          24%
worker-0       87m          4%     1265Mi          16%
worker-1       102m         5%     1268Mi          16%
worker-2       108m         5%     1299Mi          17%
```

Please note that metrics might not be available at first and need a couple of
 minutes before you can actually retrieve them.

### Network

Let's verify if the network layer is properly functioning and pods can reach
each other:

```ShellSession
kubectl run myshell1 -it --rm --image busybox -- sh
hostname -i
# launch myshell2 in separate terminal (see next code block) and ping the hostname of myshell2
ping <hostname myshell2>
```

```ShellSession
kubectl run myshell2 -it --rm --image busybox -- sh
hostname -i
ping <hostname myshell1>
```

> Output

```ShellSession
PING 10.233.108.2 (10.233.108.2): 56 data bytes
64 bytes from 10.233.108.2: seq=0 ttl=62 time=2.876 ms
64 bytes from 10.233.108.2: seq=1 ttl=62 time=0.398 ms
64 bytes from 10.233.108.2: seq=2 ttl=62 time=0.378 ms
^C
--- 10.233.108.2 ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 0.378/1.217/2.876 ms
```

### Deployments

In this section you will verify the ability to create and manage [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

Create a deployment for the [nginx](https://nginx.org/en/) web server:

```ShellSession
kubectl create deployment nginx --image=nginx
```

List the pod created by the `nginx` deployment:

```ShellSession
kubectl get pods -l app=nginx
```

> Output

```ShellSession
NAME                     READY   STATUS    RESTARTS   AGE
nginx-86c57db685-bmtt8   1/1     Running   0          18s
```

#### Port Forwarding

In this section you will verify the ability to access applications remotely using [port forwarding](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/).

Retrieve the full name of the `nginx` pod:

```ShellSession
POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath="{.items[0].metadata.name}")
```

Forward port `8080` on your local machine to port `80` of the `nginx` pod:

```ShellSession
kubectl port-forward $POD_NAME 8080:80
```

> Output

```ShellSession
Forwarding from 127.0.0.1:8080 -> 80
Forwarding from [::1]:8080 -> 80
```

In a new terminal make an HTTP request using the forwarding address:

```ShellSession
curl --head http://127.0.0.1:8080
```

> Output

```ShellSession
HTTP/1.1 200 OK
Server: nginx/1.19.1
Date: Thu, 13 Aug 2020 11:12:04 GMT
Content-Type: text/html
Content-Length: 612
Last-Modified: Tue, 07 Jul 2020 15:52:25 GMT
Connection: keep-alive
ETag: "5f049a39-264"
Accept-Ranges: bytes
```

Switch back to the previous terminal and stop the port forwarding to the `nginx` pod:

```ShellSession
Forwarding from 127.0.0.1:8080 -> 80
Forwarding from [::1]:8080 -> 80
Handling connection for 8080
^C
```

#### Logs

In this section you will verify the ability to [retrieve container logs](https://kubernetes.io/docs/concepts/cluster-administration/logging/).

Print the `nginx` pod logs:

```ShellSession
kubectl logs $POD_NAME
```

> Output

```ShellSession
...
127.0.0.1 - - [13/Aug/2020:11:12:04 +0000] "HEAD / HTTP/1.1" 200 0 "-" "curl/7.64.1" "-"
```

#### Exec

In this section you will verify the ability to [execute commands in a container](https://kubernetes.io/docs/tasks/debug/debug-application/get-shell-running-container/#running-individual-commands-in-a-container).

Print the nginx version by executing the `nginx -v` command in the `nginx` container:

```ShellSession
kubectl exec -ti $POD_NAME -- nginx -v
```

> Output

```ShellSession
nginx version: nginx/1.19.1
```

### Kubernetes services

#### Expose outside the cluster

In this section you will verify the ability to expose applications using a [Service](https://kubernetes.io/docs/concepts/services-networking/service/).

Expose the `nginx` deployment using a [NodePort](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport) service:

```ShellSession
kubectl expose deployment nginx --port 80 --type NodePort
```

> The LoadBalancer service type can not be used because your cluster is not configured with [cloud provider integration](https://kubernetes.io/docs/getting-started-guides/scratch/#cloud-provider). Setting up cloud provider integration is out of scope for this tutorial.

Retrieve the node port assigned to the `nginx` service:

```ShellSession
NODE_PORT=$(kubectl get svc nginx \
  --output=jsonpath='{range .spec.ports[0]}{.nodePort}')
```

Create a firewall rule that allows remote access to the `nginx` node port:

```ShellSession
gcloud compute firewall-rules create kubernetes-the-kubespray-way-allow-nginx-service \
  --allow=tcp:${NODE_PORT} \
  --network kubernetes-the-kubespray-way
```

Retrieve the external IP address of a worker instance:

```ShellSession
EXTERNAL_IP=$(gcloud compute instances describe worker-0 \
  --format 'value(networkInterfaces[0].accessConfigs[0].natIP)')
```

Make an HTTP request using the external IP address and the `nginx` node port:

```ShellSession
curl -I http://${EXTERNAL_IP}:${NODE_PORT}
```

> Output

```ShellSession
HTTP/1.1 200 OK
Server: nginx/1.19.1
Date: Thu, 13 Aug 2020 11:15:02 GMT
Content-Type: text/html
Content-Length: 612
Last-Modified: Tue, 07 Jul 2020 15:52:25 GMT
Connection: keep-alive
ETag: "5f049a39-264"
Accept-Ranges: bytes
```

#### Local DNS

We will now also verify that kubernetes built-in DNS works across namespaces.
Create a namespace:

```ShellSession
kubectl create namespace dev
```

Create an nginx deployment and expose it within the cluster:

```ShellSession
kubectl create deployment nginx --image=nginx -n dev
kubectl expose deployment nginx --port 80 --type ClusterIP -n dev
```

Run a temporary container to see if we can reach the service from the default
namespace:

```ShellSession
kubectl run curly -it --rm --image curlimages/curl:7.70.0 -- /bin/sh
curl --head http://nginx.dev:80
```

> Output

```ShellSession
HTTP/1.1 200 OK
Server: nginx/1.19.1
Date: Thu, 13 Aug 2020 11:15:59 GMT
Content-Type: text/html
Content-Length: 612
Last-Modified: Tue, 07 Jul 2020 15:52:25 GMT
Connection: keep-alive
ETag: "5f049a39-264"
Accept-Ranges: bytes
```

Type `exit` to leave the shell.

## Cleaning Up

### Kubernetes resources

Delete the dev namespace, the nginx deployment and service:

```ShellSession
kubectl delete namespace dev
kubectl delete deployment nginx
kubectl delete svc/nginx
```

### Kubernetes state

Note: you can skip this step if you want to entirely remove the machines.

If you want to keep the VMs and just remove the cluster state, you can simply
 run another Ansible playbook:

```ShellSession
ansible-playbook -i inventory/mycluster/ -u $USERNAME -b -v --private-key=~/.ssh/id_rsa reset.yml
```

Resetting the cluster to the VMs original state usually takes about a couple
of minutes.

### Compute instances

Delete the controller and worker compute instances:

```ShellSession
gcloud -q compute instances delete \
  controller-0 controller-1 controller-2 \
  worker-0 worker-1 worker-2 \
  --zone $(gcloud config get-value compute/zone)
  ```

<!-- markdownlint-disable no-duplicate-heading -->
### Network
<!-- markdownlint-enable no-duplicate-heading -->

Delete the fixed IP addresses (assuming you named them equal to the VM names),
if any:

```ShellSession
gcloud -q compute addresses delete controller-0 controller-1 controller-2 \
  worker-0 worker-1 worker-2
```

Delete the `kubernetes-the-kubespray-way` firewall rules:

```ShellSession
gcloud -q compute firewall-rules delete \
  kubernetes-the-kubespray-way-allow-nginx-service \
  kubernetes-the-kubespray-way-allow-internal \
  kubernetes-the-kubespray-way-allow-external
```

Delete the `kubernetes-the-kubespray-way` network VPC:

```ShellSession
gcloud -q compute networks subnets delete kubernetes
gcloud -q compute networks delete kubernetes-the-kubespray-way
```
