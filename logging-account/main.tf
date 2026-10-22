terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.0"
        }
    }
}
provider "aws" {
    region = "ap-southeast-2"
}
resource "aws_kms_key" "log_encryption_key" {
    description = "KMS key for encrypting centralised CloudTrail logs"
    deletion_window_in_days = 10
    enable_key_rotation = true
}
resource "aws_kms_alias" "log_encryption_key_alias" {
    name = "alias/cloudtrail-logs"
    target_key_id = aws_kms_key.log_encryption_key.key_id
}
resource "aws_s3_bucket" "log_archive" {
    bucket = "centralised-log-archive-686316017813"
}
resource "aws_s3_bucket_versioning" "log_archive" {
    bucket = aws_s3_bucket.log_archive.id
    versioning_configuration {
        status = "Enabled"
    }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "log_archive" {
    bucket = aws_s3_bucket.log_archive.id
    rule {
        apply_server_side_encryption_by_default{
            sse_algorithm = "aws:kms"
            kms_master_key_id = aws_kms_key.log_encryption_key.arn
        }
    }
}
resource "aws_s3_bucket_public_access_block" "log_archive" {
    bucket = aws_s3_bucket.log_archive.id

    block_public_acls = true
    block_public_policy = true
    ignore_public_acls = true
    restrict_public_buckets = true
}
resource "aws_s3_bucket_lifecycle_configuration" "log_archive" {
    bucket = aws_s3_bucket.log_archive.id

    rule {
        id = "delete-old-logs"
        status = "Enabled"

        filter{}

        expiration {
            days = 90
        }
    }
}
resource "aws_s3_bucket_policy" "log_archive" {
    bucket = aws_s3_bucket.log_archive.id

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Sid = "AWSCloudTrailAclCheck"
                Effect = "Allow"
                Principal = {
                    Service = "cloudtrail.amazonaws.com"
                }
                Action = "s3:GetBucketAcl"
                Resource = "arn:aws:s3:::centralised-log-archive-686316017813/AWSLogs/*"
            },
            {
                Sid = "AWSCloudTrailWrite"
                Effect = "Allow"
                Principal = {
                    Service = "cloudtrail.amazonaws.com"
                }
                Action = "s3:PutObject"
                Resource = "arn:aws:s3:::centralised-log-archive-686316017813/AWSLogs/*"
                Condition = {
                    StringEquals = {
                        "s3:x-amz-acl" = "bucket-owner-full-control"
                    }
                }
            },
            {
                Sid = "DenyDelete" 
                Effect = "Deny"
                Principal = {
                    AWS = "*"
                }
                Action = "s3:DeleteObject"
                Resource = "arn:aws:s3:::centralised-log-archive-686316017813/*"
            }
        ]
    })
}
resource "aws_cloudtrail" "main" {
    name = "centralised-trail"
    s3_bucket_name = "centralised-log-archive-686316017813"
    kms_key_id = aws_kms_key.log_encryption_key.arn
    include_global_service_events = true
    is_multi_region_trail = true
    enable_log_file_validation = true

    event_selector {
        read_write_type = "All"
        include_management_events = true
    }
}