#!/usr/bin/env bash
# Capture an Aurora API key WITHOUT it ever entering an agent's context.
#
#   RUN THIS YOURSELF, IN YOUR OWN TERMINAL.
#
# Do not run it through an agent, and do not run it with Claude Code's `!` prefix:
# `!` executes in the session and its OUTPUT IS ADDED TO THE CONVERSATION, so anything
# printed becomes model-visible. This script never prints the key, but the input prompt
# needs a real TTY, which only your own terminal reliably provides.
#
# Exit codes:
#   0 = key stored (and verified, unless --no-verify)
#   2 = no key entered
#   3 = key stored but live verification failed
set -euo pipefail

ENV_FILE=".env"
VERIFY=1
while [ $# -gt 0 ]; do
  case "$1" in
    --env-file) ENV_FILE="$2"; shift 2 ;;
    --no-verify) VERIFY=0; shift ;;
    *) echo "usage: $0 [--env-file PATH] [--no-verify]"; exit 1 ;;
  esac
done

if [ ! -t 0 ]; then
  echo "ERROR: no TTY. Run this directly in your own terminal, not through an agent." >&2
  exit 1
fi

umask 077

printf 'Paste your Aurora API key (input is hidden), then press Enter: '
read -rs AURORA_KEY_INPUT
printf '\n'

if [ -z "${AURORA_KEY_INPUT:-}" ]; then
  echo "No key entered. Nothing written."
  exit 2
fi

# Shape check only — never echo the value.
case "$AURORA_KEY_INPUT" in
  atp_*) ;;
  *) echo "Note: key does not start with 'atp_'. Storing it anyway." ;;
esac

ENDPOINT_DEFAULT="https://ai.aur.lu/v1"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
[ -f "$ENV_FILE" ] && grep -v -E '^AURORA_API_KEY=' "$ENV_FILE" > "$TMP" || true
printf 'AURORA_API_KEY=%s\n' "$AURORA_KEY_INPUT" >> "$TMP"
grep -qE '^AURORA_API_ENDPOINT=' "$TMP" 2>/dev/null || printf 'AURORA_API_ENDPOINT=%s\n' "$ENDPOINT_DEFAULT" >> "$TMP"
mv "$TMP" "$ENV_FILE"
chmod 600 "$ENV_FILE"
trap - EXIT

echo "Stored AURORA_API_KEY in $ENV_FILE (mode 600). The key was never displayed."

if [ "$VERIFY" -eq 1 ]; then
  ENDPOINT=$(grep -E '^AURORA_API_ENDPOINT=' "$ENV_FILE" | cut -d= -f2-)
  CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $AURORA_KEY_INPUT" "${ENDPOINT%/}/models" || echo 000)
  unset AURORA_KEY_INPUT
  if [ "$CODE" = "200" ]; then
    echo "Verified: $ENDPOINT responded 200. You can tell the agent the key is set."
  else
    echo "Stored, but verification failed (HTTP $CODE)."
    echo "  401 = wrong environment (keys are env-scoped: prod key != dev key)."
    exit 3
  fi
fi
unset AURORA_KEY_INPUT
