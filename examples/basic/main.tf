module "s3" {
  source = "../.."

  bucket             = var.bucket
  versioning_enabled = true

  tags = {
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}
