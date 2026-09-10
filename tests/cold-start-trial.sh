#!/usr/bin/env bash
# Run one onboarding scenario as a genuinely cold agent.
#
# WHY THIS EXISTS
#
# #184's definition of done is that an agent handed only a URL can get from
# nothing to a working call. You cannot test that from inside a session that
# already knows the answers. A subagent spawned in a configured repo inherits
# that session's resolved CLAUDE.md chain and its recalled memories, so it
# "discovers" facts it was handed. Measured on 2026-09-09, four of six such
# agents disclosed prior knowledge of Aurora's endpoints and model catalog.
#
# Both leak sources are PATH-SCOPED:
#   - CLAUDE.md / AGENTS.md resolve upward from the working directory
#   - agent memory is keyed to the working directory
# So running from a fresh directory with neither above it drops both.
#
# WHAT NOT TO DO
#
# Do NOT isolate CLAUDE_CONFIG_DIR and do NOT override HOME to achieve this.
# Credentials live in the OS keychain and $HOME/.claude.json; both tricks fail
# auth with "Not logged in" and tell you nothing about the onboarding flow.
# XDG_CONFIG_HOME is the right lever for keeping harness configs out of the
# real home directory.
#
# CREDENTIALS
#
# Scenarios marked `<!-- requires: key -->` simulate a developer who has already
# completed the human-only steps, so they need a real key on disk. It comes from
# AURORA_TRIAL_KEY and from nowhere else. The harness never searches the
# filesystem for one.
#
# Use a dedicated, revocable key minted for this purpose. Do NOT reuse a key
# from a working installation — a proxy checkout, a harness config, or any
# .env that exists to make something else run. Those are that thing's config,
# not a credential store, and a trial that reaches into them can revoke or
# corrupt real setups and quietly widens what a test can touch.
#
# CAVEAT: the user-level CLAUDE.md still applies, because it lives beside the
# credentials. Verify it carries no facts about the system under test; this
# script warns if it mentions Aurora.
#
# Usage:
#   tests/cold-start-trial.sh <scenario>            # tests/scenarios/<scenario>.md
#   tests/cold-start-trial.sh <scenario> --dry-run  # isolation checks only, no agent
#
# Exit codes:
#   0 = ran (or dry-run passed)
#   1 = bad usage / scenario not found
#   2 = isolation check failed: the run would not have been cold
#   3 = scenario needs a trial key and none was provided
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCENARIO="${1:-}"
DRY_RUN="${2:-}"

if [ -z "$SCENARIO" ]; then
  echo "usage: tests/cold-start-trial.sh <scenario> [--dry-run]" >&2
  echo "available:" >&2
  ls -1 "$REPO_ROOT/tests/scenarios" 2>/dev/null | sed 's/\.md$//; s/^/  /' >&2
  exit 1
fi

PROMPT_FILE="$REPO_ROOT/tests/scenarios/$SCENARIO.md"
[ -f "$PROMPT_FILE" ] || { echo "No such scenario: $PROMPT_FILE" >&2; exit 1; }

# A fresh directory every run. Never reuse one: a second run in the same path
# inherits the first run's memory directory and is no longer cold.
COLD_BASE="${COLD_BASE:-$HOME/development/aurora-cold-trial}"
ROOT="$COLD_BASE/$SCENARIO-$(date -u +%Y%m%dT%H%M%SZ)"

FAIL=0
note_ok()   { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
note_bad()  { printf '  \033[31mLEAK\033[0m  %s\n' "$1"; FAIL=1; }

echo "scenario : $SCENARIO"
echo "root     : $ROOT"
echo
echo "Isolation checks:"

# 1. The run must not sit inside this repo, or it inherits our own CLAUDE.md.
case "$ROOT/" in
  "$REPO_ROOT"/*) note_bad "root is inside the repo under test ($REPO_ROOT)" ;;
  *)              note_ok  "root is outside the repo under test" ;;
esac

# 2. No project instructions anywhere above the working directory.
d="$ROOT"; INHERITED=""
while [ "$d" != "/" ] && [ -n "$d" ]; do
  for f in CLAUDE.md AGENTS.md; do
    [ -f "$d/$f" ] && INHERITED="$INHERITED $d/$f"
  done
  d="$(dirname "$d")"
done
if [ -n "$INHERITED" ]; then
  for f in $INHERITED; do note_bad "would inherit $f"; done
else
  note_ok "no CLAUDE.md or AGENTS.md above the working directory"
fi

# 3. Memory is keyed to the working directory; a fresh path must have none.
MEMDIR="$HOME/.claude/projects/$(printf '%s' "$ROOT" | sed 's|/|-|g')/memory"
if [ -d "$MEMDIR" ]; then
  note_bad "memory directory already exists: $MEMDIR"
else
  note_ok "no memory directory for this path (nothing to recall)"
fi

# 4. The user-level CLAUDE.md survives, because it lives beside the credentials.
USER_MD="$HOME/.claude/CLAUDE.md"
if [ -f "$USER_MD" ]; then
  HITS=$(grep -ci 'aurora\|aur\.lu' "$USER_MD" 2>/dev/null || true)
  if [ "${HITS:-0}" -gt 0 ]; then
    note_bad "$USER_MD mentions Aurora $HITS time(s) and always applies"
  else
    note_ok "user-level CLAUDE.md applies but names nothing under test"
  fi
else
  note_ok "no user-level CLAUDE.md"
fi

echo
if [ "$FAIL" -ne 0 ]; then
  echo "REFUSING: this run would not have been cold. Findings from it would be worthless." >&2
  exit 2
fi

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "dry run: isolation verified, agent not invoked."
  exit 0
fi

# Scenarios that begin after the human-only steps need a real key on disk. It is
# supplied explicitly or the scenario does not run — a premise the harness cannot
# satisfy produces findings about the harness, not about onboarding.
NEEDS_KEY=0
grep -q '<!-- requires: key -->' "$PROMPT_FILE" && NEEDS_KEY=1

if [ "$NEEDS_KEY" -eq 1 ] && [ -z "${AURORA_TRIAL_KEY:-}" ]; then
  cat >&2 <<'MSG'
This scenario starts from "the developer already has a key", so it needs one on disk.

Set AURORA_TRIAL_KEY to a key minted for this trial:

    AURORA_TRIAL_KEY=... tests/cold-start-trial.sh <scenario>

Mint a dedicated, revocable key at https://portal.aur.lu. Do not reuse a key from a
working installation — a proxy checkout or harness config .env exists to make that
thing run, not to serve as a credential store.
MSG
  exit 3
fi

command -v claude >/dev/null 2>&1 || { echo "'claude' not on PATH." >&2; exit 1; }

mkdir -p "$ROOT/work" "$ROOT/home/.config"
cd "$ROOT/work"

if [ "$NEEDS_KEY" -eq 1 ]; then
  # Written the way paste-key.sh leaves it, so the scenario starts from the real
  # post-capture state. Never echoed.
  umask 077
  printf 'AURORA_API_KEY=%s\n' "$AURORA_TRIAL_KEY" > "$ROOT/work/.env"
  chmod 600 "$ROOT/work/.env"
  echo "seeded   : .env at mode 600 from \$AURORA_TRIAL_KEY (value never printed)"
  echo
fi

# HOME stays real (auth). The cwd is what makes this cold. XDG_CONFIG_HOME keeps
# any harness config the agent writes out of the real home directory.
XDG_CONFIG_HOME="$ROOT/home/.config" \
  claude -p "$(cat "$PROMPT_FILE")" --permission-mode bypassPermissions \
  > "$ROOT/result.md" 2>"$ROOT/stderr.log" || echo "(agent exited $?)"

echo "--- result ---"
cat "$ROOT/result.md"
echo
echo "transcript : $ROOT/result.md"
echo "workdir    : $ROOT/work"
