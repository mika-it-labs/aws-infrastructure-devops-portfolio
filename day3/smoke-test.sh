#!/bin/bash
set -euo pipefail
for attempt in {1..60}; do
  if curl --max-time 5 -fsS http://127.0.0.1:18080/portfolio/health.jsp | grep -q OK; then break; fi
  sleep 2
done
curl --max-time 10 -fsS http://127.0.0.1:18080/portfolio/health.jsp | grep -q OK
curl --max-time 10 -fsS http://127.0.0.1:18080/portfolio/ -o /tmp/portfolio-container.html
grep -q 'AWS Portfolio Day 3' /tmp/portfolio-container.html
grep -q 'DB_STATUS=UNCONFIGURED' /tmp/portfolio-container.html
cat /tmp/portfolio-container.html
echo CONTAINER_SMOKE_TEST=PASS
