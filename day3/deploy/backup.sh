#!/bin/bash
set -euo pipefail
systemctl stop tomcat
backup="/var/lib/portfolio-backups/${DEPLOYMENT_ID:-manual-$(date +%s)}"
install -d -m 700 "$backup"
for item in /var/lib/tomcat/webapps/portfolio /var/lib/tomcat/webapps/portfolio.war; do
  if [ -e "$item" ]; then mv "$item" "$backup/"; fi
done
