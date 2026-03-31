# Claude-Native Personal Agent

A minimal, Claude-only alternative to OpenClaw using Claude Code's built-in features.
No gateway server, no custom runtime, no dependency hell — just CLI flags, a system prompt, and a Telegram bot.

## Prerequisites

- Claude Pro or Max subscription (Max recommended for heavier use)
- Claude Code v2.1.80 or later (`claude --version`)
- Bun runtime (`curl -fsSL https://bun.sh/install | bash`)
- A Telegram account
- macOS or Linux host machine
- `tmux` or `screen` for session persistence

## Architecture

```
Phone (Telegram)
    │
    ▼
Telegram Bot API
    │
    ▼
Claude Code session (in tmux)
    ├── System prompt (persona.md)
    ├── Isolated home dir (~/agent/.claude/)
    ├── MCP servers (memory, calendar, etc.)
    ├── Subagents (researcher, planner, etc.)
    └── Access to ~/Documents, ~/notes, etc.
```

---

## Step 1: Create the Agent Directory Structure

Set up an isolated home for your agent, separate from your coding `~/.claude`.

```bash
mkdir -p ~/agent/.claude
mkdir -p ~/agent/skills
mkdir -p ~/agent/memory
```

The key directories:

- `~/agent/.claude/` — isolated Claude home (settings, auto-memories, permissions)
- `~/agent/skills/` — custom skills for the agent
- `~/agent/memory/` — persistent memory store (if using file-based memory)

## Step 2: Write the Agent Persona

Create `~/agent/persona.md`. This replaces the default Claude Code system prompt entirely, so you're defining the agent's identity from scratch.

```markdown
# Agent Identity

You are a general-purpose personal AI assistant accessible via Telegram.
You are not a coding assistant — you are a knowledgeable, resourceful companion
that can help with research, planning, writing, analysis, file management,
and any task a capable human assistant would handle.

## Behavior

- Be concise in Telegram replies — phone screens are small
- When a task requires multiple steps, outline your plan before executing
- Use web search proactively for current information
- If you don't know something, say so — never fabricate
- Remember context from earlier in the conversation

## Capabilities

- Research any topic using web search and web fetch
- Read, create, and edit files in accessible directories
- Run shell commands for system tasks
- Delegate specialized work to subagents when appropriate

## Communication Style

- Direct, no filler
- Use short paragraphs, not bullet lists
- Ask clarifying questions only when genuinely ambiguous
- Match the formality level of the user's message
```

Adjust the persona to your taste. This is where you define the agent's character.

## Step 3: Create the Agent Settings

Create `~/agent/.claude/settings.json` for agent-specific configuration.

```json
{
  "model": "claude-sonnet-4-6-20250514",
  "autoMemoryEnabled": true,
  "permissions": {
    "allow": [
      "Read",
      "Write",
      "Edit",
      "Bash",
      "WebFetch",
      "WebSearch",
      "Glob",
      "Grep",
      "LS"
    ]
  }
}
```

Notes on model choice: Sonnet is a good default for a responsive assistant. For complex research or analysis tasks, the subagents can use a different model (defined in Step 6). You can also switch to Opus here if cost is not a concern.

## Step 4: Create the Agent CLAUDE.md

Create `~/agent/.claude/CLAUDE.md` with behavioral rules for the agent context.

```markdown
# Agent Behavioral Rules

## File Access

You have access to the user's Documents and notes directories.
Treat these as read-first — only modify files when explicitly asked.

## Memory

When the user shares personal preferences, project context, or important facts,
store them in ~/agent/memory/ as individual markdown files with descriptive names.
Check this directory at the start of relevant tasks for prior context.

## Task Execution

For multi-step tasks:
1. State what you'll do
2. Execute
3. Report the result concisely

For quick questions: just answer.

## Safety

- Never delete files outside ~/agent/ without explicit confirmation
- Never expose API keys, tokens, or credentials in Telegram messages
- If a task seems destructive, confirm before proceeding
```

## Step 5: Set Up the Telegram Bot

Create your bot via Telegram's BotFather:

1. Open Telegram and message `@BotFather`
2. Send `/newbot`
3. Choose a name and username for your bot
4. Copy the API token

Install and configure the Telegram channel plugin:

```bash
# Start Claude Code temporarily to install the plugin
claude

# Inside the session:
/plugin install telegram@claude-plugins-official
/telegram:configure <your-bot-token>

# Exit
/exit
```

The token is saved to `.claude/channels/telegram/.env`. Since you're using `--claude-home`, make sure this ended up in `~/agent/.claude/channels/telegram/.env`. If it landed in `~/.claude/` instead, move it:

```bash
mkdir -p ~/agent/.claude/channels/telegram
cp ~/.claude/channels/telegram/.env ~/agent/.claude/channels/telegram/.env
```

## Step 6: Define Subagents

Prepare your agent definitions. Create `~/agent/agents.json` for readability rather than inlining JSON on the command line.

```json
{
  "researcher": {
    "description": "Deep research on any topic with web search",
    "prompt": "You are a thorough researcher. Search the web, read full pages with WebFetch when needed, synthesize findings, and cite sources. Be comprehensive but organized.",
    "tools": ["WebFetch", "WebSearch", "Bash", "Read", "Write"]
  },
  "writer": {
    "description": "Drafting and editing text — emails, articles, documents",
    "prompt": "You are a skilled writer and editor. Match the user's intended tone and audience. Produce clean, publishable text. When editing, explain your changes briefly.",
    "tools": ["Read", "Write", "Edit"]
  },
  "planner": {
    "description": "Task planning, scheduling, and breakdown",
    "prompt": "You help plan and break down tasks. Be structured and realistic about timelines. When possible, create actionable checklists the user can follow.",
    "tools": ["Read", "Write", "Bash"]
  },
  "sysadmin": {
    "description": "System tasks, file management, shell operations",
    "prompt": "You handle system administration tasks. Be careful with destructive operations. Always report what you did and what changed.",
    "tools": ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "LS"]
  }
}
```

## Step 7: (Optional) Set Up a Memory MCP Server

For persistent cross-session memory beyond Claude Code's built-in auto-memories, you have two options.

**Option A: File-based memory (simplest)**

No extra infrastructure. The CLAUDE.md from Step 4 already instructs the agent to use `~/agent/memory/` as a simple knowledge store. Auto-memories handle the rest.

**Option B: Custom MCP server**

For structured recall (key-value, semantic search, tagged memories), build or use an MCP server. A minimal approach with SQLite:

1. Create an MCP server that exposes `remember` and `recall` tools
2. Back it with SQLite in `~/agent/memory/memory.db`
3. Register it in `~/agent/mcp.json`:

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

This is a separate build step — spec it out and let Claude Code build it for you in a coding session.

## Step 8: Create the Launch Script

Create `~/agent/start.sh`:

```bash
#!/usr/bin/env bash

AGENT_HOME="$HOME/agent"

claude --claude-home "$AGENT_HOME/.claude" \
       --system-prompt-file "$AGENT_HOME/persona.md" \
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

## Step 9: Run It in a Persistent Session

The agent session must stay alive for Telegram messages to arrive. Use tmux or screen.

```bash
# Start a named tmux session
tmux new-session -d -s agent "$HOME/agent/start.sh"

# To attach and watch what's happening
tmux attach -t agent

# To detach without killing: Ctrl+B, then D
```

For auto-start on boot (macOS), create a LaunchAgent at `~/Library/LaunchAgents/com.agent.claude.plist`:

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

Load it:

```bash
launchctl load ~/Library/LaunchAgents/com.agent.claude.plist
```

## Step 10: Test It

1. Open Telegram on your phone
2. Message your bot: "Hi, what can you do?"
3. Watch the terminal (tmux attach) to see the message arrive and Claude respond
4. Try a real task: "Summarize the latest news about MCP servers"
5. Test file access: "What files do I have in my Documents folder?"
6. Test memory: "Remember that my preferred deployment day is Thursday"

---

## Directory Layout (Final)

```
~/agent/
├── .claude/
│   ├── settings.json          # Agent-specific settings
│   ├── CLAUDE.md              # Behavioral rules
│   ├── channels/
│   │   └── telegram/
│   │       └── .env           # Bot token
│   └── memory/                # Auto-memories (managed by Claude Code)
├── persona.md                 # System prompt — agent identity
├── agents.json                # Subagent definitions
├── mcp.json                   # MCP server configuration
├── skills/                    # Custom skills
├── memory/                    # Persistent memory files (Option A)
├── start.sh                   # Launch script
└── README.md                  # Your own notes
```

## What This Gives You vs. OpenClaw

| Capability | This setup | OpenClaw |
|---|---|---|
| Telegram access | ✅ native channel | ✅ grammY adapter |
| Other channels | ⚠️ limited to allowlist | ✅ 25+ channels |
| LLM quality | ✅ Opus/Sonnet direct | ✅ any provider |
| Subagents | ✅ via --agents | ✅ via skills |
| Persistent memory | ✅ auto-memories + custom | ✅ built-in |
| Skills ecosystem | ✅ build your own | ✅ 5400+ community |
| Infrastructure | ✅ zero — one CLI command | ⚠️ gateway + Node 22+ |
| Security surface | ✅ Anthropic-managed | ⚠️ self-managed |
| Cost | ✅ Pro/Max subscription | ⚠️ API keys per provider |
| Multi-user | ❌ single user | ✅ multi-user gateway |

## Known Limitations

- **Session persistence**: if the tmux session dies, Telegram messages are lost (not queued). Monitor with the LaunchAgent or a watchdog script.
- **No remote permission approval**: with `--dangerously-skip-permissions`, everything runs. Without it, permission prompts block in the terminal. The channels permission relay feature is new and may help here.
- **Context window**: long-running sessions accumulate context. The agent will auto-compact, but be aware that very old conversation context may be summarized away.
- **Channels research preview**: the plugin API may change before GA. Pin your Claude Code version if stability matters.
- **Single channel per session**: you can't run Telegram and Discord on the same session simultaneously (yet).

## Next Steps

- Build a custom memory MCP server for structured recall
- Add a calendar MCP server for scheduling awareness
- Create domain-specific skills in `~/agent/skills/`
- Experiment with `--model opus` for the main agent while keeping subagents on Sonnet
- Set up a watchdog script that restarts the tmux session if it dies
- Consider `--add-dir` for additional directories as your needs grow
