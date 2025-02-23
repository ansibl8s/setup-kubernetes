resource "null_resource" "dummy_dependency" {
  triggers = {
    dependency_id = var.router_id
  }
  depends_on = [
    var.router_internal_port_id
  ]
}

# If user specifies pre-existing IPs to use in k8s_master_fips, do not create new ones.
resource "openstack_networking_floatingip_v2" "k8s_master" {
  count      = length(var.k8s_master_fips) > 0 ? 0 : var.number_of_k8s_masters
  pool       = var.floatingip_pool
  depends_on = [null_resource.dummy_dependency]
}

resource "openstack_networking_floatingip_v2" "k8s_masters" {
  for_each   = var.number_of_k8s_masters == 0 && var.number_of_k8s_masters_no_etcd == 0 ? { for key, value in var.k8s_masters : key => value if value.floating_ip && (lookup(value, "reserved_floating_ip", "") == "") } : tomap({})
  pool       = var.floatingip_pool
  depends_on = [null_resource.dummy_dependency]
}

# If user specifies pre-existing IPs to use in k8s_master_fips, do not create new ones.
resource "openstack_networking_floatingip_v2" "k8s_master_no_etcd" {
  count      = length(var.k8s_master_fips) > 0 ? 0 : var.number_of_k8s_masters_no_etcd
  pool       = var.floatingip_pool
  depends_on = [null_resource.dummy_dependency]
}

resource "openstack_networking_floatingip_v2" "k8s_node" {
  count      = var.number_of_k8s_nodes
  pool       = var.floatingip_pool
  depends_on = [null_resource.dummy_dependency]
}

resource "openstack_networking_floatingip_v2" "bastion" {
  count      = length(var.bastion_fips) > 0 ? 0 : var.number_of_bastions
  pool       = var.floatingip_pool
  depends_on = [null_resource.dummy_dependency]
}

resource "openstack_networking_floatingip_v2" "k8s_nodes" {
  for_each   = var.number_of_k8s_nodes == 0 ? { for key, value in var.k8s_nodes : key => value if value.floating_ip && (lookup(value, "reserved_floating_ip", "") == "") } : tomap({})
  pool       = var.floatingip_pool
  depends_on = [null_resource.dummy_dependency]
}
