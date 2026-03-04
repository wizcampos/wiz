output "cluster_name" {
  value = google_container_cluster.wiz_cluster.name
}

output "network_name" {
  value = google_compute_network.wiz_vpc.name
}