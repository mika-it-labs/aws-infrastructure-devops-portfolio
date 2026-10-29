variable "region" { default = "ap-northeast-1" }
variable "expected_account_id" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" {
  type = list(string)
  validation {
    condition     = length(var.public_subnet_ids) == 2
    error_message = "Specify two public subnet IDs from the existing Day 1 VPC."
  }
}
variable "private_subnet_ids" {
  type = list(string)
  validation {
    condition     = length(var.private_subnet_ids) == 2
    error_message = "Specify two private subnet IDs from the existing Day 1 VPC."
  }
}
variable "web_security_group_id" { type = string }
variable "artifact_bucket_name" { type = string }
variable "connection_arn" {
  type        = string
  description = "Existing AVAILABLE CodeConnections connection, authorized for this repository only. OAuth installation is retained outside this state."
}
variable "repository_full_name" { default = "mika-it-labs/aws-infrastructure-devops-portfolio" }
variable "branch" { default = "main" }
variable "name_prefix" {
  default = "portfolio-day3"
  validation {
    condition     = var.name_prefix == "portfolio-day3"
    error_message = "This dedicated lab uses the same portfolio-day3 names as day3/buildspec.yml."
  }
}
variable "run_id" { default = "day3-example" }
variable "execution_role_name" { default = "ecsTaskExecutionRole" }
variable "deploy_enabled" {
  type        = bool
  default     = false
  description = "Enable ECS, ALB and API after the bootstrap image has been built."
}
variable "pipeline_enabled" {
  type    = bool
  default = false
  validation {
    condition     = !var.pipeline_enabled || var.deploy_enabled
    error_message = "The pipeline needs the deployed ECS service."
  }
}
variable "image_uri" {
  type        = string
  default     = null
  nullable    = true
  description = "ECR URI and immutable tag produced by the successful bootstrap build."
}
variable "desired_count" {
  type    = number
  default = 1
  validation {
    condition     = contains([0, 1], var.desired_count)
    error_message = "This learning environment uses zero or one desired task."
  }
}
variable "api_security_policy" { default = "SecurityPolicy_TLS13_1_3_2025_09" }
