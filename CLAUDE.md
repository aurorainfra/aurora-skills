# Project context for Claude Code

This file exists so Claude Code (or any agent working locally with full repo/org access) can pick up this project without re-deriving decisions already made in chat.

## What this repo is

A public prompt + skills library for Aurora agents. Currently one working artifact: an agent instruction file that sets up Aurora inference infrastructure for a user, plus a deterministic script it delegates to.

Intended eventual home: `aurorainfra` org (not yet moved — see open issues).

## Structure

- `README.md` — human-facing setup: repo structure, auth pattern, how to run scripts/setup.sh
- `prompts/aurora-inference-setup.md` — the agent instruction file (XML-tagged: role, context, objective, options, assumptions, constraints, instructions, success_criteria, formatting)
- `scripts/setup.sh` — deterministic bash script: creates .env from .env.example, verifies AURORA_API_KEY/AURORA_API_ENDPOINT are set, checks .gitignore, makes a live test call. Exit codes 0/1/2/3 are the contract the agent file relies on — do not change exit code meanings without updating the agent file.
- `.env.example` — AURORA_API_KEY, AURORA_API_ENDPOINT (endpoint is still a placeholder — see open issues)
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
