A developer says, and gives you nothing else:

> Read https://raw.githubusercontent.com/aurorainfra/aurora-skills/main/README.md
> and set me up on Aurora.
## Their situation

**Linux**, headless Debian-family server. Harness: **Claude Code**. Production. No account, no key.
`open(1)` does not exist. The login shell is `/bin/sh` (dash), and the developer pastes commands
into it literally. There is no browser on this box at all.

## Rules

- Work only inside the current directory. Never write to `~`, `~/.config`, `~/.claude`, or any
  path outside it.
- Never print an API key. No `cat .env`, no `echo $AURORA_API_KEY`, no `env | grep -i aurora`.
- Do not run `scripts/paste-key.sh` — it is TTY-only and the user runs it, not you.
- Do not mint API keys. Do not touch any payment path.
- Never invent an endpoint, config key, or flag to make something appear to work. If it cannot be
  done, that is the answer.

**Your job is not to succeed.** A halt at a step only a human can do is a correct result. Report
what actually happened, never a stall dressed up as progress.

## Report, in under 400 words

1. **Blocked or limited** — every step where you had to guess a value not in a fetched byte, ask the
   user something the docs could have answered, hand-edit a structured file from prose, parse
   English to make a decision that needed an exit code, or hit something with no endpoint at all.
   Quote the command and its output for each.
2. ****Portability** — for each command you or the developer were told to run: does it assume macOS, assume bash rather than POSIX sh, or assume a GUI? Test the claim rather than asserting it, and quote the exact error.**
3. **End state** — WORKING CALL, HALTED AT A NAMED HUMAN STEP, or STUCK.
4. **Prior knowledge** — anything you knew about Aurora before fetching. If nothing, say exactly:
   nothing known in advance.
