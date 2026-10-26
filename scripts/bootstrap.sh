#!/bin/bash
set -euo pipefail
exec > >(tee -a /var/log/portfolio-bootstrap.log) 2>&1
trap 'echo "FAILED at line $LINENO"' ERR
export AWS_DEFAULT_REGION=ap-northeast-1
: "${DATA_VOLUME_ID:?}" "${EFS_IP:?}" "${STATIC_BUCKET:?}" "${LOG_BUCKET:?}"
dnf -y update
dnf -y install httpd tomcat postgresql-server postgresql-jdbc java-17-openjdk-headless nfs-utils xfsprogs policycoreutils-python-utils firewalld unzip curl
systemctl stop postgresql || true
timedatectl set-timezone Asia/Tokyo
# Only the newly created data volume, verified by its AWS volume serial, may be formatted.
serial="${DATA_VOLUME_ID//-/}"
device=$(lsblk -dpno NAME,SERIAL | awk -v s="$serial" '$2 == s {print $1}')
[ -b "$device" ] || { echo 'Data volume not found'; exit 1; }
[ "$(lsblk -nr "$device" | wc -l)" -eq 1 ] || { echo 'Unexpected partitions'; exit 1; }
if ! blkid "$device" >/dev/null 2>&1; then mkfs.xfs "$device"; fi
[ "$(blkid -s TYPE -o value "$device")" = xfs ]
mkdir -p /var/lib/pgsql
uuid=$(blkid -s UUID -o value "$device")
grep -q "UUID=$uuid " /etc/fstab || echo "UUID=$uuid /var/lib/pgsql xfs defaults 0 0" >> /etc/fstab
mountpoint -q /var/lib/pgsql || mount /var/lib/pgsql
chown postgres:postgres /var/lib/pgsql
chmod 700 /var/lib/pgsql
restorecon -RF /var/lib/pgsql
[ -f /var/lib/pgsql/data/PG_VERSION ] || postgresql-setup --initdb
systemctl enable --now postgresql
# A peer-authenticated Unix socket is used for administration; the application uses loopback SCRAM.
password=$(openssl rand -hex 24)
install -d -m 750 -o root -g tomcat /etc/portfolio
if [ ! -f /etc/portfolio/db.properties ]; then
 runuser -u postgres -- psql -v ON_ERROR_STOP=1 <<SQL
SET password_encryption = 'scram-sha-256';
CREATE USER portfolio_app PASSWORD '$password';
CREATE DATABASE portfolio OWNER portfolio_app;
SQL
 printf 'url=jdbc:postgresql://127.0.0.1:5432/portfolio\nuser=portfolio_app\npassword=%s\n' "$password" > /etc/portfolio/db.properties
 chown root:tomcat /etc/portfolio/db.properties
 chmod 640 /etc/portfolio/db.properties
fi
if ! grep -q 'portfolio_app.*scram-sha-256' /var/lib/pgsql/data/pg_hba.conf; then
 sed -i '1ihost portfolio portfolio_app 127.0.0.1/32 scram-sha-256' /var/lib/pgsql/data/pg_hba.conf
fi
systemctl reload postgresql
runuser -u postgres -- psql -d portfolio -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE IF NOT EXISTS public.learning_log (id integer PRIMARY KEY, message text NOT NULL);
INSERT INTO public.learning_log VALUES (1, 'Day 1: Apache -> Tomcat -> PostgreSQL OK') ON CONFLICT (id) DO NOTHING;
GRANT SELECT ON public.learning_log TO portfolio_app;
SQL
mkdir -p /var/lib/tomcat/webapps/portfolio/WEB-INF/lib
jdbc=$(find /usr/share/java -name 'postgresql*.jar' -type f | head -1)
[ -n "$jdbc" ]
cp "$jdbc" /var/lib/tomcat/webapps/portfolio/WEB-INF/lib/postgresql.jar
cat > /var/lib/tomcat/webapps/portfolio/index.jsp <<'JSP'
<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" import="java.sql.*,java.util.*,java.io.*" %>
<!doctype html><html lang="ja"><meta charset="UTF-8"><title>AWS Portfolio Day 1</title><body>
<h1>AWS Portfolio Day 1</h1>
<% Properties p=new Properties(); try(InputStream f=new FileInputStream("/etc/portfolio/db.properties")){p.load(f);} Class.forName("org.postgresql.Driver");
try(Connection c=DriverManager.getConnection(p.getProperty("url"),p.getProperty("user"),p.getProperty("password"));PreparedStatement s=c.prepareStatement("SELECT message FROM learning_log WHERE id=1");ResultSet r=s.executeQuery()){if(r.next()){%><p><%=r.getString(1)%></p><%}} %>
</body></html>
JSP
chown -R tomcat:tomcat /var/lib/tomcat/webapps/portfolio
restorecon -RF /var/lib/tomcat
# Hide Tomcat behind Apache; only loopback can reach 8080.
sed -i 's/<Connector port="8080"/<Connector address="127.0.0.1" port="8080"/' /etc/tomcat/server.xml
cat > /etc/httpd/conf.d/portfolio.conf <<'HTTPD'
ProxyRequests Off
ProxyPreserveHost On
ProxyPass /portfolio/ http://127.0.0.1:8080/portfolio/
ProxyPassReverse /portfolio/ http://127.0.0.1:8080/portfolio/
RedirectMatch ^/$ /portfolio/
HTTPD
setsebool -P httpd_can_network_connect on
systemctl enable --now firewalld
firewall-cmd --permanent --remove-service=ssh
firewall-cmd --permanent --remove-service=cockpit
firewall-cmd --permanent --add-service=http
firewall-cmd --reload
systemctl enable --now tomcat httpd
mkdir -p /mnt/shared
grep -q ' /mnt/shared ' /etc/fstab || echo "$EFS_IP:/ /mnt/shared nfs4 nfsvers=4.1,hard,timeo=600,retrans=2,noresvport,_netdev,nofail 0 0" >> /etc/fstab
mountpoint -q /mnt/shared || mount /mnt/shared
echo 'portfolio Day 1 shared filesystem verified' > /mnt/shared/day1.txt
curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip
unzip -q -o /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --update
curl -fsSL https://amazoncloudwatch-agent.s3.amazonaws.com/redhat/amd64/latest/amazon-cloudwatch-agent.rpm -o /tmp/cloudwatch.rpm
rpm -Uvh --replacepkgs /tmp/cloudwatch.rpm
cat > /opt/aws/amazon-cloudwatch-agent/etc/portfolio.json <<'CW'
{"agent":{"metrics_collection_interval":60},"metrics":{"namespace":"Portfolio/Day1","append_dimensions":{"InstanceId":"${aws:InstanceId}"},"metrics_collected":{"mem":{"measurement":["mem_used_percent"]},"disk":{"resources":["/","/var/lib/pgsql"],"measurement":["used_percent"],"drop_device":true}}},"logs":{"logs_collected":{"files":{"collect_list":[{"file_path":"/var/log/httpd/access_log","log_group_name":"/portfolio/day1/httpd-access","log_stream_name":"{instance_id}","retention_in_days":7},{"file_path":"/var/log/httpd/error_log","log_group_name":"/portfolio/day1/httpd-error","log_stream_name":"{instance_id}","retention_in_days":7},{"file_path":"/var/log/tomcat/catalina*.log","log_group_name":"/portfolio/day1/tomcat","log_stream_name":"{instance_id}","retention_in_days":7},{"file_path":"/var/log/portfolio-bootstrap.log","log_group_name":"/portfolio/day1/bootstrap","log_stream_name":"{instance_id}","retention_in_days":7}]}}}}
CW
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/portfolio.json -s
for attempt in {1..30}; do curl -fsS http://127.0.0.1/portfolio/ -o /tmp/portfolio-result.html && break; sleep 2; done
grep -q 'PostgreSQL OK' /tmp/portfolio-result.html
aws s3 cp /tmp/portfolio-result.html "s3://$STATIC_BUCKET/index.html"
{ date -Is; cat /etc/redhat-release; timedatectl; getenforce; lsblk -f; findmnt /var/lib/pgsql /mnt/shared || true; systemctl --no-pager status httpd tomcat postgresql amazon-cloudwatch-agent; cat /tmp/portfolio-result.html; cat /mnt/shared/day1.txt; } > /tmp/day1-evidence.txt
aws s3 cp /tmp/day1-evidence.txt "s3://$LOG_BUCKET/day1/evidence.txt"
echo 'DAY1_BOOTSTRAP_SUCCESS'

