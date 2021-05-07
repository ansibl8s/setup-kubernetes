resource "ionoscloud_server" "master" {
  for_each = {
    for name, machine in var.machines :
    name => machine
    if machine.node_type == "master"
  }
  
  name              = each.value.name
  datacenter_id     = ionoscloud_datacenter.pg-data-center.id
  cores             = each.value.cpu
  ram               = each.value.mem
  availability_zone = var.zone
  boot_image        = var.boot_image
  ssh_key_path      = var.ssh_public_keys
  image_name        = var.image_name

  volume {
    size           = each.value.disk_size
    disk_type      = var.disk_type
  }

  nic {
    lan             = ionoscloud_lan.public_lan.id
    ip              = ionoscloud_ipblock.kubespray_ip.ips[0]
    dhcp            = true
    firewall_active = false
  }   
}


resource "ionoscloud_server" "worker" {
  for_each = {
    for name, machine in var.machines :
    name => machine
    if machine.node_type == "worker"
  }    
  name              = each.value.name
  datacenter_id     = ionoscloud_datacenter.pg-data-center.id
  cores             = each.value.cpu
  ram               = each.value.mem
  availability_zone = var.zone
  boot_image        = var.boot_image
  ssh_key_path      = var.ssh_public_keys
  image_name        = var.image_name

  volume {
    size           = each.value.disk_size
    disk_type      = var.disk_type
  }

  nic {
    lan             = ionoscloud_lan.public_lan.id
    ip              = ionoscloud_ipblock.kubespray_ip.ips[each.value.index]
    dhcp            = true
    firewall_active = false
  }
}
resource "ionoscloud_datacenter" "pg-data-center" {
  name        = var.datacenter
  location    = var.location
  description = "a vdc for kubespray"
}

resource "ionoscloud_lan" "public_lan" {
  datacenter_id = ionoscloud_datacenter.pg-data-center.id
  public        = true
  name          = "publicLAN"
}

resource "ionoscloud_ipblock" "kubespray_ip" {
  location = ionoscloud_datacenter.pg-data-center.location
  size     = var.ip_block_size
}

