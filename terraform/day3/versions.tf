terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.70.0"
    }
  }
  backend "local" {}
}
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.expected_account_id]
  default_tags {
    tags = { Project = "portfolio", Day = "3", ManagedBy = "Terraform", Run = var.run_id }
  }
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_vpc" "base" { id = var.vpc_id }
data "aws_s3_bucket" "artifacts" { bucket = var.artifact_bucket_name }
data "aws_iam_role" "execution" { name = var.execution_role_name }
locals {
  account_id      = data.aws_caller_identity.current.account_id
  partition       = data.aws_partition.current.partition
  pipeline_name   = "${var.name_prefix}-pipeline"
  artifact_prefix = substr(local.pipeline_name, 0, 20)
  build_name      = "${var.name_prefix}-build"
  cluster_name    = "${var.name_prefix}-cluster"
  service_name    = "${var.name_prefix}-service"
  task_family     = "${var.name_prefix}-task"
  image_uri       = coalesce(var.image_uri, "${aws_ecr_repository.app.repository_url}:bootstrap-not-built")
  build_log_group = "/portfolio/day3/codebuild"
  task_log_group  = "/portfolio/day3/ecs"
}
