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
    tags = { Project = "portfolio", Day = "4", ManagedBy = "Terraform" }
  }
}
variable "region" { default = "ap-northeast-1" }
variable "expected_account_id" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" {
  type = list(string)
  validation {
    condition     = length(distinct(var.public_subnet_ids)) == 2
    error_message = "Specify exactly two different existing public subnets."
  }
}
variable "web_security_group_id" { type = string }
variable "instance_id" { type = string }
variable "notification_email" {
  type      = string
  sensitive = true
}
variable "schedule_expression" { default = "rate(1 day)" }
variable "schedule_enabled" { default = false }
data "aws_caller_identity" "current" {}
data "aws_vpc" "base" { id = var.vpc_id }
data "aws_instance" "web" { instance_id = var.instance_id }
data "aws_subnet" "instance" {
  id = data.aws_instance.web.subnet_id
  lifecycle {
    postcondition {
      condition     = self.vpc_id == var.vpc_id
      error_message = "The existing instance must belong to the selected Day1 VPC."
    }
  }
}
data "aws_subnet" "public" {
  for_each = toset(var.public_subnet_ids)
  id       = each.value
  lifecycle {
    postcondition {
      condition     = self.vpc_id == var.vpc_id
      error_message = "Both public subnets must belong to the selected Day1 VPC."
    }
  }
}
data "aws_iam_role" "execution" { name = "ecsTaskExecutionRole" }
locals {
  prefix       = "portfolio-day4"
  base_arn     = "arn:aws"
  account      = data.aws_caller_identity.current.account_id
  workflow_arn = "arn:aws:states:${var.region}:${local.account}:stateMachine:${local.prefix}-workflow"
  schedule_arn = "arn:aws:events:${var.region}:${local.account}:rule/${local.prefix}-schedule"
  stopped_arn  = "arn:aws:events:${var.region}:${local.account}:rule/${local.prefix}-ec2-state"
}
check "base_instance_vpc" {
  assert {
    condition     = data.aws_subnet.instance.vpc_id == data.aws_vpc.base.id && length(var.public_subnet_ids) == 2 && alltrue([for s in data.aws_subnet.public : s.vpc_id == var.vpc_id])
    error_message = "Use the existing Day1 instance and two public subnets in its VPC."
  }
}
