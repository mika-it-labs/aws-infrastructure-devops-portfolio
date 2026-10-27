param(
 [Parameter(Mandatory=$true)][ValidateSet('StartBackups','StartRestores','Status')][string]$Action,
 [Parameter(Mandatory=$true)][string]$JournalPath,
 [string]$Profile='default',
 [string]$Region='ap-northeast-1',
 [string]$InstanceId,
 [string]$DatabaseVolumeArn,
 [string]$FileSystemArn,
 [string]$BackupRoleArn,
 [string]$VaultName='Default',
 [string]$AvailabilityZone='ap-northeast-1a'
)
# Requires PowerShell 7. This operational journal contains account/resource IDs.
$ErrorActionPreference='Stop'
$JournalPath=[IO.Path]::GetFullPath($JournalPath)
$RepositoryRoot=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
if($JournalPath.StartsWith($RepositoryRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
 throw 'Keep the restore journal outside the public repository.'
}
function Invoke-Day2Aws {
 param([string[]]$Arguments)
 $cliArgs=@('--profile',$Profile,'--region',$Region,'--no-cli-pager','--output','json')+$Arguments
 $raw=& aws @cliArgs
 if($LASTEXITCODE -ne 0){throw 'AWS request failed. No next operation was submitted.'}
 return (($raw -join "`n") | ConvertFrom-Json -AsHashtable)
}
function Save-Day2Journal {
 [IO.File]::WriteAllText($JournalPath,(@($script:jobs) | ConvertTo-Json -Depth 30),(New-Object Text.UTF8Encoding($false)))
}
if(!(Test-Path -LiteralPath (Split-Path $JournalPath -Parent) -PathType Container)){throw 'Create the private journal directory before starting any jobs.'}
$jobs=@()
if(Test-Path -LiteralPath $JournalPath){$jobs=@(Get-Content -Raw -LiteralPath $JournalPath | ConvertFrom-Json -AsHashtable)}
if($Action -eq 'StartBackups'){
 if($jobs.Count -gt 0){throw 'This journal already has jobs. Use Status or StartRestores, or a new journal for a new run.'}
 if(!$InstanceId -or !$DatabaseVolumeArn -or !$FileSystemArn -or !$BackupRoleArn){throw 'Supply the instance, exact source ARNs, and existing backup role.'}
 $instance=Invoke-Day2Aws @('ec2','describe-instances','--instance-ids',$InstanceId)
 if($instance.Reservations[0].Instances[0].State.Name -ne 'stopped'){throw 'Normally stop EC2 before backing up its database volume.'}
 foreach($target in @(@{Kind='EBS';Arn=$DatabaseVolumeArn},@{Kind='EFS';Arn=$FileSystemArn})){
  $job=Invoke-Day2Aws @('backup','start-backup-job','--backup-vault-name',$VaultName,'--resource-arn',$target.Arn,'--iam-role-arn',$BackupRoleArn,'--lifecycle','DeleteAfterDays=7')
  $jobs+=@{Kind=$target.Kind;SourceArn=$target.Arn;BackupJobId=$job.BackupJobId;RecoveryPointArn=$job.RecoveryPointArn;RoleArn=$BackupRoleArn}
  Save-Day2Journal
 }
}
elseif($Action -eq 'StartRestores'){
 if($jobs.Count -eq 0){throw 'No backup jobs in this journal.'}
 foreach($job in $jobs){
  if($job.RestoreJobId){continue}
  $backup=Invoke-Day2Aws @('backup','describe-backup-job','--backup-job-id',$job.BackupJobId)
  if($backup.State -ne 'COMPLETED'){throw ("Backup is not complete: "+$job.Kind+" "+$backup.State)}
  $job.RecoveryPointArn=$backup.RecoveryPointArn
  $response=Invoke-Day2Aws @('backup','get-recovery-point-restore-metadata','--backup-vault-name',$VaultName,'--recovery-point-arn',$job.RecoveryPointArn)
  $metadata=$response.RestoreMetadata
  if($job.Kind -eq 'EFS'){
   $metadata.newFileSystem='true';$metadata.CreationToken='day2-tf-'+$job.BackupJobId
   $metadata.Encrypted='true';$metadata.PerformanceMode='generalPurpose';$metadata.KmsKeyId='alias/aws/elasticfilesystem'
  }else{
   $metadata.volumeType='gp3';$metadata.volumeSize='8';$metadata.availabilityZone=$AvailabilityZone
   $metadata.encrypted='true';$metadata.iops='3000';$metadata.throughput='125'
  }
  $metadataPath=$JournalPath+'.'+$job.Kind+'.restore-metadata.json'
  [IO.File]::WriteAllText($metadataPath,($metadata | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
  $restore=Invoke-Day2Aws @('backup','start-restore-job','--recovery-point-arn',$job.RecoveryPointArn,'--metadata',('file://'+$metadataPath),'--iam-role-arn',$job.RoleArn,'--resource-type',$job.Kind,'--idempotency-token',('tf-'+$job.BackupJobId),'--copy-source-tags-to-restored-resource')
  $job.RestoreJobId=$restore.RestoreJobId
  Save-Day2Journal
 }
}
foreach($job in $jobs){
 $backup=Invoke-Day2Aws @('backup','describe-backup-job','--backup-job-id',$job.BackupJobId)
 $job.RecoveryPointArn=$backup.RecoveryPointArn
 $job.BackupState=$backup.State
 if($job.RestoreJobId){
  $restore=Invoke-Day2Aws @('backup','describe-restore-job','--restore-job-id',$job.RestoreJobId)
  $job.RestoreState=$restore.Status
  $job.CreatedResourceArn=$restore.CreatedResourceArn
 }
}
if($jobs.Count -gt 0){Save-Day2Journal}
$jobs | ForEach-Object {[pscustomobject]@{Kind=$_.Kind;BackupState=$_.BackupState;RestoreState=$_.RestoreState;CreatedResourceArn=$_.CreatedResourceArn}}



