output "target" {
  description = "Where Terraform sent the API calls."
  value       = var.use_localstack ? "LocalStack (${var.localstack_endpoint})" : "AWS"
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet."
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet."
  value       = aws_subnet.private.id
}

output "internet_gateway_id" {
  description = "ID of the internet gateway."
  value       = aws_internet_gateway.main.id
}

output "security_group_id" {
  description = "ID of the web security group."
  value       = aws_security_group.web.id
}

output "ami_id" {
  description = "AMI the instance was launched from."
  value       = data.aws_ami.al2023.id
}

output "instance_id" {
  description = "ID of the web server instance."
  value       = aws_instance.web.id
}

output "instance_public_ip" {
  description = "Public IP of the web server."
  value       = aws_instance.web.public_ip
}

output "instance_private_ip" {
  description = "Private IP of the web server inside the public subnet."
  value       = aws_instance.web.private_ip
}

output "website_url" {
  description = "URL the web server answers on (real AWS only; LocalStack instances are mocks)."
  value       = "http://${aws_instance.web.public_ip}"
}

output "site_bucket" {
  description = "Bucket that stores the site content."
  value       = aws_s3_bucket.site.bucket
}

output "web_role_arn" {
  description = "IAM role attached to the instance."
  value       = aws_iam_role.web.arn
}
