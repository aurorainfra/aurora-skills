> **Agents: read the raw file, not this rendered page.**
> `https://raw.githubusercontent.com/aurorainfra/aurora-skills/main/prompts/harness/claude-code.md`
>
> GitHub's markdown renderer strips the XML section tags below (`<role>`, `<context>`,
> `<constraints>` …). On the rendered page every section runs together with no boundary,
> which is exactly the structure this file depends on. Fetched raw, the tags are intact.

<role>
You configure Claude Code to run on Aurora inference, then prove it works. Act, verify, report.
</role>

<context>
See README.md for repo structure and the auth pattern. Do not restate it here.

**A translating proxy is mandatory here, and this is architectural, not preference.**

Claude Code speaks only the Anthropic Messages API (`POST /v1/messages`). Aurora serves only an
OpenAI-compatible API (`POST /v1/chat/completions`). Pointing `ANTHROPIC_BASE_URL` straight at
Aurora does not work — Aurora returns `404 {"error":"unsupported endpoint"}`. The difference is not
cosmetic: system-prompt placement, content blocks, tool schemas, tool-call encoding, stop reasons
and the whole SSE event grammar all differ.

The working path is:

    Claude Code --/v1/messages--> LiteLLM (127.0.0.1:4000) --/v1/chat/completions--> Aurora

If Aurora ever ships a native Anthropic-compatible endpoint, the proxy can be deleted and
`ANTHROPIC_BASE_URL` can point at Aurora directly. Until then, do not tell the user otherwise.

Four proxy settings are load-bearing. Each was a silent failure before it was set:
- `use_chat_completions_url_for_anthropic_messages: true` — without it LiteLLM's default bridge
  targets the OpenAI *Responses* API, which Aurora does not serve.
- `merge_reasoning_content_in_choices: true` — Aurora's models are reasoning models and return
  `reasoning_content`. The bridge turns that into an unsigned `thinking` block, which Claude Code
  hard-rejects. Note this is implemented in the streaming handler only.
- `additional_drop_params: ["stop_sequences"]` — the bridge copies Anthropic's `stop_sequences`
  verbatim instead of mapping it to OpenAI's `stop`; Aurora validates strictly and 400s.
- `drop_params: true` — Aurora advertises a fixed sampling-parameter set and rejects the rest.
</context>

<objective>
1. Run `scripts/setup.sh claude-code` and branch on the exit code.
2. Stand up the translating proxy.
3. Launch Claude Code against it and prove a turn actually reached Aurora.
</objective>

<constraints>
- Never claim `ANTHROPIC_BASE_URL` can point at Aurora directly. It cannot.
- Bind the proxy to `127.0.0.1` only. Do not add a master key — it buys nothing here and has
  previously ended up committed to git as a live secret.
- Reference the key via `os.environ/AURORA_TOKEN`. Never write its literal value.
- Read the model catalog live rather than hardcoding an id.
</constraints>

<instructions>
<agent_actions>
1. Run `scripts/setup.sh claude-code`:
   - 0: proceed. Note the printed `/v1/messages` status — it confirms why the proxy is needed.
   - 2: relay the credential message, re-run once the user confirms.
   - 3: halt. Auth failed.
   - 4: halt. `claude` is not on PATH.
2. Configure the proxy with the four load-bearing settings above, pointing `api_base` at the
   verified `AURORA_API_ENDPOINT` and the model at a live catalog id.
3. Start the proxy and confirm it is listening on `127.0.0.1:4000`.
4. Launch Claude Code with `ANTHROPIC_BASE_URL` pointed at the proxy.
5. **Prove the turn reached Aurora.** Do not check `ANTHROPIC_BASE_URL` from inside the session —
   it reads back empty, because Claude Code applies the override to its own API client rather than
   exporting it to the shell. Check the proxy log instead: a real turn appears as
   `POST /v1/messages ... 200 OK`. No new lines means the session is NOT on Aurora.
</agent_actions>
</instructions>

<success_criteria>
- `scripts/setup.sh claude-code` exits 0.
- The proxy is up on 127.0.0.1:4000 with all four settings applied.
- A Claude Code turn produced a `POST /v1/messages ... 200` line in the proxy log.
- The user has been told the proxy is required and why.
- No key value in any file, log or output.
</success_criteria>
