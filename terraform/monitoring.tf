locals {
  log_names = toset(["httpd-access", "httpd-error", "tomcat", "bootstrap"])
  alarms = {
    cpu-high        = { namespace = "AWS/EC2", metric = "CPUUtilization", threshold = 80, period = 300, dimensions = { InstanceId = aws_instance.web.id } }
    status-failed   = { namespace = "AWS/EC2", metric = "StatusCheckFailed", threshold = 0, period = 60, dimensions = { InstanceId = aws_instance.web.id } }
    memory-high     = { namespace = "Portfolio/Day1", metric = "mem_used_percent", threshold = 85, period = 60, dimensions = { InstanceId = aws_instance.web.id } }
    disk-root-high  = { namespace = "Portfolio/Day1", metric = "disk_used_percent", threshold = 80, period = 60, dimensions = { InstanceId = aws_instance.web.id, path = "/", fstype = "xfs" } }
    disk-pgsql-high = { namespace = "Portfolio/Day1", metric = "disk_used_percent", threshold = 80, period = 60, dimensions = { InstanceId = aws_instance.web.id, path = "/var/lib/pgsql", fstype = "xfs" } }
  }
}
resource "aws_cloudwatch_log_group" "app" {
  for_each          = local.log_names
  name              = "/portfolio/day1/${each.key}"
  retention_in_days = 7
}
resource "aws_cloudwatch_metric_alarm" "this" {
  for_each            = local.alarms
  alarm_name          = "${var.name_prefix}-${each.key}"
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  dimensions          = each.value.dimensions
  statistic           = "Average"
  threshold           = each.value.threshold
  period              = each.value.period
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = []
  tags                = { Name = "${var.name_prefix}-${each.key}" }
}
