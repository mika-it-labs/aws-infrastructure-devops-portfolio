resource "aws_ssm_document" "day2_verify" {
  count           = var.day2_enabled && var.day2_restore_enabled ? 1 : 0
  name            = "${var.day2_name_prefix}-terraform-verify"
  document_type   = "Command"
  document_format = "JSON"
  tags            = local.day2_tags
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Verify Day 2 load balancers and restored data without replacing the source database"
    parameters = {
      FaultDrill = { type = "String", default = "false", allowedValues = ["true", "false"] }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "VerifyDay2"
      inputs = {
        timeoutSeconds = "900"
        runCommand = [
          "export ALB_DNS='${aws_lb.day2_alb[0].dns_name}' NLB_DNS='${aws_lb.day2_nlb[0].dns_name}' RESTORED_EBS_SERIAL='${replace(aws_ebs_volume.day2_restored[0].id, "-", "")}' RESTORED_EFS_IP='${aws_efs_mount_target.day2_restored[0].ip_address}' FAULT_DRILL='{{ FaultDrill }}'",
          "echo '${filebase64("${path.module}/../scripts/day2-verify.sh")}' | base64 -d > /root/portfolio-day2-verify.sh",
          "bash /root/portfolio-day2-verify.sh"
        ]
      }
    }]
  })
}
output "day2_verification_document" {
  value = try(aws_ssm_document.day2_verify[0].name, null)
}

