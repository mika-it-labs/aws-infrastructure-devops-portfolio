resource "aws_s3_bucket" "this" {
  for_each      = var.bucket_names
  bucket        = each.value
  force_destroy = false
  tags          = { Name = "${var.name_prefix}-${each.key}" }
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = var.bucket_names
  bucket                  = aws_s3_bucket.this[each.key].id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = var.bucket_names
  bucket   = aws_s3_bucket.this[each.key].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "this" {
  for_each = var.bucket_names
  bucket   = aws_s3_bucket.this[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      { Effect = "Allow", Principal = { AWS = aws_iam_role.ec2.arn }, Action = ["s3:PutObject", "s3:GetObject"], Resource = "${aws_s3_bucket.this[each.key].arn}/*" },
      { Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.this[each.key].arn, "${aws_s3_bucket.this[each.key].arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } }
      ], var.day2_enabled && each.key == "logs" ? [{
        Sid       = "PortfolioDay2ALBLogs"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.this[each.key].arn}/${var.day2_log_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = { ArnLike = { "aws:SourceArn" = "arn:aws:elasticloadbalancing:${var.region}:${data.aws_caller_identity.current.account_id}:loadbalancer/*" } }
    }] : [])
  })
  depends_on = [aws_s3_bucket_public_access_block.this]
}
resource "aws_efs_file_system" "shared" {
  creation_token   = var.run_id
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  tags             = { Name = "${var.name_prefix}-shared" }
  lifecycle { prevent_destroy = true }
}
resource "aws_efs_mount_target" "shared" {
  file_system_id  = aws_efs_file_system.shared.id
  subnet_id       = aws_subnet.this["private_a"].id
  security_groups = [aws_security_group.efs.id]
}
resource "aws_ebs_volume" "postgres" {
  availability_zone = var.availability_zones[0]
  size              = 8
  type              = "gp3"
  encrypted         = true
  tags              = { Name = "${var.name_prefix}-ebs" }
  lifecycle { prevent_destroy = true }
}
resource "aws_volume_attachment" "postgres" {
  device_name                    = "/dev/sdf"
  volume_id                      = aws_ebs_volume.postgres.id
  instance_id                    = aws_instance.web.id
  force_detach                   = false
  stop_instance_before_detaching = true
}
resource "aws_ebs_snapshot" "postgres" {
  count       = var.snapshot_enabled ? 1 : 0
  volume_id   = aws_ebs_volume.postgres.id
  description = "Portfolio Day1 PostgreSQL data - clean EC2 shutdown"
  tags        = { Name = "${var.name_prefix}-pgsql" }
  depends_on  = [aws_ec2_instance_state.web]
  lifecycle { prevent_destroy = true }
}

