# aurora-skills

Prompt and skills library for Aurora agents.

## Structure

- `prompts/meta/` — prompts that generate other prompts. `build-agent-setup-suite.md` is the
  instruction file used to produce everything in `prompts/harness/`.
- `prompts/harness/` — one agent instruction file per harness use case.
- `prompts/aurora-inference-setup.md` — the general setup agent file (payment + credentials).
- `scripts/` — deterministic setup/verification, meant to be run rather than reimplemented.
- `tests/` — fixture suite. Runs green with no key and no network.
- `skills/` — packaged skills (placeholder).

## Endpoints

Verified live 2026-08-31.

| | Value |
|---|---|
| Prod inference base | `https://ai.aur.lu/v1` |
| Dev inference base | `https://inference.dev.aur.lu/v1` |
| Portal API base | `https://api-portal.aur.lu/api` |
| Raw OpenAPI spec | `https://docs.aur.lu/portal-api-spec.json` (plain-fetchable, no JS, no auth) |

Aurora is **OpenAI-compatible only**: `/v1/models`, `/v1/chat/completions`, `/v1/completions`.
It does **not** serve `/v1/messages` (Anthropic Messages API) — that returns 404.

## Auth

One token, but **the two APIs require opposite headers**. Verified live 2026-08-31.

| API | Header that works | Header that 401s |
|---|---|---|
| Inference (`ai.aur.lu`) | `Authorization: Bearer` | `X-Api-Key` |
| Portal (`api-portal.aur.lu`) | `X-Api-Key` | `Authorization: Bearer` |

```
# inference
Authorization: Bearer $AURORA_API_KEY
# portal
X-Api-Key: $AURORA_API_KEY
```

This is the single easiest way to get a spurious 401. The Portal OpenAPI spec declares
`X-Api-Key` as its only scheme, which is correct **for the Portal API** — it is not correct for
inference.
- Keys are **environment-scoped** — a dev key will not authenticate against prod.
- Key generation is a human action: prod at `portal.aur.lu`, dev at `dashboard.dev.aur.lu`.

## Setup

```bash
scripts/setup.sh [api|claude-code|opencode|claude-desktop]
```

Exit codes are a contract that the prompt files branch on:

| Code | Meaning |
|---|---|
| 0 | Success — credentials verified live against Aurora |
| 1 | Cannot proceed (missing `.env.example`, unknown harness) |
| 2 | User input needed (`.env` created, or values still placeholders) |
| 3 | Endpoint reachable but auth/response failed |
| 4 | Harness prerequisite missing (CLI not on PATH, or config absent) |

Agents consuming these prompts should run the script and branch on the exit code rather than
reimplementing its steps.

## Harness use cases

Claude Desktop is deliberately **not** supported: it exposes no model-backend override, so it
cannot be pointed at Aurora. See the "Known limitation" note in `CLAUDE.md`.

| Use case | Path to Aurora | Prompt |
|---|---|---|
| **Claude Code** | Requires a translating proxy — Claude Code speaks only the Anthropic Messages API | `prompts/harness/claude-code.md` |
| **OpenCode** | Direct. OpenCode speaks OpenAI-compatible natively | `prompts/harness/opencode.md` |

## Tests

```bash
tests/run-fixtures.sh                                    # static only, no key needed
AURORA_LIVE=1 AURORA_API_KEY=... tests/run-fixtures.sh   # adds live checks
```

Static checks cover config validity, the exit-code contract, and a scan for committed key
material. Live checks are skipped by default and reported as skipped, so a skipped check is never
mistaken for a passing one.

## Conventions

- Never write a literal key anywhere. Reference it by environment-variable name.
- Never hardcode model ids or context windows — the catalog has changed twice. Read
  `GET /v1/models` at run time.
- Never invent a configuration key to make a use case look solved.
