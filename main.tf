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

resource "aws_s3_bucket" "dbt_poc_envs_bucket" {
  bucket = "dbt-poc-envs"
}

resource "aws_ecs_cluster" "dbt_poc_cluster" {
  name = "dbt-poc-cluster"
}

data "aws_iam_policy" "ecs_task_aws_managed_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "dbt_poc_task_exec_role" {
  name               = "dbt-poc-task-exec-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Sid       = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dbt_poc_task_exec_role_policy_attachment" {
  role       = aws_iam_role.dbt_poc_task_exec_role.name
  policy_arn = data.aws_iam_policy.ecs_task_aws_managed_policy.arn
}

resource "aws_iam_role_policy" "dbt_poc_task_exec_role_policy" {
  name   = "dbt-poc-task-exec-role-policy"
  role   = aws_iam_role.dbt_poc_task_exec_role.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action   = "s3:GetObject"
        Resource = aws_s3_bucket.dbt_poc_envs_bucket.arn
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_iam_role" "dbt_poc_task_container_role" {
  name               = "dbt-poc-task-container-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Sid       = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "dbt_poc_task_container_role_policy" {
  name   = "dbt-poc-task-container-role-policy"
  role   = aws_iam_role.dbt_poc_task_container_role.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.snowflake_password.arn
        Effect   = "Allow"
      },
      {
        Action   = "s3:GetObject"
        Resource = aws_s3_bucket.dbt_poc_envs_bucket.arn
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "dbt_poc_task_log_group" {
  name              = "dbt-poc-task-log-group"
  skip_destroy      = true
  retention_in_days = 1
}

resource "aws_ecs_task_definition" "dbt_poc_task" {
  family                   = "dbt-poc-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.dbt_poc_task_exec_role.arn
  task_role_arn            = aws_iam_role.dbt_poc_task_container_role.arn
  container_definitions    = jsonencode([
    {
      name             = "dbt-poc-container"
      image            = "981619280753.dkr.ecr.eu-west-1.amazonaws.com/dbt_poc_repo:latest"
      cpu              = 1024
      memory           = 2048
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = aws_cloudwatch_log_group.dbt_poc_task_log_group.name
          awslogs-region        = "eu-west-1"
          awslogs-stream-prefix = "dbt_poc"
        }
      }
    }
  ])
}

