resource "aws_s3_bucket" "this" {
  bucket        = var.bucket
  force_destroy = var.force_destroy

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = var.sse_algorithm == "aws:kms" ? var.kms_key_id : null
    }

    # S3 Bucket Keys cut KMS request cost for object-heavy buckets. They are
    # meaningless for SSE-S3, so only set the flag for SSE-KMS.
    bucket_key_enabled = var.sse_algorithm == "aws:kms" ? var.bucket_key_enabled : null
  }

  lifecycle {
    precondition {
      condition     = var.kms_key_id == null || var.sse_algorithm == "aws:kms"
      error_message = "kms_key_id is only used when sse_algorithm is \"aws:kms\"; set sse_algorithm = \"aws:kms\" or drop kms_key_id."
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  count = var.block_public_access ? 1 : 0

  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disabling ACLs is the AWS-recommended posture: it makes the bucket owner the
# owner of every object and removes ACLs as a way to grant access, so public
# exposure can only ever come from a bucket policy.
resource "aws_s3_bucket_ownership_controls" "this" {
  count = var.object_ownership == null ? 0 : 1

  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = var.object_ownership
  }
}

# Deny any request that did not arrive over TLS. Without this, S3 happily
# serves the bucket over plain HTTP and credentials/objects travel in cleartext.
locals {
  tls_only_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
    ]
  })
}

resource "aws_s3_bucket_policy" "this" {
  count = var.enforce_tls ? 1 : 0

  bucket = aws_s3_bucket.this.id
  policy = local.tls_only_policy

  # The public access block evaluates every PutBucketPolicy call. Creating both
  # in the same apply without ordering can fail with AccessDenied.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_logging" "this" {
  count = var.logging_target_bucket == null ? 0 : 1

  bucket = aws_s3_bucket.this.id

  target_bucket = var.logging_target_bucket
  target_prefix = var.logging_target_prefix
}
