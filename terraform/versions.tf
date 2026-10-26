terraform {
  required_version = ">= 1.5.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "local" {}
}
provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "portfolio", Run = var.run_id, ManagedBy = "Terraform" }
  }
}
data "aws_caller_identity" "current" {}
variable "region" { default = "ap-northeast-1" }
variable "run_id" { default = "day1-example" }
variable "name_prefix" { default = "portfolio-day1" }
variable "availability_zones" {
  type    = list(string)
  default = ["ap-northeast-1a", "ap-northeast-1c"]
  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Specify exactly two availability zones."
  }
}
variable "ami_id" {
  type        = string
  description = "Verified official RHEL 9 x86_64 AMI in the selected region."
}
variable "bucket_names" {
  type        = map(string)
  description = "Globally unique static and logs bucket names."
}
variable "instance_state" {
  default = "stopped"
  validation {
    condition     = contains(["running", "stopped"], var.instance_state)
    error_message = "instance_state must be running or stopped."
  }
}
variable "configure_instance" { default = false }
variable "snapshot_enabled" { default = false }
locals {
  subnets = {
    public_a  = { cidr = "10.40.1.0/24", az = 0, public = true, label = "PublicA" }
    public_b  = { cidr = "10.40.2.0/24", az = 1, public = true, label = "PublicB" }
    private_a = { cidr = "10.40.11.0/24", az = 0, public = false, label = "PrivateA" }
    private_b = { cidr = "10.40.12.0/24", az = 1, public = false, label = "PrivateB" }
  }
}
