
variable "datacenter" {
  type = string
}
variable "location" {
  type = string
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


# variable "boot_image" {
#   description = "Ubuntu Server"
# }


# variable "image_name" {
#   description = "name of the image"
# }

variable "inventory_file" {
  description = "Where to store the generated inventory file"
}

# variable "disk_type" {
#   description = "type of hard drive"
#   default     = "SSD"
# }

variable "machines" {
  description = "Cluster machines"
  type = map(object({
    index = number
    name      = string
    node_type = string
    cpu       = string
    mem       = string
    disk_size = number
  }))
}
