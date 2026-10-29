param(
 [Parameter(Mandatory=$true)][string]$Profile,
 [Parameter(Mandatory=$true)][string]$StateDirectory,
 [Parameter(Mandatory=$true)][string]$VarFile
)
$ErrorActionPreference='Stop'
$StateDirectory=[IO.Path]::GetFullPath($StateDirectory)
$VarFile=[IO.Path]::GetFullPath($VarFile)
$tf=Join-Path $PSScriptRoot 'Invoke-Terraform.ps1'
function Invoke-Aws {
 param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
 $raw=& aws.exe @Arguments --profile $Profile --region ap-northeast-1 --output json --no-cli-pager 2>&1
 if($LASTEXITCODE -ne 0){throw ($raw -join [Environment]::NewLine)}
 return (($raw -join [Environment]::NewLine)|ConvertFrom-Json -Depth 80)
}
function Set-TestSchedule([bool]$Enabled) {
 $label=if($Enabled){'enabled'}else{'disabled'}
 $planPath=Join-Path $StateDirectory ('schedule-'+$label+'.tfplan')
 $args4=@('plan',('-var-file='+$VarFile),('-out='+$planPath),'-no-color')
 if($Enabled){$args4+=@('-var=schedule_enabled=true','-var=schedule_expression=rate(1 minute)')}
 & $tf -Profile $Profile -StateDirectory $StateDirectory @args4 *> (Join-Path $StateDirectory ('schedule-'+$label+'-plan.txt'))
 if($LASTEXITCODE -ne 0){throw 'Cannot plan schedule change'}
 $raw=& $tf -Profile $Profile -StateDirectory $StateDirectory show -json $planPath
 if($LASTEXITCODE -ne 0){throw 'Cannot read schedule plan'}
 $plan=($raw -join [Environment]::NewLine)|ConvertFrom-Json -Depth 80
 foreach($change in @($plan.resource_changes|Where-Object {$_.mode -eq 'managed' -and $_.change.actions -notcontains 'no-op'})) {
  if($change.address -ne 'aws_cloudwatch_event_rule.schedule' -or ($change.change.actions -join ',') -ne 'update'){throw 'Unexpected resource in schedule-only plan'}
 }
 & $tf -Profile $Profile -StateDirectory $StateDirectory apply -no-color $planPath *> (Join-Path $StateDirectory ('schedule-'+$label+'-apply.txt'))
 if($LASTEXITCODE -ne 0){throw 'Cannot apply schedule change'}
}
$raw=& $tf -Profile $Profile -StateDirectory $StateDirectory output -json
if($LASTEXITCODE -ne 0){throw 'Cannot load Day4 outputs'}
$out=($raw -join [Environment]::NewLine)|ConvertFrom-Json
$startedAt=[DateTimeOffset]::UtcNow
$found=$null
try {
 Set-TestSchedule $true
 for($i=0;$i -lt 60;$i++) {
  $executions=Invoke-Aws @('stepfunctions','list-executions','--state-machine-arn',$out.workflow_arn.value,'--max-results','10')
  foreach($execution in $executions.executions) {
   if([DateTimeOffset]::Parse($execution.startDate.ToString()) -lt $startedAt){continue}
   $detail=Invoke-Aws @('stepfunctions','describe-execution','--execution-arn',$execution.executionArn)
   $inputData=$detail.input|ConvertFrom-Json
   if($inputData.trigger -eq 'EventBridge'){$found=$detail;break}
  }
  if($found){break}; Start-Sleep -Seconds 5
 }
 if(!$found){throw 'No EventBridge-started execution observed within the test window'}
} finally {
 Set-TestSchedule $false
}
for($i=0;$i -lt 120;$i++) {
 $found=Invoke-Aws @('stepfunctions','describe-execution','--execution-arn',$found.executionArn)
 if($found.status -ne 'RUNNING'){break}; Start-Sleep -Seconds 5
}
$found|ConvertTo-Json -Depth 70|Set-Content -LiteralPath (Join-Path $StateDirectory 'scheduled-execution.json') -Encoding utf8
if($found.status -ne 'SUCCEEDED'){throw ('Scheduled execution status: '+$found.status)}
Write-Output 'EventBridge execution succeeded; rule restored to daily schedule and DISABLED through Terraform'
