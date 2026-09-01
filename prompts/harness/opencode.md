> **Agents: read the raw file, not this rendered page.**
> `https://raw.githubusercontent.com/aurorainfra/aurora-skills/main/prompts/harness/opencode.md`
>
> GitHub's markdown renderer strips the XML section tags below (`<role>`, `<context>`,
> `<constraints>` …). On the rendered page every section runs together with no boundary,
> which is exactly the structure this file depends on. Fetched raw, the tags are intact.

<role>
You configure OpenCode to run on Aurora inference, then prove it works. Act, verify, report.
</role>

<context>
See README.md for repo structure and the auth pattern. Do not restate it here.

OpenCode speaks the OpenAI-compatible API natively (Vercel AI SDK), and Aurora serves exactly
that. So this is a plain provider registration: no proxy, no translation layer, nothing to keep
running. This is the simplest of the three harness setups — if you find yourself adding a shim,
you have taken a wrong turn.

Config lives at `~/.config/opencode/opencode.jsonc`.
</context>

<objective>
1. Run `scripts/setup.sh opencode` and branch on the exit code.
2. Register Aurora as an OpenCode provider.
3. Prove a real completion runs on Aurora.
</objective>

<constraints>
- Reference the key as `{env:AURORA_TOKEN}` in config. Never write its literal value.
- Read the model catalog live. The catalog has changed twice; ids and context windows drift.
- Do not copy the key into a second credential store. Keep exactly one copy on disk, mode 600.
</constraints>

<instructions>
<agent_actions>
1. Run `scripts/setup.sh opencode`:
   - 0: proceed. The script prints the live model list — use it.
   - 2: relay the message asking the user to set AURORA_API_KEY, then re-run once confirmed.
   - 3: halt. Auth failed; do not retry with another header scheme.
   - 4: halt. `opencode` is not on PATH; tell the user to install it.
2. Add a provider block to `~/.config/opencode/opencode.jsonc`:
   - `npm`: `@ai-sdk/openai-compatible`
   - `options.baseURL`: the verified `AURORA_API_ENDPOINT`
   - `options.apiKey`: `{env:AURORA_TOKEN}`
   - `models`: one entry per id returned by the live catalog. Do not invent entries.
   Preserve any existing providers in that file.
3. Prove it: run `opencode run "Reply with exactly: pong"` against an Aurora model and confirm
   the reply. Report the model id actually used.
</agent_actions>
</instructions>

<success_criteria>
- `scripts/setup.sh opencode` exits 0.
- `opencode.jsonc` parses, and every model entry corresponds to a live catalog id.
- A real completion returned from an Aurora model.
- No key value in any file, log or output.
</success_criteria>
