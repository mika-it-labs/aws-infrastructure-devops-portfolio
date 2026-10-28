resource "aws_iam_role" "pipeline" {
  name = "${local.pipeline_name}-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "codepipeline.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy" "pipeline" {
  name = "PortfolioDay3PipelinePolicy"
  role = aws_iam_role.pipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetBucketVersioning", "s3:GetBucketAcl", "s3:GetBucketLocation"], Resource = data.aws_s3_bucket.artifacts.arn },
      {
        Effect   = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetObjectTagging", "s3:PutObjectTagging"]
        Resource = "${data.aws_s3_bucket.artifacts.arn}/${local.artifact_prefix}/*"
      },
      { Effect = "Allow", Action = ["codeconnections:UseConnection"], Resource = var.connection_arn },
      { Effect = "Allow", Action = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"], Resource = aws_codebuild_project.app.arn },
      { Effect = "Allow", Action = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"], Resource = "*" },
      {
        Effect   = "Allow", Action = ["ecs:DescribeServices", "ecs:UpdateService"]
        Resource = "arn:${local.partition}:ecs:${var.region}:${local.account_id}:service/${local.cluster_name}/${local.service_name}"
      },
      {
        Effect    = "Allow", Action = ["ecs:TagResource"]
        Resource  = "arn:${local.partition}:ecs:${var.region}:${local.account_id}:task-definition/${local.task_family}:*"
        Condition = { StringEquals = { "ecs:CreateAction" = "RegisterTaskDefinition" } }
      },
      {
        Effect    = "Allow", Action = ["iam:PassRole"], Resource = data.aws_iam_role.execution.arn
        Condition = { StringEquals = { "iam:PassedToService" = ["ecs.amazonaws.com", "ecs-tasks.amazonaws.com"] } }
      }
    ]
  })
}
resource "aws_codepipeline" "app" {
  count          = var.pipeline_enabled ? 1 : 0
  name           = local.pipeline_name
  role_arn       = aws_iam_role.pipeline.arn
  pipeline_type  = "V2"
  execution_mode = "QUEUED"
  artifact_store {
    location = data.aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }
  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceArtifact"]
      namespace        = "SourceVariables"
      configuration = {
        ConnectionArn        = var.connection_arn
        FullRepositoryId     = var.repository_full_name
        BranchName           = var.branch
        OutputArtifactFormat = "CODE_ZIP"
        DetectChanges        = "true"
      }
    }
  }
  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]
      namespace        = "BuildVariables"
      configuration    = { ProjectName = aws_codebuild_project.app.name }
    }
  }
  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["BuildArtifact"]
      configuration = {
        ClusterName = aws_ecs_cluster.app[0].name
        ServiceName = aws_ecs_service.app[0].name
        FileName    = "imagedefinitions.json"
      }
    }
  }
  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      push {
        branches { includes = [var.branch] }
        file_paths { includes = ["day3/**"] }
      }
    }
  }
  depends_on = [aws_iam_role_policy.pipeline, aws_ecs_service.app]
}
