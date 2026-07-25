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
  description = "Whether to attach a bucket policy denying any request not made over TLS. Set to false only if you manage the bucket policy yourself."
  type        = bool
  default     = true
}

variable "logging_target_bucket" {
  description = "Name of an existing bucket to deliver S3 server access logs to. Null disables access logging."
  type        = string
  default     = null
}

variable "logging_target_prefix" {
  description = "Key prefix for delivered server access logs. Only used when logging_target_bucket is set."
  type        = string
  default     = "s3-access-logs/"
}

variable "tags" {
  description = "Tags applied to the bucket."
  type        = map(string)
  default     = {}
}
