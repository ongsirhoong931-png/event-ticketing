output "alb_public_url" {
  description = "Public URL for presentation and grading"
  value       = "http://${aws_lb.tarumt_alb.dns_name}"
}

output "rds_private_endpoint" {
  description = "Private RDS MySQL address"
  value       = aws_db_instance.mysql.address
}

output "s3_bucket_name" {
  description = "Name of the S3 media bucket"
  value       = aws_s3_bucket.assets.id
}