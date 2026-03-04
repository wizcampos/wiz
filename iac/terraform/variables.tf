variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-east1"
}

variable "network_name" {
  default = "wiz-vpc"
}

variable "gke_cluster_name" {
  default = "wiz-gke-cluster"
}