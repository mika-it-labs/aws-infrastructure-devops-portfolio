#!/usr/bin/env bash
set -euo pipefail
: "${ALB_DNS:?}" "${NLB_DNS:?}" "${RESTORED_EBS_SERIAL:?}" "${RESTORED_EFS_IP:?}"
FAULT_DRILL="${FAULT_DRILL:-false}"
pg_started=0
efs_mounted=0
ebs_mounted=0
tomcat_stopped=0
cleanup() {
  if [ "$tomcat_stopped" = 1 ]; then systemctl start tomcat; fi
  if [ "$pg_started" = 1 ]; then runuser -u postgres -- pg_ctl -D /mnt/portfolio-day2-ebs/data -m fast -w stop; fi
  if [ "$efs_mounted" = 1 ]; then umount /mnt/portfolio-day2-efs; fi
  if [ "$ebs_mounted" = 1 ]; then umount /mnt/portfolio-day2-ebs; fi
}
trap cleanup EXIT
date -Iseconds
systemctl is-active httpd tomcat postgresql
for endpoint in "$ALB_DNS" "$NLB_DNS"; do
  curl -fsS --max-time 15 --retry 12 --retry-delay 5 --retry-all-errors "http://$endpoint/portfolio/" | grep 'Apache -&gt;\|Apache ->'
done
echo LOAD_BALANCERS=PASS
restore_dev=$(lsblk -dnpo PATH,SERIAL | awk -v serial="$RESTORED_EBS_SERIAL" '$2==serial {print $1}')
test -n "$restore_dev"
test "$restore_dev" != "$(findmnt -nro SOURCE /var/lib/pgsql)"
if ss -H -ltn 'sport = :55432' | grep -q .; then echo 'Restore-test port is already in use' >&2; exit 1; fi
mkdir -p /mnt/portfolio-day2-ebs /mnt/portfolio-day2-efs
mount -o nouuid "$restore_dev" /mnt/portfolio-day2-ebs
ebs_mounted=1
runuser -u postgres -- pg_ctl -D /mnt/portfolio-day2-ebs/data -l /tmp/portfolio-day2-restore-postgres.log -o "-p 55432 -k /tmp -c listen_addresses=127.0.0.1" -w start
pg_started=1
runuser -u postgres -- psql -h /tmp -p 55432 -d portfolio -v ON_ERROR_STOP=1 -Atc "SELECT message FROM public.learning_log WHERE id=1;" | grep -F 'Day 1: Apache -> Tomcat -> PostgreSQL OK'
echo EBS_RESTORE_SQL=PASS
runuser -u postgres -- pg_ctl -D /mnt/portfolio-day2-ebs/data -m fast -w stop
pg_started=0
umount /mnt/portfolio-day2-ebs
ebs_mounted=0
mount -t nfs4 -o ro,nfsvers=4.1,soft,timeo=50,retrans=2 "$RESTORED_EFS_IP:/" /mnt/portfolio-day2-efs
efs_mounted=1
restore_file=$(find /mnt/portfolio-day2-efs -type f -name day1.txt -print -quit)
test -n "$restore_file"
cmp "$restore_file" /mnt/shared/day1.txt
cat "$restore_file"
echo EFS_RESTORE_CONTENT_MATCH=PASS
umount /mnt/portfolio-day2-efs
efs_mounted=0
if [ "$FAULT_DRILL" = true ]; then
  tomcat_stopped=1
  systemctl stop tomcat
  for round in $(seq 1 10); do
    date -Iseconds
    code=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "http://$ALB_DNS/portfolio/")
    echo "ALB_FAULT_HTTP=$code"
    test "$code" = 503
    sleep 10
  done
  systemctl start tomcat
  tomcat_stopped=0
  curl -fsS --max-time 15 --retry 15 --retry-delay 3 --retry-all-errors "http://$ALB_DNS/portfolio/" | grep -F 'PostgreSQL OK'
  echo FAULT_RECOVERY=PASS
fi
systemctl is-active httpd tomcat postgresql
echo DAY2_VERIFICATION=PASS
