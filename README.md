# Claudette - Claude-Native Personal Agent

A minimal, always-on personal AI assistant accessible via Telegram, powered entirely by Claude Code. No gateway server, no custom runtime -- just CLI flags, a system prompt, and a Telegram bot running in tmux.

## Prerequisites

- Claude Pro or Max subscription (Max recommended)
- Claude Code v2.1.87+ (`claude --version`)
- Bun runtime (`curl -fsSL https://bun.sh/install | bash`)
- A Telegram account
- macOS or Linux
- `tmux` for session persistence

## Architecture

```
Phone (Telegram)
    |
Telegram Bot API
    |
Claude Code session (in tmux)
    +-- System prompt (persona.md)
    +-- Config dir (~/agent/.claude/)
    +-- MCP servers (memory, calendar, etc.)
    +-- Subagents (researcher, writer, planner, sysadmin)
    +-- Access to ~/Documents, ~/notes, etc.
```

Channels are MCP servers with the `claude/channel` capability. The Telegram plugin polls the Telegram API locally (no exposed URL), forwards messages to Claude via MCP notifications, and replies back through a reply tool. Sender gating via allowlist prevents prompt injection from strangers.

## Setup

### 1. Create Directory Structure

```bash
mkdir -p ~/agent/.claude ~/agent/skills ~/agent/memory
```

### 2. Write the Agent Persona

Create `~/agent/persona.md` -- this defines the agent's identity:

```markdown
# Agent Identity

You are a general-purpose personal AI assistant accessible via Telegram.
You are not a coding assistant -- you are a knowledgeable, resourceful companion
that can help with research, planning, writing, analysis, file management,
and any task a capable human assistant would handle.

## Behavior
- Be concise -- phone screens are small
- Outline multi-step plans before executing
- Use web search proactively for current information
- Never fabricate -- say when you don't know

## Communication Style
- Direct, no filler
- Short paragraphs over bullet lists
- Match the user's formality level
```

### 3. Configure Settings

Create `~/agent/.claude/settings.json`:

```json
{
  "model": "claude-sonnet-4-6-20250514",
  "autoMemoryEnabled": true,
  "permissions": {
    "allow": ["Read", "Write", "Edit", "Bash", "WebFetch", "WebSearch", "Glob", "Grep", "LS"]
  }
}
```

### 4. Add Behavioral Rules

Create `~/agent/.claude/CLAUDE.md`:

```markdown
# Agent Rules
- Read-first access to ~/Documents and ~/notes -- only modify when asked
- Store user preferences and context in ~/agent/memory/ as markdown files
- Multi-step tasks: state plan, execute, report result
- Quick questions: just answer
- Never delete files outside ~/agent/ without confirmation
- Never expose API keys or credentials in Telegram messages
```

### 5. Set Up Telegram Bot

1. Message `@BotFather` on Telegram
2. Send `/newbot`, choose a name and username
3. Copy the API token
4. Install the plugin:

```bash
claude plugin install telegram@claude-plugins-official
```

5. Configure with your bot token and ensure the token ends up at `~/agent/.claude/channels/telegram/.env`

### 6. Define Subagents

Create `~/agent/agents.json`:

```json
{
  "researcher": {
    "description": "Deep research on any topic with web search",
    "prompt": "You are a thorough researcher. Search the web, read full pages when needed, synthesize findings, and cite sources.",
    "tools": ["WebFetch", "WebSearch", "Bash", "Read", "Write"]
  },
  "writer": {
    "description": "Drafting and editing text",
    "prompt": "You are a skilled writer and editor. Match the intended tone and audience. Produce clean, publishable text.",
    "tools": ["Read", "Write", "Edit"]
  },
  "planner": {
    "description": "Task planning and breakdown",
    "prompt": "You help plan and break down tasks. Be structured and realistic. Create actionable checklists.",
    "tools": ["Read", "Write", "Bash"]
  },
  "sysadmin": {
    "description": "System tasks and file management",
    "prompt": "You handle system administration tasks. Be careful with destructive operations. Report what changed.",
    "tools": ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "LS"]
  }
}
```

### 7. (Optional) Memory MCP Server

**File-based (simplest):** The CLAUDE.md rules already instruct the agent to use `~/agent/memory/` as a knowledge store. Auto-memories handle the rest.

**Custom MCP server:** For structured recall, create an MCP server backed by SQLite and register it in `~/agent/mcp.json`:

```json
{
  "mcpServers": {
    "memory": {
      "type": "stdio",
      "command": "node",
      "args": ["~/agent/mcp-memory-server/index.js"]
    }
  }
}
```

### 8. Create the Launch Script

Create `~/agent/start.sh`:

```bash
#!/usr/bin/env bash
AGENT_HOME="$HOME/agent"

export CLAUDE_CONFIG_DIR="$AGENT_HOME/.claude"

claude --system-prompt "$(cat $AGENT_HOME/persona.md)" \
       --dangerously-skip-permissions \
       --channels plugin:telegram@claude-plugins-official \
       --add-dir "$HOME/Documents" \
       --add-dir "$HOME/notes" \
       --mcp-config "$AGENT_HOME/mcp.json" \
       --agents "$(cat $AGENT_HOME/agents.json)"
```

```bash
chmod +x ~/agent/start.sh
```

> **Note:** Use `CLAUDE_CONFIG_DIR` env var (not `--claude-home`) for config isolation. Use `--system-prompt "$(cat file)"` if `--system-prompt-file` isn't available in your version.

### 9. Run It

```bash
# Start in a persistent tmux session
tmux new-session -d -s agent "$HOME/agent/start.sh"

# Attach to watch
tmux attach -t agent

# Detach: Ctrl+B, then D
```

**Auto-start on macOS:** Create a LaunchAgent at `~/Library/LaunchAgents/com.agent.claude.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.agent.claude</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>tmux new-session -d -s agent "$HOME/agent/start.sh"</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/claude-agent.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/claude-agent.err</string>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.agent.claude.plist
```

## Directory Layout

```
~/agent/
+-- .claude/
|   +-- settings.json
|   +-- CLAUDE.md
|   +-- channels/telegram/.env
|   +-- memory/              (auto-memories)
+-- persona.md               (system prompt)
+-- agents.json              (subagent definitions)
+-- mcp.json                 (MCP server config)
+-- skills/                  (custom skills)
+-- memory/                  (persistent memory files)
+-- start.sh                 (launch script)
```

## How Channels Work

1. Claude Code spawns the Telegram plugin as a subprocess over stdio
2. Plugin polls Telegram API for messages (no exposed URL)
3. Messages forwarded via MCP notification
4. Claude replies via a reply tool back to Telegram
5. Permission relay forwards tool-approval prompts to your phone
6. Sender gating via user ID allowlist

Permission relay lets you approve/deny tool use from your phone -- an alternative to `--dangerously-skip-permissions`.

## Risks

| Risk | Mitigation |
|---|---|
| Channels API changes (research preview) | Pin Claude Code version |
| Prompt injection via Telegram | Built-in sender gating by user ID |
| `--dangerously-skip-permissions` | Use permission relay instead |
| tmux session dies | LaunchAgent + watchdog script |
| Context window bloat | Auto-compaction handles this |
| Requires Claude subscription | Need Claude Pro or Max |

## Known Limitations

- If the tmux session dies, Telegram messages are lost (not queued)
- Without `--dangerously-skip-permissions`, permission prompts block in the terminal (use permission relay)
- Long-running sessions auto-compact -- very old context may be summarized away
- Single channel per session (can't run Telegram + Discord simultaneously yet)

## Next Steps

- Build a custom memory MCP server for structured recall
- Add a calendar MCP server for scheduling awareness
- Create domain-specific skills in `~/agent/skills/`
- Use `--model opus` for the main agent with subagents on Sonnet
- Set up a watchdog script to restart the session on failure
