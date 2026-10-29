resource "aws_cloudwatch_log_group" "batch" {
  name              = "/portfolio/day4/batch"
  retention_in_days = 7
}
resource "aws_security_group" "batch" {
  name        = "${local.prefix}-batch-sg"
  description = "No inbound; HTTPS egress for image download and logging"
  vpc_id      = var.vpc_id
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_ecs_cluster" "batch" { name = "${local.prefix}-cluster" }
resource "aws_ecs_task_definition" "batch" {
  family                   = "${local.prefix}-batch"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = data.aws_iam_role.execution.arn
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  container_definitions = jsonencode([{
    name        = "batch", essential = true
    image       = "public.ecr.aws/amazonlinux/amazonlinux:2023"
    command     = ["/bin/sh", "-c", "echo BATCH_START; sleep 5; if [ \"$${DEMO_FAIL:-false}\" = \"true\" ]; then echo BATCH_RESULT=FAIL; exit 42; fi; echo BATCH_RESULT=SUCCESS; exit 0"]
    environment = [{ name = "DEMO_FAIL", value = "false" }]
    logConfiguration = { logDriver = "awslogs", options = {
      awslogs-group         = aws_cloudwatch_log_group.batch.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "batch"
    } }
  }])
}
resource "aws_iam_role" "sfn" {
  name = "${local.prefix}-sfn-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { Service = "states.amazonaws.com" }, Action = "sts:AssumeRole"
    Condition = { StringEquals = { "aws:SourceAccount" = local.account }, ArnEquals = { "aws:SourceArn" = local.workflow_arn } }
  }] })
}
resource "aws_iam_role_policy" "sfn" {
  name = "PortfolioDay4SfnPolicy"
  role = aws_iam_role.sfn.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "ecs:RunTask", Resource = aws_ecs_task_definition.batch.arn, Condition = { ArnEquals = { "ecs:cluster" = aws_ecs_cluster.batch.arn } } },
    { Effect = "Allow", Action = ["ecs:DescribeTasks", "ecs:StopTask"], Resource = "arn:aws:ecs:${var.region}:${local.account}:task/${aws_ecs_cluster.batch.name}/*" },
    { Effect = "Allow", Action = ["events:PutTargets", "events:PutRule", "events:DescribeRule"], Resource = "arn:aws:events:${var.region}:${local.account}:rule/StepFunctionsGetEventsForECSTaskRule" },
    { Effect = "Allow", Action = "sns:Publish", Resource = aws_sns_topic.alerts.arn },
    { Effect = "Allow", Action = "iam:PassRole", Resource = data.aws_iam_role.execution.arn, Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } } }
  ] })
}
resource "aws_sfn_state_machine" "batch" {
  name     = "${local.prefix}-workflow"
  type     = "STANDARD"
  role_arn = aws_iam_role.sfn.arn
  definition = templatefile("${path.module}/workflow.asl.json.tftpl", {
    cluster_arn = aws_ecs_cluster.batch.arn, task_arn = aws_ecs_task_definition.batch.arn,
    subnet_ids  = jsonencode(var.public_subnet_ids), sg_id = aws_security_group.batch.id,
    topic_arn   = aws_sns_topic.alerts.arn
  })
  depends_on = [aws_iam_role_policy.sfn]
}
