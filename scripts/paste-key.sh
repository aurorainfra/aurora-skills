#!/usr/bin/env bash
# Aurora credential bootstrap — capture an API key WITHOUT it reaching an agent.
#
#   RUN THIS YOURSELF, IN YOUR OWN TERMINAL:
#
#     bash <(curl -fsSL https://raw.githubusercontent.com/aurorainfra/aurora-skills/main/scripts/paste-key.sh)
#
# Self-contained: needs only bash + curl. No clone required.
#
# Why not `curl ... | bash`? Piping makes stdin the SCRIPT, so the hidden read would
# consume script text instead of your keystrokes. Process substitution `<(...)` keeps
# stdin attached to your terminal. This script refuses to run without a TTY rather than
# fail quietly.
#
# Why not Claude Code's `!` prefix? `!` runs in the session and its OUTPUT IS ADDED TO
# THE CONVERSATION. It feeds the model rather than bypassing it.
#
# Exit codes:
#   0 = key stored and verified
#   1 = no TTY, or bad usage
#   2 = no key entered
#   3 = stored, but live verification failed
set -euo pipefail

ENV_FILE=".env"
ENDPOINT="https://ai.aur.lu/v1"
while [ $# -gt 0 ]; do
  case "$1" in
    --env-file) ENV_FILE="$2"; shift 2 ;;
    --dev)      ENDPOINT="https://inference.dev.aur.lu/v1"; shift ;;
    --endpoint) ENDPOINT="$2"; shift 2 ;;
    -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "usage: $0 [--env-file PATH] [--dev | --endpoint URL]" >&2; exit 1 ;;
  esac
done

if [ ! -t 0 ]; then
  cat >&2 <<'MSG'
ERROR: no TTY.

This script must run in YOUR OWN terminal so your keystrokes stay off the agent's
transcript. Do not run it through an agent, and do not pipe it into bash.

  bash <(curl -fsSL https://raw.githubusercontent.com/aurorainfra/aurora-skills/main/scripts/paste-key.sh)
MSG
  exit 1
fi

command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found." >&2; exit 1; }
umask 077

echo "Aurora credential setup"
echo "  endpoint: $ENDPOINT"
echo "  writing:  $ENV_FILE"
echo
echo "Create a key at https://portal.aur.lu (prod) or https://dashboard.dev.aur.lu (dev)."
echo "Keys are environment-scoped: a dev key will NOT work against prod."
echo
printf 'Paste your Aurora API key (input is hidden), then press Enter: '
read -rs AURORA_KEY_INPUT
printf '\n'

[ -n "${AURORA_KEY_INPUT:-}" ] || { echo "No key entered. Nothing written."; exit 2; }
case "$AURORA_KEY_INPUT" in
  atp_*) ;;
  *) echo "Note: key does not begin with 'atp_'. Storing it anyway." ;;
esac

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
[ -f "$ENV_FILE" ] && grep -vE '^(AURORA_API_KEY|AURORA_API_ENDPOINT)=' "$ENV_FILE" > "$TMP" || true
printf 'AURORA_API_KEY=%s\n'      "$AURORA_KEY_INPUT" >> "$TMP"
printf 'AURORA_API_ENDPOINT=%s\n' "$ENDPOINT"         >> "$TMP"
mv "$TMP" "$ENV_FILE"; chmod 600 "$ENV_FILE"; trap - EXIT

echo "Stored in $ENV_FILE (mode 600). The key was never displayed."

# Make sure .env can't be committed from this directory.
if [ -d .git ] && ! grep -qE '^\.env$' .gitignore 2>/dev/null; then
  printf '\n.env\n' >> .gitignore
  echo "Added .env to .gitignore (this is a git repo)."
fi

echo
echo "Verifying..."
BODY="$(mktemp)"; trap 'rm -f "$BODY"' EXIT
CODE=$(curl -sS -o "$BODY" -w "%{http_code}" \
  -H "Authorization: Bearer $AURORA_KEY_INPUT" "${ENDPOINT%/}/models" || echo 000)
unset AURORA_KEY_INPUT

if [ "$CODE" = "200" ]; then
  echo "SUCCESS — $ENDPOINT responded 200. Models available to you:"
  python3 -c "
import json,sys
try:
    for m in json.load(open('$BODY')).get('data',[]): print('  -', m.get('id'))
except Exception: print('  (catalog parsed empty)')
" 2>/dev/null || echo "  (install python3 to list models)"
  echo
  echo "Done. Tell your agent: \"the key is set and verified\"."
  exit 0
else
  echo "Stored, but verification FAILED (HTTP $CODE)."
  case "$CODE" in
    401) echo "  401 = key rejected. Most likely the wrong environment (prod key vs dev key)." ;;
    000) echo "  000 = could not connect. Check your network." ;;
  esac
  echo "  Tell your agent: \"verification failed with HTTP $CODE\"."
  exit 3
fi
