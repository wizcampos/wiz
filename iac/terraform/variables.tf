variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "clgcporg10-178"
}

variable "region" {
  description = "Deployment region"
  type        = string
  default     = "us-east1"
}

variable "vpc_name" {
  default = "wiz-vpc"
}

variable "gke_cluster_name" {
  default = "wiz-gke-cluster"
}