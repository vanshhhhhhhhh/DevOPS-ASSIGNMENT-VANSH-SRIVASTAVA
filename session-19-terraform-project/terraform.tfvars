# No secrets in here, so this file is committed.
# Real AWS: set use_localstack = false, run `aws configure`, choose your own bucket_name
# and put your own public IP (curl -s https://checkip.amazonaws.com) in ssh_allowed_cidr.

aws_region          = "ap-south-1"
project_name        = "s19-webapp"
environment         = "dev"
vpc_cidr            = "10.20.0.0/16"
public_subnet_cidr  = "10.20.1.0/24"
private_subnet_cidr = "10.20.2.0/24"
instance_type       = "t3.micro"
bucket_name         = "vansh-24bcs10567-s19-site"
ssh_allowed_cidr    = "203.0.113.10/32" # documentation-range placeholder, not a real admin IP
use_localstack      = true
