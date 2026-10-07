variable "project" {
  description = "Name prefix for every resource."
  type        = string
  default     = "final-ticketdesk"
}

variable "environment" {
  description = "Environment tag."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region (LocalStack accepts any region)."
  type        = string
  default     = "ap-south-1"
}

variable "localstack_endpoint" {
  description = "LocalStack edge endpoint used for every AWS service."
  type        = string
  default     = "http://localhost:4566"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "availability_zones" {
  description = "Two AZs, one public and one private subnet in each."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnets (load balancer / ingress tier)."
  type        = list(string)
  default     = ["10.42.1.0/24", "10.42.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnets (Kubernetes nodes and the database)."
  type        = list(string)
  default     = ["10.42.11.0/24", "10.42.12.0/24"]
}

variable "backup_bucket_name" {
  description = "Globally unique S3 bucket name for database backups and build artifacts."
  type        = string
  default     = "final-ticketdesk-backups-24bcs10567"
}

variable "backup_retention_days" {
  description = "How long old (non-current) object versions are kept."
  type        = number
  default     = 30
}
