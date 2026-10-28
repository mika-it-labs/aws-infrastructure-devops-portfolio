resource "aws_security_group" "task" {
  count       = var.deploy_enabled ? 1 : 0
  name        = "${var.name_prefix}-ecs-sg"
  description = "Tomcat from the existing VPC only"
  vpc_id      = data.aws_vpc.base.id
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.base.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_lb" "app" {
  count                      = var.deploy_enabled ? 1 : 0
  name                       = "${var.name_prefix}-alb"
  internal                   = true
  load_balancer_type         = "application"
  ip_address_type            = "ipv4"
  subnets                    = var.public_subnet_ids
  security_groups            = [var.web_security_group_id]
  enable_deletion_protection = false
}
resource "aws_lb_target_group" "app" {
  count                = var.deploy_enabled ? 1 : 0
  name                 = "${var.name_prefix}-ecs-tg"
  port                 = 8080
  protocol             = "HTTP"
  protocol_version     = "HTTP1"
  target_type          = "ip"
  vpc_id               = data.aws_vpc.base.id
  deregistration_delay = 300
  health_check {
    path                = "/portfolio/health.jsp"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}
resource "aws_lb_listener" "app" {
  count             = var.deploy_enabled ? 1 : 0
  load_balancer_arn = aws_lb.app[0].arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[0].arn
  }
}
resource "aws_ecs_cluster" "app" {
  count = var.deploy_enabled ? 1 : 0
  name  = local.cluster_name
}
resource "aws_ecs_cluster_capacity_providers" "app" {
  count              = var.deploy_enabled ? 1 : 0
  cluster_name       = aws_ecs_cluster.app[0].name
  capacity_providers = ["FARGATE"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 0
  }
}
resource "aws_ecs_task_definition" "app" {
  count                    = var.deploy_enabled ? 1 : 0
  family                   = local.task_family
  cpu                      = "256"
  memory                   = "1024"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = data.aws_iam_role.execution.arn
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  container_definitions = jsonencode([{
    name         = "tomcat"
    image        = local.image_uri
    essential    = true
    portMappings = [{ containerPort = 8080, hostPort = 8080, protocol = "tcp", appProtocol = "http" }]
    logConfiguration = {
      logDriver = "awslogs"
      options   = { awslogs-group = aws_cloudwatch_log_group.task.name, awslogs-region = var.region, awslogs-stream-prefix = "ecs" }
    }
  }])
}
resource "aws_ecs_service" "app" {
  count                              = var.deploy_enabled ? 1 : 0
  name                               = local.service_name
  cluster                            = aws_ecs_cluster.app[0].id
  task_definition                    = aws_ecs_task_definition.app[0].arn
  desired_count                      = var.desired_count
  platform_version                   = "LATEST"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  wait_for_steady_state              = true
  force_delete                       = true
  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.task[0].id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.app[0].arn
    container_name   = "tomcat"
    container_port   = 8080
  }
  lifecycle {
    ignore_changes = [task_definition]
  }
  depends_on = [aws_lb_listener.app, aws_ecs_cluster_capacity_providers.app]
  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}
