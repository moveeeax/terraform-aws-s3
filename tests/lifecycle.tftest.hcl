# Lifecycle rules: wired through when given, and never created when the input
# is empty, because the lifecycle configuration resource replaces every rule on
# the bucket.

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

run "no_lifecycle_configuration_by_default" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this) == 0
    error_message = "An empty lifecycle_rules list must not create a lifecycle configuration, or it would wipe rules managed elsewhere."
  }
}

run "rules_are_passed_through" {
  command = plan

  variables {
    lifecycle_rules = [
      {
        id     = "logs"
        prefix = "logs/"
        transitions = [
          { days = 30, storage_class = "STANDARD_IA" },
          { days = 90, storage_class = "GLACIER" },
        ]
        expiration_days                    = 365
        noncurrent_version_expiration_days = 30
      },
      {
        id                                     = "everything"
        noncurrent_version_expiration_days     = 90
        abort_incomplete_multipart_upload_days = 3
      },
    ]
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this) == 1
    error_message = "A non-empty lifecycle_rules list must create one lifecycle configuration."
  }

  assert {
    condition     = [for r in aws_s3_bucket_lifecycle_configuration.this[0].rule : r.id] == ["logs", "everything"]
    error_message = "Rules must keep their ids and order."
  }

  assert {
    condition     = alltrue([for r in aws_s3_bucket_lifecycle_configuration.this[0].rule : r.status == "Enabled"])
    error_message = "Every rule must be enabled."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[0].filter[0].prefix == "logs/"
    error_message = "prefix must land in the rule filter."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this[0].rule[1].filter) == 1
    error_message = "A rule without prefix must still get a filter block (an empty one matches every object)."
  }

  assert {
    condition = toset([for t in aws_s3_bucket_lifecycle_configuration.this[0].rule[0].transition : "${t.days}:${t.storage_class}"]) == toset([
      "30:STANDARD_IA",
      "90:GLACIER",
    ])
    error_message = "Transitions must be passed through."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[0].expiration[0].days == 365
    error_message = "expiration_days must be passed through."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this[0].rule[1].expiration) == 0
    error_message = "A rule without expiration_days must not expire current versions."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[0].noncurrent_version_expiration[0].noncurrent_days == 30
    error_message = "noncurrent_version_expiration_days must be passed through."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 7
    error_message = "abort_incomplete_multipart_upload_days must default to 7."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].rule[1].abort_incomplete_multipart_upload[0].days_after_initiation == 3
    error_message = "abort_incomplete_multipart_upload_days must be passed through."
  }
}

run "zero_abort_days_leaves_the_action_out" {
  command = plan

  variables {
    lifecycle_rules = [
      {
        id                                     = "expire"
        expiration_days                        = 30
        abort_incomplete_multipart_upload_days = 0
      },
    ]
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this[0].rule[0].abort_incomplete_multipart_upload) == 0
    error_message = "abort_incomplete_multipart_upload_days = 0 must leave the action out."
  }
}

run "rejects_duplicate_rule_ids" {
  command = plan

  variables {
    lifecycle_rules = [
      { id = "dup", expiration_days = 30 },
      { id = "dup", expiration_days = 60 },
    ]
  }

  expect_failures = [var.lifecycle_rules]
}

run "rejects_an_empty_rule_id" {
  command = plan

  variables {
    lifecycle_rules = [{ id = " ", expiration_days = 30 }]
  }

  expect_failures = [var.lifecycle_rules]
}

run "rejects_an_unknown_storage_class" {
  command = plan

  variables {
    lifecycle_rules = [
      {
        id          = "tier"
        transitions = [{ days = 30, storage_class = "STANDARD" }]
      },
    ]
  }

  expect_failures = [var.lifecycle_rules]
}

run "rejects_negative_transition_days" {
  command = plan

  variables {
    lifecycle_rules = [
      {
        id          = "tier"
        transitions = [{ days = -1, storage_class = "GLACIER" }]
      },
    ]
  }

  expect_failures = [var.lifecycle_rules]
}

run "rejects_zero_expiration_days" {
  command = plan

  variables {
    lifecycle_rules = [{ id = "expire", expiration_days = 0 }]
  }

  expect_failures = [var.lifecycle_rules]
}

run "rejects_fractional_noncurrent_days" {
  command = plan

  variables {
    lifecycle_rules = [{ id = "expire", noncurrent_version_expiration_days = 1.5 }]
  }

  expect_failures = [var.lifecycle_rules]
}

run "rejects_negative_abort_days" {
  command = plan

  variables {
    lifecycle_rules = [{ id = "abort", abort_incomplete_multipart_upload_days = -1 }]
  }

  expect_failures = [var.lifecycle_rules]
}

run "rejects_a_rule_without_any_action" {
  command = plan

  variables {
    lifecycle_rules = [{ id = "noop", abort_incomplete_multipart_upload_days = 0 }]
  }

  expect_failures = [var.lifecycle_rules]
}
