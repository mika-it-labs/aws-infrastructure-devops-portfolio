param(
 [Parameter(Mandatory=$true)][string]$Profile,
 [Parameter(Mandatory=$true)][string]$StateDirectory,
 [string]$CommitId,
 [string]$ExpectedRelease='day3-cicd-v1'
)
$ErrorActionPreference='Stop';$env:AWS_PAGER=''
$StateDirectory=[IO.Path]::GetFullPath($StateDirectory)
$tfRaw=& "$PSScriptRoot/Invoke-Terraform.ps1" -Profile $Profile -StateDirectory $StateDirectory output -json
if($LASTEXITCODE -ne 0){throw 'Terraform outputs are unavailable'}
$outputs=($tfRaw -join [Environment]::NewLine)|ConvertFrom-Json
function Read-Aws([string[]]$Arguments){
 $r=& aws.exe @Arguments --profile $Profile --region ap-northeast-1 --output json --no-cli-pager 2>&1
 if($LASTEXITCODE -ne 0){throw ($r -join ' ')}
 return (($r -join [Environment]::NewLine)|ConvertFrom-Json)
}
$pipeline=$outputs.pipeline_name.value
$deadline=(Get-Date).AddMinutes(30)
do{
 $history=Read-Aws @('codepipeline','list-pipeline-executions','--pipeline-name',$pipeline,'--max-results','20')
 $history|ConvertTo-Json -Depth 40|Set-Content (Join-Path $StateDirectory 'pipeline-history.json') -Encoding utf8
 $matches=@($history.pipelineExecutionSummaries)
 if($CommitId){$matches=@($matches|Where-Object {($_.sourceRevisions.revisionId -contains $CommitId) -and ($_.trigger.triggerType -notin @('CreatePipeline','StartPipelineExecution'))})}
 $execution=$matches|Select-Object -First 1
 if($execution){Write-Output ('Pipeline: '+$execution.status+' / '+$execution.pipelineExecutionId)}
 else{Write-Output 'Waiting for the matching automatic pipeline execution'}
 if($execution.status -eq 'Succeeded'){break}
 if($execution.status -in @('Failed','Stopped','Superseded','Cancelled')){throw 'The selected pipeline execution did not succeed. Inspect the saved history.'}
 if((Get-Date) -ge $deadline){throw 'Pipeline verification timed out.'}
 Start-Sleep -Seconds 15
}while($true)
$detail=Read-Aws @('codepipeline','get-pipeline-execution','--pipeline-name',$pipeline,'--pipeline-execution-id',$execution.pipelineExecutionId)
$detail|ConvertTo-Json -Depth 50|Set-Content (Join-Path $StateDirectory 'pipeline-execution.json') -Encoding utf8
$actions=Read-Aws @('codepipeline','list-action-executions','--pipeline-name',$pipeline,'--filter',('pipelineExecutionId='+$execution.pipelineExecutionId))
$actions|ConvertTo-Json -Depth 50|Set-Content (Join-Path $StateDirectory 'pipeline-actions.json') -Encoding utf8
$service=Read-Aws @('ecs','describe-services','--cluster',$outputs.cluster_name.value,'--services',$outputs.service_name.value)
$service|ConvertTo-Json -Depth 60|Set-Content (Join-Path $StateDirectory 'ecs-verification.json') -Encoding utf8
$svc=$service.services[0]
if($svc.runningCount -ne 1 -or $svc.pendingCount -ne 0){throw 'ECS is not at one running task with no pending tasks'}
$health=Read-Aws @('elbv2','describe-target-health','--target-group-arn',$outputs.target_group_arn.value)
$health|ConvertTo-Json -Depth 30|Set-Content (Join-Path $StateDirectory 'target-health.json') -Encoding utf8
if(!$health.TargetHealthDescriptions.Count -or @($health.TargetHealthDescriptions|Where-Object {$_.TargetHealth.State -ne 'healthy'}).Count){throw 'An ALB target is not healthy'}
$url=$outputs.api_url.value
$without=Invoke-WebRequest -Uri $url -SkipHttpErrorCheck
if([int]$without.StatusCode -ne 403){throw 'An API request without a key was not rejected with HTTP 403'}
$key=Read-Aws @('apigateway','get-api-key','--api-key',$outputs.api_key_id.value,'--include-value')
try{
 $with=Invoke-WebRequest -Uri $url -Headers @{'x-api-key'=$key.value} -SkipHttpErrorCheck
 if([int]$with.StatusCode -ne 200){throw ('API request with a key returned HTTP '+$with.StatusCode)}
 if(!$with.Content.Contains($ExpectedRelease) -or !$with.Content.Contains('DB_STATUS=UNCONFIGURED')){throw 'The expected release and declared DB state were not found in the API response'}
 [IO.File]::WriteAllText((Join-Path $StateDirectory 'application.html'),$with.Content,[Text.UTF8Encoding]::new($false))
}finally{$key=$null}
$summary=[ordered]@{
 checked_at=(Get-Date).ToString('o')
 pipeline_status=$execution.status
 pipeline_trigger=$execution.trigger.triggerType
 source_commit=($execution.sourceRevisions|Select-Object -First 1).revisionId
 action_statuses=@($actions.actionExecutionDetails|Select-Object stageName,status)
 ecs_running=$svc.runningCount
 ecs_pending=$svc.pendingCount
 task_revision=($svc.taskDefinition -split ':')[-1]
 healthy_targets=$health.TargetHealthDescriptions.Count
 no_key_http=[int]$without.StatusCode
 with_key_http=[int]$with.StatusCode
 expected_release=$ExpectedRelease
 release_found=$true
 db_status='UNCONFIGURED'
 result='PASS'
}
$summary|ConvertTo-Json -Depth 20|Set-Content (Join-Path $StateDirectory 'verification-summary.json') -Encoding utf8
$summary|ConvertTo-Json -Depth 20
