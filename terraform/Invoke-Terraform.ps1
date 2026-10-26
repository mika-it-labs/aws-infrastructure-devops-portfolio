param(
  [Parameter(Mandatory=$true)][string]$Profile,
  [Parameter(ValueFromRemainingArguments=$true)][string[]]$TerraformArgs
)
$ErrorActionPreference='Stop'
$Raw=& aws.exe configure export-credentials --profile $Profile --format process 2>&1
if($LASTEXITCODE -ne 0){throw 'AWS authentication failed. Refresh the selected profile first.'}
$Credential=($Raw -join "`n")|ConvertFrom-Json
$Names='AWS_ACCESS_KEY_ID','AWS_SECRET_ACCESS_KEY','AWS_SESSION_TOKEN','AWS_REGION','AWS_EC2_METADATA_DISABLED'
$Previous=@{};foreach($Name in $Names){$Previous[$Name]=[Environment]::GetEnvironmentVariable($Name,'Process')}
try {
 $env:AWS_ACCESS_KEY_ID=$Credential.AccessKeyId
 $env:AWS_SECRET_ACCESS_KEY=$Credential.SecretAccessKey
 $env:AWS_SESSION_TOKEN=$Credential.SessionToken
 $env:AWS_REGION='ap-northeast-1'
 $env:AWS_EC2_METADATA_DISABLED='true'
 & terraform "-chdir=$PSScriptRoot" @TerraformArgs
 $Result=$LASTEXITCODE
} finally {
 foreach($Name in $Names){[Environment]::SetEnvironmentVariable($Name,$Previous[$Name],'Process')}
}
exit $Result
