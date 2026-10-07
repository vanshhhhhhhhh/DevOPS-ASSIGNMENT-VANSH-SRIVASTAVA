terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State is local (terraform.tfstate) by default.
  # See backend.tf.example for the remote S3 backend with locking.
}
