# The AWS provider is pointed at LocalStack (a local AWS emulator) instead of a
# real account: fake credentials, every service endpoint overridden, and
# path-style S3 URLs (http://localhost:4566/<bucket>).
provider "aws" {
  region     = var.aws_region
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    ec2      = var.localstack_endpoint
    s3       = var.localstack_endpoint
    dynamodb = var.localstack_endpoint
    sts      = var.localstack_endpoint
    iam      = var.localstack_endpoint
  }

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "vansh-srivastava-24bcs10567" # S3 tag values may not contain ( )
    }
  }
}
