output "instance_id" { value = aws_instance.web.id }
output "instance_state" { value = aws_ec2_instance_state.web.state }
output "vpc_id" { value = aws_vpc.this.id }
output "data_volume_id" { value = aws_ebs_volume.postgres.id }
output "efs_id" { value = aws_efs_file_system.shared.id }
output "bucket_names" { value = var.bucket_names }
output "bootstrap_document" { value = aws_ssm_document.bootstrap.name }
output "snapshot_id" { value = try(aws_ebs_snapshot.postgres[0].id, null) }
