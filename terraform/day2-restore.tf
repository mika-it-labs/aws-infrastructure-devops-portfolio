variable "day2_restore_enabled" {
  description = "Adopt AWS Backup restore-job results and manage their attachments with Terraform."
  type        = bool
  default     = false
}
variable "day2_restored_ebs_id" {
  type    = string
  default = null
}
variable "day2_restored_efs_id" {
  type    = string
  default = null
}
variable "day2_restored_snapshot_id" {
  type    = string
  default = null
}
# AWS Backup jobs are operations, not aws_backup resource instances.
# Supply completed restore-job IDs; these blocks adopt the actual restored data.
import {
  for_each = var.day2_restore_enabled && var.day2_restored_ebs_id != null ? { restored = var.day2_restored_ebs_id } : {}
  to       = aws_ebs_volume.day2_restored[0]
  id       = each.value
}
import {
  for_each = var.day2_restore_enabled && var.day2_restored_efs_id != null ? { restored = var.day2_restored_efs_id } : {}
  to       = aws_efs_file_system.day2_restored[0]
  id       = each.value
}
resource "aws_ebs_volume" "day2_restored" {
  count             = var.day2_restore_enabled ? 1 : 0
  availability_zone = var.availability_zones[0]
  snapshot_id       = var.day2_restored_snapshot_id
  size              = 8
  type              = "gp3"
  iops              = 3000
  throughput        = 125
  encrypted         = true
  tags              = merge(local.day2_tags, { Name = "${var.day2_name_prefix}-restored-ebs" })
  lifecycle {
    precondition {
      condition     = var.day2_restored_ebs_id != null && var.day2_restored_snapshot_id != null
      error_message = "Finish an AWS Backup restore job and provide its volume ID and source snapshot ID before planning."
    }
  }
}
resource "aws_efs_file_system" "day2_restored" {
  count            = var.day2_restore_enabled ? 1 : 0
  encrypted        = true
  performance_mode = "generalPurpose"
  tags             = merge(local.day2_tags, { Name = "${var.day2_name_prefix}-restored-efs" })
  lifecycle {
    precondition {
      condition     = var.day2_restored_efs_id != null
      error_message = "Finish an AWS Backup restore job and provide its filesystem ID; do not create an empty substitute."
    }
  }
}
resource "aws_volume_attachment" "day2_restored" {
  count                          = var.day2_restore_enabled ? 1 : 0
  device_name                    = "/dev/sdg"
  volume_id                      = aws_ebs_volume.day2_restored[0].id
  instance_id                    = aws_instance.web.id
  force_detach                   = false
  stop_instance_before_detaching = true
}
resource "aws_efs_mount_target" "day2_restored" {
  count           = var.day2_restore_enabled ? 1 : 0
  file_system_id  = aws_efs_file_system.day2_restored[0].id
  subnet_id       = aws_subnet.this["private_a"].id
  security_groups = [aws_security_group.efs.id]
}
output "day2_restore" {
  value = {
    volume_id       = try(aws_ebs_volume.day2_restored[0].id, null)
    filesystem_id   = try(aws_efs_file_system.day2_restored[0].id, null)
    mount_target_ip = try(aws_efs_mount_target.day2_restored[0].ip_address, null)
  }
}

