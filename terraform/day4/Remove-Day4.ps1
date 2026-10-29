param(
 [Parameter(Mandatory=$true)][string]$Profile,
 [Parameter(Mandatory=$true)][string]$StateDirectory,
 [Parameter(Mandatory=$true)][string]$VarFile,
 [switch]$Apply
)
$ErrorActionPreference='Stop'
$StateDirectory=[IO.Path]::GetFullPath($StateDirectory)
$VarFile=[IO.Path]::GetFullPath($VarFile)
$tf=Join-Path $PSScriptRoot 'Invoke-Terraform.ps1'
$known=@(
 'aws_cloudwatch_dashboard.operations','aws_cloudwatch_event_rule.schedule','aws_cloudwatch_event_rule.stopped',
 'aws_cloudwatch_event_target.schedule','aws_cloudwatch_event_target.stopped','aws_cloudwatch_log_group.batch',
 'aws_cloudwatch_metric_alarm.cpu','aws_cloudwatch_metric_alarm.disk','aws_cloudwatch_metric_alarm.errors',
 'aws_ecs_cluster.batch','aws_ecs_task_definition.batch','aws_iam_role.sfn','aws_iam_role.events',
 'aws_iam_role_policy.sfn','aws_iam_role_policy.events','aws_lb.web','aws_lb_listener.web',
 'aws_lb_target_group.web','aws_lb_target_group_attachment.web','aws_security_group.batch',
 'aws_sfn_state_machine.batch','aws_sns_topic.alerts','aws_sns_topic_policy.alerts','aws_sns_topic_subscription.email'
)
$raw=& $tf -Profile $Profile -StateDirectory $StateDirectory output -json
if($LASTEXITCODE -ne 0){throw 'Cannot inspect Day4 outputs'}
$outputs=($raw -join [Environment]::NewLine)|ConvertFrom-Json
$savedFile=Join-Path $StateDirectory 'cleanup-identifiers.json'
if($outputs.task_definition_arn.value) {
 @{task_definition_arn=$outputs.task_definition_arn.value;instance_id=$outputs.instance_id.value}|ConvertTo-Json|Set-Content -LiteralPath $savedFile -Encoding utf8
}
if(!(Test-Path -LiteralPath $savedFile)){throw 'Need saved identifiers from this state before cleanup'}
$saved=Get-Content -LiteralPath $savedFile -Raw|ConvertFrom-Json
if($saved.task_definition_arn -notmatch ':task-definition/portfolio-day4-batch:\d+$'){throw 'Unexpected task definition'}
$planPath=Join-Path $StateDirectory 'cleanup.tfplan'
& $tf -Profile $Profile -StateDirectory $StateDirectory plan -destroy ('-var-file='+$VarFile) ('-out='+$planPath) -no-color *> (Join-Path $StateDirectory 'cleanup-plan.txt')
if($LASTEXITCODE -ne 0){throw 'Cleanup plan failed'}
$raw=& $tf -Profile $Profile -StateDirectory $StateDirectory show -json $planPath
if($LASTEXITCODE -ne 0){throw 'Cannot inspect cleanup plan'}
$plan=($raw -join [Environment]::NewLine)|ConvertFrom-Json -Depth 80
$changes=@($plan.resource_changes|Where-Object {$_.mode -eq 'managed' -and $_.change.actions -notcontains 'no-op'})
foreach($change in $changes) {
 if($change.address -notin $known -or ($change.change.actions -join ',') -ne 'delete'){throw ('Unexpected deletion: '+$change.address)}
}
Write-Output ('Reviewed Day4-only deletions: '+$changes.Count)
if(!$Apply){return}
try {
 & $tf -Profile $Profile -StateDirectory $StateDirectory apply -no-color $planPath *> (Join-Path $StateDirectory 'cleanup-apply.txt')
 if($LASTEXITCODE -ne 0){throw 'Terraform destroy failed; preserve state and retry after inspecting log'}
 # The provider deregisters the revision. Remove only the exact revision saved from this state.
 $raw=& aws.exe ecs delete-task-definitions --task-definitions $saved.task_definition_arn --profile $Profile --region ap-northeast-1 --output json --no-cli-pager 2>&1
 if($LASTEXITCODE -ne 0){throw ($raw -join [Environment]::NewLine)}
 $taskDelete=($raw -join [Environment]::NewLine)|ConvertFrom-Json
 if(@($taskDelete.failures).Count){throw 'Task definition deletion returned failures'}
 $taskDelete|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $StateDirectory 'task-definition-deletion.json') -Encoding utf8
} finally {
 $null=& aws.exe ec2 stop-instances --instance-ids $saved.instance_id --profile $Profile --region ap-northeast-1 --output json --no-cli-pager
 if($LASTEXITCODE -ne 0){Write-Warning 'EC2 stop failed; inspect the existing instance immediately'}
}
Write-Output 'Day4 state destroyed. Verify AWS inventories and the retained Day1 data separately.'
