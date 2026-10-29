set -eu
url='ALB_URL_PLACEHOLDER'
trap 'systemctl start tomcat' EXIT
echo BASELINE_START
for n in $(seq 1 30); do
 code=$(curl --max-time 8 -s -o /tmp/day4-iac-before.html -w '%{http_code}' "$url" || true)
 if [ "$code" = 200 ] && grep -q 'PostgreSQL OK' /tmp/day4-iac-before.html; then break; fi
 sleep 10
done
test "$code" = 200
grep -q 'PostgreSQL OK' /tmp/day4-iac-before.html
echo BASELINE_HTTP=200
echo BASELINE_DB=PASS
echo FAULT_START
date -u +%FT%TZ
systemctl stop tomcat
for n in $(seq 1 36); do
 date -u +%FT%TZ
 curl --max-time 8 -s -o /dev/null -w 'FAULT_HTTP=%{http_code}\n' "$url" || true
 sleep 10
done
systemctl start tomcat
echo TOMCAT_STARTED
for n in $(seq 1 24); do
 code=$(curl --max-time 8 -s -o /tmp/day4-iac-after.html -w '%{http_code}' "$url" || true)
 echo "RECOVERY_HTTP=$code"
 if [ "$code" = 200 ] && grep -q 'PostgreSQL OK' /tmp/day4-iac-after.html; then
  systemctl is-active httpd tomcat postgresql
  date -u +%FT%TZ
  echo FAULT_RECOVERY=PASS
  exit 0
 fi
 sleep 10
done
echo FAULT_RECOVERY=FAIL
exit 1
