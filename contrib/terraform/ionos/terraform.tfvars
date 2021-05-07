zone = "ZONE_1"

inventory_file = "inventory.ini"

ssh_public_keys = [
  # Put your public SSH key here
  "/root/.ssh/id_rsa.pub",
  # "ssh-rsa public key 2",
]

# image_name = "ubuntu"

# boot_image = "ubuntu-20.04"

ip_block_size = 4

datacenter = "kubespray-default-datacenter"
location = "de/txl"

machines = {
  "master-0" : {
    "index" : "0",
    "name" : "master",
    "node_type" : "master",
    #number of cpu cores
    "cpu" : "2",
    #memory size in MB
    "mem" : "4096"
    # The size of the storage in GB
    "disk_size" : 50
  },
  "worker-0" : {
    "index" : "1",
    "name" : "worker-0",
    "node_type" : "worker",
    #number of cpu cores
    "cpu" : "2",
    #memory size in MB
    "mem" : "4096"
    # The size of the storage in GB
    "disk_size" : 80
  },
  "worker-1" : {
    "index" : "2",
    "name" : "worker-1",
    "node_type" : "worker",
    #number of cpu cores
    "cpu" : "2",
    #memory size in MB
    "mem" : "4096"
    # The size of the storage in GB
    "disk_size" : 80
  },
  "worker-2" : {
    "index" : "3",
    "name" : "worker-2",
    "node_type" : "worker",
    #number of cpu cores
    "cpu" : "2",
    #memory size in MB
    "mem" : "4096"
    # The size of the storage in GB
    "disk_size" : 80
  }
}

