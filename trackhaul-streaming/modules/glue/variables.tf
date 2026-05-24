variable "database_name" {
  type = string
}

variable "table_name" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}