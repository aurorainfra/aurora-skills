#!/usr/bin/env bash
# Deterministic setup + verification for Aurora inference.
#
# Usage: scripts/setup.sh [harness]
#   harness: api (default) | claude-code | opencode
#
# Exit codes (CONTRACT — prompts/ branch on these; do not redefine 0-3):
#   0 = success, credentials verified live against Aurora
#   1 = cannot proceed (missing .env.example, unknown harness)
#   2 = user input needed (.env just created, or values still placeholders)
#   3 = endpoint reachable but auth/response failed
#   4 = harness prerequisite missing (harness CLI or config path absent)
set -euo pipefail

HARNESS="${1:-api}"
ENV_FILE=".env"
ENV_EXAMPLE=".env.example"

case "$HARNESS" in
  api|claude-code|opencode) ;;
  *) echo "Unknown harness: $HARNESS (expected: api|claude-code|opencode)"; exit 1 ;;
esac

# ── 1. Credentials ────────────────────────────────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
  if [ -f "$ENV_EXAMPLE" ]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    echo "Created $ENV_FILE from $ENV_EXAMPLE. Set AURORA_API_KEY, then re-run."
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

: "${AURORA_API_ENDPOINT:=https://ai.aur.lu/v1}"

if [ -z "${AURORA_API_KEY:-}" ] || [ "$AURORA_API_KEY" = "your_key_here" ]; then
  echo "AURORA_API_KEY is not set in $ENV_FILE."
  echo "Generate one at https://portal.aur.lu (prod) or https://dashboard.dev.aur.lu (dev), then re-run."
  exit 2
fi

if [ -z "${AURORA_API_ENDPOINT:-}" ] || [ "$AURORA_API_ENDPOINT" = "your_endpoint_here" ]; then
  echo "AURORA_API_ENDPOINT is not set in $ENV_FILE. Use https://ai.aur.lu/v1 for prod."
  exit 2
fi

if [ -f ".gitignore" ] && grep -qE '^\.env$|^\.env\*' .gitignore; then
  echo "OK: .env is gitignored."
else
  echo "WARNING: .env does not appear to be gitignored. Add it before committing anything."
fi

# ── 2. Live credential check ──────────────────────────────────────────────────
# Aurora is OpenAI-compatible: the catalog lives at <base>/models.
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

HTTP_STATUS=$(curl -sS -o "$BODY_FILE" -w "%{http_code}" \
  -H "Authorization: Bearer $AURORA_API_KEY" \
  "${AURORA_API_ENDPOINT%/}/models" || echo "000")

if ! [[ "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]]; then
  echo "FAILURE: ${AURORA_API_ENDPOINT%/}/models responded $HTTP_STATUS."
  case "$HTTP_STATUS" in
    401) echo "  401 = key rejected. Keys are environment-scoped: a dev key will not work on prod." ;;
    404) echo "  404 = wrong base path. Expected a base ending in /v1." ;;
    000) echo "  000 = could not connect. Check the hostname and your network." ;;
  esac
  echo "  Note: Aurora authenticates with 'Authorization: Bearer'. X-Api-Key does not work anywhere."
  exit 3
fi

# Read the catalog dynamically — it has changed twice; never hardcode ids.
MODELS=$(python3 -c "
import json,sys
try:
    d=json.load(open('$BODY_FILE'))
    ids=[m.get('id') for m in d.get('data',[]) if m.get('id')]
    print('\n'.join(ids))
except Exception:
    pass
" 2>/dev/null || true)

if [ -z "$MODELS" ]; then
  echo "FAILURE: $HTTP_STATUS but no models parsed from the catalog."
  exit 3
fi

MODEL_COUNT=$(printf '%s\n' "$MODELS" | grep -c . || true)
FIRST_MODEL=$(printf '%s\n' "$MODELS" | head -1)
echo "SUCCESS: key verified. $MODEL_COUNT model(s) available:"
printf '  - %s\n' $MODELS

# ── 3. Harness prerequisites ──────────────────────────────────────────────────
case "$HARNESS" in
  api)
    ;;
  opencode)
    if ! command -v opencode >/dev/null 2>&1; then
      echo "Harness prerequisite missing: 'opencode' not on PATH."
      exit 4
    fi
    echo "OK: opencode found. Register the Aurora provider with baseURL ${AURORA_API_ENDPOINT%/}"
    echo "    and default model '$FIRST_MODEL' (read live, do not hardcode)."
    ;;
  claude-code)
    if ! command -v claude >/dev/null 2>&1; then
      echo "Harness prerequisite missing: 'claude' not on PATH."
      exit 4
    fi
    # Aurora does not serve the Anthropic Messages API. Prove it rather than assert it.
    MSG_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" -X POST \
      -H "Authorization: Bearer $AURORA_API_KEY" -H "Content-Type: application/json" \
      -d '{"model":"'"$FIRST_MODEL"'","max_tokens":16,"messages":[{"role":"user","content":"ping"}]}' \
      "${AURORA_API_ENDPOINT%/}/messages" || echo "000")
    echo "OK: claude found. Aurora /v1/messages returned $MSG_STATUS (non-2xx expected)."
    echo "    Claude Code speaks ONLY /v1/messages, so a translating proxy is required."
    echo "    See prompts/harness/claude-code.md."
    ;;
esac

exit 0
