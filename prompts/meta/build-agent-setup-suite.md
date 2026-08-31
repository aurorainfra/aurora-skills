<role>
You are building the agent-setup suite for this repository: the full set of prompts, scripts and
fixtures that let an agent take a user from "no Aurora access" to "my harness is running on Aurora
inference, and I have proof it works."

You are not writing documentation about Aurora. You are writing the artifacts another agent will
execute. Every claim you make must be executable or verifiable.
</role>

<context>
Read before writing anything:
- `README.md` — repo structure and auth pattern. Source of truth for setup facts.
- `CLAUDE.md` — decisions already made. Do not relitigate them.
- `scripts/setup.sh` — the existing deterministic script and its exit-code contract.
- `prompts/aurora-inference-setup.md` — the existing agent instruction file.

Ground truth about Aurora, verified live 2026-08-31. Do not re-derive, but DO re-verify at run time:

| Fact | Value |
|---|---|
| Prod inference base | `https://ai.aur.lu/v1` — OpenAI-compatible only |
| Dev inference base | `https://inference.dev.aur.lu/v1` |
| Portal API base | `https://api-portal.aur.lu/api` — Swagger 2.0, 44 paths |
| Raw OpenAPI spec | `https://docs.aur.lu/portal-api-spec.json` — plain-fetchable, no JS, no auth |
| Auth header | `Authorization: Bearer <atp_…>` — the ONLY scheme that works |
| `X-Api-Key` | Documented but 401s in **both** environments. Never use it. |
| Key scope | Environment-scoped. A dev key 401s on prod and vice versa. |
| Key generation | Human action. Prod: `portal.aur.lu`. Dev: `dashboard.dev.aur.lu`. |
| Aurora serves | `/v1/models`, `/v1/chat/completions`, `/v1/completions` |
| Aurora does NOT serve | `/v1/messages` (Anthropic Messages API) → 404 `unsupported endpoint` |

The model catalog **moves** — it went from 1 model to 4 between 2026-07-21 and 2026-08-18, and one
model's context window doubled. Never hardcode model ids, context windows or prices into a prompt,
a script or a fixture assertion. Always read `GET /v1/models` at run time and branch on what comes back.
</context>

<objective>
Produce three things, in this order.

**1. One harness-aware setup script.** Extends `scripts/setup.sh` to take a target harness as its
first argument. It must preserve the existing exit-code contract exactly — 0 success, 1 cannot
proceed, 2 user input needed, 3 endpoint/auth failed — because the agent instruction files branch
on those. You may add new codes above 3; you may not redefine 0–3.

**2. A prompt set, one file per use case,** in `prompts/harness/`. Each is an agent instruction
file that configures one harness against Aurora and then proves it. Cover exactly these three:

  a. **Claude Code on the Aurora backend.** Claude Code speaks only the Anthropic Messages API.
     Aurora serves only OpenAI-compatible. A translating proxy is therefore mandatory — this is an
     architectural fact, not a preference, and the prompt must say so rather than implying
     `ANTHROPIC_BASE_URL` can point at Aurora directly.

  b. **OpenCode as the harness.** OpenCode speaks OpenAI-compatible natively, so it connects
     directly with no proxy. This is the simplest of the three and the prompt should stay
     correspondingly short.

  c. **Claude Desktop on the Aurora backend.** Establish what is actually possible before writing
     instructions. If the product exposes no way to redirect its model backend, say so plainly,
     do not invent a config key, and instead document the closest achievable outcome and what it
     does and does not give the user.

**3. Fixtures that test all three**, runnable offline by default. See `<fixtures>`.
</objective>

<constraints>
- **Never** write the literal value of an API key into any file, log, commit, prompt output, or
  test artifact. Reference it only by environment-variable name.
- **Never** generate, rotate or fetch a key on the user's behalf. That is a human action.
- **Never** collect raw payment details. Payment entry always happens on a Stripe-hosted page.
- **Never invent a configuration key to make a use case look solved.** If a harness cannot be
  pointed at Aurora, the correct output is a clear statement of the limitation plus the nearest
  real alternative. A prompt that instructs an agent to write a setting that does not exist is
  worse than no prompt, because it fails silently and the user believes it worked.
- Do not reimplement the setup script's logic as individual agent tool calls. Run it, branch on
  the exit code.
- Every file you write must be consistent with the others. If the script's exit codes change, the
  prompts that branch on them change in the same commit.
</constraints>

<fixtures>
Fixtures must run and pass **without network access and without a key**, so they are usable in CI
and by a contributor who has no Aurora account. Structure each use case as two layers:

- **Static checks (always run, no credentials).** Does the generated config parse? Is it valid
  JSON/YAML? Does it name only endpoints and headers that match the ground-truth table? Does the
  proxy config translate the correct direction? Does any file contain something shaped like a
  live key (`atp_…`) — which must fail the suite loudly?
- **Live checks (opt-in, skipped by default).** Gate behind an env var. When a real key is
  present, hit `GET /v1/models`, assert HTTP 200 and a non-empty model list read dynamically.
  Never print the key or any header containing it.

A fixture that requires a secret to pass is a fixture nobody runs. Default to green-without-secrets,
and make the skip visible in the output so a skipped live check is never mistaken for a passing one.
</fixtures>

<instructions>
1. Read `README.md`, `CLAUDE.md`, `scripts/setup.sh`, `prompts/aurora-inference-setup.md`.
2. Write the harness-aware script. Keep it POSIX-ish bash, `set -euo pipefail`, no dependencies
   beyond `curl` and the harness's own CLI.
3. Write the three harness prompts using the same XML-tagged section structure as the existing
   agent file — `role`, `context`, `objective`, `constraints`, `instructions`, `success_criteria`.
   Consistency across the set matters more than per-file cleverness.
4. Write the fixtures and **actually run them**. Report real output, not expected output.
5. For anything you could not resolve — a missing endpoint value, an unconfirmed product
   capability, a decision that is genuinely the maintainer's to make — open a GitHub issue on this
   repository rather than guessing in a file. One issue per question, with the evidence you
   gathered and the specific decision needed.
</instructions>

<success_criteria>
- `scripts/setup.sh <harness>` runs for each of the three harnesses and returns a documented exit code.
- Three prompt files exist, structurally consistent, each ending in a verifiable proof step.
- The fixture suite runs green with no key and no network, and reports its skipped live checks explicitly.
- No key material anywhere in the repo, enforced by a fixture rather than by inspection.
- Any use case that cannot be fully delivered is documented as such, in the repo and as an issue,
  with no invented configuration.
</success_criteria>

<formatting>
XML-tagged sections, one concept per tag, matching `prompts/aurora-inference-setup.md`.
</formatting>
