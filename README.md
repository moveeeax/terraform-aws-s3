# terraform-aws-s3

Terraform module that manages an [Amazon S3](https://aws.amazon.com/s3/) bucket.
It creates a single bucket and wires up versioning, default server-side
encryption, public access blocking, disabled ACLs and a TLS-only bucket policy
so the bucket is private and durable by default.

## Secure by default

With nothing but `bucket` set, the module gives you:

| Control                  | Default                                                   | Opt out with              |
|--------------------------|-----------------------------------------------------------|---------------------------|
| Public access block      | all four settings enabled                                 | `block_public_access`     |
| Object ownership         | `BucketOwnerEnforced` — ACLs disabled entirely             | `object_ownership = null` |
| Encryption at rest       | SSE-S3 (`AES256`)                                         | `sse_algorithm`           |
| Encryption in transit    | bucket policy denying `aws:SecureTransport = false`        | `enforce_tls`             |
| Versioning               | enabled                                                   | `versioning_enabled`      |
| Accidental deletion      | `force_destroy = false`                                   | `force_destroy`           |

Server access logging is the one control that is **off** by default, because it
needs a destination bucket you already own — set `logging_target_bucket` to turn
it on.

## Usage

```hcl
module "s3" {
  source = "github.com/moveeeax/terraform-aws-s3?ref=v1.0.0" # pin to a release tag

  bucket             = "prod-app-assets"
  versioning_enabled = true

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

A runnable example lives in [`examples/basic`](examples/basic).

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| aws       | >= 5.0   |

## Inputs

| Name                  | Description                                                             | Type          | Default    | Required |
|-----------------------|-------------------------------------------------------------------------|---------------|------------|:--------:|
| `bucket`                | Name of the S3 bucket. Must be globally unique.                        | `string`      | n/a                    |   yes    |
| `force_destroy`         | Allow deletion of a non-empty bucket by removing all objects first.    | `bool`        | `false`                |    no    |
| `versioning_enabled`    | Enable object versioning on the bucket.                                | `bool`        | `true`                 |    no    |
| `block_public_access`   | Enable all four S3 public access block settings on the bucket.         | `bool`        | `true`                 |    no    |
| `object_ownership`      | Object ownership rule. `null` leaves ownership controls unmanaged.      | `string`      | `"BucketOwnerEnforced"` |    no    |
| `enforce_tls`           | Attach a bucket policy denying any request not made over TLS.          | `bool`        | `true`                 |    no    |
| `sse_algorithm`         | Server-side encryption algorithm. Either AES256 or aws:kms.            | `string`      | `"AES256"`             |    no    |
| `kms_key_id`            | ARN of the KMS key used when sse_algorithm is aws:kms.                 | `string`      | `null`                 |    no    |
| `bucket_key_enabled`    | Use S3 Bucket Keys to cut KMS request cost. Only applies to SSE-KMS.   | `bool`        | `true`                 |    no    |
| `logging_target_bucket` | Existing bucket to deliver server access logs to. `null` disables it.  | `string`      | `null`                 |    no    |
| `logging_target_prefix` | Key prefix for delivered access logs.                                  | `string`      | `"s3-access-logs/"`    |    no    |
| `lifecycle_rules`       | Lifecycle rules. `[]` leaves the lifecycle configuration unmanaged. See [Lifecycle rules](#lifecycle-rules). | `list(object)` | `[]` | no |
| `tags`                  | Tags applied to the bucket.                                            | `map(string)` | `{}`                   |    no    |

`enforce_tls` attaches an `aws_s3_bucket_policy` to the bucket. If you manage
that bucket's policy elsewhere, set `enforce_tls = false` and carry the
`aws:SecureTransport` deny statement over into your own policy — otherwise the
two resources will fight over the same bucket.

## Lifecycle rules

Nothing expires by default. With `versioning_enabled = true` that means
noncurrent versions are kept forever, so log and backup buckets keep growing.
`lifecycle_rules` adds an `aws_s3_bucket_lifecycle_configuration`:

```hcl
module "logs" {
  source = "github.com/moveeeax/terraform-aws-s3?ref=v1.0.0" # pin to a release tag

  bucket = "prod-app-logs"

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
  ]
}
```

Each rule takes:

| Attribute                                | Type           | Default | Notes                                                        |
|------------------------------------------|----------------|---------|--------------------------------------------------------------|
| `id`                                     | `string`       | n/a     | Unique within the bucket, 1-255 characters.                  |
| `prefix`                                 | `string`       | `null`  | Key prefix the rule applies to. `null` matches every object. |
| `transitions`                            | `list(object)` | `[]`    | `{ days, storage_class }`; `days` counts from object creation. |
| `expiration_days`                        | `number`       | `null`  | Expire current versions after this many days.                |
| `noncurrent_version_expiration_days`     | `number`       | `null`  | Delete noncurrent versions this many days after they become noncurrent. |
| `abort_incomplete_multipart_upload_days` | `number`       | `7`     | Abort unfinished multipart uploads. `0` leaves the action out. |

`storage_class` is one of `STANDARD_IA`, `ONEZONE_IA`, `INTELLIGENT_TIERING`,
`GLACIER_IR`, `GLACIER` or `DEEP_ARCHIVE`. Every rule is created with status
`Enabled` and needs at least one action.

A reasonable starting point for a versioned bucket is a single rule with no
prefix and `noncurrent_version_expiration_days = 30`; the default 7-day abort
for multipart uploads rides along.

The lifecycle configuration resource is authoritative: it replaces every
lifecycle rule on the bucket. That is why the module creates it only when
`lifecycle_rules` is non-empty. If you manage the bucket's lifecycle rules
elsewhere, leave the list empty.

## Outputs

| Name                          | Description                                        |
|-------------------------------|----------------------------------------------------|
| `id`                          | Name of the bucket.                                |
| `arn`                         | ARN of the bucket.                                 |
| `bucket_domain_name`          | Domain name of the bucket.                         |
| `bucket_regional_domain_name` | Region-specific domain name of the bucket.         |
| `hosted_zone_id`              | Route 53 hosted zone ID for the bucket's region.   |

## Development

The test suite uses `mock_provider`, so it needs Terraform >= 1.7 but no AWS
credentials and no network access to AWS:

```sh
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test

TFLINT_CONFIG_FILE="$PWD/.tflint.hcl" tflint --recursive
```

`tflint --recursive` re-reads its config in each directory it visits, which is
why `TFLINT_CONFIG_FILE` has to be set to an absolute path.

## License

[MIT](LICENSE)
