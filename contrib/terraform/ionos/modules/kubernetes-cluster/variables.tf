
variable "datacenter" {
  type    = string
  # default = "kubespray-default-datacenter"
}
variable "location" {
  type    = string
  # default = "de/txl"
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "List of SSH keys to be added to the VMs"

}
variable "ip_block_size" {
  type = number
}

variable "zone" {
  description = "zone of the data center"
}


variable "boot_image" {
  description = "Ubuntu Server"
  default     = "ubuntu-20.04"
}


variable "image_name" {
  description = "name of the image"
  default     = "ubuntu"
}



variable "disk_type" {
  description = "type of hard drive"
  default     = "SSD"
}

variable "machines" {
  description = "Cluster machines"
  type = map(object({
    index = number
    name = string
    node_type = string
    cpu      = string
    mem      = string
    disk_size = number
  }))
}
