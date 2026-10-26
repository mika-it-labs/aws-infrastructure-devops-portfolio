resource "aws_instance" "web" {
  ami                         = var.ami_id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.this["public_a"].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  ebs_optimized               = false
  monitoring                  = false
  user_data                   = file("${path.module}/../scripts/user-data.sh")
  credit_specification { cpu_credits = "standard" }
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    volume_size           = 15
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
    tags                  = { Name = "${var.name_prefix}-ebs", Project = "portfolio", Run = var.run_id }
  }
  tags       = { Name = "${var.name_prefix}-rhel" }
  depends_on = [aws_route.internet, aws_iam_role_policy_attachment.ec2]
  lifecycle {
    prevent_destroy = true
    # The data disk is managed by aws_ebs_volume / aws_volume_attachment.
    # Preserve the original SSM-only user-data on the adopted server.
    ignore_changes = [ebs_block_device, user_data, associate_public_ip_address]
  }
}
resource "aws_ec2_instance_state" "web" {
  instance_id = aws_instance.web.id
  state       = var.instance_state
}
resource "aws_ssm_document" "bootstrap" {
  name            = "${var.name_prefix}-terraform-bootstrap"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Configure the RHEL Day1 app without storing DB passwords in Terraform state"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "ConfigureDay1"
      inputs = {
        timeoutSeconds = "1800"
        runCommand = [
          "export DATA_VOLUME_ID='${aws_ebs_volume.postgres.id}' EFS_IP='${aws_efs_mount_target.shared.ip_address}' STATIC_BUCKET='${aws_s3_bucket.this["static"].id}' LOG_BUCKET='${aws_s3_bucket.this["logs"].id}'",
          "echo '${filebase64("${path.module}/../scripts/bootstrap.sh")}' | base64 -d > /root/portfolio-terraform-bootstrap.sh",
          "bash /root/portfolio-terraform-bootstrap.sh"
        ]
      }
    }]
  })
}
resource "aws_ssm_association" "bootstrap" {
  count            = var.configure_instance ? 1 : 0
  name             = aws_ssm_document.bootstrap.name
  association_name = "${var.name_prefix}-terraform-configure"
  document_version = aws_ssm_document.bootstrap.latest_version
  targets {
    key    = "InstanceIds"
    values = [aws_instance.web.id]
  }
  wait_for_success_timeout_seconds = 1800
  depends_on                       = [aws_volume_attachment.postgres, aws_ec2_instance_state.web, aws_s3_bucket_policy.this, aws_cloudwatch_log_group.app]
  lifecycle {
    precondition {
      condition     = var.instance_state == "running"
      error_message = "Start EC2 and wait for SSM Online before enabling configure_instance."
    }
  }
}

