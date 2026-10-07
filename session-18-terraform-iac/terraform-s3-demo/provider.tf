terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# One provider block for both targets.
# use_localstack = true  -> fake "test" credentials + every API call goes to LocalStack.
# use_localstack = false -> normal AWS credential chain (aws configure / env vars / SSO)
#                           and the real AWS endpoints. The LocalStack-only arguments
#                           below become null/false and are ignored.
provider "aws" {
  region = var.aws_region

  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null

  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  # LocalStack serves every bucket under one host, so use
  # http://localhost:4566/<bucket> instead of http://<bucket>.localhost:4566
  s3_use_path_style = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      s3  = var.localstack_endpoint
      sts = var.localstack_endpoint
    }
  }

  default_tags {
    tags = {
      Project   = var.project
      Owner     = var.owner
      ManagedBy = "Terraform"
    }
  }
}
