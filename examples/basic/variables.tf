variable "region" {
  description = "AWS region to deploy the example bucket into."
  type        = string
  default     = "us-east-1"
}

variable "bucket" {
  description = "Name of the example bucket. Must be globally unique, so override it before applying."
  type        = string
  default     = "example-bucket-moveeeax-0001"
}
