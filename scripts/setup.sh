#!/usr/bin/env bash
# Deterministic setup + verification for Aurora inference auth.
# Exit codes:
#   0 = success, key verified live
#   1 = missing .env.example, cannot proceed
#   2 = user input needed (.env just created, or key still placeholder)
#   3 = endpoint reachable but auth/response failed
set -euo pipefail

ENV_FILE=".env"
ENV_EXAMPLE=".env.example"

if [ ! -f "$ENV_FILE" ]; then
  if [ -f "$ENV_EXAMPLE" ]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    echo "Created $ENV_FILE from $ENV_EXAMPLE. Set AURORA_API_KEY and AURORA_API_ENDPOINT, then re-run."
    exit 2
  else
    echo "No $ENV_EXAMPLE found. Cannot proceed."
    exit 1
  fi
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [ -z "${AURORA_API_KEY:-}" ] || [ "$AURORA_API_KEY" = "your_key_here" ]; then
  echo "AURORA_API_KEY is not set in $ENV_FILE. Edit it and re-run."
  exit 2
fi

if [ -z "${AURORA_API_ENDPOINT:-}" ] || [ "$AURORA_API_ENDPOINT" = "your_endpoint_here" ]; then
  echo "AURORA_API_ENDPOINT is not set in $ENV_FILE. Edit it and re-run."
  exit 2
fi

if [ -f ".gitignore" ] && grep -qE '^\.env$|^\.env\*' .gitignore; then
  echo "OK: .env is gitignored."
else
  echo "WARNING: .env does not appear to be gitignored. Add it before committing anything."
fi

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $AURORA_API_KEY" \
  "$AURORA_API_ENDPOINT")

if [[ "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]]; then
  echo "SUCCESS: endpoint responded with $HTTP_STATUS. Key is valid."
  exit 0
else
  echo "FAILURE: endpoint responded with $HTTP_STATUS. Check your key and endpoint."
  exit 3
fi
