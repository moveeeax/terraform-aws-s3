# Confirms the opt-out knobs and input validation behave as documented.

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

run "kms_encryption_uses_the_supplied_key" {
  command = apply

  variables {
    sse_algorithm = "aws:kms"
    kms_key_id    = "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "sse_algorithm must be passed through to the bucket."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).kms_master_key_id == "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"
    error_message = "kms_key_id must be passed through when sse_algorithm is aws:kms."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).bucket_key_enabled == true
    error_message = "S3 Bucket Keys must be enabled by default for SSE-KMS."
  }
}

run "versioning_can_be_suspended" {
  command = apply

  variables {
    versioning_enabled = false
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Suspended"
    error_message = "versioning_enabled = false must suspend versioning."
  }
}

run "opting_out_removes_the_optional_resources" {
  command = apply

  variables {
    block_public_access = false
    enforce_tls         = false
    object_ownership    = null
  }

  assert {
    condition     = length(aws_s3_bucket_public_access_block.this) == 0
    error_message = "block_public_access = false must not create a public access block."
  }

  assert {
    condition     = length(aws_s3_bucket_policy.this) == 0
    error_message = "enforce_tls = false must not create a bucket policy."
  }

  assert {
    condition     = length(aws_s3_bucket_ownership_controls.this) == 0
    error_message = "object_ownership = null must leave ownership controls unmanaged."
  }
}

run "access_logging_is_wired_when_a_target_is_given" {
  command = apply

  variables {
    logging_target_bucket = "central-log-bucket"
    logging_target_prefix = "buckets/unit-test-bucket/"
  }

  assert {
    condition     = aws_s3_bucket_logging.this[0].target_bucket == "central-log-bucket"
    error_message = "logging_target_bucket must be passed through."
  }

  assert {
    condition     = aws_s3_bucket_logging.this[0].target_prefix == "buckets/unit-test-bucket/"
    error_message = "logging_target_prefix must be passed through."
  }
}

run "rejects_an_uppercase_bucket_name" {
  command = plan

  variables {
    bucket = "Not-A-Valid-Bucket"
  }

  expect_failures = [var.bucket]
}

run "rejects_a_bucket_name_shaped_like_an_ip_address" {
  command = plan

  variables {
    bucket = "192.168.0.1"
  }

  expect_failures = [var.bucket]
}

run "rejects_a_bucket_name_with_adjacent_periods" {
  command = plan

  variables {
    bucket = "not..a.valid.bucket"
  }

  expect_failures = [var.bucket]
}

run "rejects_an_empty_kms_key_id" {
  command = plan

  variables {
    sse_algorithm = "aws:kms"
    kms_key_id    = ""
  }

  expect_failures = [var.kms_key_id]
}

run "rejects_a_whitespace_only_logging_target_bucket" {
  command = plan

  variables {
    logging_target_bucket = "   "
  }

  expect_failures = [var.logging_target_bucket]
}

run "rejects_an_unsupported_sse_algorithm" {
  command = plan

  variables {
    sse_algorithm = "AES128"
  }

  expect_failures = [var.sse_algorithm]
}

run "rejects_a_kms_key_without_kms_encryption" {
  command = plan

  variables {
    sse_algorithm = "AES256"
    kms_key_id    = "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"
  }

  expect_failures = [aws_s3_bucket_server_side_encryption_configuration.this]
}
