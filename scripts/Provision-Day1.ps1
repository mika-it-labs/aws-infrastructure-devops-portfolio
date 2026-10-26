param([string]$Profile='portfolio-lab',[switch]$SkipS3,[switch]$SkipEFS)
. "$PSScriptRoot/Deploy-Day1.ps1" -Phase Network -Profile $Profile
$Account=(Invoke-PortfolioAws sts get-caller-identity).Account
if(!$S.InstanceProfile){throw 'Run Deploy-Day1.ps1 -Phase Server first.'}
$UseRole=$S.InstanceProfile
$RoleArn="arn:aws:iam::${Account}:role/$UseRole"
$S.ReusedInstanceProfile=$UseRole;Save
if(!$SkipS3){ foreach($Kind in 'static','logs'){
 $Key=if($Kind -eq 'static'){'StaticBucket'}else{'LogBucket'}
 if(!$S[$Key]){
  $Name="portfolio-day1-$Kind-$Account-$($S.Run)"
  Invoke-PortfolioAws s3api create-bucket @{Bucket=$Name;CreateBucketConfiguration=@{LocationConstraint=$Region}}|Out-Null
  $S[$Key]=$Name;Save
 }
 $Name=$S[$Key]
 Invoke-PortfolioAws s3api put-bucket-tagging @{Bucket=$Name;Tagging=@{TagSet=(Tags "portfolio-day1-$Kind")}}|Out-Null
 Invoke-PortfolioAws s3api put-public-access-block @{Bucket=$Name;PublicAccessBlockConfiguration=@{BlockPublicAcls=$true;IgnorePublicAcls=$true;BlockPublicPolicy=$true;RestrictPublicBuckets=$true}}|Out-Null
 Invoke-PortfolioAws s3api put-bucket-encryption @{Bucket=$Name;ServerSideEncryptionConfiguration=@{Rules=@(@{ApplyServerSideEncryptionByDefault=@{SSEAlgorithm='AES256'}})}}|Out-Null
 $Policy=@{Version='2012-10-17';Statement=@(@{Effect='Allow';Principal=@{AWS=$RoleArn};Action=@('s3:PutObject','s3:GetObject');Resource="arn:aws:s3:::$Name/*"},@{Effect='Deny';Principal='*';Action='s3:*';Resource=@("arn:aws:s3:::$Name","arn:aws:s3:::$Name/*");Condition=@{Bool=@{'aws:SecureTransport'='false'}}})}
 Invoke-PortfolioAws s3api put-bucket-policy @{Bucket=$Name;Policy=($Policy|ConvertTo-Json -Depth 15 -Compress)}|Out-Null
}
}
if(!$SkipEFS){ if(!$S.Efs){$S.Efs=(Invoke-PortfolioAws efs create-file-system @{CreationToken=$S.Run;Encrypted=$true;PerformanceMode='generalPurpose';ThroughputMode='bursting';Tags=(Tags portfolio-day1-shared)}).FileSystemId;Save}
if(!$S.MountTarget){
 for($i=0;$i -lt 30;$i++){if((Invoke-PortfolioAws efs describe-file-systems @{FileSystemId=$S.Efs}).FileSystems[0].LifeCycleState -eq 'available'){break};Start-Sleep 2}
 $M=Invoke-PortfolioAws efs create-mount-target @{FileSystemId=$S.Efs;SubnetId=$S.PrivateA;SecurityGroups=@($S.EfsSG)}
 $S.MountTarget=$M.MountTargetId;$S.EfsIP=$M.IpAddress;Save
}
}
if(!$S.Instance){
 $Images=(Invoke-PortfolioAws ec2 describe-images @{Owners=@('309956199498');Filters=@(@{Name='name';Values=@('RHEL-9.6.0_HVM-*-x86_64-*-Hourly2-GP3')},@{Name='state';Values=@('available')})}).Images
 $S.Ami=($Images|Sort-Object CreationDate -Descending|Select-Object -First 1).ImageId;Save
 $UserData=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content "$PSScriptRoot/user-data.sh" -Raw).Replace("`r`n","`n")))
 $Body=@{ImageId=$S.Ami;InstanceType='t3.small';MinCount=1;MaxCount=1;ClientToken=$S.Run;IamInstanceProfile=@{Name=$S.ReusedInstanceProfile};MetadataOptions=@{HttpTokens='required';HttpEndpoint='enabled'};CreditSpecification=@{CpuCredits='standard'};NetworkInterfaces=@(@{DeviceIndex=0;SubnetId=$S.PublicA;Groups=@($S.WebSG);AssociatePublicIpAddress=$true});BlockDeviceMappings=@(@{DeviceName='/dev/sda1';Ebs=@{VolumeSize=15;VolumeType='gp3';Encrypted=$true;DeleteOnTermination=$true}},@{DeviceName='/dev/sdf';Ebs=@{VolumeSize=8;VolumeType='gp3';Encrypted=$true;DeleteOnTermination=$false}});UserData=$UserData;TagSpecifications=@(@{ResourceType='instance';Tags=(Tags portfolio-day1-rhel)},@{ResourceType='volume';Tags=(Tags portfolio-day1-ebs)})}
 $S.Instance=(Invoke-PortfolioAws ec2 run-instances $Body).Instances[0].InstanceId;Save
}
$Instance=(Invoke-PortfolioAws ec2 describe-instances @{InstanceIds=@($S.Instance)}).Reservations[0].Instances[0]
$S.DataVolume=($Instance.BlockDeviceMappings|Where-Object DeviceName -eq '/dev/sdf').Ebs.VolumeId;Save
Write-Output "Provisioned instance $($S.Instance); data volume $($S.DataVolume)"





