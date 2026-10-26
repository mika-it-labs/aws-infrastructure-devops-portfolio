param([Parameter(Mandatory=$true)][string]$ResourceFile)
$ErrorActionPreference='Stop'
$Output=Join-Path $PSScriptRoot 'imports.local.tf'
if(Test-Path $Output){throw 'imports.local.tf already exists. Inspect it before replacing it.'}
$S=Get-Content $ResourceFile -Raw|ConvertFrom-Json
foreach($Key in 'Vpc','Igw','PublicRoute','PrivateRoute','WebSG','EfsSG','Role','InstanceProfile','Efs','MountTarget','DataVolume','Instance','Snapshot','PublicA','PublicB','PrivateA','PrivateB','StaticBucket','LogBucket'){
 if(!$S.$Key){throw "Missing resource mapping: $Key"}
}
$M=[ordered]@{
 'aws_vpc.this'=$S.Vpc
 'aws_internet_gateway.this'=$S.Igw
 'aws_route_table.public'=$S.PublicRoute
 'aws_route_table.private'=$S.PrivateRoute
 'aws_route.internet'="$($S.PublicRoute)_0.0.0.0/0"
 'aws_security_group.web'=$S.WebSG
 'aws_security_group.efs'=$S.EfsSG
 'aws_iam_role.ec2'=$S.Role
 'aws_iam_instance_profile.ec2'=$S.InstanceProfile
 'aws_efs_file_system.shared'=$S.Efs
 'aws_efs_mount_target.shared'=$S.MountTarget
 'aws_ebs_volume.postgres'=$S.DataVolume
 'aws_instance.web'=$S.Instance
 'aws_volume_attachment.postgres'="/dev/sdf:$($S.DataVolume):$($S.Instance)"
 'aws_ec2_instance_state.web'=$S.Instance
 'aws_ebs_snapshot.postgres[0]'=$S.Snapshot
}
foreach($Pair in @(@('public_a','PublicA'),@('public_b','PublicB'),@('private_a','PrivateA'),@('private_b','PrivateB'))){
 $Key=$Pair[0];$Subnet=$S.($Pair[1]);$Rt=if($Key.StartsWith('public')){$S.PublicRoute}else{$S.PrivateRoute}
 $M[('aws_subnet.this["'+$Key+'"]')]=$Subnet
 $M[('aws_route_table_association.this["'+$Key+'"]')]="$Subnet/$Rt"
}
foreach($P in 'AmazonSSMManagedInstanceCore','CloudWatchAgentServerPolicy'){$M[('aws_iam_role_policy_attachment.ec2["'+$P+'"]')]="$($S.Role)/arn:aws:iam::aws:policy/$P"}
foreach($Kind in 'static','logs'){
 $Bucket=if($Kind -eq 'static'){$S.StaticBucket}else{$S.LogBucket}
 foreach($Type in 'aws_s3_bucket','aws_s3_bucket_public_access_block','aws_s3_bucket_server_side_encryption_configuration','aws_s3_bucket_policy'){$M[($Type+'.this["'+$Kind+'"]')]=$Bucket}
}
foreach($Log in 'httpd-access','httpd-error','tomcat','bootstrap'){$M[('aws_cloudwatch_log_group.app["'+$Log+'"]')]="/portfolio/day1/$Log"}
foreach($Alarm in 'cpu-high','status-failed','memory-high','disk-root-high','disk-pgsql-high'){$M[('aws_cloudwatch_metric_alarm.this["'+$Alarm+'"]')]="portfolio-day1-$Alarm"}
$Lines=foreach($E in $M.GetEnumerator()){"import {`n  to = $($E.Key)`n  id = $(ConvertTo-Json $E.Value -Compress)`n}`n"}
[IO.File]::WriteAllText($Output,($Lines -join "`n"),[Text.UTF8Encoding]::new($false))
Write-Output "Wrote $($M.Count) import blocks to the Git-ignored imports.local.tf."
