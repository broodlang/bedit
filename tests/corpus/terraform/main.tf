# The log bucket.
# ^^^^^^^^^^^^^^^ comment
terraform {
  required_providers {
    # ^^^^^^^^^^^^^^ keyword
    aws = {
      source  = "hashicorp/aws"
      #         ^^^^^^^^^^^^^^^ string
      version = "~> 5.0"
    }
  }
}

variable "environment" {
  type    = string
  default = "staging"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    #               ^^^^^^^^ function
    error_message = "Must be staging or production."
    # ^^^^^^^^^^^ special
  }
}

locals {
  # ^^ keyword
  // tags every resource carries
  # ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ comment
  tags = {
    Environment = var.environment
    Count       = 3
    #             ^ number
    Enabled     = true
    #             ^^^^ constant
    Owner       = null
    #             ^^^^ constant
  }
  names = [for name in var.names : upper(name) if name != ""]
  #        ^^^ keyword             ^^^^^ function
  #                 ^^ keyword                 ^^ keyword
  zones = [
    "a",
    "b",
  ]
}

/* the bucket itself */
# ^^^^^^^^^^^^^^^^^^^^^ comment
resource "aws_s3_bucket" "logs" {
  # ^^^^ keyword         ^^^^^^ string
  #      ^^^^^^^^^^^^^^^ string
  bucket = "logs-${var.environment}-${local.tags.Count}"
  # ^^^^ special ^^ special
  #         ^^^^^ string
  #                ^^^ plain
  tags = merge(
    #    ^^^^^ function
    local.tags,
    # ^^^ plain
    { Name = "logs" },
  )

  lifecycle {
    # ^^^^^ keyword
    prevent_destroy = true
    # ^^^^^^^^^^^^^ special
  }
}

resource "aws_iam_policy" "read" {
  #      ^^^^^^^^^^^^^^^^ string
  policy = <<-EOT
    {
      "Bucket": "${aws_s3_bucket.logs.id}"
    }
  EOT
}

output "bucket_arn" {
  value = aws_s3_bucket.logs.arn
  #       ^^^^^^^^^^^^^ plain
}
