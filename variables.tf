variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "name" {
  type        = string
  description = "Name prefix for all resources"
  default     = "vpc-project"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "vpc_cidr" {
  type        = string
  description = "Primary VPC CIDR. The subnet maths below assumes a /16."
  default     = "10.0.0.0/16"
}

variable "az_count" {
  type        = number
  description = "Number of Availability Zones to use"
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "single_nat_gateway" {
  type        = bool
  description = "Use one shared NAT gateway. Cheaper, but not highly available. Intended for dev and staging only."
  default     = false
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "db_port" {
  type    = number
  default = 5432
}
