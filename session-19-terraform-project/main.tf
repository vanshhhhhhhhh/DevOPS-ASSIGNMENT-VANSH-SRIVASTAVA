locals {
  name = "${var.project_name}-${var.environment}"

  # First two AZs of the region: public subnet in one, private subnet in the other.
  az_public  = data.aws_availability_zones.available.names[0]
  az_private = data.aws_availability_zones.available.names[1]
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Latest Amazon Linux 2023 AMI owned by Amazon (works on real AWS and on LocalStack).
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = [var.ami_name_pattern]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
