resource "google_compute_network" "wiz_vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "private_subnet" {
  name          = "wiz-private-subnet"
  ip_cidr_range = "10.20.0.0/16"
  region        = var.region
  network       = google_compute_network.wiz_vpc.id
}

resource "google_container_cluster" "wiz_cluster" {
  name     = var.gke_cluster_name
  location = var.region

  network    = google_compute_network.wiz_vpc.name
  subnetwork = google_compute_subnetwork.private_subnet.name

  remove_default_node_pool = true
  initial_node_count       = 1
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "default-pool"
  location   = var.region
  cluster    = google_container_cluster.wiz_cluster.name

  node_config {
    machine_type = "e2-medium"
  }

  node_count = 1
}