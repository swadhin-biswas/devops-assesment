#!/usr/bin/env bash
# shellcheck disable=SC2154
# $${...} placeholders are substituted by Terraform templatefile, not shell variables.
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# IAM instance profile credentials can take a few minutes to appear in
# IMDS after first boot. Retry the whole bootstrap so a transient
# credential lookup does not fail the boot.
apt-get update -qq
apt-get install -y -qq -o DPkg::Lock::Timeout=120 docker.io curl
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
actual_sha=$(sha256sum /opt/devops-task/deploy.sh | awk '{print $1}')
if [ "$actual_sha" != "${deploy_script_sha256}" ]; then
  echo "deploy.sh checksum mismatch: expected ${deploy_script_sha256}, got $actual_sha" >&2
  exit 1
fi
chmod +x /opt/devops-task/deploy.sh

for attempt in $(seq 1 5); do
  if APP_PORT=${app_port} /opt/devops-task/deploy.sh "${image_uri}" "${app_version}"; then
    exit 0
  fi
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) bootstrap attempt $attempt failed, retrying in 60s" >&2
  sleep 60
done

exit 1
