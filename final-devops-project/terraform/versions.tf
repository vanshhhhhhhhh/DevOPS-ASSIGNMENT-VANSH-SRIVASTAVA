terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State stays local for this LocalStack lab (it is git-ignored). The S3 bucket
  # and DynamoDB table created below are what a remote "s3" backend with state
  # locking would use on real AWS; see backend-s3.tf.example.
}
