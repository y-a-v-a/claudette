# Feasibility Assessment: Remote-Controllable Claude Instance via Telegram

## Context

PLAN.md describes a "Claude-native personal agent" — a long-running Claude Code session controlled via Telegram, with subagents, MCP servers, and persistent memory. The goal is an always-on personal AI assistant on your phone, with zero custom infrastructure.

## Verdict: ~95% Feasible — Almost everything exists

The architecture is sound and nearly all the pieces exist. Channels are a research preview feature but are well-documented with full Telegram support.

---

## Flag-by-Flag Status

### Confirmed working (in `claude --help` v2.1.87)
| Flag | Status |
|---|---|
| `--dangerously-skip-permissions` | ✅ Exists |
| `--add-dir` | ✅ Exists |
| `--mcp-config` | ✅ Exists |
| `--agents` | ✅ Exists |
| `--system-prompt` | ✅ Exists |
| `--settings` | ✅ Exists |
| `--plugin-dir` | ✅ Exists |
| `claude plugin install` | ✅ Plugin system exists |

### Documented but not in current --help (v2.1.87)
These are documented at code.claude.com and referenced in `--bare` description, but not yet showing as top-level flags. May require a newer version or feature flag:

| Flag | Docs Status | Workaround |
|---|---|---|
| `--system-prompt-file` | Referenced in `--bare` docs (`--system-prompt[-file]`) | Use `--system-prompt "$(cat persona.md)"` |
| `--channels` | Full docs at code.claude.com/docs/en/channels-reference | May need version update; channels use MCP under the hood |
| `CLAUDE_CONFIG_DIR` | Env var for config directory isolation | Set in launch script: `export CLAUDE_CONFIG_DIR=~/agent/.claude` |

### Research Preview (Documented, Working)
| Feature | Status | Notes |
|---|---|---|
| Telegram channel plugin | ✅ Documented with full implementation | `plugin:telegram@claude-plugins-official` — [source on GitHub](https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/telegram) |
| Discord channel | ✅ Available | Same plugin architecture |
| iMessage channel | ✅ macOS only | Reads Messages database directly |
| Channel two-way communication | ✅ Full reply tool support | MCP-based, well-documented protocol |
| Permission relay | ✅ v2.1.81+ | Approve/deny tool use from Telegram |

---

## How Channels Actually Work (from official docs)

A channel is an MCP server with the `claude/channel` capability. Key architecture:

1. **Claude Code spawns it as a subprocess** over stdio
2. **Plugin polls Telegram API** for messages (no exposed URL needed — runs locally)
3. **Forwards messages** via `mcp.notification()` with `notifications/claude/channel`
4. **Reply tool** lets Claude send messages back to Telegram
5. **Permission relay** forwards tool-approval prompts to your phone
6. **Sender gating** — allowlist prevents prompt injection from strangers

The Telegram plugin handles pairing (DM bot → pairing code → approve in terminal) and gates on `message.from.id`.

### Channel MCP Server Structure

A channel server declares the `claude/channel` capability:

```ts
const mcp = new Server(
  { name: 'your-channel', version: '0.0.1' },
  {
    capabilities: {
      experimental: {
        'claude/channel': {},            // registers the channel listener
        'claude/channel/permission': {}, // opt-in to permission relay
      },
      tools: {},  // enables reply tool discovery
    },
    instructions: 'Messages arrive as <channel source="your-channel" chat_id="...">. Reply with the reply tool.',
  },
)
```

Events arrive in Claude's context as:
```
<channel source="telegram" chat_id="12345" sender="username">
Hello, what can you do?
</channel>
```

### Permission Relay Flow

1. Claude wants to run a tool (e.g., `Bash`)
2. Claude Code generates a 5-letter request ID and notifies your channel
3. Channel forwards the prompt to Telegram: "Claude wants to run Bash: list files. Reply `yes abcde` or `no abcde`"
4. You reply from your phone
5. Claude Code applies the verdict

Both the local terminal dialog AND the phone stay live — first answer wins.

---

## Corrected Launch Script

```bash
#!/usr/bin/env bash
AGENT_HOME="$HOME/agent"

# Isolate config from dev sessions
export CLAUDE_CONFIG_DIR="$AGENT_HOME/.claude"

claude --system-prompt "$(cat $AGENT_HOME/persona.md)" \
       --dangerously-skip-permissions \
       --channels plugin:telegram@claude-plugins-official \
       --add-dir "$HOME/Documents" \
       --add-dir "$HOME/notes" \
       --mcp-config "$AGENT_HOME/mcp.json" \
       --agents "$(cat $AGENT_HOME/agents.json)"
```

If `--channels` isn't available in your version, update Claude Code first:
```bash
claude update
```

---

## What PLAN.md Gets Right

- Overall architecture (tmux + Claude Code + Telegram)
- Subagent definitions via `--agents`
- MCP server integration via `--mcp-config`
- Directory access via `--add-dir`
- LaunchAgent for auto-start on macOS
- File-based memory approach
- Security considerations

## What PLAN.md Gets Wrong / Needs Update

1. **`--claude-home`** → Use `CLAUDE_CONFIG_DIR` env var instead
2. **`--system-prompt-file`** → Use `--system-prompt "$(cat file)"` as fallback (or update Claude Code if the flag has landed)
3. **Plugin install flow** — The `/plugin install telegram@claude-plugins-official` and `/telegram:configure` flow needs testing against actual plugin marketplace
4. **Settings model field** — `settings.json` format should use `--settings` flag or be placed in the `CLAUDE_CONFIG_DIR` path

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Research preview breaks on update | Medium | Pin Claude Code version; monitor changelogs |
| Prompt injection via Telegram | High | Sender gating is built into the Telegram plugin (allowlist by user ID) |
| `--dangerously-skip-permissions` | High | Use permission relay instead — approve/deny from phone |
| tmux session dies | Medium | LaunchAgent + watchdog script |
| Context window bloat | Low | Auto-compaction handles this; old context gets summarized |
| Requires claude.ai auth (not API key) | Blocker if no sub | Need Claude Pro or Max subscription |

## Implementation Steps

1. **Update Claude Code** to latest version (`claude update`)
2. **Create directory structure** (`~/agent/.claude/`, etc.)
3. **Set up Telegram bot** via BotFather, get token
4. **Install Telegram plugin** (`claude plugin install telegram@claude-plugins-official`)
5. **Configure plugin** with bot token
6. **Write persona.md, agents.json, mcp.json**
7. **Write and test launch script** (start minimal: just `--channels` + `--dangerously-skip-permissions`)
8. **Test basic Telegram ↔ Claude communication**
9. **Add subagents, MCP servers, directory access**
10. **Set up tmux persistence and LaunchAgent**

## Verification

1. Send "Hi" from Telegram → see response in terminal and on phone
2. Send "What files are in my Documents?" → verify file access works
3. Trigger a tool that needs approval → verify permission relay works on phone
4. Kill and restart tmux session → verify LaunchAgent restarts it
5. Test after 24h → verify long-running session stability
