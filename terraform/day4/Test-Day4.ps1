param(
 [Parameter(Mandatory=$true)][string]$Profile,
 [Parameter(Mandatory=$true)][string]$StateDirectory,
 [ValidateSet('Batch','Fault','Stop','Logs')][string]$Phase='Batch'
)
$ErrorActionPreference='Stop'
$StateDirectory=[IO.Path]::GetFullPath($StateDirectory)
$tf=Join-Path $PSScriptRoot 'Invoke-Terraform.ps1'
function Save-Private([string]$Name,$Value) {
 $Value|ConvertTo-Json -Depth 70|Set-Content -LiteralPath (Join-Path $StateDirectory $Name) -Encoding utf8
}
function Invoke-Aws {
 param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
 $raw=& aws.exe @Arguments --profile $Profile --region ap-northeast-1 --output json --no-cli-pager 2>&1
 if($LASTEXITCODE -ne 0){throw ($raw -join [Environment]::NewLine)}
 $text=$raw -join [Environment]::NewLine
 if($text.Trim()){return ($text|ConvertFrom-Json -Depth 80)}
}
$raw=& $tf -Profile $Profile -StateDirectory $StateDirectory output -json
if($LASTEXITCODE -ne 0){throw 'Cannot load Day4 Terraform outputs'}
$out=($raw -join [Environment]::NewLine)|ConvertFrom-Json
$workflow=$out.workflow_arn.value
$instance=$out.instance_id.value
if($workflow -notmatch ':stateMachine:portfolio-day4-workflow$'){throw 'Unexpected workflow'}
if($Phase -eq 'Batch') {
 $subscriptions=Invoke-Aws @('sns','list-subscriptions-by-topic','--topic-arn',$out.topic_arn.value)
 if(@($subscriptions.Subscriptions|Where-Object {$_.Protocol -eq 'email' -and $_.SubscriptionArn -match '^arn:'}).Count -ne 1){throw 'Confirm the SNS email subscription before notification verification'}
 foreach($case in @(@{label='success';force='false';expected='SUCCEEDED'},@{label='failure';force='true';expected='FAILED'})) {
  $name='day4-tf-'+$case.label+'-'+(Get-Date -Format yyyyMMddHHmmss)
  $request=@{stateMachineArn=$workflow;name=$name;input=(@{forceFailure=$case.force;trigger='TerraformVerification'}|ConvertTo-Json -Compress)}
  Save-Private 'execution-request.json' $request
  $started=Invoke-Aws @('stepfunctions','start-execution','--cli-input-json',('file://'+(Join-Path $StateDirectory 'execution-request.json')))
  $end=$null
  for($i=0;$i -lt 120;$i++) {
   $end=Invoke-Aws @('stepfunctions','describe-execution','--execution-arn',$started.executionArn)
   if($end.status -ne 'RUNNING'){break}; Start-Sleep -Seconds 5
  }
  Save-Private ($case.label+'-execution.json') $end
  $history=Invoke-Aws @('stepfunctions','get-execution-history','--execution-arn',$started.executionArn)
  Save-Private ($case.label+'-history.json') $history
  if($end.status -ne $case.expected){throw ('Unexpected batch result: '+$end.status)}
  $notify=@($history.events|Where-Object {$_.type -eq 'TaskSucceeded' -and $_.taskSucceededEventDetails.resourceType -eq 'sns'})
  if($notify.Count -ne 1){throw 'Expected exactly one successful SNS publish task'}
  if($case.label -eq 'failure') {
   $failure=@($history.events|Where-Object {$_.type -eq 'TaskFailed'})[0]
   $cause=$failure.taskFailedEventDetails.cause|ConvertFrom-Json
   if($cause.Containers[0].ExitCode -ne 42){throw 'Failure was not the intentional exit code 42'}
  }
  Save-Private ($case.label+'-summary.json') @{name=$name;status=$end.status;start=$end.startDate;stop=$end.stopDate;sns_publish_tasks=$notify.Count;expected_exit_code= $(if($case.label -eq 'failure'){42}else{0})}
  Write-Output ($case.label+': '+$end.status+'; SNS publish succeeded')
 }
}
if($Phase -eq 'Fault') {
 $null=Invoke-Aws @('ec2','start-instances','--instance-ids',$instance)
 $null=Invoke-Aws @('ec2','wait','instance-running','--instance-ids',$instance)
 for($i=0;$i -lt 60;$i++) {
  $info=Invoke-Aws @('ssm','describe-instance-information','--filters',('Key=InstanceIds,Values='+$instance))
  if($info.InstanceInformationList[0].PingStatus -eq 'Online'){break}; Start-Sleep -Seconds 5
 }
 if($info.InstanceInformationList[0].PingStatus -ne 'Online'){throw 'SSM agent did not become online'}
 $url='http://'+$out.alb_dns.value+'/portfolio/'
 $script=(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fault-test.sh') -Raw).Replace('ALB_URL_PLACEHOLDER',$url)
 $request=@{DocumentName='AWS-RunShellScript';InstanceIds=@($instance);Comment='Day4 Terraform controlled fault and automatic recovery';Parameters=@{commands=@($script);executionTimeout=@('900')}}
 Save-Private 'fault-request.json' $request
 $command=Invoke-Aws @('ssm','send-command','--cli-input-json',('file://'+(Join-Path $StateDirectory 'fault-request.json')))
 Save-Private 'fault-command.json' $command
 $result=$null
 for($i=0;$i -lt 200;$i++) {
  Start-Sleep -Seconds 5
  $result=Invoke-Aws @('ssm','get-command-invocation','--command-id',$command.Command.CommandId,'--instance-id',$instance)
  if($result.Status -notin @('Pending','InProgress','Delayed')){break}
 }
 Save-Private 'fault-result.json' $result
 if($result.Status -ne 'Success' -or $result.StandardOutputContent -notmatch 'FAULT_RECOVERY=PASS'){throw 'Inspect private fault output; automatic Tomcat restart is included in the script'}
 Save-Private 'fault-summary.json' @{status=$result.Status;start=$result.ExecutionStartDateTime;end=$result.ExecutionEndDateTime;http_503_count=([regex]::Matches($result.StandardOutputContent,'FAULT_HTTP=503')).Count;recovered_http_200=$result.StandardOutputContent.Contains('RECOVERY_HTTP=200');recovery_pass=$true}
 Write-Output 'Fault exercise passed: HTTP/DB recovery confirmed'
}
if($Phase -eq 'Stop') {
 $null=Invoke-Aws @('ec2','stop-instances','--instance-ids',$instance)
 $null=Invoke-Aws @('ec2','wait','instance-stopped','--instance-ids',$instance)
 Save-Private 'stopped-instance.json' (Invoke-Aws @('ec2','describe-instances','--instance-ids',$instance))
 Write-Output 'Existing Day1 EC2 stopped; check the EC2 stopped SNS email separately'
}
if($Phase -eq 'Logs') {
 $now=[DateTimeOffset]::UtcNow
 $query=Invoke-Aws @('logs','start-query','--log-group-name','/portfolio/day4/batch','--start-time',([string]$now.AddHours(-3).ToUnixTimeSeconds()),'--end-time',([string]$now.ToUnixTimeSeconds()),'--query-string','fields @timestamp, @message | sort @timestamp desc | limit 20')
 for($i=0;$i -lt 30;$i++) {
  Start-Sleep -Seconds 2
  $result=Invoke-Aws @('logs','get-query-results','--query-id',$query.queryId)
  if($result.status -notin @('Scheduled','Running')){break}
 }
 Save-Private 'logs-query.json' $result
 if($result.status -ne 'Complete' -or $result.results.Count -eq 0){throw 'Logs Insights did not return batch records'}
 Save-Private 'alarm-history.json' (Invoke-Aws @('cloudwatch','describe-alarm-history','--alarm-name','portfolio-day4-alb-target-5xx'))
 Save-Private 'alarms.json' (Invoke-Aws @('cloudwatch','describe-alarms','--alarm-name-prefix','portfolio-day4-'))
 Write-Output ('Logs Insights complete: '+$result.results.Count+' rows')
}
