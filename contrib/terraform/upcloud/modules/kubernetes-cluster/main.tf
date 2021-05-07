
resource "upcloud_server" "master" {
  for_each = {
    for name, machine in var.machines :
    name => machine
    if machine.node_type == "master"
  }

  hostname    = "${each.key}.${var.hostname}"
  cpu            = each.value.cpu
  mem       = each.value.mem
  zone            = var.zone

  template {
  storage = var.template_name
  size = each.value.disk_size
  }

  # Network interfaces
 network_interface {
   type = "public"
 }

 network_interface {
   type = "utility"
 }
 # Include at least one public SSH key
 login {
   user = var.username
   keys = var.ssh_public_keys
   create_password = false

 }

}


resource "upcloud_server" "worker" {
  for_each = {
    for name, machine in var.machines :
    name => machine
    if machine.node_type == "worker"
  }

  hostname    = "${each.key}.${var.hostname}"
  cpu            = each.value.cpu
  mem       = each.value.mem
  zone            = var.zone

  template {
  storage = var.template_name
  size = each.value.disk_size
  }

  # Network interfaces
 network_interface {
   type = "public"
 }

network_interface {
   type = "utility"
}

 # Include at least one public SSH key
 login {
   user = var.username
   keys = var.ssh_public_keys
   create_password = false
 }
}
