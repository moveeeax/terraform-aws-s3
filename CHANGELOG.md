# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `lifecycle_rules` input: transitions, expiration of current and noncurrent
  versions, and abort of incomplete multipart uploads (7 days by default per
  rule), via `aws_s3_bucket_lifecycle_configuration`. The resource is created
  only when the list is non-empty, so existing deployments plan no changes and
  lifecycle rules managed elsewhere are not wiped.
- `policy_statements` input: a JSON policy document whose statements are
  appended to the module's bucket policy after the TLS deny, so cross-account
  or CloudFront access no longer requires `enforce_tls = false`. The Sids
  `DenyUnencryptedTransport` and `DenyOutdatedTls` are reserved.
- `require_latest_tls` input (default `false`): adds a `DenyOutdatedTls`
  statement for requests with `s3:TlsVersion` below 1.2.

### Changed

- The bucket policy is now created whenever it has at least one statement
  (TLS deny, TLS version deny or caller statements), not only when
  `enforce_tls = true`. With the defaults the policy JSON is byte-for-byte the
  same as in 1.1.0 and the resource address is unchanged.

## [1.1.0] - 2026-11-05

### Fixed

- Reject empty or whitespace-only `kms_key_id` and `logging_target_bucket`, and
  bucket names with adjacent periods, at plan time instead of at apply.

### Changed

- CI: add job timeouts, move to node24 action majors and pin tool versions.
- CI: group Dependabot updates monthly and auto-merge patch updates.

## [1.0.0] - 2026-07-26

Initial release with versioning, default encryption, public access block,
disabled ACLs, a TLS-only bucket policy and a native test suite (`v0.1.0`
points at the same commit).

[Unreleased]: https://github.com/moveeeax/terraform-aws-s3/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/moveeeax/terraform-aws-s3/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/moveeeax/terraform-aws-s3/releases/tag/v1.0.0
