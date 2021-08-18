provider "aws" {
  region = "us-west-2"
}

resource "aws_security_group" "sg" {
  vpc_id = "vpc-0ebd3d12fcb5455ae"
}

resource "aws_kms_key" "kms" {
  description = "example"
}

resource "aws_cloudwatch_log_group" "test" {
  name = "msk_broker_logs"
}

resource "aws_s3_bucket" "bucket" {
  bucket = "test-robson-msk-broker-logs-bucket"
  acl    = "private"
  force_destroy = true
}

resource "aws_iam_role" "firehose_role" {
  name = "firehose_test_role"

  assume_role_policy = <<EOF
{
"Version": "2012-10-17",
"Statement": [
  {
    "Action": "sts:AssumeRole",
    "Principal": {
      "Service": "firehose.amazonaws.com"
    },
    "Effect": "Allow",
    "Sid": ""
  }
  ]
}
EOF
}

resource "aws_kinesis_firehose_delivery_stream" "test_stream" {
  name        = "terraform-kinesis-firehose-msk-broker-logs-stream"
  destination = "s3"

  s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.bucket.arn
  }

  tags = {
    LogDeliveryEnabled = "placeholder"
  }

  lifecycle {
    ignore_changes = [
      tags["LogDeliveryEnabled"],
    ]
  }
}

module "msk-cluster" {
  source  = "angelabad/msk-cluster/aws"

  cluster_name    = "ecommerce"
  instance_type   = "kafka.t3.small"
  number_of_nodes = 2
  client_subnets  = ["subnet-0085f19806163273e", "subnet-0102a3dd40194204f"] //privadas
  kafka_version   = "2.8.0"

  extra_security_groups = ["sg-07b69a212f2c47e1d"] //tentar colocar o sg do all_worker_management

  enhanced_monitoring = "PER_BROKER"

  s3_logs_bucket = "test-robson-msk-broker-logs-bucket"
  s3_logs_prefix = "msklogs"

  prometheus_jmx_exporter  = true
  prometheus_node_exporter = true

  server_properties = {
    "auto.create.topics.enable"  = "true"
    "default.replication.factor" = "2"
  }

  encryption_in_transit_client_broker = "PLAINTEXT"

  tags = {
    Owner       = "user"
    Environment = "dev"
  }
}
