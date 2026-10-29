resource "aws_lb" "web" {
  name                       = "${local.prefix}-alb"
  internal                   = true
  load_balancer_type         = "application"
  subnets                    = var.public_subnet_ids
  security_groups            = [var.web_security_group_id]
  enable_deletion_protection = false
}
resource "aws_lb_target_group" "web" {
  name        = "${local.prefix}-web-tg"
  target_type = "instance"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  health_check {
    path                = "/portfolio/"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}
resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = var.instance_id
  port             = 80
}
resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "${local.prefix}-cpu-high"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = var.instance_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
resource "aws_cloudwatch_metric_alarm" "disk" {
  alarm_name          = "${local.prefix}-disk-root-high"
  namespace           = "Portfolio/Day1"
  metric_name         = "disk_used_percent"
  dimensions          = { InstanceId = var.instance_id, path = "/", fstype = "xfs" }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.prefix}-alb-target-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = aws_lb.web.arn_suffix }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}
resource "aws_cloudwatch_dashboard" "operations" {
  dashboard_name = "${local.prefix}-operations"
  dashboard_body = jsonencode({ start = "-PT3H", widgets = [
    { type = "metric", x = 0, y = 0, width = 12, height = 6, properties = { region = var.region, title = "RHEL CPU and disk", period = 60, stat = "Average", metrics = [["AWS/EC2", "CPUUtilization", "InstanceId", var.instance_id], ["Portfolio/Day1", "disk_used_percent", "InstanceId", var.instance_id, "path", "/", "fstype", "xfs"]] } },
    { type = "metric", x = 12, y = 0, width = 12, height = 6, properties = { region = var.region, title = "ALB requests and target 5xx", period = 60, stat = "Sum", metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.web.arn_suffix], ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.web.arn_suffix]] } },
    { type = "metric", x = 0, y = 6, width = 12, height = 6, properties = { region = var.region, title = "Workflow results", period = 60, stat = "Sum", metrics = [["AWS/States", "ExecutionsSucceeded", "StateMachineArn", local.workflow_arn], ["AWS/States", "ExecutionsFailed", "StateMachineArn", local.workflow_arn]] } },
    { type = "metric", x = 12, y = 6, width = 12, height = 6, properties = { region = var.region, title = "SNS delivered", period = 60, stat = "Sum", metrics = [["AWS/SNS", "NumberOfNotificationsDelivered", "TopicName", aws_sns_topic.alerts.name]] } },
    { type = "log", x = 0, y = 12, width = 24, height = 6, properties = { region = var.region, title = "Batch logs", view = "table", query = "SOURCE '${aws_cloudwatch_log_group.batch.name}' | fields @timestamp, @message | sort @timestamp desc | limit 20" } }
  ] })
}
