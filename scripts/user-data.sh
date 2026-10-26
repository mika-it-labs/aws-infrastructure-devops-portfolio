#!/bin/bash
set -eu
dnf -y install python3
rpm -q amazon-ssm-agent || dnf -y install https://s3.ap-northeast-1.amazonaws.com/amazon-ssm-ap-northeast-1/latest/linux_amd64/amazon-ssm-agent.rpm
systemctl enable --now amazon-ssm-agent
