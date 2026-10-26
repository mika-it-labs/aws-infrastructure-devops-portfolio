param([string]$Profile='portfolio-lab',[string]$Command)
. "$PSScriptRoot/Deploy-Day1.ps1" -Phase Library -Profile $Profile
if($Command){$R=Invoke-PortfolioAws ssm send-command @{InstanceIds=@($S.Instance);DocumentName='AWS-RunShellScript';Parameters=@{commands=@($Command)};Comment='Portfolio Day1 verification'};$Id=$R.Command.CommandId;Write-Output $Id}else{$Id=$S.BootstrapCommand}
if(!$Id){throw 'No command ID available.'}
Invoke-PortfolioAws ssm get-command-invocation @{CommandId=$Id;InstanceId=$S.Instance}|ConvertTo-Json -Depth 20


