param(
 [Parameter(Mandatory=$true)][string]$Profile,
 [Parameter(Mandatory=$true)][string]$StateDirectory,
 [Parameter(Mandatory=$true)][string[]]$VarFiles,
 [switch]$Apply
)
$ErrorActionPreference='Stop';$env:AWS_PAGER=''
$StateDirectory=[IO.Path]::GetFullPath($StateDirectory)
$tf="$PSScriptRoot/Invoke-Terraform.ps1"
$raw=& $tf -Profile $Profile -StateDirectory $StateDirectory output -json
if($LASTEXITCODE -ne 0){throw 'Could not inspect this Day 3 state'}
$outputs=($raw -join [Environment]::NewLine)|ConvertFrom-Json
$taskArn=$outputs.task_definition_arn.value
if($taskArn -and $taskArn -notmatch ':task-definition/portfolio-day3-task:\d+$'){throw 'Unexpected task definition ARN'}
$family='portfolio-day3-task'
$planPath=Join-Path $StateDirectory 'cleanup.tfplan'
$planArgs=@('plan','-destroy','-no-color')
foreach($f in $VarFiles){$planArgs+=('-var-file='+[IO.Path]::GetFullPath($f))}
$planArgs+=('-out='+$planPath)
& $tf -Profile $Profile -StateDirectory $StateDirectory @planArgs *> (Join-Path $StateDirectory 'cleanup-plan.txt')
if($LASTEXITCODE -ne 0){throw 'Could not prepare cleanup plan'}
$planJson=& $tf -Profile $Profile -StateDirectory $StateDirectory show -json $planPath
if($LASTEXITCODE -ne 0){throw 'Could not read cleanup plan'}
$planText=$planJson -join [Environment]::NewLine
[IO.File]::WriteAllText((Join-Path $StateDirectory 'cleanup-plan.json'),$planText,[Text.UTF8Encoding]::new($false))
$plan=$planText|ConvertFrom-Json
$allowed=@(
 'aws_cloudwatch_log_group.build','aws_cloudwatch_log_group.task','aws_ecr_repository.app',
 'aws_iam_role.build','aws_iam_role.pipeline','aws_iam_role_policy.build','aws_iam_role_policy.pipeline','aws_codebuild_project.app',
 'aws_security_group.task','aws_lb.app','aws_lb_target_group.app','aws_lb_listener.app','aws_ecs_cluster.app','aws_ecs_cluster_capacity_providers.app','aws_ecs_task_definition.app','aws_ecs_service.app',
 'aws_apigatewayv2_vpc_link.app','aws_api_gateway_rest_api.app','aws_api_gateway_method.app','aws_api_gateway_integration.app','aws_api_gateway_deployment.app','aws_api_gateway_stage.app','aws_api_gateway_api_key.app','aws_api_gateway_usage_plan.app','aws_api_gateway_usage_plan_key.app','aws_codepipeline.app'
)
$changes=@($plan.resource_changes|Where-Object {$_.mode -eq 'managed' -and $_.change.actions -notcontains 'no-op'})
foreach($c in $changes){
 $baseAddress=$c.address -replace '\[\d+\]$',''
 if($baseAddress -notin $allowed -or ($c.change.actions -join ',') -ne 'delete'){throw ('Cleanup includes an unexpected resource or action: '+$c.address)}
}
Write-Output ('Reviewed Day 3 deletions: '+$changes.Count+'. Day 1 resources are data references only.')
if(!$Apply){Write-Output 'Plan only. Supply -Apply to execute the saved cleanup workflow.';return}
foreach($group in @('/portfolio/day3/codebuild','/portfolio/day3/ecs')){
 $events=& aws.exe logs filter-log-events --log-group-name $group --limit 10000 --no-paginate --profile $Profile --region ap-northeast-1 --output json --no-cli-pager 2>&1
 if($LASTEXITCODE -eq 0){
  $file=($group.Trim('/') -replace '/','-')+'-before-destroy.json'
  [IO.File]::WriteAllText((Join-Path $StateDirectory $file),($events -join [Environment]::NewLine),[Text.UTF8Encoding]::new($false))
 }
}
& $tf -Profile $Profile -StateDirectory $StateDirectory apply -no-color $planPath *> (Join-Path $StateDirectory 'cleanup-apply.txt')
if($LASTEXITCODE -ne 0){throw 'Terraform cleanup failed; inspect the saved apply log'}
if($family){
 $defs=& aws.exe ecs list-task-definitions --family-prefix $family --profile $Profile --region ap-northeast-1 --output json --no-cli-pager
 if($LASTEXITCODE -ne 0){throw 'Could not list pipeline-generated task definitions'}
 foreach($arn in (($defs -join [Environment]::NewLine)|ConvertFrom-Json).taskDefinitionArns){
  if($arn -notmatch ':task-definition/portfolio-day3-task:\d+$'){throw 'Unexpected task definition'}
  $null=& aws.exe ecs deregister-task-definition --task-definition $arn --profile $Profile --region ap-northeast-1 --output json --no-cli-pager
  if($LASTEXITCODE -ne 0){throw 'Could not deregister a pipeline-generated revision'}
 }
}
Write-Output 'Day 3 Terraform resources removed. Pipeline-generated task revisions were also deregistered. Verify the retained base separately.'
