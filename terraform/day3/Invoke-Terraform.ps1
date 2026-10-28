param(
 [Parameter(Mandatory=$true)][string]$Profile,
 [Parameter(Mandatory=$true)][string]$StateDirectory,
 [Parameter(ValueFromRemainingArguments=$true)][string[]]$TerraformArgs
)
$ErrorActionPreference='Stop'
$PrivateRoot=[IO.Path]::GetFullPath($StateDirectory)
$RepositoryRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if($PrivateRoot.StartsWith($RepositoryRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Keep Terraform state and provider data outside the public repository.'}
New-Item -ItemType Directory -Path $PrivateRoot -Force|Out-Null
$raw=& aws.exe configure export-credentials --profile $Profile --format process 2>&1
if($LASTEXITCODE -ne 0){throw 'Refresh the selected AWS CLI profile before running Terraform.'}
$credential=($raw -join [Environment]::NewLine)|ConvertFrom-Json
$names=@('AWS_ACCESS_KEY_ID','AWS_SECRET_ACCESS_KEY','AWS_SESSION_TOKEN','AWS_REGION','AWS_EC2_METADATA_DISABLED','TF_DATA_DIR')
$previous=@{}
foreach($n in $names){$previous[$n]=[Environment]::GetEnvironmentVariable($n,'Process')}
try {
 $env:AWS_ACCESS_KEY_ID=$credential.AccessKeyId
 $env:AWS_SECRET_ACCESS_KEY=$credential.SecretAccessKey
 $env:AWS_SESSION_TOKEN=$credential.SessionToken
 $env:AWS_REGION='ap-northeast-1'
 $env:AWS_EC2_METADATA_DISABLED='true'
 $env:TF_DATA_DIR=Join-Path $PrivateRoot 'provider-data'
 if($TerraformArgs[0] -eq 'init'){$TerraformArgs+=('-backend-config=path='+ (Join-Path $PrivateRoot 'terraform.tfstate'))}
 & terraform "-chdir=$PSScriptRoot" @TerraformArgs
 $result=$LASTEXITCODE
} finally {
 foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$previous[$n],'Process')}
}
exit $result
