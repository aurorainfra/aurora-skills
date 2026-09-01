#!/usr/bin/env bash
# Fixture suite for the Aurora agent-setup prompts.
#
# Static checks run with NO network and NO credentials — that is the point.
# Live checks are opt-in: AURORA_LIVE=1 and a real AURORA_API_KEY in the environment.
#
# Usage: tests/run-fixtures.sh
set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0; FAIL=0; SKIP=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33mSKIP\033[0m  %s\n' "$1"; SKIP=$((SKIP+1)); }
sec()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

# Consume PASS::/FAIL:: lines emitted by the python fixture checks.
consume() { while IFS= read -r line; do
  case "$line" in
    PASS::*) ok "${line#PASS::}" ;;
    FAIL::*) bad "${line#FAIL::}" ;;
    *) [ -n "$line" ] && printf '        %s\n' "$line" ;;
  esac
done; }

F=tests/fixtures

# ── 0. Repo hygiene ───────────────────────────────────────────────────────────
sec "0. Repo hygiene (no credentials may exist in this repo)"

# Looks for a real Aurora token (atp_ + >=16 chars). Must find none.
if git grep -nIE 'atp_[A-Za-z0-9_-]{16,}' -- . >/dev/null 2>&1; then
  bad "key-shaped string (atp_...) found in tracked files"
  git grep -nIE 'atp_[A-Za-z0-9_-]{16,}' -- . | head -5
else
  ok "no key-shaped strings in tracked files"
fi

if grep -qE '^\.env$|^\.env\*' .gitignore 2>/dev/null; then
  ok ".env is gitignored"
else
  bad ".env is not gitignored"
fi

if git ls-files --error-unmatch .env >/dev/null 2>&1; then
  bad ".env is tracked by git"
else
  ok ".env is not tracked"
fi

# ── 1. Script contract ────────────────────────────────────────────────────────
sec "1. setup.sh exit-code contract"

if bash -n scripts/setup.sh 2>/dev/null; then ok "setup.sh parses"; else bad "setup.sh syntax error"; fi

OUT=$(bash scripts/setup.sh not-a-harness 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok "unknown harness exits 1" || bad "unknown harness exited $RC (want 1)"

for h in api claude-code opencode; do
  grep -q -- "$h" scripts/setup.sh && ok "harness '$h' handled" || bad "harness '$h' missing"
done

# .env absent -> exit 2 (run in a throwaway copy so we never touch a real .env)
TMP=$(mktemp -d)
cp -R scripts .env.example .gitignore "$TMP/" 2>/dev/null
OUT=$( cd "$TMP" && bash scripts/setup.sh api 2>&1 ); RC=$?
[ "$RC" -eq 2 ] && ok "missing .env exits 2 (user input needed)" || bad "missing .env exited $RC (want 2)"
# second run: .env now exists but holds placeholders -> still 2
OUT=$( cd "$TMP" && bash scripts/setup.sh api 2>&1 ); RC=$?
[ "$RC" -eq 2 ] && ok "placeholder key exits 2" || bad "placeholder key exited $RC (want 2)"
rm -rf "$TMP"

# ── 2. Use case 1 — Claude Code (proxy is mandatory) ──────────────────────────
sec "2. Use case 1: Claude Code -> Aurora (via translating proxy)"

C=$F/litellm-config.yaml
for k in use_chat_completions_url_for_anthropic_messages merge_reasoning_content_in_choices additional_drop_params drop_params; do
  grep -q "$k" "$C" && ok "load-bearing setting present: $k" || bad "missing load-bearing setting: $k"
done
grep -qE 'api_base:\s*https://(ai\.aur\.lu|inference\.dev\.aur\.lu)/v1' "$C" \
  && ok "api_base points at a known Aurora endpoint" || bad "api_base is not a known Aurora endpoint"
grep -qE 'api_key:\s*os\.environ/' "$C" \
  && ok "api_key is an env reference, not a literal" || bad "api_key is not an env reference"
grep -q 'stop_sequences' "$C" \
  && ok "stop_sequences dropped (Aurora validates strictly)" || bad "stop_sequences not dropped"

# The prompt must not claim ANTHROPIC_BASE_URL can point straight at Aurora.
if grep -qiE 'ANTHROPIC_BASE_URL.{0,40}(ai\.aur\.lu|directly at Aurora)' prompts/harness/claude-code.md \
   && ! grep -qi 'does not work' prompts/harness/claude-code.md; then
  bad "claude-code.md implies ANTHROPIC_BASE_URL can point at Aurora directly"
else
  ok "claude-code.md states the proxy is mandatory"
fi

# ── 3. Use case 2 — OpenCode (direct, no proxy) ───────────────────────────────
sec "3. Use case 2: OpenCode -> Aurora (direct)"

O=$F/opencode.json
python3 -c "import json,sys; json.load(open('$O'))" 2>/dev/null \
  && ok "opencode.json parses" || bad "opencode.json does not parse"
PYOUT=$(mktemp)
python3 - "$O" > "$PYOUT" <<'PY'
import json,sys,re
d=json.load(open(sys.argv[1])); p=d.get("provider",{}).get("aurora",{})
o=p.get("options",{})
checks=[
 ("baseURL is an Aurora /v1 endpoint", bool(re.match(r'https://(ai\.aur\.lu|inference\.dev\.aur\.lu)/v1$', o.get("baseURL","")))),
 ("apiKey is env interpolation, not a literal", o.get("apiKey","").startswith("{env:")),
 ("uses the openai-compatible sdk", p.get("npm")=="@ai-sdk/openai-compatible"),
 ("declares at least one model", len(p.get("models",{}))>0),
 ("no proxy/localhost in config", "127.0.0.1" not in json.dumps(d) and "localhost" not in json.dumps(d)),
]
for name,cond in checks: print(("PASS::" if cond else "FAIL::")+name)
PY
consume < "$PYOUT"; rm -f "$PYOUT"

# ── 4. Prompt-set consistency ────────────────────────────────────────────────
sec "4. Prompt-set structural consistency"

for p in prompts/harness/claude-code.md prompts/harness/opencode.md; do
  MISSING=""
  for tag in role context objective constraints instructions success_criteria; do
    grep -q "<$tag>" "$p" || MISSING="$MISSING $tag"
  done
  [ -z "$MISSING" ] && ok "$(basename "$p") has all required sections" \
                    || bad "$(basename "$p") missing:$MISSING"
done

# Claude Desktop was dropped deliberately (no model-backend override exists).
# Fail if it reappears, so nobody re-adds it with an invented config key.
if [ -e prompts/harness/claude-desktop.md ] || [ -e tests/fixtures/claude_desktop_config.json ]; then
  bad "Claude Desktop artifacts are back — it was dropped on purpose; see CLAUDE.md"
else
  ok "Claude Desktop stays dropped (no invented backend config)"
fi

# ── 5. Live checks (opt-in) ──────────────────────────────────────────────────
sec "5. Live checks against Aurora (opt-in)"

if [ "${AURORA_LIVE:-0}" != "1" ]; then
  skip "live catalog check (set AURORA_LIVE=1 with a real AURORA_API_KEY to run)"
  skip "live /v1/messages negative check"
elif [ -z "${AURORA_API_KEY:-}" ]; then
  skip "AURORA_LIVE=1 but AURORA_API_KEY is unset"
  skip "live /v1/messages negative check"
else
  BASE="${AURORA_API_ENDPOINT:-https://ai.aur.lu/v1}"
  B=$(mktemp)
  S1=$(curl -sS -o "$B" -w "%{http_code}" -H "Authorization: Bearer $AURORA_API_KEY" "${BASE%/}/models" || echo 000)
  if [ "$S1" = "200" ]; then
    N=$(python3 -c "import json;print(len(json.load(open('$B')).get('data',[])))" 2>/dev/null || echo 0)
    [ "$N" -gt 0 ] && ok "live catalog: $N model(s) returned" || bad "live catalog: 200 but empty"
  else
    bad "live catalog: HTTP $S1"
  fi
  rm -f "$B"
  # Aurora must NOT serve the Anthropic Messages API — this is why the proxy exists.
  S2=$(curl -sS -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $AURORA_API_KEY" \
       -H "Content-Type: application/json" -d '{"model":"x","max_tokens":8,"messages":[]}' \
       "${BASE%/}/messages" || echo 000)
  [ "$S2" != "200" ] && ok "/v1/messages returns $S2 (proxy justified)" \
                     || bad "/v1/messages returned 200 — Aurora may now be Anthropic-compatible; revisit claude-code.md"
fi

printf '\n\033[1mResults:\033[0m %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
