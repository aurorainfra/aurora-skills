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

# Unreachable endpoint must NOT share an exit code with a rejected key. A developer
# whose network is down should not be sent back to the portal to mint a new key.
TMP=$(mktemp -d)
cp -R scripts .env.example .gitignore "$TMP/" 2>/dev/null
printf 'AURORA_API_KEY=not-a-real-key\nAURORA_API_ENDPOINT=https://127.0.0.1:1/v1\n' > "$TMP/.env"
OUT=$( cd "$TMP" && bash scripts/setup.sh api 2>&1 ); RC=$?
[ "$RC" -eq 5 ] && ok "unreachable endpoint exits 5 (not 3)" \
  || bad "unreachable endpoint exited $RC (want 5, and never 3)"
printf '%s' "$OUT" | grep -q 'not an auth failure' \
  && ok "unreachable message says the key was not tested" \
  || bad "unreachable message does not distinguish itself from an auth failure"
printf '%s' "$OUT" | grep -q '000000' \
  && bad "status code was captured twice (the '|| echo 000' regression)" \
  || ok "status captured once; the unreachable branch stays matchable"
rm -rf "$TMP"

# A missing local interpreter must be reported as such, not as an auth or catalog failure.
TMP=$(mktemp -d); BIN="$TMP/bin"; mkdir -p "$BIN"
for b in grep cp mktemp curl head rm cat sed; do
  src=$(command -v "$b" 2>/dev/null) && ln -sf "$src" "$BIN/$b"
done
cp -R scripts .env.example .gitignore "$TMP/" 2>/dev/null
printf 'AURORA_API_KEY=not-a-real-key\nAURORA_API_ENDPOINT=https://127.0.0.1:1/v1\n' > "$TMP/.env"
BASH_ABS=$(command -v bash)
OUT=$( cd "$TMP" && PATH="$BIN" "$BASH_ABS" scripts/setup.sh api 2>&1 ); RC=$?
if [ "$RC" -eq 6 ]; then
  ok "missing python3 exits 6 (not 3)"
  printf '%s' "$OUT" | grep -q 'python3' \
    && ok "missing-prerequisite message names python3" \
    || bad "missing-prerequisite message does not name the tool"
else
  bad "missing python3 exited $RC (want 6, and never 3)"
fi
rm -rf "$TMP"

# The exit-code contract must document every code the script can actually return.
for code in 5 6; do
  grep -qE "^#   $code = " scripts/setup.sh \
    && ok "exit code $code is documented in the contract" \
    || bad "exit code $code is returned but undocumented"
done
# Both harness prompts branch on the contract, so both must carry the new codes.
for f in prompts/harness/opencode.md prompts/harness/claude-code.md; do
  for code in 5 6; do
    grep -qE "^   - $code: " "$f" \
      && ok "$(basename "$f") handles exit $code" \
      || bad "$(basename "$f") does not handle exit $code"
  done
done
# No file may claim X-Api-Key is universally invalid — it is the Portal API's header.
if grep -rn 'X-Api-Key does not work anywhere\|401s in \*\*both\*\* environments\. Never use it' \
     scripts/ prompts/ README.md 2>/dev/null | grep -q .; then
  bad "a file still claims X-Api-Key is universally invalid (it is the Portal API's header)"
else
  ok "X-Api-Key is described per-API, never as universally invalid"
fi

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

# ── 4b. Skill 1 — credential handling ────────────────────────────────────────
sec "4b. Skill 1: account setup + credential safety"

P=prompts/aurora-account-setup.md
[ -f "$P" ] && ok "aurora-account-setup.md exists" || bad "aurora-account-setup.md missing"

MISSING=""
for tag in role context objective constraints instructions success_criteria; do
  grep -q "<$tag>" "$P" 2>/dev/null || MISSING="$MISSING $tag"
done
[ -z "$MISSING" ] && ok "aurora-account-setup.md has all required sections" \
                  || bad "aurora-account-setup.md missing:$MISSING"

# The prompt must warn that `!` does NOT bypass the model.
grep -q 'output is added to the conversation' "$P" 2>/dev/null \
  && ok "warns that Claude Code's \`!\` does not bypass the model" \
  || bad "does not warn about \`!\` — a user may leak a key believing it is a passthrough"

# The prompt must forbid asking for the key in chat.
grep -qi 'never ask for, echo, log, or read the key' "$P" 2>/dev/null \
  && ok "forbids asking for / echoing the key" || bad "does not forbid handling the key"

# paste-key.sh must never print the captured value.
K=scripts/paste-key.sh
[ -f "$K" ] && ok "paste-key.sh exists" || bad "paste-key.sh missing"
if grep -nE '(echo|printf)[^#]*\$AURORA_KEY_INPUT' "$K" 2>/dev/null | grep -qv "printf 'AURORA_API_KEY=%s"; then
  bad "paste-key.sh may print the key value"
else
  ok "paste-key.sh never prints the key value"
fi
grep -q 'read -rs' "$K" 2>/dev/null && ok "paste-key.sh reads input with echo disabled" \
                                   || bad "paste-key.sh does not hide input"
grep -q 'chmod 600' "$K" 2>/dev/null && ok "paste-key.sh chmods .env to 600" \
                                     || bad "paste-key.sh does not restrict .env perms"
grep -q '! -t 0' "$K" 2>/dev/null && ok "paste-key.sh refuses to run without a TTY" \
                                  || bad "paste-key.sh does not require a TTY"

# ── 4c. Bootstrap entry point ────────────────────────────────────────────────
sec "4c. Bootstrap: README is the front door and the one-liner resolves"

RAW=https://raw.githubusercontent.com/aurorainfra/aurora-skills/main
TMPSH=$(mktemp)

grep -q "Read $RAW/README.md" README.md 2>/dev/null \
  && ok "README tells the user how to point an agent at it" \
  || bad "README has no agent entry instruction"

grep -q "$RAW/scripts/paste-key.sh" README.md 2>/dev/null \
  && ok "README carries the bootstrap one-liner" \
  || bad "README missing the bootstrap one-liner"

# The bootstrap line is handed to a HUMAN to paste verbatim, so it must parse in their
# shell — not just in bash. Process substitution is a parse error under sh/dash.
if grep -rn 'bash <(curl' README.md prompts/ 2>/dev/null | grep -qv 'Do not offer\|Why not'; then
  bad "a user-facing command uses process substitution (parse error under sh/dash)"
else
  ok "no user-facing command relies on process substitution"
fi

# Every ```sh block is a block a human may be told to run verbatim: it must parse
# under POSIX sh. Blocks that legitimately need bash are tagged ```bash instead.
SH_BAD=0; SH_N=0
while IFS= read -r blk; do
  SH_N=$((SH_N+1))
  printf '%s' "$blk" | python3 -m base64 -d > "$TMPSH" 2>/dev/null || continue
  sh -n "$TMPSH" 2>/dev/null || { SH_BAD=$((SH_BAD+1)); }
done < <(python3 - <<'PYX'
import re, base64
src = open('README.md').read()
for m in re.finditer(r'```sh\n(.*?)```', src, re.S):
    print(base64.b64encode(m.group(1).encode()).decode())
PYX
)
if [ "$SH_N" -eq 0 ]; then
  bad "no \`\`\`sh blocks found in README (user-facing commands must be tagged sh)"
elif [ "$SH_BAD" -eq 0 ]; then
  ok "all $SH_N user-facing \`\`\`sh block(s) parse under POSIX sh"
else
  bad "$SH_BAD of $SH_N user-facing \`\`\`sh block(s) fail to parse under POSIX sh"
fi

# Host prerequisites must be stated before the first command that needs one.
grep -q 'python3' README.md 2>/dev/null \
  && ok "README states the python3 prerequisite" \
  || bad "README never mentions python3, which setup.sh requires"

# The no-browser case is the normal shape of agent-on-server, human-on-laptop.
grep -qi 'no browser' README.md 2>/dev/null \
  && ok "README handles the no-browser machine" \
  || bad "README assumes a browser exists on the configured machine"

# curl|bash would break the hidden read — it must not be recommended anywhere.
if grep -rnE 'curl[^|]*\|[[:space:]]*(sudo[[:space:]]+)?bash' README.md prompts/ 2>/dev/null | grep -qv 'Do not offer\|Why not'; then
  bad "a 'curl | bash' form is recommended somewhere (breaks interactive read)"
else
  ok "no 'curl | bash' recommended (would break the hidden read)"
fi

grep -q 'aurora-account-setup.md' README.md 2>/dev/null \
  && ok "README links the interactive setup skill" || bad "README does not link Skill 1"
for h in claude-code opencode; do
  grep -q "prompts/harness/$h.md" README.md 2>/dev/null \
    && ok "README links harness prompt: $h" || bad "README missing harness link: $h"
done
grep -qi 'output is added to the conversation' README.md 2>/dev/null \
  && ok "README warns that \`!\` does not bypass the model" \
  || bad "README omits the \`!\` warning"

# ── 4d. Prompt files must survive the rendered-page path ─────────────────────
sec "4d. XML structure: raw-fetch guidance present"

for f in prompts/aurora-account-setup.md prompts/aurora-inference-setup.md \
         prompts/harness/claude-code.md prompts/harness/opencode.md \
         prompts/meta/build-agent-setup-suite.md; do
  head -1 "$f" 2>/dev/null | grep -q 'read the raw file' \
    && ok "$(basename "$f"): carries raw-fetch header" \
    || bad "$(basename "$f"): missing raw-fetch header (rendered page strips its XML tags)"
done

grep -q 'not the rendered GitHub pages' README.md 2>/dev/null \
  && ok "README requires raw URLs for prompt files" \
  || bad "README does not warn that rendered pages strip XML tags"

# ── 4e. Cold-start trial harness ─────────────────────────────────────────────
sec "4e. Cold-start harness: a trial that is not actually cold is worthless"

if bash -n tests/cold-start-trial.sh 2>/dev/null; then
  ok "cold-start-trial.sh parses"
else
  bad "cold-start-trial.sh syntax error"
fi

for sc in tests/scenarios/*.md; do
  n=$(basename "$sc" .md)
  if [ "$n" = "S4-rendered-github" ]; then
    grep -q 'github.com/aurorainfra/aurora-skills/blob/main/README.md' "$sc" \
      && ok "scenario $n starts from the rendered entry point" \
      || bad "scenario $n does not start from the rendered README page"
  else
    grep -q 'raw.githubusercontent.com/aurorainfra/aurora-skills/main/README.md' "$sc" \
      && ok "scenario $n starts from the pasteable entry point" \
      || bad "scenario $n does not start from the README paste line"
  fi
  grep -q 'nothing known in advance' "$sc" \
    && ok "scenario $n asks the agent to disclose prior knowledge" \
    || bad "scenario $n does not ask for a prior-knowledge disclosure"
done

# The harness must refuse to run anywhere its findings would be contaminated.
set +e
OUT=$( COLD_BASE="$PWD/tests" bash tests/cold-start-trial.sh \
         "$(basename "$(ls -1 tests/scenarios/*.md | head -1)" .md)" --dry-run 2>&1 ); RC=$?
set -e
[ "$RC" -eq 2 ] && ok "refuses a root inside the repo under test (exit 2)" \
  || bad "accepted a root inside the repo under test (exit $RC, want 2)"
printf '%s' "$OUT" | grep -q 'would inherit' \
  && ok "names the CLAUDE.md it would have inherited" \
  || bad "refusal does not name the inherited instructions"

# ... and must pass on a root with nothing above it.
CLEANBASE=$(mktemp -d)
set +e
OUT=$( COLD_BASE="$CLEANBASE" bash tests/cold-start-trial.sh \
         "$(basename "$(ls -1 tests/scenarios/*.md | head -1)" .md)" --dry-run 2>&1 ); RC=$?
set -e
[ "$RC" -eq 0 ] && ok "accepts a root with no instructions above it" \
  || bad "rejected a clean root (exit $RC, want 0)"
rm -rf "$CLEANBASE"

# A scenario that starts from "the developer already has a key" must declare it, or
# the harness silently runs it against an empty directory and the premise is a lie.
for sc in tests/scenarios/*.md; do
  n=$(basename "$sc" .md)
  if grep -qi 'already have a key\|already have an Aurora API key\|a key in `.env`' "$sc"; then
    grep -q '<!-- requires: key -->' "$sc" \
      && ok "scenario $n declares its key requirement" \
      || bad "scenario $n assumes a key on disk but does not declare 'requires: key'"
  fi
done

# ... and must refuse rather than run that scenario without one.
KEYSC=$(grep -l '<!-- requires: key -->' tests/scenarios/*.md 2>/dev/null | head -1)
if [ -n "$KEYSC" ]; then
  set +e
  ( unset AURORA_API_KEY; COLD_BASE="$(mktemp -d)" \
      bash tests/cold-start-trial.sh "$(basename "$KEYSC" .md)" >/dev/null 2>&1 ); RC=$?
  set -e
  [ "$RC" -eq 3 ] && ok "refuses a key-requiring scenario when no trial key is set (exit 3)" \
    || bad "ran a key-requiring scenario with no trial key (exit $RC, want 3)"
else
  bad "no scenario declares 'requires: key' — S2/S3/S6 depend on a pre-existing key"
fi

# The trial key is supplied explicitly, never discovered. Reaching into a working
# installation's .env (a proxy checkout, a harness config) to find one treats that
# install's config as a credential store and lets a test revoke or corrupt real setups.
if grep -nE 'aurora-litellm|find[^|]*\.env|source[[:space:]]+[^|]*\.env|^[[:space:]]*\.[[:space:]]+[^|]*\.env' \
     tests/cold-start-trial.sh >/dev/null 2>&1; then
  bad "harness discovers credentials on the filesystem instead of taking them explicitly"
else
  ok "trial key comes only from \$AURORA_API_KEY, never discovered on disk"
fi

# The seeded key must never reach stdout. An escaped \$AURORA_API_KEY prints the
# variable's NAME and is fine; an unescaped expansion not redirected to a file is not.
LEAKY=$(grep -nE '(echo|printf)' tests/cold-start-trial.sh \
        | grep -F '$AURORA_API_KEY' \
        | grep -v '\\$AURORA_API_KEY' \
        | grep -v '>' || true)
if [ -n "$LEAKY" ]; then
  bad "harness may print the trial key: $LEAKY"
else
  ok "harness never expands the trial key into output"
fi
# Reading the seeded file back would put the secret in the harness's own output.
# (An escaped \$AURORA_API_KEY prints only the variable name and is covered by the
# expansion check above, so it is deliberately not matched here.)
grep -qE '(cat|less|head|tail)[[:space:]]+[^|]*\.env' tests/cold-start-trial.sh \
  && bad "harness reads back the seeded .env" \
  || ok "harness never reads back the seeded .env"

# Regression guard: overriding HOME or CLAUDE_CONFIG_DIR fails auth ("Not logged
# in") because credentials live in the OS keychain and $HOME/.claude.json. Both
# were tried on 2026-09-09 and both broke the run without improving isolation.
if grep -qE '^[[:space:]]*(HOME=|CLAUDE_CONFIG_DIR=)[^ ]*[[:space:]]+claude' tests/cold-start-trial.sh; then
  bad "harness overrides HOME/CLAUDE_CONFIG_DIR for the agent (breaks auth)"
else
  ok "harness leaves HOME and CLAUDE_CONFIG_DIR alone (cwd is what makes it cold)"
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
