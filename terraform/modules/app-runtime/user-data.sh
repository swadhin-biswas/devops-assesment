#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq docker.io curl
systemctl enable --now docker

mkdir -p /opt/devops-task

cat > /opt/devops-task/app.env <<ENV
AWS_REGION=${aws_region}
LOG_GROUP=${log_group}
APP_ENV=${app_env}
LOG_LEVEL=${log_level}
ENV
chmod 600 /opt/devops-task/app.env

curl -fsSL -o /opt/devops-task/deploy.sh "${deploy_script}"
chmod +x /opt/devops-task/deploy.sh

APP_PORT=${app_port} /opt/devops-task/deploy.sh "${image_uri}" "${app_version}"
