variable "bucket" {
  description = "Name of the S3 bucket. Must be globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket))
    error_message = "bucket must be 3-63 characters of lowercase letters, digits, hyphens or dots, and must start and end with a letter or digit."
  }

  validation {
    condition     = !can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.bucket))
    error_message = "bucket must not be formatted as an IP address."
  }

  validation {
    condition     = !can(regex("\\.\\.", var.bucket))
    error_message = "bucket must not contain two adjacent periods."
  }
}

variable "force_destroy" {
  description = "Whether to allow deletion of a non-empty bucket by removing all objects first."
  type        = bool
  default     = false
}

variable "versioning_enabled" {
  description = "Whether to enable object versioning on the bucket."
  type        = bool
  default     = true
}

variable "block_public_access" {
  description = "Whether to enable all four S3 public access block settings on the bucket."
  type        = bool
  default     = true
}

variable "sse_algorithm" {
  description = "Server-side encryption algorithm. Either AES256 or aws:kms."
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "sse_algorithm must be either AES256 or aws:kms."
  }
}

variable "kms_key_id" {
  description = "ARN of the KMS key used when sse_algorithm is aws:kms. Null uses the default S3 KMS key."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_id == null || length(trimspace(var.kms_key_id)) > 0
    error_message = "kms_key_id must not be an empty or whitespace-only string; use null to fall back to the default S3 KMS key."
  }
}

variable "bucket_key_enabled" {
  description = "Whether to use S3 Bucket Keys to reduce KMS request costs. Only applies when sse_algorithm is aws:kms."
  type        = bool
  default     = true
}

variable "object_ownership" {
  description = "Object ownership rule for the bucket. BucketOwnerEnforced disables ACLs entirely and is strongly recommended. Set to null to leave ownership controls unmanaged."
  type        = string
  default     = "BucketOwnerEnforced"

  validation {
    condition     = var.object_ownership == null || contains(["BucketOwnerEnforced", "BucketOwnerPreferred", "ObjectWriter"], coalesce(var.object_ownership, "BucketOwnerEnforced"))
    error_message = "object_ownership must be one of BucketOwnerEnforced, BucketOwnerPreferred, ObjectWriter, or null."
  }
}

variable "enforce_tls" {
  description = "Whether to include a bucket policy statement denying any request not made over TLS. Set to false only if you manage the bucket policy yourself; to add your own statements, use policy_statements instead."
  type        = bool
  default     = true
}

variable "require_latest_tls" {
  description = "Whether to add a bucket policy statement denying requests made with TLS older than 1.2 (s3:TlsVersion < 1.2)."
  type        = bool
  default     = false
}

variable "policy_statements" {
  description = "JSON policy document whose statements are appended to the module's bucket policy, after the TLS deny statements. Use it for cross-account or CloudFront access instead of turning off enforce_tls. Its Version is ignored; Statement must be a list. Null adds nothing."
  type        = string
  default     = null

  validation {
    condition     = var.policy_statements == null || can(jsondecode(var.policy_statements).Statement)
    error_message = "policy_statements must be a JSON policy document with a Statement key, for example data.aws_iam_policy_document.x.json."
  }

  validation {
    condition = var.policy_statements == null || try(
      !can(keys(jsondecode(var.policy_statements).Statement)) && length(jsondecode(var.policy_statements).Statement) > 0,
      false,
    )
    error_message = "policy_statements must contain a non-empty Statement list."
  }

  validation {
    condition = var.policy_statements == null || try(
      alltrue([for st in jsondecode(var.policy_statements).Statement : !contains(["DenyUnencryptedTransport", "DenyOutdatedTls"], try(st.Sid, ""))]),
      false,
    )
    error_message = "policy_statements must not use the Sids DenyUnencryptedTransport or DenyOutdatedTls, which the module reserves for its own statements."
  }

  validation {
    condition = var.policy_statements == null || try(
      length(compact([for st in jsondecode(var.policy_statements).Statement : try(st.Sid, "")])) == length(distinct(compact([for st in jsondecode(var.policy_statements).Statement : try(st.Sid, "")]))),
      false,
    )
    error_message = "Statement Sids in policy_statements must be unique."
  }
}

variable "logging_target_bucket" {
  description = "Name of an existing bucket to deliver S3 server access logs to. Null disables access logging."
  type        = string
  default     = null

  validation {
    condition     = var.logging_target_bucket == null || length(trimspace(var.logging_target_bucket)) > 0
    error_message = "logging_target_bucket must not be an empty or whitespace-only string; use null to disable access logging."
  }
}

variable "logging_target_prefix" {
  description = "Key prefix for delivered server access logs. Only used when logging_target_bucket is set."
  type        = string
  default     = "s3-access-logs/"
}

variable "lifecycle_rules" {
  description = "Lifecycle rules for the bucket. Each rule needs a unique id; prefix null matches every object. abort_incomplete_multipart_upload_days defaults to 7, set it to 0 to leave it out. An empty list leaves the bucket's lifecycle configuration unmanaged."
  type = list(object({
    id     = string
    prefix = optional(string)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
    expiration_days                        = optional(number)
    noncurrent_version_expiration_days     = optional(number)
    abort_incomplete_multipart_upload_days = optional(number, 7)
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for r in var.lifecycle_rules : length(trimspace(r.id)) > 0 && length(r.id) <= 255])
    error_message = "Every lifecycle rule id must be 1-255 characters and not whitespace-only."
  }

  validation {
    condition     = length(distinct([for r in var.lifecycle_rules : r.id])) == length(var.lifecycle_rules)
    error_message = "Lifecycle rule ids must be unique."
  }

  validation {
    condition = alltrue(flatten([
      for r in var.lifecycle_rules : [
        for t in r.transitions : contains(["GLACIER", "STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "DEEP_ARCHIVE", "GLACIER_IR"], t.storage_class)
      ]
    ]))
    error_message = "Transition storage_class must be one of GLACIER, STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, DEEP_ARCHIVE, GLACIER_IR."
  }

  validation {
    condition = alltrue(flatten([
      for r in var.lifecycle_rules : [
        for t in r.transitions : t.days >= 0 && floor(t.days) == t.days
      ]
    ]))
    error_message = "Transition days must be a whole number of 0 or more."
  }

  validation {
    condition = alltrue(flatten([
      for r in var.lifecycle_rules : [
        for d in [r.expiration_days, r.noncurrent_version_expiration_days] : d == null || (d >= 1 && floor(d) == d)
      ]
    ]))
    error_message = "expiration_days and noncurrent_version_expiration_days must be null or a whole number of 1 or more."
  }

  validation {
    condition     = alltrue([for r in var.lifecycle_rules : r.abort_incomplete_multipart_upload_days >= 0 && floor(r.abort_incomplete_multipart_upload_days) == r.abort_incomplete_multipart_upload_days])
    error_message = "abort_incomplete_multipart_upload_days must be a whole number of 0 or more; 0 leaves the action out."
  }

  validation {
    condition = alltrue([
      for r in var.lifecycle_rules : length(r.transitions) > 0 || r.expiration_days != null || r.noncurrent_version_expiration_days != null || r.abort_incomplete_multipart_upload_days > 0
    ])
    error_message = "Every lifecycle rule needs at least one action: a transition, expiration_days, noncurrent_version_expiration_days or abort_incomplete_multipart_upload_days."
  }
}

variable "tags" {
  description = "Tags applied to the bucket."
  type        = map(string)
  default     = {}
}
