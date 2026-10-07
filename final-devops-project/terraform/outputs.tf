output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (one per AZ)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (one per AZ)."
  value       = aws_subnet.private[*].id
}

output "security_group_ids" {
  description = "Security group per tier."
  value = {
    web = aws_security_group.web.id
    app = aws_security_group.app.id
    db  = aws_security_group.db.id
  }
}

output "backup_bucket" {
  description = "S3 bucket for database backups and CI artifacts."
  value       = aws_s3_bucket.backups.bucket
}

output "tf_lock_table" {
  description = "DynamoDB table for Terraform state locking."
  value       = aws_dynamodb_table.tf_locks.name
}
