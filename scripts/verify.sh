#!/bin/bash
set -eu
printf '\n=== OS / security ===\n'
cat /etc/redhat-release
uname -r
timedatectl show -p Timezone
getenforce
getsebool httpd_can_network_connect
firewall-cmd --list-services
printf '\n=== services ===\n'
for s in httpd tomcat postgresql amazon-ssm-agent amazon-cloudwatch-agent; do printf '%s: ' "$s"; systemctl is-active "$s"; systemctl is-enabled "$s"; done
printf '\n=== application HTTP / DB query ===\n'
curl -fsS http://127.0.0.1/portfolio/
printf '\n=== database ===\n'
runuser -u postgres -- psql -d portfolio -c 'SELECT id,message FROM learning_log;'
printf '\n=== storage ===\n'
lsblk -o NAME,SERIAL,SIZE,FSTYPE,MOUNTPOINTS
findmnt /var/lib/pgsql
findmnt /mnt/shared
cat /mnt/shared/day1.txt
printf '\n=== listeners ===\n'
ss -lntp | grep -E ':(80|8080|5432) '
printf '\n=== agent ===\n'
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status
