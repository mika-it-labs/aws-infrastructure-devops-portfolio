param([string]$Profile='portfolio-lab')
. "$PSScriptRoot/Deploy-Day1.ps1" -Phase Library -Profile $Profile
if(!$S.Instance){throw 'Instance not recorded.'}
# A stopped EC2 instance produces a consistent snapshot after a clean PostgreSQL shutdown.
Invoke-PortfolioAws ec2 stop-instances @{InstanceIds=@($S.Instance)}|Out-Null
Write-Output 'Stop requested. Confirm stopped before taking the snapshot.'



