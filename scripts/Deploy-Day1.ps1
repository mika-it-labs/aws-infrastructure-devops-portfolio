param([ValidateSet('Network','Server','Library')][string]$Phase='Network',[string]$Profile='portfolio-lab')
$ErrorActionPreference='Stop'
$Region='ap-northeast-1'
$StatePath=Join-Path $PSScriptRoot '../.local/resources.json'
$Scratch=Join-Path $PSScriptRoot '../.local/work'
New-Item -ItemType Directory -Force $Scratch | Out-Null
$S=if(Test-Path $StatePath){Get-Content $StatePath -Raw|ConvertFrom-Json -AsHashtable}else{@{Region=$Region;Project='portfolio';Run=('day1-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))}}
function Save { $S|ConvertTo-Json -Depth 30|Set-Content $StatePath -Encoding utf8 }
function Invoke-PortfolioAws([string]$Service,[string]$Action,[hashtable]$Body=@{}) {
 $InputPath=Join-Path $Scratch 'request.json'
 $Body|ConvertTo-Json -Depth 40|Set-Content $InputPath -Encoding utf8
 $Raw=& aws.exe $Service $Action --profile $Profile --region $Region --cli-input-json "file://$InputPath" --output json --no-cli-pager 2>&1
 if($LASTEXITCODE -ne 0){throw ($Raw -join "`n")}
 if($Raw){return ($Raw -join "`n"|ConvertFrom-Json -AsHashtable)}
}
function Tags([string]$Name){return @(@{Key='Project';Value='portfolio'},@{Key='Run';Value=$S.Run},@{Key='Name';Value=$Name})}
function Spec([string]$Type,[string]$Name){return ,@(@{ResourceType=$Type;Tags=(Tags $Name)})}
if($Phase -eq 'Network'){
 if(!$S.Vpc){$S.Vpc=(Invoke-PortfolioAws ec2 create-vpc @{CidrBlock='10.40.0.0/16';TagSpecifications=(Spec vpc portfolio-day1)}).Vpc.VpcId;Save}
 Invoke-PortfolioAws ec2 modify-vpc-attribute @{VpcId=$S.Vpc;EnableDnsSupport=@{Value=$true}}|Out-Null
 Invoke-PortfolioAws ec2 modify-vpc-attribute @{VpcId=$S.Vpc;EnableDnsHostnames=@{Value=$true}}|Out-Null
 $AZ=(Invoke-PortfolioAws ec2 describe-availability-zones @{Filters=@(@{Name='state';Values=@('available')})}).AvailabilityZones | Sort-Object ZoneName | Select-Object -First 2
 $S.AZ=@($AZ.ZoneName);Save
 foreach($Def in @(@('PublicA','10.40.1.0/24',0),@('PublicB','10.40.2.0/24',1),@('PrivateA','10.40.11.0/24',0),@('PrivateB','10.40.12.0/24',1))){
  if(!$S[$Def[0]]){$S[$Def[0]]=(Invoke-PortfolioAws ec2 create-subnet @{VpcId=$S.Vpc;CidrBlock=$Def[1];AvailabilityZone=$S.AZ[$Def[2]];TagSpecifications=(Spec subnet ('portfolio-day1-'+$Def[0]))}).Subnet.SubnetId;Save}
 }
 if(!$S.Igw){$S.Igw=(Invoke-PortfolioAws ec2 create-internet-gateway @{TagSpecifications=(Spec internet-gateway portfolio-day1)}).InternetGateway.InternetGatewayId;Save;Invoke-PortfolioAws ec2 attach-internet-gateway @{VpcId=$S.Vpc;InternetGatewayId=$S.Igw}|Out-Null}
 if(!$S.PublicRoute){$S.PublicRoute=(Invoke-PortfolioAws ec2 create-route-table @{VpcId=$S.Vpc;TagSpecifications=(Spec route-table portfolio-day1-public)}).RouteTable.RouteTableId;Save;Invoke-PortfolioAws ec2 create-route @{RouteTableId=$S.PublicRoute;DestinationCidrBlock='0.0.0.0/0';GatewayId=$S.Igw}|Out-Null}
 if(!$S.PrivateRoute){$S.PrivateRoute=(Invoke-PortfolioAws ec2 create-route-table @{VpcId=$S.Vpc;TagSpecifications=(Spec route-table portfolio-day1-private)}).RouteTable.RouteTableId;Save}
 foreach($Key in 'PublicA','PublicB','PrivateA','PrivateB'){
  if(!$S[($Key+'Association')]){$Rt=if($Key.StartsWith('Public')){$S.PublicRoute}else{$S.PrivateRoute};$S[($Key+'Association')]=(Invoke-PortfolioAws ec2 associate-route-table @{SubnetId=$S[$Key];RouteTableId=$Rt}).AssociationId;Save}
 }
 if(!$S.WebSG){$S.WebSG=(Invoke-PortfolioAws ec2 create-security-group @{VpcId=$S.Vpc;GroupName='portfolio-day1-web';Description='SSM management; HTTP restricted to VPC';TagSpecifications=(Spec security-group portfolio-day1-web)}).GroupId;Save;Invoke-PortfolioAws ec2 authorize-security-group-ingress @{GroupId=$S.WebSG;IpPermissions=@(@{IpProtocol='tcp';FromPort=80;ToPort=80;IpRanges=@(@{CidrIp='10.40.0.0/16';Description='VPC HTTP only'})})}|Out-Null}
 if(!$S.EfsSG){$S.EfsSG=(Invoke-PortfolioAws ec2 create-security-group @{VpcId=$S.Vpc;GroupName='portfolio-day1-efs';Description='NFS from day1 EC2 only';TagSpecifications=(Spec security-group portfolio-day1-efs)}).GroupId;Save;Invoke-PortfolioAws ec2 authorize-security-group-ingress @{GroupId=$S.EfsSG;IpPermissions=@(@{IpProtocol='tcp';FromPort=2049;ToPort=2049;UserIdGroupPairs=@(@{GroupId=$S.WebSG})})}|Out-Null}
 Write-Output 'Network phase completed.'
}
if($Phase -eq 'Server'){
 if(!$S.Vpc){throw 'Run Network phase first.'}
 if(!$S.Role){
  $Role='portfolio-'+$S.Run+'-ec2'
  Invoke-PortfolioAws iam create-role @{RoleName=$Role;AssumeRolePolicyDocument='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}';Tags=(Tags portfolio-day1-ec2)}|Out-Null
  $S.Role=$Role;Save
 }
 foreach($Policy in 'AmazonSSMManagedInstanceCore','CloudWatchAgentServerPolicy'){Invoke-PortfolioAws iam attach-role-policy @{RoleName=$S.Role;PolicyArn="arn:aws:iam::aws:policy/$Policy"}|Out-Null}
 if(!$S.InstanceProfile){Invoke-PortfolioAws iam create-instance-profile @{InstanceProfileName=$S.Role;Tags=(Tags portfolio-day1-ec2)}|Out-Null;Invoke-PortfolioAws iam add-role-to-instance-profile @{InstanceProfileName=$S.Role;RoleName=$S.Role}|Out-Null;$S.InstanceProfile=$S.Role;Save}
 Write-Output 'Server identity prepared.'
}





