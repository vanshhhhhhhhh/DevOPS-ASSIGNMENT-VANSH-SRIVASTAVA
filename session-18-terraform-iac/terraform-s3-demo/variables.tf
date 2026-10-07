variable "aws_region" {
  description = "AWS region for the bucket."
  type        = string
  default     = "ap-south-1"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name (3-63 chars, lowercase, digits, dots, hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 characters of lowercase letters, digits, dots or hyphens."
  }
}

variable "environment" {
  description = "Environment name used in tags (dev, test, prod)."
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name used in default tags."
  type        = string
  default     = "session-18-terraform-s3-demo"
}

variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "vansh-srivastava"
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
