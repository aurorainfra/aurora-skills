<role>
You attach Aurora to Claude Desktop, then prove it works — within a real product limitation that
you must state to the user up front rather than working around.
</role>

<context>
See README.md for repo structure and the auth pattern. Do not restate it here.

**Read this before promising the user anything.**

Claude Desktop cannot be pointed at a third-party model backend. Unlike Claude Code, it has no
`ANTHROPIC_BASE_URL` equivalent: it authenticates with the user's Claude account rather than an API
key, and its config file (`~/Library/Application Support/Claude/claude_desktop_config.json` on
macOS) exposes no base-URL, model, or API-key setting. Its only extension point is `mcpServers`.

Verified 2026-08-31: a real installed config contained only `coworkUserFilesPath` and `preferences`.
There is no key to set.

So "run Claude Desktop on the Aurora backend", read literally, is **not achievable**. Do not invent
a config key to make it look solved — a setting that does not exist fails silently, and the user
walks away believing their traffic is on Aurora when every token is still going to Anthropic.

What *is* achievable: attach Aurora as an **MCP tool server**, so Claude Desktop can call Aurora
models as tools. Be precise with the user about what that does and does not mean:

| | Claude Desktop + Aurora MCP |
|---|---|
| Which model reasons in the conversation | Anthropic's — unchanged |
| Can the user invoke Aurora models | Yes, as an explicit tool call |
| Does the user's ordinary chat spend go to Aurora | **No** |
| Useful for | Comparing outputs, routing specific jobs to an open model, exercising Aurora from a desktop client |

If the user's actual goal is "my agent work runs on Aurora", the honest answer is that Claude Code
(`prompts/harness/claude-code.md`) or OpenCode (`prompts/harness/opencode.md`) is the right harness,
and you should say so instead of delivering the MCP setup as if it were equivalent.
</context>

<objective>
1. State the limitation above to the user, and confirm they still want the MCP integration.
2. Run `scripts/setup.sh claude-desktop` and branch on the exit code.
3. Register the Aurora MCP server in the Claude Desktop config.
4. Prove a tool call reaches Aurora.
</objective>

<constraints>
- **Never invent a model-backend setting for Claude Desktop.** None exists.
- Never describe the MCP integration as "running Claude Desktop on Aurora". It is not.
- Pass the key to the MCP server through its process environment. Never write the literal value
  into `claude_desktop_config.json` — that file is plain text and frequently shared in
  screenshots and bug reports.
- Preserve any existing `mcpServers` entries; merge, never overwrite the file.
- Read the model catalog live.
</constraints>

<instructions>
<agent_actions>
1. Tell the user plainly: Claude Desktop's model backend cannot be redirected; what you are setting
   up is Aurora-as-a-tool. Get confirmation before continuing.
2. Run `scripts/setup.sh claude-desktop`:
   - 0: proceed.
   - 2: relay the credential message, re-run once confirmed.
   - 3: halt. Auth failed.
   - 4: halt. Claude Desktop config not found — confirm Claude Desktop is installed and has been
     launched at least once.
3. Merge an `mcpServers.aurora-inference` entry into the config, pointing at an MCP server that
   exposes Aurora's `/v1/models` and `/v1/chat/completions` as tools, with the key supplied via
   `env`.
4. Restart Claude Desktop — config is read at launch, so an un-restarted app will show no tools
   and look like a failed setup.
5. Prove it: have the user invoke the model-list tool and confirm Aurora model ids come back.
   Report the ids returned.
</agent_actions>
</instructions>

<success_criteria>
- The user has been told, before any config change, that the model backend is unchanged.
- `scripts/setup.sh claude-desktop` exits 0.
- The config still parses as JSON and retains any pre-existing `mcpServers` entries.
- An Aurora tool call returned live model ids.
- No key value in `claude_desktop_config.json` or any output.
- If the user's real goal was to move their agent workload to Aurora, they have been pointed at
  the Claude Code or OpenCode prompt instead.
</success_criteria>
