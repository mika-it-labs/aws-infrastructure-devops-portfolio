param([string]$Profile='portfolio-lab')
. "$PSScriptRoot/Deploy-Day1.ps1" -Phase Library -Profile $Profile
$R=Invoke-PortfolioAws ssm get-command-invocation @{CommandId=$S.VerificationCommand;InstanceId=$S.Instance}
$R|ConvertTo-Json -Depth 20|Set-Content "$PSScriptRoot/../.local/verification.json" -Encoding utf8
$R.StandardOutputContent|Set-Content "$PSScriptRoot/../.local/verification.txt" -Encoding utf8
if($R.Status -ne 'Success'){throw "Verification not successful: $($R.Status)"}
$Metrics=Invoke-PortfolioAws cloudwatch list-metrics @{Namespace='Portfolio/Day1'}
$Metrics|ConvertTo-Json -Depth 30|Set-Content "$PSScriptRoot/../.local/metrics.json"
$Groups=(Invoke-PortfolioAws logs describe-log-groups @{logGroupNamePrefix='/portfolio/day1/'}).logGroups
$Evidence=@()
foreach($G in $Groups){
 $Arn=if($G.logGroupArn){$G.logGroupArn}else{$G.arn.Replace(':*','')}
 Invoke-PortfolioAws logs tag-resource @{resourceArn=$Arn;tags=@{Project='portfolio';Run=$S.Run}}|Out-Null
 $Streams=(Invoke-PortfolioAws logs describe-log-streams @{logGroupName=$G.logGroupName}).logStreams
 $Count=0
 foreach($Stream in $Streams){$Events=(Invoke-PortfolioAws logs get-log-events @{logGroupName=$G.logGroupName;logStreamName=$Stream.logStreamName;limit=1}).events; $Count+=@($Events).Count}
 $Evidence+=@{Name=$G.logGroupName;RetentionDays=$G.retentionInDays;Streams=@($Streams).Count;ObservedEventsAtLeast=$Count}
}
$Evidence|ConvertTo-Json -Depth 20|Set-Content "$PSScriptRoot/../.local/log-groups.json"
$Alarms=Invoke-PortfolioAws cloudwatch describe-alarms @{AlarmNamePrefix='portfolio-day1-'}
$Alarms|ConvertTo-Json -Depth 30|Set-Content "$PSScriptRoot/../.local/alarms.json"
& aws.exe s3 cp "s3://$($S.StaticBucket)/index.html" "$PSScriptRoot/../.local/application.html" --profile $Profile --region $Region --no-progress
if($LASTEXITCODE -ne 0){throw 'S3 static artifact download failed'}
& aws.exe s3 cp "s3://$($S.LogBucket)/day1/evidence.txt" "$PSScriptRoot/../.local/server-evidence.txt" --profile $Profile --region $Region --no-progress
if($LASTEXITCODE -ne 0){throw 'S3 evidence download failed'}
Write-Output ($R.StandardOutputContent)
Write-Output ($Evidence|ConvertTo-Json -Depth 10)
Write-Output "Metric series: $(@($Metrics.Metrics).Count); Alarms: $(@($Alarms.MetricAlarms).Count)"

