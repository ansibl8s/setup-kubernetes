
module "kubernetes" {
  source = "./modules/kubernetes-cluster"

  zone = var.zone


  machines = var.machines

  ssh_public_keys = var.ssh_public_keys

  datacenter    = var.datacenter
  location      = var.location
  ip_block_size = var.ip_block_size
}

data "template_file" "inventory" {
  template = file("${path.module}/templates/inventory.tpl")

  vars = {
    connection_strings_master = join("\n", formatlist("%s ansible_user=root ansible_host=%s etcd_member_name=etcd%d",
      keys(module.kubernetes.master_ip),
      values(module.kubernetes.master_ip),
    range(1, length(module.kubernetes.master_ip) + 1)))
    connection_strings_worker = join("\n", formatlist("%s ansible_user=root ansible_host=%s",
      keys(module.kubernetes.worker_ip),
    values(module.kubernetes.worker_ip)))
    list_master = join("\n", formatlist("%s",
    keys(module.kubernetes.master_ip)))
    list_worker = join("\n", formatlist("%s",
    keys(module.kubernetes.worker_ip)))
  }
}

resource "null_resource" "inventories" {
  provisioner "local-exec" {
    command = "echo '${data.template_file.inventory.rendered}' > ${var.inventory_file}"
  }

  triggers = {
    template = data.template_file.inventory.rendered
  }
}
