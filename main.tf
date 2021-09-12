provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

locals {
  name         = "ecommerce-vpc"
  region       = "us-west-2"
  cluster_name = "ecommerce-eks"
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}


data "aws_availability_zones" "available" {
}

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2"

  name = local.name
  cidr = "10.0.0.0/16"

  azs                = ["${local.region}a", "${local.region}b", "${local.region}c"]
  public_subnets     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  private_subnets    = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  database_subnets   = ["10.0.7.0/24", "10.0.8.0/24", "10.0.9.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = true

  create_database_subnet_group           = true
  create_database_subnet_route_table     = true
  create_database_internet_gateway_route = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

resource "aws_security_group" "my_home_access" {
  name_prefix = "my_home_access"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "postgres" {
  name_prefix = "postgres"
  vpc_id      = module.vpc.vpc_id

  ingress {
      from_port = 5432
      to_port   = 5432
      protocol  = "tcp"

      cidr_blocks = [module.vpc.vpc_cidr_block]
  }
  
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    security_groups = [aws_security_group.my_home_access.id]
  }
}

resource "aws_security_group" "worker_group_mgmt_one" {
  name_prefix = "worker_group_mgmt_one"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
    ]
  }
}

resource "aws_security_group" "worker_group_mgmt_two" {
  name_prefix = "worker_group_mgmt_two"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "192.168.0.0/16",
    ]
  }
}

resource "aws_security_group" "all_worker_mgmt" {
  name_prefix = "all_worker_management"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }
}

resource "aws_security_group" "kafka-sg" {
  name_prefix = "kafka"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    security_groups = [aws_security_group.all_worker_mgmt.id]
  }
}

module "ec2_cluster" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 2.0"

  name           = "bastion"
  instance_count = 1

  ami                    = "ami-083ac7c7ecf9bb9b0"
  instance_type          = "t3.micro"
  key_name               = "my-key-aws"
  monitoring             = true
  vpc_security_group_ids = [aws_security_group.my_home_access.id]
  subnet_id              = module.vpc.public_subnets[0]
}


///RDS////

module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 3.0"

  for_each = toset( ["logistics", "orderprocessor", "orderreceiver", "payments", "productviewer", "stock"] )

  identifier = each.key

  engine            = "postgres"
  engine_version    = "11.10"
  instance_class    = "db.t3.micro" //"db.m5.large"
  allocated_storage = 10

  name     = each.key
  username = "postgres"
  password = "postgres"
  port     = "5432"

  iam_database_authentication_enabled = true

  subnet_ids             = module.vpc.database_subnets
  vpc_security_group_ids = [aws_security_group.postgres.id]

  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"

  monitoring_interval    = "30"
  monitoring_role_name   = each.key
  create_monitoring_role = true
  publicly_accessible    = true

  family               = "postgres11"
  major_engine_version = "11"
  deletion_protection  = false
  skip_final_snapshot  = true
}

//EKS

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = local.cluster_name
  cluster_version = "1.20"
  subnets         = module.vpc.private_subnets

  tags = {
    Environment = "test"
    GithubRepo  = "terraform-aws-eks"
    GithubOrg   = "terraform-aws-modules"
  }

  vpc_id = module.vpc.vpc_id

  worker_groups = [
    {
      name                          = "worker-group-1"
      instance_type                 = "t3.small" //"m5.large" 
      additional_userdata           = "echo foo bar"
      asg_desired_capacity          = 2
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_one.id]
    },
    {
      name                          = "worker-group-2"
      instance_type                 = "t3.small" //"m5.large"
      additional_userdata           = "echo foo bar"
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_two.id]
      asg_desired_capacity          = 2
    },
  ]

  worker_additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
  map_roles                            = var.map_roles
  map_users                            = var.map_users
  map_accounts                         = var.map_accounts
}

//MSK

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
  instance_type   = "kafka.t3.small" //"kafka.m5.large"
  number_of_nodes = 3
  client_subnets  = module.vpc.private_subnets
  kafka_version   = "2.8.0"

  extra_security_groups = [aws_security_group.kafka-sg.id]

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
