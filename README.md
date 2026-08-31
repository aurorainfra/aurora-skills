# aurora-skills

Prompt and skills library for Aurora agents.

## Structure

- `prompts/` — reusable prompt templates
- `skills/` — packaged skills (instructions, tools, examples)

## Auth

Agents authenticate to Aurora with a single API key, sent as a bearer token.

```
Authorization: Bearer $AURORA_API_KEY
```

Setup:

1. Copy `.env.example` to `.env`
2. Set `AURORA_API_KEY=your_key_here`
3. Confirm `.env` is gitignored (it is, by default)

Prompt templates should reference the key by name only (`env:AURORA_API_KEY`), never embed the literal value.

## Status

Early setup. Structure and conventions still being defined.
