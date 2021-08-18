 
provider "aws" {
  region = local.region
}

locals {
  name   = "logistics"
  region = "us-west-2"
}

module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 3.0"

  identifier = "logistics"

  engine            = "postgres"
  engine_version    = "11.10"
  instance_class    = "db.t3.micro"
  allocated_storage = 5

  name     = "logistics"
  username = "postgres"
  password = "postgres"
  port     = "5432"

  iam_database_authentication_enabled = true

  subnet_ids             = ["subnet-0d8e5f7e56e44dfe8", "subnet-044fa9450478e2a29", "subnet-0e4598472e8d63dcb"] //db subnets
  vpc_security_group_ids = ["sg-0c789fa224bf07e74"] //	Complete PostgreSQL

  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"

  # Enhanced Monitoring - see example for details on how to create the role
  # by yourself, in case you don't want to create it automatically
  monitoring_interval = "30"
  monitoring_role_name = "MyRDSMonitoringRole"
  create_monitoring_role = true
  publicly_accessible = true
  
  # DB parameter group
  family = "postgres11"

  # DB option group
  major_engine_version = "11"

  # Database Deletion Protection
  deletion_protection = false
}