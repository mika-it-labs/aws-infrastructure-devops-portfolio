param(
 [Parameter(Mandatory=$true)][string]$Profile,
 [Parameter(Mandatory=$true)][string]$VarFile,
 [Parameter(Mandatory=$true)][string]$OutputFile
)
$ErrorActionPreference='Stop'
$vars=Get-Content -LiteralPath $VarFile -Raw|ConvertFrom-Json
function Invoke-Aws {
 param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
 $raw=& aws.exe @Arguments --profile $Profile --region ap-northeast-1 --output json --no-cli-pager 2>&1
 if($LASTEXITCODE -ne 0){throw ($raw -join [Environment]::NewLine)}
 return (($raw -join [Environment]::NewLine)|ConvertFrom-Json -Depth 80)
}
$identity=Invoke-Aws @('sts','get-caller-identity')
if($identity.Account -ne $vars.expected_account_id){throw 'Unexpected AWS account'}
$counts=[ordered]@{}
$counts.load_balancers=@((Invoke-Aws @('elbv2','describe-load-balancers')).LoadBalancers|Where-Object {$_.LoadBalancerName -eq 'portfolio-day4-alb'}).Count
$counts.target_groups=@((Invoke-Aws @('elbv2','describe-target-groups')).TargetGroups|Where-Object {$_.TargetGroupName -eq 'portfolio-day4-web-tg'}).Count
$counts.ecs_clusters=@((Invoke-Aws @('ecs','list-clusters')).clusterArns|Where-Object {$_ -match ':cluster/portfolio-day4-cluster$'}).Count
foreach($state in @('ACTIVE','INACTIVE')) {
 $counts['task_definitions_'+$state.ToLower()]=@((Invoke-Aws @('ecs','list-task-definitions','--family-prefix','portfolio-day4-batch','--status',$state)).taskDefinitionArns|Where-Object {$_ -match ':task-definition/portfolio-day4-batch:\d+$'}).Count
}
$counts.workflows=@((Invoke-Aws @('stepfunctions','list-state-machines')).stateMachines|Where-Object {$_.name -eq 'portfolio-day4-workflow'}).Count
$counts.event_rules=@((Invoke-Aws @('events','list-rules','--name-prefix','portfolio-day4-')).Rules).Count
$counts.sns_topics=@((Invoke-Aws @('sns','list-topics')).Topics|Where-Object {$_.TopicArn -match ':portfolio-day4-alerts$'}).Count
$counts.sns_subscriptions=@((Invoke-Aws @('sns','list-subscriptions')).Subscriptions|Where-Object {$_.TopicArn -match ':portfolio-day4-alerts$'}).Count
$counts.alarms=@((Invoke-Aws @('cloudwatch','describe-alarms','--alarm-name-prefix','portfolio-day4-')).MetricAlarms).Count
$counts.dashboards=@((Invoke-Aws @('cloudwatch','list-dashboards','--dashboard-name-prefix','portfolio-day4-')).DashboardEntries).Count
$counts.log_groups=@((Invoke-Aws @('logs','describe-log-groups','--log-group-name-prefix','/portfolio/day4/')).logGroups).Count
$counts.security_groups=@((Invoke-Aws @('ec2','describe-security-groups','--filters','Name=group-name,Values=portfolio-day4-batch-sg')).SecurityGroups).Count
$counts.iam_roles=@((Invoke-Aws @('iam','list-roles')).Roles|Where-Object {$_.RoleName -in @('portfolio-day4-sfn-role','portfolio-day4-events-role')}).Count
$counts.managed_policies=@((Invoke-Aws @('iam','list-policies','--scope','Local')).Policies|Where-Object {$_.PolicyName -eq 'PortfolioDay4SfnPolicy'}).Count
$base=Invoke-Aws @('ec2','describe-instances','--instance-ids',$vars.instance_id)
$vpc=Invoke-Aws @('ec2','describe-vpcs','--vpc-ids',$vars.vpc_id)
$volumes=Invoke-Aws @('ec2','describe-volumes','--filters',('Name=attachment.instance-id,Values='+$vars.instance_id))
$summary=[ordered]@{checked_at_utc=[DateTimeOffset]::UtcNow.ToString('o');day4_counts=$counts;all_day4_counts_zero=(@($counts.Values|Where-Object {$_ -ne 0}).Count -eq 0);retained=@{instance_state=$base.Reservations[0].Instances[0].State.Name;vpc_available=($vpc.Vpcs[0].State -eq 'available');attached_ebs_count=@($volumes.Volumes).Count};cost_finalized=$false}
$summary|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $OutputFile -Encoding utf8
$summary|ConvertTo-Json -Depth 12
