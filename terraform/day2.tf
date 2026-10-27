variable "day2_enabled" {
  description = "Create the internal Day 2 load balancers and 5xx alarm."
  type        = bool
  default     = false
}
variable "manage_day2_backup" {
  description = "Manage the Day 2 backup plan. Import an existing plan before applying."
  type        = bool
  default     = false
}
variable "day2_backup_assignment_enabled" {
  description = "Enable scheduled backups for only the Day 1 database EBS and EFS."
  type        = bool
  default     = false
}
variable "day2_run_id" {
  type    = string
  default = "day2-example"
}
variable "day2_name_prefix" {
  type    = string
  default = "portfolio-day2"
}
variable "day2_backup_vault_name" {
  type    = string
  default = "Default"
}
variable "day2_backup_role_name" {
  type    = string
  default = "AWSBackupDefaultServiceRole"
}
variable "day2_log_prefix" {
  type    = string
  default = "alb"
}
locals {
  day2_tags = { Project = "portfolio", Day = "2", Run = var.day2_run_id, ManagedBy = "Terraform" }
}
data "aws_iam_role" "day2_backup" {
  count = var.manage_day2_backup ? 1 : 0
  name  = var.day2_backup_role_name
}
data "aws_backup_vault" "day2" {
  count = var.manage_day2_backup ? 1 : 0
  name  = var.day2_backup_vault_name
}
resource "aws_backup_plan" "day2" {
  count = var.manage_day2_backup ? 1 : 0
  name  = "${var.day2_name_prefix}-backup"
  rule {
    rule_name                    = "day2-daily-seven-days"
    target_vault_name            = data.aws_backup_vault.day2[0].name
    schedule                     = "cron(30 0 * * ? *)"
    schedule_expression_timezone = "Asia/Tokyo"
    start_window                 = 480
    completion_window            = 10080
    lifecycle { delete_after = 7 }
  }
  tags = local.day2_tags
}
resource "aws_backup_selection" "day2" {
  count        = var.manage_day2_backup && var.day2_backup_assignment_enabled ? 1 : 0
  name         = "${var.day2_name_prefix}-ebs-efs"
  plan_id      = aws_backup_plan.day2[0].id
  iam_role_arn = data.aws_iam_role.day2_backup[0].arn
  resources    = [aws_ebs_volume.postgres.arn, aws_efs_file_system.shared.arn]
}
resource "aws_lb" "day2_alb" {
  count                      = var.day2_enabled ? 1 : 0
  name                       = "${var.day2_name_prefix}-alb"
  internal                   = true
  load_balancer_type         = "application"
  ip_address_type            = "ipv4"
  subnets                    = [aws_subnet.this["public_a"].id, aws_subnet.this["public_b"].id]
  security_groups            = [aws_security_group.web.id]
  enable_deletion_protection = false
  access_logs {
    bucket  = aws_s3_bucket.this["logs"].id
    prefix  = var.day2_log_prefix
    enabled = true
  }
  tags       = local.day2_tags
  depends_on = [aws_s3_bucket_policy.this]
}
resource "aws_lb_target_group" "day2_alb" {
  count       = var.day2_enabled ? 1 : 0
  name        = "${var.day2_name_prefix}-alb-http"
  protocol    = "HTTP"
  port        = 80
  vpc_id      = aws_vpc.this.id
  target_type = "instance"
  health_check {
    protocol            = "HTTP"
    path                = "/portfolio/"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
  tags = local.day2_tags
}
resource "aws_lb_target_group_attachment" "day2_alb" {
  count            = var.day2_enabled ? 1 : 0
  target_group_arn = aws_lb_target_group.day2_alb[0].arn
  target_id        = aws_instance.web.id
  port             = 80
}
resource "aws_lb_listener" "day2_alb" {
  count             = var.day2_enabled ? 1 : 0
  load_balancer_arn = aws_lb.day2_alb[0].arn
  protocol          = "HTTP"
  port              = 80
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.day2_alb[0].arn
  }
  tags = local.day2_tags
}
resource "aws_lb" "day2_nlb" {
  count                            = var.day2_enabled ? 1 : 0
  name                             = "${var.day2_name_prefix}-nlb"
  internal                         = true
  load_balancer_type               = "network"
  ip_address_type                  = "ipv4"
  subnets                          = [aws_subnet.this["public_a"].id, aws_subnet.this["public_b"].id]
  security_groups                  = [aws_security_group.web.id]
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = false
  tags                             = local.day2_tags
}
resource "aws_lb_target_group" "day2_nlb" {
  count                             = var.day2_enabled ? 1 : 0
  name                              = "${var.day2_name_prefix}-nlb-tcp"
  protocol                          = "TCP"
  port                              = 80
  vpc_id                            = aws_vpc.this.id
  target_type                       = "instance"
  preserve_client_ip                = false
  load_balancing_cross_zone_enabled = "true"
  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
  tags = local.day2_tags
}
resource "aws_lb_target_group_attachment" "day2_nlb" {
  count            = var.day2_enabled ? 1 : 0
  target_group_arn = aws_lb_target_group.day2_nlb[0].arn
  target_id        = aws_instance.web.id
  port             = 80
}
resource "aws_lb_listener" "day2_nlb" {
  count             = var.day2_enabled ? 1 : 0
  load_balancer_arn = aws_lb.day2_nlb[0].arn
  protocol          = "TCP"
  port              = 80
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.day2_nlb[0].arn
  }
  tags = local.day2_tags
}
resource "aws_cloudwatch_metric_alarm" "day2_alb_target_5xx" {
  count               = var.day2_enabled ? 1 : 0
  alarm_name          = "${var.day2_name_prefix}-alb-target-5xx"
  alarm_description   = "Day 2 lab: target HTTP 5xx Sum > 0 per minute; SNS integration is deferred."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = aws_lb.day2_alb[0].arn_suffix }
  statistic           = "Sum"
  threshold           = 0
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = []
  ok_actions          = []
  tags                = local.day2_tags
}
output "day2" {
  value = {
    enabled              = var.day2_enabled
    alb_dns              = try(aws_lb.day2_alb[0].dns_name, null)
    nlb_dns              = try(aws_lb.day2_nlb[0].dns_name, null)
    alb_target_group_arn = try(aws_lb_target_group.day2_alb[0].arn, null)
    nlb_target_group_arn = try(aws_lb_target_group.day2_nlb[0].arn, null)
    backup_plan_id       = try(aws_backup_plan.day2[0].id, null)
    backup_vault         = var.manage_day2_backup ? data.aws_backup_vault.day2[0].name : null
    backup_role_arn      = var.manage_day2_backup ? data.aws_iam_role.day2_backup[0].arn : null
    backup_assigned      = var.manage_day2_backup && var.day2_backup_assignment_enabled
    db_volume_arn        = aws_ebs_volume.postgres.arn
    efs_arn              = aws_efs_file_system.shared.arn
    log_bucket           = aws_s3_bucket.this["logs"].id
    log_prefix           = var.day2_log_prefix
  }
}

