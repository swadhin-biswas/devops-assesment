#!/bin/sh
# Render the Alertmanager config from the template, substituting the webhook
# URL from the environment. Without a URL, alerts stay in the Alertmanager UI.
set -eu

template=/etc/alertmanager/alertmanager.tmpl.yml
config=/tmp/alertmanager.yml

if [ -n "${ALERT_WEBHOOK_URL:-}" ]; then
  sed "s|__ALERT_WEBHOOK_URL__|${ALERT_WEBHOOK_URL}|g" "$template" > "$config"
  echo "alertmanager: routing notifications to the configured webhook" >&2
else
  cat > "$config" <<'YAML'
global:
  resolve_timeout: 5m
route:
  receiver: noop
receivers:
  - name: noop
YAML
  echo "alertmanager: ALERT_WEBHOOK_URL is not set; alerts stay in the UI" >&2
fi

exec /bin/alertmanager --config.file="$config" --storage.path=/tmp/alertmanager
