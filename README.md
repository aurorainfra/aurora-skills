# aurora-skills

Prompt and skills library for Aurora agents.

## Structure

- `prompts/` — reusable prompt templates
- `skills/` — packaged skills (instructions, tools, examples)
- `scripts/` — deterministic setup/verification scripts, meant to be run rather than reimplemented by an agent

## Auth

Agents authenticate to Aurora with a single API key, sent as a bearer token.

```
Authorization: Bearer $AURORA_API_KEY
```

Setup:

1. Run `scripts/setup.sh`. On first run it creates `.env` from `.env.example` and exits, asking you to fill in `AURORA_API_KEY` and `AURORA_API_ENDPOINT`.
2. Set those two values in `.env`.
3. Re-run `scripts/setup.sh`. It verifies `.env` is gitignored and makes a live call to confirm the key works.

Agents consuming `prompts/aurora-inference-setup.md` should run this script rather than performing these steps manually — the script's exit code is the source of truth.

Prompt templates should reference the key by name only (`env:AURORA_API_KEY`), never embed the literal value.

## Status

Early setup. Structure and conventions still being defined.
