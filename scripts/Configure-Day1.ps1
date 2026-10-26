param([string]$Profile='portfolio-lab')
. "$PSScriptRoot/Deploy-Day1.ps1" -Phase Library -Profile $Profile
if(!$S.DataVolume -or !$S.EfsIP -or !$S.StaticBucket){throw 'Provision-Day1.ps1 must complete first.'}
$Script=(Get-Content "$PSScriptRoot/bootstrap.sh" -Raw).Replace("`r`n","`n")
$Encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
$Command="export DATA_VOLUME_ID='$($S.DataVolume)' EFS_IP='$($S.EfsIP)' STATIC_BUCKET='$($S.StaticBucket)' LOG_BUCKET='$($S.LogBucket)'; echo '$Encoded' | base64 -d > /root/portfolio-bootstrap.sh; bash /root/portfolio-bootstrap.sh"
$R=Invoke-PortfolioAws ssm send-command @{InstanceIds=@($S.Instance);DocumentName='AWS-RunShellScript';TimeoutSeconds=1800;Parameters=@{commands=@($Command);executionTimeout=@('1800')};Comment='Portfolio Day1 Apache Tomcat PostgreSQL EBS EFS CloudWatch'}
$S.BootstrapCommand=$R.Command.CommandId;Save
Write-Output $S.BootstrapCommand



