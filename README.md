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
- `tests/cold-start-trial.sh` — runs one scenario as a cold agent; `tests/scenarios/` holds the six
- `tests/run-fixtures.sh` — fixture suite; green with no key and no network

Claude Desktop is deliberately unsupported: it exposes no model-backend override, so it cannot be
pointed at Aurora. Do not add a config key for it — none exists, and a fake one fails silently.

## Tests

```bash
tests/run-fixtures.sh                                    # static only, no key needed
AURORA_LIVE=1 AURORA_API_KEY=... tests/run-fixtures.sh   # adds live checks
tests/docs-agent-readiness.sh                            # probes the live docs as an agent would
```

`cold-start-trial.sh` runs one onboarding scenario as a **genuinely cold agent** — the only way to
test this repo's actual claim, which is that someone who knows nothing can paste one line and end up
working:

```bash
tests/cold-start-trial.sh S5-linux-dash --dry-run   # isolation checks only, no agent, no spend
tests/cold-start-trial.sh S5-linux-dash             # run it
```

Scenarios live in `tests/scenarios/`: cold start, an OpenCode merge over a config that already has
other providers, raw API with no harness, the rendered-GitHub entry point, Linux with a dash login
shell, and a re-run over a working install.

Three of them begin *after* the human-only steps, so they need a real key on disk. It is supplied
explicitly and from nowhere else:

```bash
AURORA_API_KEY=... tests/cold-start-trial.sh S2-opencode-merge
```

Without it the harness exits 3 rather than run the scenario against an empty directory and report
findings about its own setup. **Mint a dedicated, revocable key for this.** Do not reuse one from a
working installation — a proxy checkout or a harness config `.env` exists to make that thing run,
not to serve as a credential store, and a test that reaches into it can revoke or corrupt a real
setup. The harness never searches the filesystem for a key; a fixture enforces that, and another
enforces that it never expands the key into its output.

You cannot get this from a subagent spawned inside a configured checkout. It inherits the session's
resolved `CLAUDE.md` chain and its recalled memories, so it "discovers" what it was handed — measured
2026-09-09, four of six such agents disclosed prior knowledge of Aurora's endpoints and catalog.
Both leak sources are path-scoped: instructions resolve upward from the working directory, and memory
is keyed to it. So the harness runs from a fresh directory each time with neither above it, and
**refuses with exit 2** rather than produce findings that would be worthless.

Do not try to achieve this by isolating `CLAUDE_CONFIG_DIR` or overriding `HOME`. Credentials live in
the OS keychain and `$HOME/.claude.json`; both fail auth with `Not logged in` and isolate nothing that
matters. A fixture guards against reintroducing either.

`docs-agent-readiness.sh` is the repeatable acceptance test for
[inference-roadmap#185](https://github.com/aurorainfra/inference-roadmap/issues/185): it fetches
Aurora's docs over plain HTTP with no JavaScript and asserts an agent can actually use them —
distinct content per page, real 404s, real `robots.txt`, a sitemap that points at the real host, and
the raw OpenAPI spec still fetchable. Exit 0 means the docs are agent-ready. It currently exits 1.

## Conventions

- Never write a literal key anywhere. Reference it by environment-variable name.
- Never hardcode model ids or context windows.
- Never invent a configuration key to make a use case look solved.
