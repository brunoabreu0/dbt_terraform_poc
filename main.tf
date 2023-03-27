terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.57"
    }
  }

  required_version = ">= 1.3.8"

  backend "s3" {
    bucket = "dbt-tf-poc"
    key    = "dbt-tf-poc-state"
    region = "eu-west-1"
  }
}

provider "aws" {
  region = "eu-west-1"
  default_tags {
    tags = {
      project = "dbt_poc"
    }
  }
}

resource "aws_ecr_repository" "dbt_poc" {
  name         = "dbt_poc_repo"
  force_delete = true
}

resource "aws_secretsmanager_secret" "snowflake_password" {
  name = "dbt_poc_snowflake_password"
}

resource "aws_ecs_cluster" "dbt_poc_cluster" {
  name = "dbt-poc-cluster"
}

resource "aws_ecs_task_definition" "dbt_poc_task" {
  family                   = "dbt-poc-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  container_definitions    = <<TASK_DEFINITION
[
  {
    "name": "dbt-poc-container",
    "image": "981619280753.dkr.ecr.eu-west-1.amazonaws.com/dbt_poc_repo:latest",
    "cpu": 1024,
    "memory": 2048
  }
]
TASK_DEFINITION
}
