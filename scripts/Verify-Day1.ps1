param([string]$Profile='portfolio-lab')
. "$PSScriptRoot/Deploy-Day1.ps1" -Phase Library -Profile $Profile
$Command=(Get-Content "$PSScriptRoot/verify.sh" -Raw).Replace("`r`n","`n")
$R=Invoke-PortfolioAws ssm send-command @{InstanceIds=@($S.Instance);DocumentName='AWS-RunShellScript';Parameters=@{commands=@($Command)};Comment='Day1 final evidence'}
$S.VerificationCommand=$R.Command.CommandId;Save
Write-Output $S.VerificationCommand

