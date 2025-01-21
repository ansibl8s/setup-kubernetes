# vSphere

Kubespray can be deployed with vSphere as Cloud provider. This feature supports:

- Volumes
- Persistent Volumes
- Storage Classes and provisioning of volumes
- vSphere Storage Policy Based Management for Containers orchestrated by Kubernetes

## Out-of-tree vSphere cloud provider

### Prerequisites

You need at first to configure your vSphere environment by following the [official documentation](https://github.com/kubernetes/cloud-provider-vsphere/blob/master/docs/book/tutorials/kubernetes-on-vsphere-with-kubeadm.md#prerequisites).

After this step you should have:

- vSphere upgraded to 6.7 U3 or later
- VM hardware upgraded to version 15 or higher
- UUID activated for each VM where Kubernetes will be deployed

### Kubespray configuration

First in `<inventory_path>/group_vars/all/all.yml` you must set the `cloud_provider` to `external` and `external_cloud_provider` to `vsphere`.

```yml
cloud_provider:  "external"
external_cloud_provider: "vsphere"
```

Then, `<inventory_path>/group_vars/all/vsphere.yml`, you need to declare your vCenter credentials and enable the vSphere CSI following the description below.

| Variable                               | Required | Type    | Choices                    | Default                   | Comment                                                                                                             |
|----------------------------------------|----------|---------|----------------------------|---------------------------|---------------------------------------------------------------------------------------------------------------------|
| external_vsphere_vcenter_ip            | TRUE     | string  |                            |                           | IP/URL of the vCenter                                                                                               |
| external_vsphere_vcenter_port          | TRUE     | string  |                            | "443"                     | Port of the vCenter API                                                                                             |
| external_vsphere_insecure              | TRUE     | string  | "true", "false"            | "true"                    | set to "true" if the host above uses a self-signed cert                                                             |
| external_vsphere_user                  | TRUE     | string  |                            |                           | User name for vCenter with required privileges (Can also be specified with the `VSPHERE_USER` environment variable) |
| external_vsphere_password              | TRUE     | string  |                            |                           | Password for vCenter (Can also be specified with the `VSPHERE_PASSWORD` environment variable)                       |
| external_vsphere_datacenter            | TRUE     | string  |                            |                           | Datacenter name to use                                                                                              |
| external_vsphere_kubernetes_cluster_id | TRUE     | string  |                            | "kubernetes-cluster-id"   | Kubernetes cluster ID to use                                                                                        |
| vsphere_csi_enabled                    | TRUE     | boolean |                            | false                     | Enable vSphere CSI                                                                                                  |

Example configuration:

```yml
external_vsphere_vcenter_ip: "myvcenter.domain.com"
external_vsphere_vcenter_port: "443"
external_vsphere_insecure: "true"
external_vsphere_user: "administrator@vsphere.local"
external_vsphere_password: "K8s_admin"
external_vsphere_datacenter: "DATACENTER_name"
external_vsphere_kubernetes_cluster_id: "kubernetes-cluster-id"
vsphere_csi_enabled: true
```

For a more fine-grained CSI setup, refer to the [vsphere-csi](/docs/CSI/vsphere-csi.md) documentation.

### Deployment

Once the configuration is set, you can execute the playbook again to apply the new configuration:

```ShellSession
cd kubespray
ansible-playbook -i <inventory_path>/hosts.ini -b -v cluster.yml
```

You'll find some useful examples [here](https://github.com/kubernetes/cloud-provider-vsphere/blob/master/docs/book/tutorials/kubernetes-on-vsphere-with-kubeadm.md#sample-manifests-to-test-csi-driver-functionality) to test your configuration.

## In-tree vSphere cloud provider ([deprecated](https://cloud-provider-vsphere.sigs.k8s.io/concepts/in_tree_vs_out_of_tree.html))

### Prerequisites (deprecated)

You need at first to configure your vSphere environment by following the [official documentation](https://kubernetes.io/docs/getting-started-guides/vsphere/#vsphere-cloud-provider).

After this step you should have:

- UUID activated for each VM where Kubernetes will be deployed
- A vSphere account with required privileges

If you intend to leverage the [zone and region node labeling](https://kubernetes.io/docs/reference/kubernetes-api/labels-annotations-taints/#failure-domain-beta-kubernetes-io-region), create a tag category for both the zone and region in vCenter.  The tags can then be applied at the host, cluster, datacenter, or folder level, and the cloud provider will walk the hierarchy to extract and apply the labels to the Kubernetes nodes.

### Kubespray configuration (deprecated)

First you must define the cloud provider in `<inventory_path>/group_vars/all.yml` and set it to `vsphere`.

```yml
cloud_provider: vsphere
```

Then, in the same file, you need to declare your vCenter credentials following the description below.

| Variable                     | Required | Type    | Choices                    | Default | Comment                                                                                                                                                                                                                                 |
|------------------------------|----------|---------|----------------------------|---------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| vsphere_vcenter_ip           | TRUE     | string  |                            |         | IP/URL of the vCenter                                                                                                                                                                                                                   |
| vsphere_vcenter_port         | TRUE     | integer |                            |         | Port of the vCenter API. Commonly 443                                                                                                                                                                                                   |
| vsphere_insecure             | TRUE     | integer | 1, 0                       |         | set to 1 if the host above uses a self-signed cert                                                                                                                                                                                      |
| vsphere_user                 | TRUE     | string  |                            |         | User name for vCenter with required privileges                                                                                                                                                                                          |
| vsphere_password             | TRUE     | string  |                            |         | Password for vCenter                                                                                                                                                                                                                    |
| vsphere_datacenter           | TRUE     | string  |                            |         | Datacenter name to use                                                                                                                                                                                                                  |
| vsphere_datastore            | TRUE     | string  |                            |         | Datastore name to use                                                                                                                                                                                                                   |
| vsphere_working_dir          | TRUE     | string  |                            |         | Working directory from the view "VMs and template" in the   vCenter where VM are placed                                                                                                                                                 |
| vsphere_scsi_controller_type | TRUE     | string  | buslogic, pvscsi, parallel | pvscsi  | SCSI controller name. Commonly "pvscsi".                                                                                                                                                                                                |
| vsphere_vm_uuid              | FALSE    | string  |                            |         | VM Instance UUID of virtual machine that host K8s master. Can be retrieved from instanceUuid property in VmConfigInfo, or as vc.uuid in VMX file or in `/sys/class/dmi/id/product_serial` (Optional, only used for Kubernetes <= 1.9.2) |
| vsphere_public_network       | FALSE    | string  |                            | Blank   | Name of the   network the VMs are joined to                                                                                                                                                                                             |
| vsphere_resource_pool        | FALSE    | string  |                            | Blank   | Name of the Resource pool where the VMs are located (Optional, only used for Kubernetes >= 1.9.2)                                                                                                                                       |
| vsphere_zone_category        | FALSE    | string  |                            |         | Name of the tag category used to set the `failure-domain.beta.kubernetes.io/zone` label on nodes (Optional, only used for Kubernetes >= 1.12.0)                                                                                         |
| vsphere_region_category      | FALSE    | string  |                            |         | Name of the tag category used to set the `failure-domain.beta.kubernetes.io/region` label on nodes (Optional, only used for Kubernetes >= 1.12.0)                                                                                       |

Example configuration:

```yml
vsphere_vcenter_ip: "myvcenter.domain.com"
vsphere_vcenter_port: 443
vsphere_insecure: 1
vsphere_user: "k8s@vsphere.local"
vsphere_password: "K8s_admin"
vsphere_datacenter: "DATACENTER_name"
vsphere_datastore: "DATASTORE_name"
vsphere_working_dir: "Docker_hosts"
vsphere_scsi_controller_type: "pvscsi"
vsphere_resource_pool: "K8s-Pool"
```

### Deployment (deprecated)

Once the configuration is set, you can execute the playbook again to apply the new configuration:

```ShellSession
cd kubespray
ansible-playbook -i <inventory_path>/hosts.ini -b -v cluster.yml
```

You'll find some useful examples [here](https://github.com/kubernetes/examples/tree/master/staging/volumes/vsphere) to test your configuration.
