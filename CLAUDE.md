# Project context for Claude Code

This file exists so Claude Code (or any agent working locally with full repo/org access) can pick up this project without re-deriving decisions already made in chat.

## What this repo is

A public prompt + skills library for Aurora agents. Currently one working artifact: an agent instruction file that sets up Aurora inference infrastructure for a user, plus a deterministic script it delegates to.

Home: **`aurorainfra/aurora-skills`** — content and full history were pushed there 2026-08-31.
This personal repo still holds the CLAUDE.md and the issue tracker, so the two have diverged.
Resolving that is issue #4.

## Structure

- `README.md` — human-facing setup: repo structure, auth pattern, how to run scripts/setup.sh
- `prompts/meta/build-agent-setup-suite.md` — the meta-prompt: the instruction file used to generate the harness prompt set. Re-run it when the suite needs regenerating.
- `prompts/harness/{claude-code,opencode,claude-desktop}.md` — one agent instruction file per harness use case
- `prompts/aurora-inference-setup.md` — the general setup agent file (XML-tagged: role, context, objective, options, assumptions, constraints, instructions, success_criteria, formatting)
- `tests/run-fixtures.sh` — fixture suite; green with no key and no network, live checks opt-in behind `AURORA_LIVE=1`
- `scripts/setup.sh` — deterministic bash script, now harness-aware (`setup.sh [api|claude-code|opencode|claude-desktop]`): creates .env from .env.example, verifies credentials, checks .gitignore, makes a live call to `/v1/models`, then checks harness prerequisites. Exit codes 0/1/2/3 keep their original meanings; **4 was added** for "harness prerequisite missing". Do not change 0-3 without updating every file in prompts/.
- `.env.example` — AURORA_API_KEY, AURORA_API_ENDPOINT (endpoint **resolved 2026-08-31**: `https://ai.aur.lu/v1`)
- `skills/` — empty so far, placeholder for future packaged skills

## Design decisions already made (don't relitigate without reason)

- **XML tags, not markdown**, for the agent instruction file — clearer nesting, unambiguous section boundaries.
- **README is source of truth for setup facts** (auth pattern, repo structure). The agent file references README rather than duplicating it, to avoid drift.
- **Agent file is source of truth for behavior** (objective, constraints, what counts as done).
- **Script over prose for anything deterministic.** The agent's job is to run `scripts/setup.sh` and branch on exit code — not to reimplement its steps as individual tool calls. Reserve agent judgment for things that actually need it (payment flow decisions, model selection).
- **Credentials never touch agent context.** AURORA_API_KEY is read from env by the script/code, never echoed, never written into prompt output. Same principle extended to payment: no raw card data ever reaches the agent — payment method entry always happens on a Stripe-hosted Checkout/Customer Portal page, agent only calls Stripe APIs server-side (balance check, coupon apply, session creation) and verifies completion via status, not by reading card data back.
- **OAuth over password-based "login on behalf of user"** was rejected earlier as a pattern anywhere in this project — same reasoning as the credential rule above. If future work touches auth flows beyond the API key, preserve this.
- **Objective order**: payment flow (balance check → coupon → top-up if needed) runs *before* infra setup, not after — don't want inference calls happening before payment is resolved.

## Current objective in prompts/aurora-inference-setup.md

1. Payment flow (balance check, coupon, Stripe-hosted top-up if needed)
2. Run scripts/setup.sh, verify inference is live
3. Return available models to the user

## Open items

See repo Issues — each open item from the working session is filed there so status/discussion lives in one place rather than duplicated here.

## Working style notes

- User (Tim) wants direct, succinct answers, no sycophancy, proactive surfacing of blind spots — carry this into any autonomous work.
- When a design choice has a safety/leakage implication (credentials, payment data, auth), flag it explicitly rather than silently picking an option.

## Verified ground truth (2026-08-31)

Re-verified live, not inherited from chat. The catalog moves — re-check before trusting specifics.

- Prod inference: `https://ai.aur.lu/v1`, OpenAI-compatible only. 4 models live.
- Aurora does **not** serve `/v1/messages` — returns 404. This is why Claude Code needs a proxy
  and OpenCode does not. It is architectural, not a config preference.
- Auth is `Authorization: Bearer` only. `X-Api-Key` 401s in both environments.
- Keys are environment-scoped; a dev key 401s on prod.
- Raw OpenAPI spec at `https://docs.aur.lu/portal-api-spec.json` is plain-fetchable by an agent —
  the one Aurora docs artifact that works without JavaScript.

## Known limitation: Claude Desktop

Claude Desktop exposes **no** model-backend override — no `ANTHROPIC_BASE_URL` equivalent, no
api-key or model field in `claude_desktop_config.json`. Its only extension point is `mcpServers`.
"Run Claude Desktop on Aurora" is therefore not achievable as literally stated. The suite delivers
Aurora-as-an-MCP-tool instead and says so explicitly. **Do not "fix" this by adding a config key —
none exists, and a fake one fails silently.**
