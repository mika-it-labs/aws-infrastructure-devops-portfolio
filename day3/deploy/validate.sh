#!/bin/bash
set -euo pipefail
for attempt in {1..50}; do
  if curl -fsS http://127.0.0.1/portfolio/ -o /tmp/portfolio-day3.html; then
    if grep -q 'AWS Portfolio Day 3' /tmp/portfolio-day3.html && grep -q 'DB_STATUS=CONNECTED' /tmp/portfolio-day3.html; then
      echo EC2_DEPLOYMENT_DB_CHECK=PASS
      exit 0
    fi
  fi
  sleep 2
done
echo EC2_DEPLOYMENT_DB_CHECK=FAIL
exit 1
