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