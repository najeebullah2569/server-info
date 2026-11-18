variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "roboshop"
}

variable "environment" {
  type    = string
  default = "prod"
}

# ---------- Network ----------
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to spread instances across (min 2 for ALB/RDS Multi-AZ)."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "true = one NAT GW (cheaper, lab). false = one NAT GW per AZ (production HA)."
  type        = bool
  default     = false
}

variable "admin_cidr" {
  description = "Your public IP in CIDR form (e.g. 203.0.113.10/32). Only this can SSH to the bastion."
  type        = string
}

# ---------- DNS ----------
variable "domain_name" {
  description = "Existing public Route53 hosted zone you own, e.g. example.com"
  type        = string
}

variable "app_subdomain" {
  description = "Public hostname prefix: <app_subdomain>.<domain_name>"
  type        = string
  default     = "roboshop"
}

variable "private_zone_name" {
  description = "Private Route53 zone used for internal service discovery."
  type        = string
  default     = "roboshop.internal"
}

# ---------- Compute ----------
variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/roboshop.pub"
}

variable "ssh_private_key_path" {
  description = "Written into the generated Ansible inventory."
  type        = string
  default     = "~/.ssh/roboshop"
}

variable "bastion_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "web_count" {
  type    = number
  default = 2
}

variable "web_instance_type" {
  type    = string
  default = "t3.small"
}

variable "app_count" {
  type    = number
  default = 2
}

variable "app_instance_type" {
  description = "Java + Maven build needs >= 4 GB RAM."
  type        = string
  default     = "t3.medium"
}

variable "app_health_check_path" {
  type    = string
  default = "/health"
}

# ---------- Database ----------
variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_multi_az" {
  type    = bool
  default = true
}

variable "db_deletion_protection" {
  description = "Set false for labs so 'terraform destroy' works without a final snapshot."
  type        = bool
  default     = true
}
