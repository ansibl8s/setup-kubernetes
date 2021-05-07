output "master_ip" {
  value = {
    for instance in ionoscloud_server.master :
    instance.name => instance.primary_ip
 }
} 
output "worker_ip" {
  value = {
    for instance in ionoscloud_server.worker :
    instance.name => instance.primary_ip
  }
}
