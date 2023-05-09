provider "aws" {
  region = "us-east-1"
  access_key = "YOUR-ACCESS-KEY-HERE"
  secret_key = "YOUR-SECRET-HERE"
}

resource "aws_instance" "test-instance" {
    ami = "ami-02396cdd13e9a1257"
    instance_type = "t2.micro"
    tags = {
        name = "linux"
    }
}

resource "aws_s3_bucket" "my-test-bucket" {
    bucket = "data-dog-failed-logs-test"
}

data "aws_iam_policy_document" "policy-assume-role" {
    statement {
        effect = "Allow"
        principals {
            type = "Service"
            identifiers = ["logs.amazonaws.com", "firehose.amazonaws.com"]
        }
        actions = ["sts:AssumeRole"]
    }
}

data "aws_iam_policy_document" "policy-doc" {
    statement {
        actions = [
            "firehose:PutRecord",
            "firehose:PutRecordBatch",
            "kinesis:PutRecord",
            "kinesis:PutRecords"
        ]
        effect    = "Allow"
        resources = ["*"]
    }
}

resource "aws_iam_role" "firehose-role" {
    name = "DatadogCloudWatchLogs"
    assume_role_policy = data.aws_iam_policy_document.policy-assume-role.json
}

resource "aws_iam_role_policy" "firehose-role-policy" {
    name = "DatadogCloudWatchLogsPolicy"
    role = aws_iam_role.firehose-role.id
    policy = data.aws_iam_policy_document.policy-doc.json
}

resource "aws_kinesis_firehose_delivery_stream" "my-test-stream" {
  name        = "DatadogCWLogsforwarder"
  destination = "http_endpoint"

  s3_configuration {
    role_arn           = aws_iam_role.firehose-role.arn
    bucket_arn         = aws_s3_bucket.my-test-bucket.arn
    buffer_size        = 10
    buffer_interval    = 400
    compression_format = "GZIP"
  }

  http_endpoint_configuration {
    url                = "https://aws-kinesis-http-intake.logs.datadoghq.com/v1/input"
    name               = "Datadog"
    access_key         = "YOUR-ACCESS-KEY-HERE"
    buffering_size     = 2
    buffering_interval = 600
    role_arn           = aws_iam_role.firehose-role.arn
    s3_backup_mode     = "FailedDataOnly"

    request_configuration {
      content_encoding = "GZIP"

      common_attributes {
        name  = "test_attr_1"
        value = "XYZ"
      }

      common_attributes {
        name  = "test_attr_2"
        value = "ABC"
      }
    }
  }
}

resource "aws_cloudwatch_log_group" "test-log-group" {
  name = "test-log-group"
}

resource "aws_cloudwatch_log_stream" "test-stream" {
  name           = "test-stream"
  log_group_name = aws_cloudwatch_log_group.test-log-group.name
}

resource "aws_cloudwatch_log_subscription_filter" "test-subscription-logfilter" {
  name            = "test-subscription-logfilter"
  role_arn        = aws_iam_role.firehose-role.arn
  log_group_name  = aws_cloudwatch_log_group.test-log-group.name
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.my-test-stream.arn
  distribution    = "Random"
}