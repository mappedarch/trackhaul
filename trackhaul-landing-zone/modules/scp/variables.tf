# modules/scp/variables.tf

variable "security_ou_id" {
  description = "Security OU ID"
  type        = string
}

variable "infrastructure_ou_id" {
  description = "Infrastructure OU ID"
  type        = string
}

variable "workloads_ou_id" {
  description = "Workloads OU ID"
  type        = string
}