#!/bin/bash
set -euo pipefail
chown tomcat:tomcat /var/lib/tomcat/webapps/portfolio.war
chmod 640 /var/lib/tomcat/webapps/portfolio.war
restorecon /var/lib/tomcat/webapps/portfolio.war
