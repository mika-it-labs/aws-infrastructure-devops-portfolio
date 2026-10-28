param(
 [Parameter(Mandatory=$true)][string]$Profile,
 [Parameter(Mandatory=$true)][string]$StateDirectory
)
$ErrorActionPreference='Stop';$env:AWS_PAGER=''
$StateDirectory=[IO.Path]::GetFullPath($StateDirectory)
$tfRaw=& "$PSScriptRoot/Invoke-Terraform.ps1" -Profile $Profile -StateDirectory $StateDirectory output -json
if($LASTEXITCODE -ne 0){throw 'Terraform outputs are unavailable'}
$outputs=($tfRaw -join [Environment]::NewLine)|ConvertFrom-Json
$project=$outputs.codebuild_project_name.value
$repository=$outputs.ecr_repository_url.value
function Read-Aws([string[]]$Arguments){
 $r=& aws.exe @Arguments --profile $Profile --region ap-northeast-1 --output json --no-cli-pager 2>&1
 if($LASTEXITCODE -ne 0){throw ($r -join ' ')}
 return (($r -join [Environment]::NewLine)|ConvertFrom-Json)
}
$started=Read-Aws @('codebuild','start-build','--project-name',$project)
$buildId=$started.build.id
$started|ConvertTo-Json -Depth 40|Set-Content (Join-Path $StateDirectory 'bootstrap-build-start.json') -Encoding utf8
$deadline=(Get-Date).AddMinutes(30)
do {
 $current=Read-Aws @('codebuild','batch-get-builds','--ids',$buildId)
 $build=$current.builds[0]
 $current|ConvertTo-Json -Depth 50|Set-Content (Join-Path $StateDirectory 'bootstrap-build.json') -Encoding utf8
 Write-Output ("Bootstrap build: "+$build.buildStatus+" / "+$build.currentPhase)
 if($build.buildStatus -eq 'SUCCEEDED'){break}
 if($build.buildStatus -in @('FAILED','FAULT','STOPPED','TIMED_OUT')){throw 'Bootstrap failed; inspect the saved build phases and CloudWatch logs.'}
 if((Get-Date) -ge $deadline){throw 'Bootstrap polling timed out. The saved build ID identifies any remaining job.'}
 Start-Sleep -Seconds 10
} while($true)
$deployment=@{image_uri=($repository+':build-'+$build.buildNumber);deploy_enabled=$true;pipeline_enabled=$true}
$deployment|ConvertTo-Json|Set-Content (Join-Path $StateDirectory 'deployment.tfvars.json') -Encoding utf8
Write-Output ('Bootstrap succeeded. Build number: '+$build.buildNumber+'. Private deployment variables saved.')
