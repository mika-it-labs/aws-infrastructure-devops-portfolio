resource "aws_sns_topic" "alerts" { name = "${local.prefix}-alerts" }
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "Owner", Effect = "Allow", Principal = { AWS = "arn:aws:iam::${local.account}:root" }, Action = ["SNS:GetTopicAttributes", "SNS:SetTopicAttributes", "SNS:AddPermission", "SNS:RemovePermission", "SNS:DeleteTopic", "SNS:Subscribe", "SNS:ListSubscriptionsByTopic", "SNS:Publish"], Resource = aws_sns_topic.alerts.arn },
    { Sid = "Day4CloudWatch", Effect = "Allow", Principal = { Service = "cloudwatch.amazonaws.com" }, Action = "sns:Publish", Resource = aws_sns_topic.alerts.arn, Condition = { StringEquals = { "aws:SourceAccount" = local.account }, ArnLike = { "aws:SourceArn" = "arn:aws:cloudwatch:${var.region}:${local.account}:alarm:${local.prefix}-*" } } },
    { Sid = "Day4Stopped", Effect = "Allow", Principal = { Service = "events.amazonaws.com" }, Action = "sns:Publish", Resource = aws_sns_topic.alerts.arn, Condition = { StringEquals = { "aws:SourceAccount" = local.account }, ArnEquals = { "aws:SourceArn" = local.stopped_arn } } }
  ] })
}
resource "aws_iam_role" "events" {
  name = "${local.prefix}-events-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { Service = "events.amazonaws.com" }, Action = "sts:AssumeRole"
    Condition = { StringEquals = { "aws:SourceAccount" = local.account }, ArnEquals = { "aws:SourceArn" = local.schedule_arn } }
  }] })
}
resource "aws_iam_role_policy" "events" {
  name   = "PortfolioDay4StartExecution"
  role   = aws_iam_role.events.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "states:StartExecution", Resource = local.workflow_arn }] })
}
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${local.prefix}-schedule"
  schedule_expression = var.schedule_expression
  state               = var.schedule_enabled ? "ENABLED" : "DISABLED"
}
resource "aws_cloudwatch_event_target" "schedule" {
  rule       = aws_cloudwatch_event_rule.schedule.name
  target_id  = "workflow"
  arn        = aws_sfn_state_machine.batch.arn
  role_arn   = aws_iam_role.events.arn
  input      = jsonencode({ forceFailure = "false", trigger = "EventBridge", schedule = "${local.prefix}-schedule" })
  depends_on = [aws_iam_role_policy.events]
}
resource "aws_cloudwatch_event_rule" "stopped" {
  name          = "${local.prefix}-ec2-state"
  event_pattern = jsonencode({ source = ["aws.ec2"], "detail-type" = ["EC2 Instance State-change Notification"], detail = { "instance-id" = [var.instance_id], state = ["stopped"] } })
}
resource "aws_cloudwatch_event_target" "stopped" {
  rule       = aws_cloudwatch_event_rule.stopped.name
  target_id  = "sns"
  arn        = aws_sns_topic.alerts.arn
  input      = jsonencode({ message = "Portfolio Day4 IaC: portfolio Day1 EC2 reached stopped state.", rule = "${local.prefix}-ec2-state" })
  depends_on = [aws_sns_topic_policy.alerts]
}
