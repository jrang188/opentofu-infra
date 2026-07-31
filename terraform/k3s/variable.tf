variable "hcloud_token" {
  sensitive = true
  default   = ""
}

variable "robot_user" {
  sensitive = true
  default   = ""
}

variable "robot_password" {
  sensitive = true
  default   = ""
}

variable "kubernetes_distribution" {
  type        = string
  default     = "k3s"
  description = "Kubernetes distribution type. Can be either k3s or rke2."
}

variable "ingress_controller" {
  type        = string
  default     = "traefik"
  description = "The ingress controller to deploy. Valid values are traefik, nginx, haproxy, none, and custom."
}

variable "ingress_replica_count" {
  type        = number
  default     = 0
  description = "Number of replicas per ingress controller. 0 means autodetect based on the number of agent nodes."
}

variable "cluster_name" {
  type        = string
  default     = "k3s"
  description = "Name of the cluster."
}
