variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Short name used as a prefix for every resource name."
  type        = string
  default     = "s19-webapp"
}

variable "environment" {
  description = "Environment name (dev, test, prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be dev, test or prod."
  }
}

variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "vansh-srivastava"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block of the public subnet (route to the internet gateway)."
  type        = string
  default     = "10.20.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block of the private subnet (no route to the internet)."
  type        = string
  default     = "10.20.2.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for the web server."
  type        = string
  default     = "t3.micro"
}

variable "ami_name_pattern" {
  description = "Name filter for the Amazon-owned AMI lookup (Amazon Linux 2023, x86_64)."
  type        = string
  default     = "al2023-ami-2023.*-kernel-6.1-x86_64"
}

variable "ssh_allowed_cidr" {
  description = "Single CIDR allowed to SSH to the instance. null = no SSH rule at all."
  type        = string
  default     = null
}

variable "bucket_name" {
  description = "Globally unique name of the S3 bucket that holds the site content."
  type        = string
}

variable "use_localstack" {
  description = "true = send all AWS API calls to LocalStack with fake credentials, false = real AWS."
  type        = bool
  default     = false
}

variable "localstack_endpoint" {
  description = "LocalStack edge URL, only used when use_localstack = true."
  type        = string
  default     = "http://localhost:4566"
}
