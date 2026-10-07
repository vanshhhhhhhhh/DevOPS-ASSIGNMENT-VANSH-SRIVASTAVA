output "bucket_name" {
  description = "Name of the S3 bucket."
  value       = aws_s3_bucket.demo.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.demo.arn
}

output "bucket_region" {
  description = "Region the bucket lives in."
  value       = aws_s3_bucket.demo.region
}

output "versioning_status" {
  description = "Versioning state of the bucket."
  value       = aws_s3_bucket_versioning.demo.versioning_configuration[0].status
}

output "encryption_algorithm" {
  description = "Default server-side encryption algorithm."
  value = one([
    for r in aws_s3_bucket_server_side_encryption_configuration.demo.rule :
    r.apply_server_side_encryption_by_default[0].sse_algorithm
  ])
}

output "target" {
  description = "Where Terraform sent the API calls."
  value       = var.use_localstack ? "LocalStack (${var.localstack_endpoint})" : "AWS"
}
