# aurora-skills

Point your coding agent at this file and it will set you up on Aurora inference.

> **To the user:** paste this to Claude Code, Cursor, OpenCode, or any coding agent:
>
> ```
> Read https://raw.githubusercontent.com/aurorainfra/aurora-skills/main/README.md
> and set me up on Aurora.
> ```

---

## For the agent: start here

You are setting a user up on Aurora inference. Work through these phases in order. Do not skip
phase 0 — a user who already has a working key should not be walked through signup again.

### Phase 0 — Find out where they are

Ask, in one message, not one at a time:

1. Do you already have an Aurora account? (`portal.aur.lu`)
2. Do you already have an API key?
3. Which harness do you want — **Claude Code**, **OpenCode**, or just raw API access?
4. Production or dev?

If they already have a key, skip to Phase 3.

### Phase 1 — Account and key (browser; you cannot do this)

There is **no signup endpoint** and **no key-creation endpoint reachable without a key**. These
steps are human-only. Open the pages for them:

```bash
open https://portal.aur.lu        # macOS   (xdg-open on Linux, start on Windows)
```

Tell them to sign in (or create an account — it is an Auth0 flow), then create an API key and
**leave the value on screen**. Do not ask them to read it to you. Wait for confirmation.

### Phase 2 — Credentials (they run this; you must not)

Give them this line **verbatim** and tell them to run it in **their own terminal**, in the
directory they want configured:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/aurorainfra/aurora-skills/main/scripts/paste-key.sh)
```

Add `--dev` for the dev environment.

It hides their input, writes `.env` at mode 600, verifies the key live, prints the model list, and
never displays the key. It refuses to run without a TTY.

**Tell them explicitly not to paste the key into the chat, and not to use Claude Code's `!` prefix.**
`!` runs in the session and its *output is added to the conversation* — it feeds the model rather
than bypassing it. Users routinely assume the opposite.

**Do not** run this script yourself. **Do not** `cat .env`, `echo $AURORA_API_KEY`, or
`env | grep AURORA`. The key must never enter your context.

### Phase 3 — Verify (you do this)

The script prints its own result. If you need to re-check, run it — never read the file:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $(grep '^AURORA_API_KEY=' .env | cut -d= -f2-)" \
  https://ai.aur.lu/v1/models
```

`200` is good. `401` almost always means the wrong environment — keys are environment-scoped.

### Phase 4 — Payment, only if needed

Credit balance is readable, but **there is no payment endpoint**. If they need credits, open the
portal and let them pay there; then re-check the balance. Never handle card details.

### Phase 5 — Configure their harness

**Fetch the `raw.githubusercontent.com` URLs below, not the rendered GitHub pages.** These prompts
use XML section tags (`<role>`, `<context>`, `<constraints>` …) for their structure, and GitHub's
markdown renderer strips them — on the rendered page every section runs together with no boundary.
Raw is `text/plain`, so the tags survive.

Fetch and follow the matching file:

| Harness | Prompt | Note |
|---|---|---|
| Claude Code | [`prompts/harness/claude-code.md`](https://raw.githubusercontent.com/aurorainfra/aurora-skills/main/prompts/harness/claude-code.md) | Needs a translating proxy — see below |
| OpenCode | [`prompts/harness/opencode.md`](https://raw.githubusercontent.com/aurorainfra/aurora-skills/main/prompts/harness/opencode.md) | Direct, no proxy |

The full interactive version of this flow is
[`prompts/aurora-account-setup.md`](https://raw.githubusercontent.com/aurorainfra/aurora-skills/main/prompts/aurora-account-setup.md).

---

## Facts an agent needs

Verified live 2026-08-31. The catalog moves — read `GET /v1/models` at run time, never hardcode.

### Endpoints

| | Value |
|---|---|
| Prod inference | `https://ai.aur.lu/v1` |
| Dev inference | `https://inference.dev.aur.lu/v1` |
| Portal API | `https://api-portal.aur.lu/api` |
| Raw OpenAPI spec | `https://docs.aur.lu/portal-api-spec.json` (plain-fetchable, no JS, no auth) |

Aurora is **OpenAI-compatible only** — `/v1/models`, `/v1/chat/completions`, `/v1/completions`.
It does **not** serve `/v1/messages`; that returns 404. This is why Claude Code needs a proxy and
OpenCode does not.

### Auth — the two APIs take opposite headers

| API | Works | 401s |
|---|---|---|
| Inference (`ai.aur.lu`) | `Authorization: Bearer` | `X-Api-Key` |
| Portal (`api-portal.aur.lu`) | `X-Api-Key` | `Authorization: Bearer` |

This is the easiest way to get a spurious 401. The Portal OpenAPI spec declares `X-Api-Key` as its
only scheme — correct for the Portal, wrong for inference.

Keys are **environment-scoped**: a dev key will not authenticate against prod.

### What is human-only

| Step | Agent? |
|---|---|
| Create account / tenant | No — no endpoint |
| Auth0 login | No — browser |
| Create first API key | No — portal UI |
| Verify a key | Yes |
| Resolve tenant, read credits | Yes |
| Top up credits | No — no payment endpoint |
| Mint additional scoped keys | API exists; blocked on undocumented `permissions` values |

---

## Repo layout

- `prompts/aurora-account-setup.md` — the interactive setup skill (Phases 0–5 above)
- `prompts/harness/` — one file per supported harness
- `prompts/meta/` — the meta-prompt that generates the harness set
- `scripts/paste-key.sh` — self-contained credential capture; user-run, TTY-only
- `scripts/setup.sh` — repo-local verification + harness prerequisites
- `tests/run-fixtures.sh` — fixture suite; green with no key and no network

Claude Desktop is deliberately unsupported: it exposes no model-backend override, so it cannot be
pointed at Aurora. Do not add a config key for it — none exists, and a fake one fails silently.

## Tests

```bash
tests/run-fixtures.sh                                    # static only, no key needed
AURORA_LIVE=1 AURORA_API_KEY=... tests/run-fixtures.sh   # adds live checks
```

## Conventions

- Never write a literal key anywhere. Reference it by environment-variable name.
- Never hardcode model ids or context windows.
- Never invent a configuration key to make a use case look solved.
