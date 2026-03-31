#!/usr/bin/env bash
set -euo pipefail

# --- Usage ---
usage() {
  cat <<'USAGE'
Usage: sh claudette.sh -d <directory>

Scaffolds a Claude-native personal agent directory with all config files
and a launch script for running Claude Code as a Telegram-connected agent.

Options:
  -d <dir>   Target directory to scaffold (required)
  -h         Show this help message

Example:
  sh claudette.sh -d .
  sh claudette.sh -d ~/agent
USAGE
  exit 1
}

# --- Parse args ---
TARGET_DIR=""
while getopts "d:h" opt; do
  case $opt in
    d) TARGET_DIR="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done
[ -z "$TARGET_DIR" ] && usage

# --- Resolve path ---
if [ -e "$TARGET_DIR" ] && [ ! -d "$TARGET_DIR" ]; then
  echo "Error: $TARGET_DIR exists but is not a directory"
  exit 1
fi
mkdir -p "$TARGET_DIR"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# --- Helper ---
CREATED=0
SKIPPED=0

create_file() {
  local filepath="$1"
  local content="$2"
  if [ -f "$filepath" ]; then
    echo "  SKIP (exists): $filepath"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi
  mkdir -p "$(dirname "$filepath")"
  printf '%s\n' "$content" > "$filepath"
  echo "  CREATE: $filepath"
  CREATED=$((CREATED + 1))
  return 0
}

# --- Create directories ---
echo "Scaffolding agent directory: $TARGET_DIR"
echo ""

for dir in ".claude/memory" "skills" "memory"; do
  dirpath="$TARGET_DIR/$dir"
  if [ -d "$dirpath" ]; then
    echo "  SKIP (exists): $dirpath/"
  else
    mkdir -p "$dirpath"
    echo "  CREATE: $dirpath/"
  fi
done

# --- .claude/settings.json ---
create_file "$TARGET_DIR/.claude/settings.json" '{
  "model": "sonnet",
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
  },
  "spinnerTipsEnabled": false,
  "promptSuggestionEnabled": false,
  "cleanupPeriodDays": 99999,
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "0",
    "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1",
    "CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL": "1",
    "DISABLE_ERROR_REPORTING": "1",
    "DISABLE_FEEDBACK_COMMAND": "1",
    "DISABLE_TELEMETRY": "1",
    "DISABLE_INSTALLATION_CHECKS": "1",
    "IS_DEMO": "1",
    "TELEGRAM_STATE_DIR": "'"$TARGET_DIR"'/.claude/channels/telegram"
  }
}'

# --- .claude/CLAUDE.md ---
create_file "$TARGET_DIR/.claude/CLAUDE.md" '# Agent Behavioral Rules

## File Access

You have access to the user'\''s Documents and notes directories.
Treat these as read-first — only modify files when explicitly asked.

## Memory

When the user shares personal preferences, project context, or important facts,
store them in ~/agent/memory/ as individual markdown files with descriptive names.
Check this directory at the start of relevant tasks for prior context.

## Task Execution

For multi-step tasks:
1. State what you will do
2. Execute
3. Report the result concisely

For quick questions: just answer.

## Safety

- Never delete files outside ~/agent/ without explicit confirmation
- Never expose API keys, tokens, or credentials in Telegram messages
- If a task seems destructive, confirm before proceeding'

# --- persona.md ---
create_file "$TARGET_DIR/persona.md" '# Agent Identity

You are a general-purpose personal AI assistant accessible via Telegram.
You are not a coding assistant — you are a knowledgeable, resourceful companion
that can help with research, planning, writing, analysis, file management,
and any task a capable human assistant would handle.

## Behavior

- Be concise in Telegram replies — phone screens are small
- When a task requires multiple steps, outline your plan before executing
- Use web search proactively for current information
- If you don'\''t know something, say so — never fabricate
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
- Match the formality level of the user'\''s message'

# --- agents.json ---
create_file "$TARGET_DIR/agents.json" '{
  "researcher": {
    "description": "Deep research on any topic with web search",
    "prompt": "You are a thorough researcher. Search the web, read full pages with WebFetch when needed, synthesize findings, and cite sources. Be comprehensive but organized.",
    "tools": ["WebFetch", "WebSearch", "Bash", "Read", "Write"]
  },
  "writer": {
    "description": "Drafting and editing text — emails, articles, documents",
    "prompt": "You are a skilled writer and editor. Match the user'\''s intended tone and audience. Produce clean, publishable text. When editing, explain your changes briefly.",
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
}'

# --- mcp.json ---
create_file "$TARGET_DIR/mcp.json" '{
  "mcpServers": {}
}'

# --- start.sh ---
create_file "$TARGET_DIR/start.sh" '#!/usr/bin/env bash
AGENT_HOME="$(cd "$(dirname "$0")" && pwd)"
export CLAUDE_CONFIG_DIR="$AGENT_HOME/.claude"

claude --system-prompt "$(cat "$AGENT_HOME/persona.md")" \
       --dangerously-skip-permissions \
       --channels plugin:telegram@claude-plugins-official \
       --add-dir "$HOME/Documents" \
       --add-dir "$HOME/notes" \
       --mcp-config "$AGENT_HOME/mcp.json" \
       --agents "$(cat "$AGENT_HOME/agents.json")"'

chmod +x "$TARGET_DIR/start.sh"

# --- Summary ---
echo ""
echo "Done! Created $CREATED files, skipped $SKIPPED."
echo ""
echo "Directory: $TARGET_DIR"
echo ""
echo "Next steps:"
echo "  1. Create a Telegram bot via @BotFather and copy the token"
echo "  2. Install the Telegram plugin:"
echo "       claude plugin install telegram@claude-plugins-official"
echo "  3. Edit persona.md to customize your agent's personality"
echo "  4. Launch in tmux:"
echo "       tmux new-session -d -s agent \"$TARGET_DIR/start.sh\""
