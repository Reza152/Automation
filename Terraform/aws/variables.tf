variable "aws_region" {
  description = "AWS region yang digunakan"
  type        = string
}

variable "servers" {
  description = "Daftar server yang akan dibuat"

  type = map(object({
    os            = string
    instance_type = string
    group         = string
    disk_size     = optional(number)
  }))
}