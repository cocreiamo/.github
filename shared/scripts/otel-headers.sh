#!/usr/bin/env bash
# Prints the Cloudflare Access service-token headers for otel.cocreiamo.com as JSON (Claude Code otelHeadersHelper).
# The values come from Secret Manager at run time, never from git. Without access (no gcloud login, CI) it prints {}:
# the telemetry is then refused at the edge and Claude Code carries on.
set -uo pipefail
account="${CLOUDSDK_CORE_ACCOUNT:-francesco.bilotta@cocreiamo.com}"
project="${OTEL_SECRETS_PROJECT:-gen-lang-client-0890849161}"
get() { gcloud --account="$account" secrets versions access latest --secret="$1" --project="$project" 2>/dev/null; }
# shellcheck disable=SC2015
id="$(get otel-access-client-id)" && secret="$(get otel-access-client-secret)" || { echo '{}'; exit 0; }
[ -n "$id" ] && [ -n "$secret" ] || { echo '{}'; exit 0; }
ACCESS_ID="$id" ACCESS_SECRET="$secret" python3 -I -c 'import json, os; print(json.dumps({"CF-Access-Client-Id": os.environ["ACCESS_ID"], "CF-Access-Client-Secret": os.environ["ACCESS_SECRET"]}))'
