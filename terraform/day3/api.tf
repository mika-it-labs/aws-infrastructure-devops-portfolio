resource "aws_apigatewayv2_vpc_link" "app" {
  count              = var.deploy_enabled ? 1 : 0
  name               = "${var.name_prefix}-vpclink"
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [var.web_security_group_id]
}
resource "aws_api_gateway_rest_api" "app" {
  count                = var.deploy_enabled ? 1 : 0
  name                 = "${var.name_prefix}-api"
  description          = "Day 3 REST API to internal Tomcat service"
  api_key_source       = "HEADER"
  security_policy      = var.api_security_policy
  endpoint_access_mode = "BASIC"
  endpoint_configuration {
    types           = ["REGIONAL"]
    ip_address_type = "ipv4"
  }
}
resource "aws_api_gateway_method" "app" {
  count            = var.deploy_enabled ? 1 : 0
  rest_api_id      = aws_api_gateway_rest_api.app[0].id
  resource_id      = aws_api_gateway_rest_api.app[0].root_resource_id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
}
resource "aws_api_gateway_integration" "app" {
  count                   = var.deploy_enabled ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.app[0].id
  resource_id             = aws_api_gateway_rest_api.app[0].root_resource_id
  http_method             = aws_api_gateway_method.app[0].http_method
  integration_http_method = "GET"
  type                    = "HTTP_PROXY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_apigatewayv2_vpc_link.app[0].id
  integration_target      = aws_lb.app[0].arn
  uri                     = "http://${aws_lb.app[0].dns_name}/portfolio/"
  timeout_milliseconds    = 29000
  passthrough_behavior    = "WHEN_NO_MATCH"
}
resource "aws_api_gateway_deployment" "app" {
  count       = var.deploy_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.app[0].id
  triggers = {
    configuration = sha1(jsonencode({
      method           = aws_api_gateway_method.app[0].http_method
      api_key_required = aws_api_gateway_method.app[0].api_key_required
      uri              = aws_api_gateway_integration.app[0].uri
      connection       = aws_apigatewayv2_vpc_link.app[0].id
      target           = aws_lb.app[0].arn
    }))
  }
  lifecycle { create_before_destroy = true }
  depends_on = [aws_api_gateway_integration.app]
}
resource "aws_api_gateway_stage" "app" {
  count                 = var.deploy_enabled ? 1 : 0
  rest_api_id           = aws_api_gateway_rest_api.app[0].id
  deployment_id         = aws_api_gateway_deployment.app[0].id
  stage_name            = "lab"
  cache_cluster_enabled = false
}
resource "aws_api_gateway_api_key" "app" {
  count   = var.deploy_enabled ? 1 : 0
  name    = "${var.name_prefix}-key"
  enabled = true
}
resource "aws_api_gateway_usage_plan" "app" {
  count = var.deploy_enabled ? 1 : 0
  name  = "${var.name_prefix}-usage"
  api_stages {
    api_id = aws_api_gateway_rest_api.app[0].id
    stage  = aws_api_gateway_stage.app[0].stage_name
  }
  throttle_settings {
    rate_limit  = 1
    burst_limit = 2
  }
  quota_settings {
    limit  = 100
    period = "DAY"
  }
}
resource "aws_api_gateway_usage_plan_key" "app" {
  count         = var.deploy_enabled ? 1 : 0
  key_id        = aws_api_gateway_api_key.app[0].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.app[0].id
}
