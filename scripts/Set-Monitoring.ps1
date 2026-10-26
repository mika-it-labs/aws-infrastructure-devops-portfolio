param([string]$Profile='portfolio-lab')
. "$PSScriptRoot/Deploy-Day1.ps1" -Phase Library -Profile $Profile
$D=@(@{Name='InstanceId';Value=$S.Instance})
$Alarms=@(
 @{AlarmName='portfolio-day1-cpu-high';Namespace='AWS/EC2';MetricName='CPUUtilization';Dimensions=$D;Threshold=80;Period=300},
 @{AlarmName='portfolio-day1-status-failed';Namespace='AWS/EC2';MetricName='StatusCheckFailed';Dimensions=$D;Threshold=0;Period=60},
 @{AlarmName='portfolio-day1-memory-high';Namespace='Portfolio/Day1';MetricName='mem_used_percent';Dimensions=$D;Threshold=85;Period=60}
)
foreach($A in $Alarms){$A.Statistic='Average';$A.EvaluationPeriods=2;$A.ComparisonOperator='GreaterThanThreshold';$A.TreatMissingData='missing';$A.Tags=(Tags $A.AlarmName);Invoke-PortfolioAws cloudwatch put-metric-alarm $A|Out-Null}
$Metrics=(Invoke-PortfolioAws cloudwatch list-metrics @{Namespace='Portfolio/Day1';MetricName='disk_used_percent';Dimensions=$D}).Metrics
foreach($M in $Metrics){$Path=($M.Dimensions|Where-Object Name -eq path).Value;$Suffix=if($Path -eq '/'){'root'}else{'pgsql'};Invoke-PortfolioAws cloudwatch put-metric-alarm @{AlarmName="portfolio-day1-disk-$Suffix-high";Namespace=$M.Namespace;MetricName=$M.MetricName;Dimensions=$M.Dimensions;Threshold=80;Period=60;Statistic='Average';EvaluationPeriods=2;ComparisonOperator='GreaterThanThreshold';TreatMissingData='missing';Tags=(Tags "portfolio-day1-disk-$Suffix-high")}|Out-Null}
Write-Output 'CloudWatch alarms configured; no SNS action attached (Day4).'



