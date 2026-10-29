output "workflow_arn" { value = aws_sfn_state_machine.batch.arn }
output "topic_arn" { value = aws_sns_topic.alerts.arn }
output "cluster_arn" { value = aws_ecs_cluster.batch.arn }
output "task_definition_arn" { value = aws_ecs_task_definition.batch.arn }
output "alb_dns" { value = aws_lb.web.dns_name }
output "target_group_arn" { value = aws_lb_target_group.web.arn }
output "schedule_rule" { value = aws_cloudwatch_event_rule.schedule.name }
output "instance_id" { value = var.instance_id }
