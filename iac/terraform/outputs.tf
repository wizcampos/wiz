output "gke_cluster_name" {
  value = google_container_cluster.wiz_cluster.name
}

output "vpc_name" {
  value = google_compute_network.wiz_vpc.name
}