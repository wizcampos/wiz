resource "google_compute_network" "wiz_vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "gke_subnet" {
  name          = "gke-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.wiz_vpc.id
}

resource "google_compute_subnetwork" "vm_subnet" {
  name          = "vm-subnet"
  ip_cidr_range = "10.20.0.0/24"
  region        = var.region
  network       = google_compute_network.wiz_vpc.id
}

resource "google_container_cluster" "wiz_cluster" {
  name     = var.gke_cluster_name
  location = var.region

  network    = google_compute_network.wiz_vpc.name
  subnetwork = google_compute_subnetwork.gke_subnet.name

  remove_default_node_pool = true
  initial_node_count       = 1
}

resource "google_container_node_pool" "default_nodes" {
  name       = "default-pool"
  cluster    = google_container_cluster.wiz_cluster.name
  location   = var.region
  node_count = 1

  node_config {
    machine_type = "e2-medium"
  }
}