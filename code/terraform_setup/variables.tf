variable "flavor" {
  description = "Default worker node flaver. Use 'ibmcloud ks flavors --zone us-south-1' to verify the availability."
}

variable "worker_count" {
  description = "Default worker node count is set to 2."
}

variable "kubernetes_pricing" {
  description = "Kubernetes Cluster pricing."
}

variable "resource_group" {
  description = "IBM Cloud resource group name."
}

variable "vpc_name" {
  description = "The Virtual Private Cloud name."
}

variable "region" {
  description = "IBM Cloud region for the Kubernetes Cluster and the VPC"
}

variable "kube_version" {
  description = "The tested Kubernetes Cluster version for the example is 1.23.8."
}

variable "cluster_name" {
  description = "Kubernetes Cluster Name running in VPC Gen2."
}