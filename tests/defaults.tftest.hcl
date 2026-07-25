# Guards the module's secure-by-default posture. These run entirely against a
# mocked AWS provider: no credentials, no network, no cost.

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

run "public_access_is_blocked_by_default" {
  command = apply

  assert {
    condition     = length(aws_s3_bucket_public_access_block.this) == 1
    error_message = "The public access block must be created by default."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this[0].block_public_acls,
      aws_s3_bucket_public_access_block.this[0].block_public_policy,
      aws_s3_bucket_public_access_block.this[0].ignore_public_acls,
      aws_s3_bucket_public_access_block.this[0].restrict_public_buckets,
    ])
    error_message = "All four public access block settings must be enabled."
  }
}

run "acls_are_disabled_by_default" {
  command = apply

  assert {
    condition     = aws_s3_bucket_ownership_controls.this[0].rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "Object ownership must default to BucketOwnerEnforced so ACLs cannot grant access."
  }
}

run "versioning_is_enabled_by_default" {
  command = apply

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled by default."
  }
}

run "encryption_is_enabled_by_default" {
  command = apply

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Default server-side encryption must be AES256."
  }
}

run "bucket_is_not_destroyable_by_default" {
  command = apply

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "force_destroy must default to false so a non-empty bucket cannot be silently emptied."
  }
}

run "tls_is_enforced_by_default" {
  command = apply

  assert {
    condition     = length(aws_s3_bucket_policy.this) == 1
    error_message = "A bucket policy enforcing TLS must be attached by default."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[0].Effect == "Deny"
    error_message = "The TLS statement must be a Deny."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "The TLS statement must trigger on aws:SecureTransport = false."
  }

  assert {
    condition = alltrue([
      contains(jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[0].Resource, "arn:aws:s3:::unit-test-bucket"),
      contains(jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[0].Resource, "arn:aws:s3:::unit-test-bucket/*"),
    ])
    error_message = "The TLS statement must cover both the bucket and its objects."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[0].Principal == "*"
    error_message = "The TLS statement must apply to every principal."
  }
}

run "access_logging_is_off_unless_a_target_is_given" {
  command = apply

  assert {
    condition     = length(aws_s3_bucket_logging.this) == 0
    error_message = "Access logging must not be configured without a target bucket."
  }
}
