resource "aws_ecr_repository" "app" {
  name                 = "${var.name_prefix}-tomcat"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true
  encryption_configuration { encryption_type = "AES256" }
}
resource "aws_cloudwatch_log_group" "build" {
  name              = local.build_log_group
  retention_in_days = 7
}
resource "aws_cloudwatch_log_group" "task" {
  name              = local.task_log_group
  retention_in_days = 7
}
resource "aws_iam_role" "build" {
  name = "codebuild-${local.build_name}-service-role"
  path = "/service-role/"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "codebuild.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy" "build" {
  name = "PortfolioDay3Build"
  role = aws_iam_role.build.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = ["${aws_cloudwatch_log_group.build.arn}:*"] },
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"]
        Resource = aws_ecr_repository.app.arn
      },
      { Effect = "Allow", Action = ["s3:GetBucketAcl", "s3:GetBucketLocation"], Resource = data.aws_s3_bucket.artifacts.arn },
      {
        Effect   = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = ["${data.aws_s3_bucket.artifacts.arn}/day3/artifacts/*", "${data.aws_s3_bucket.artifacts.arn}/${local.artifact_prefix}/*"]
      }
    ]
  })
}
resource "aws_codebuild_project" "app" {
  name           = local.build_name
  description    = "Day 3 WAR build, container smoke test and ECR publish"
  service_role   = aws_iam_role.build.arn
  build_timeout  = 15
  queued_timeout = 30
  source_version = var.branch
  artifacts {
    type                   = "S3"
    location               = data.aws_s3_bucket.artifacts.bucket
    path                   = "day3/artifacts"
    namespace_type         = "NONE"
    name                   = "deployment.zip"
    packaging              = "ZIP"
    override_artifact_name = false
    encryption_disabled    = false
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux-x86_64-standard:6.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }
  source {
    type                = "GITHUB"
    location            = "https://github.com/${var.repository_full_name}"
    git_clone_depth     = 1
    buildspec           = "day3/buildspec.yml"
    report_build_status = false
    insecure_ssl        = false
  }
  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
      status     = "ENABLED"
    }
  }
  depends_on = [aws_iam_role_policy.build]
}
