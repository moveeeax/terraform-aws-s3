# Caller policy statements are merged into the module's bucket policy without
# losing the TLS-only deny, and the policy JSON is unchanged for callers who do
# not pass any.

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

# The exact string v1.1.0 renders. Any change here shows up as a plan diff on
# every existing deployment.
run "default_policy_json_is_unchanged" {
  command = apply

  assert {
    condition     = aws_s3_bucket_policy.this[0].policy == "{\"Statement\":[{\"Action\":\"s3:*\",\"Condition\":{\"Bool\":{\"aws:SecureTransport\":\"false\"}},\"Effect\":\"Deny\",\"Principal\":\"*\",\"Resource\":[\"arn:aws:s3:::unit-test-bucket\",\"arn:aws:s3:::unit-test-bucket/*\"],\"Sid\":\"DenyUnencryptedTransport\"}],\"Version\":\"2012-10-17\"}"
    error_message = "With no caller statements the bucket policy JSON must match v1.1.0 byte for byte."
  }
}

run "caller_statements_are_appended_after_the_tls_deny" {
  command = apply

  variables {
    policy_statements = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "AllowCloudFrontRead"
          Effect    = "Allow"
          Principal = { Service = "cloudfront.amazonaws.com" }
          Action    = "s3:GetObject"
          Resource  = "arn:aws:s3:::unit-test-bucket/*"
          Condition = {
            StringEquals = {
              "AWS:SourceArn" = "arn:aws:cloudfront::111122223333:distribution/EDFDVBD6EXAMPLE"
            }
          }
        },
        {
          Effect    = "Allow"
          Principal = { AWS = "arn:aws:iam::444455556666:root" }
          Action    = ["s3:ListBucket"]
          Resource  = "arn:aws:s3:::unit-test-bucket"
        },
      ]
    })
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this[0].policy).Statement) == 3
    error_message = "The policy must hold the TLS deny plus both caller statements."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[0].Sid == "DenyUnencryptedTransport"
    error_message = "The TLS deny must stay first in the merged policy."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "The TLS deny must be kept intact when caller statements are merged."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[1].Sid == "AllowCloudFrontRead"
    error_message = "Caller statements must follow the module's statements in order."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[1].Principal.Service == "cloudfront.amazonaws.com"
    error_message = "Caller statements must be passed through unchanged."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[2].Principal.AWS == "arn:aws:iam::444455556666:root"
    error_message = "A caller statement without a Sid must be passed through unchanged."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this[0].policy).Version == "2012-10-17"
    error_message = "The merged policy must keep Version 2012-10-17."
  }
}

run "require_latest_tls_adds_a_tls_version_deny" {
  command = apply

  variables {
    require_latest_tls = true
  }

  assert {
    condition     = [for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement : st.Sid] == ["DenyUnencryptedTransport", "DenyOutdatedTls"]
    error_message = "require_latest_tls must add DenyOutdatedTls after the TLS-only deny."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[1].Effect == "Deny"
    error_message = "The TLS version statement must be a Deny."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[1].Condition.NumericLessThan["s3:TlsVersion"] == 1.2
    error_message = "The TLS version statement must trigger on s3:TlsVersion < 1.2."
  }

  assert {
    condition = alltrue([
      contains(jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[1].Resource, "arn:aws:s3:::unit-test-bucket"),
      contains(jsondecode(aws_s3_bucket_policy.this[0].policy).Statement[1].Resource, "arn:aws:s3:::unit-test-bucket/*"),
    ])
    error_message = "The TLS version statement must cover both the bucket and its objects."
  }
}

run "caller_statements_alone_still_create_a_policy" {
  command = apply

  variables {
    enforce_tls = false
    policy_statements = jsonencode({
      Statement = [
        {
          Sid       = "AllowCrossAccountRead"
          Effect    = "Allow"
          Principal = { AWS = "arn:aws:iam::444455556666:root" }
          Action    = "s3:GetObject"
          Resource  = "arn:aws:s3:::unit-test-bucket/*"
        },
      ]
    })
  }

  assert {
    condition     = [for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement : st.Sid] == ["AllowCrossAccountRead"]
    error_message = "With enforce_tls = false the policy must hold only the caller statements."
  }
}

run "rejects_policy_statements_that_are_not_json" {
  command = plan

  variables {
    policy_statements = "not json"
  }

  expect_failures = [var.policy_statements]
}

run "rejects_policy_statements_without_a_statement_list" {
  command = plan

  variables {
    policy_statements = jsonencode({
      Version   = "2012-10-17"
      Statement = { Effect = "Allow", Action = "s3:GetObject", Resource = "*", Principal = "*" }
    })
  }

  expect_failures = [var.policy_statements]
}

run "rejects_an_empty_statement_list" {
  command = plan

  variables {
    policy_statements = jsonencode({ Version = "2012-10-17", Statement = [] })
  }

  expect_failures = [var.policy_statements]
}

run "rejects_a_reserved_sid" {
  command = plan

  variables {
    policy_statements = jsonencode({
      Statement = [
        { Sid = "DenyUnencryptedTransport", Effect = "Allow", Principal = "*", Action = "s3:GetObject", Resource = "arn:aws:s3:::unit-test-bucket/*" },
      ]
    })
  }

  expect_failures = [var.policy_statements]
}

run "rejects_duplicate_caller_sids" {
  command = plan

  variables {
    policy_statements = jsonencode({
      Statement = [
        { Sid = "Read", Effect = "Allow", Principal = { AWS = "arn:aws:iam::444455556666:root" }, Action = "s3:GetObject", Resource = "arn:aws:s3:::unit-test-bucket/*" },
        { Sid = "Read", Effect = "Allow", Principal = { AWS = "arn:aws:iam::444455556666:root" }, Action = "s3:ListBucket", Resource = "arn:aws:s3:::unit-test-bucket" },
      ]
    })
  }

  expect_failures = [var.policy_statements]
}
