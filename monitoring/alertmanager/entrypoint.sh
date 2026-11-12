#!/bin/sh
# Render the Alertmanager config from the template, substituting the webhook
# URL from the environment. Without a URL, alerts stay in the Alertmanager UI.
set -eu

template=/etc/alertmanager/alertmanager.tmpl.yml
config=/tmp/alertmanager.yml

if [ -n "${ALERT_WEBHOOK_URL:-}" ]; then
  # awk treats the URL literally; sed would expand & in the replacement.
  awk -v url="$ALERT_WEBHOOK_URL" '
    {
      while ((i = index($0, "https://example.invalid/hook")) > 0) {
        $0 = substr($0, 1, i - 1) url substr($0, i + length("https://example.invalid/hook"))
      }
      print
    }
  ' "$template" > "$config"
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
