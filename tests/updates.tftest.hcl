# Guards behavior across an update, not just a single apply. Round 1's suite
# only ever created a bucket once per run; nothing proved that flipping
# several optional settings together on an existing bucket lands correctly
# and updates the bucket in place instead of replacing it.

mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = {
      id                          = "unit-test-bucket"
      arn                         = "arn:aws:s3:::unit-test-bucket"
      bucket_domain_name          = "unit-test-bucket.s3.amazonaws.com"
      bucket_regional_domain_name = "unit-test-bucket.s3.us-east-1.amazonaws.com"
      hosted_zone_id              = "Z3AQBSTGFYJSTF"
    }
  }
}

variables {
  bucket = "unit-test-bucket"
}

run "created_with_secure_defaults" {
  command = apply

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must start out enabled."
  }

  assert {
    condition     = length(aws_s3_bucket_logging.this) == 0
    error_message = "Access logging must start out disabled."
  }
}

run "multiple_optional_settings_flip_together_without_replacing_the_bucket" {
  command = apply

  variables {
    versioning_enabled    = false
    sse_algorithm         = "aws:kms"
    kms_key_id            = "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"
    object_ownership      = "BucketOwnerPreferred"
    logging_target_bucket = "central-log-bucket"
    logging_target_prefix = "buckets/unit-test-bucket/"
  }

  assert {
    condition     = aws_s3_bucket.this.id == "unit-test-bucket"
    error_message = "Flipping several optional settings together must update the existing bucket in place, not replace it."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Suspended"
    error_message = "versioning_enabled = false must suspend versioning even when combined with other changes."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "sse_algorithm must switch to aws:kms alongside the other changes."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).kms_master_key_id == "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"
    error_message = "kms_key_id must switch over alongside sse_algorithm."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.this[0].rule[0].object_ownership == "BucketOwnerPreferred"
    error_message = "object_ownership must switch to BucketOwnerPreferred alongside the other changes."
  }

  assert {
    condition     = aws_s3_bucket_logging.this[0].target_bucket == "central-log-bucket"
    error_message = "Access logging must turn on alongside the other changes."
  }

  assert {
    condition     = length(aws_s3_bucket_public_access_block.this) == 1
    error_message = "Settings that were not touched by this update, like the public access block, must be left intact."
  }
}
