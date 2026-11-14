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

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Sid = "EnableRootAccountAccess"
                Effect = "Allow"
                Principal = {
                    AWS = "arn:aws:iam::686316017813:root"
                }
                Action = "kms:*"
                Resource = "*"
            },
            {
                Sid = "AllowCloudTrailEncrypt"
                Effect = "Allow"
                Principal = {
                    Service = "cloudtrail.amazonaws.com"
                }
                Action = "kms:GenerateDataKey*"
                Resource = "*"
            },
            {
                Sid = "AllowLogDeliveryEncrypt"
                Effect = "Allow"
                Principal = {
                    Service = "delivery.logs.amazonaws.com"
                }
                Action = ["kms:GenerateDataKey*", "kms:Decrypt"]
                Resource = "*"
            }
        ]
    })
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
                Resource = "arn:aws:s3:::centralised-log-archive-686316017813"
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
                Sid = "AWSLogDeliveryWrite"
                Effect = "Allow"
                Principal = {
                    Service = "delivery.logs.amazonaws.com"
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
                Sid = "AWSLogDeliveryAclCheck"
                Effect = "Allow"
                Principal = {
                    Service = "delivery.logs.amazonaws.com"
                }
                Action = "s3:GetBucketAcl"
                Resource = "arn:aws:s3:::centralised-log-archive-686316017813"
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
    cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail_logs.arn}:*"
    cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_to_cloudwatch.arn

    event_selector {
        read_write_type = "All"
        include_management_events = true
    }
}
data "aws_vpc" "default" {
    default = true
}
resource "aws_flow_log" "main" {
    vpc_id = data.aws_vpc.default.id
    traffic_type = "ALL"
    log_destination_type = "s3"
    log_destination = aws_s3_bucket.log_archive.arn
}
resource "aws_cloudwatch_log_group" "cloudtrail_logs" {
    name = "/aws/cloudtrail/centralised-trail"
    retention_in_days = 90
}
resource "aws_sns_topic" "logging_alerts" {
    name = "logging-alerts"
}
resource "aws_iam_role" "cloudtrail_to_cloudwatch" {
    name = "CloudTrailToCloudWatchRole"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Principal = {
                    Service = "cloudtrail.amazonaws.com"
                }
                Action = "sts:AssumeRole"
            }
        ]
    })
}
resource "aws_iam_role_policy" "cloudtrail_to_cloudwatch" {
    name = "CloudTrailToCloudWatchPolicy"
    role = aws_iam_role.cloudtrail_to_cloudwatch.name

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
                Resource = "${aws_cloudwatch_log_group.cloudtrail_logs.arn}:*"
            }
        ]
    })
}