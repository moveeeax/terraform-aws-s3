output "bucket_arn" {
  description = "ARN of the bucket created by the example."
  value       = module.s3.arn
}
