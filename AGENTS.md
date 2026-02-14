# Instructions for AI Agents Working on Efrit

> **For humans**: This file contains instructions for AI coding assistants. See [README.md](README.md) for user documentation.

## Project Overview

**Efrit** is an AI-powered Emacs coding assistant built on the **Zero Client-Side Intelligence** principle: Efrit is a pure executor that delegates ALL cognitive computation to Claude.

## Core Architectural Principle

**ZERO CLIENT-SIDE INTELLIGENCE**: Efrit must NEVER contain:
- Pattern recognition or parsing logic
- Decision-making heuristics
- Pre-written solutions or templates
- Task-specific logic
- Flow control decisions

Efrit's ONLY job: execute what Claude tells it to do. See [ARCHITECTURE.md](ARCHITECTURE.md) for details.

## 🚨 COMMIT AND PUSH AFTER EVERY FIX 🚨

**This is the most important rule.** After completing ANY task:

```bash
git add -A
git commit -m "Descriptive message"
git push
```

Do NOT batch multiple fixes. Do NOT wait until "end of session". Push immediately after each completed task.

## Issue Tracking with Beads

This project uses **br (beads_rust)** for ALL issue tracking. Do NOT use markdown TODOs or other tracking methods.

**Note:** `br` is non-invasive and never executes git commands. After `br sync --flush-only`, you must manually run `git add .beads/ && git commit`.

```bash
br ready                              # Find unblocked work
br create "Title" -t bug|feature|task -p 0-4
br update <id> --status in_progress
br close <id> --reason "Done"
br sync --flush-only                  # Export to JSONL (no git)
git add .beads/
git commit -m "sync beads"
```

**Issue Types**: bug, feature, task, epic, chore  
**Priorities**: 0=Critical, 1=High, 2=Medium, 3=Low, 4=Backlog

## Development Workflow

### Before Making Changes
1. Check ready work: `br ready`
2. Claim task: `br update <id> --status in_progress`

### After Each Fix
1. Compile: `make compile`
2. Commit and push immediately
3. Close issue: `br close <id> --reason "Done"`

### Verification Requirements

**YOU MUST VERIFY ALL CHANGES BEFORE REPORTING COMPLETION.**

Acceptable:
- ✅ `make compile` passes
- ✅ `emacs --batch` execution without errors
- ✅ Actual API calls for efrit-chat/efrit-do changes

Unacceptable:
- ❌ "The code looks correct"
- ❌ "This should work"
- ❌ Reading code and assuming it works

## Code Standards

- Use `lexical-binding: t` in all elisp files
- Use `efrit-` prefix for public functions
- Use `efrit--` (double dash) for private functions
- Docstrings required for all functions
- NO client-side intelligence

## Project Structure

```
efrit/
├── lisp/
│   ├── efrit.el              # Main entry point
│   ├── core/                 # Core functionality
│   │   ├── efrit-chat.el     # Chat interface
│   │   ├── efrit-tools.el    # Tool implementations
│   │   ├── efrit-session.el  # Session management
│   │   └── efrit-do-schema.el # Tool schemas
│   ├── interfaces/           # User-facing interfaces
│   │   ├── efrit-do.el       # Command execution
│   │   ├── efrit-agent.el    # Agent mode
│   │   └── efrit-remote-queue.el # AI-to-AI queue
│   ├── tools/                # Individual tool implementations
│   └── support/              # UI helpers (dashboard, todos)
├── test/                     # Test files
├── docs/                     # Documentation
├── mcp/                      # MCP server (TypeScript/Node)
├── .beads/                   # Issue tracker database
└── ARCHITECTURE.md           # Core design principles
```

## Key Files

- **ARCHITECTURE.md** - Pure Executor principle (READ FIRST)
- **lisp/interfaces/efrit-do.el** - Main command execution
- **lisp/core/efrit-do-schema.el** - Tool definitions
- **lisp/core/efrit-tools.el** - Tool system prompt and utilities

## Common Tasks

**Adding a new tool**:
1. Add handler to `lisp/tools/efrit-tool-*.el`
2. Add schema to `lisp/core/efrit-do-schema.el`
3. Add dispatch entry in `lisp/interfaces/efrit-do.el`

**Fixing a bug**:
1. `br create "Bug: description" -t bug -p 1`
2. Fix the bug
3. `make compile`
4. Commit and push
5. `br close <id> --reason "Fixed"`

### Planning Work with Dependencies

When breaking down large features into tasks, use **beads dependencies** to sequence work - NOT phases or numbered steps.

**⚠️ COGNITIVE TRAP: Temporal Language Inverts Dependencies**

Words like "Phase 1", "Step 1", "first", "before" trigger temporal reasoning that **flips dependency direction**. Your brain thinks:
- "Phase 1 comes before Phase 2" → "Phase 1 blocks Phase 2" → `br dep add phase1 phase2`

But that's **backwards**! The correct mental model:
- "Phase 2 **depends on** Phase 1" → `br dep add phase2 phase1`

**Solution: Use requirement language, not temporal language**

Instead of phases, name tasks by what they ARE, and think about what they NEED:

```bash
# ❌ WRONG - temporal thinking leads to inverted deps
br create "Phase 1: Create buffer layout" ...
br create "Phase 2: Add message rendering" ...
br dep add phase1 phase2  # WRONG! Says phase1 depends on phase2

# ✅ RIGHT - requirement thinking
br create "Create buffer layout" ...
br create "Add message rendering" ...
br dep add msg-rendering buffer-layout  # msg-rendering NEEDS buffer-layout
```

**Verification**: After adding deps, run `br blocked` - tasks should be blocked by their prerequisites, not their dependents.

**Example breakdown** (for a multi-part feature):
```bash
# Create tasks named by what they do, not what order they're in
br create "Implement conversation region" -t task -p 1
br create "Add header-line status display" -t task -p 1
br create "Render tool calls inline" -t task -p 2
br create "Add streaming content support" -t task -p 2

# Set up dependencies: X depends on Y means "X needs Y first"
br dep add header-line conversation-region    # header needs region
br dep add tool-calls conversation-region     # tools need region
br dep add streaming tool-calls               # streaming needs tools

# Verify with br blocked - should show sensible blocking
br blocked
```

## Testing

```bash
# Compile all elisp
make compile

# Run tests (if available)
make test

# Quick elisp check
emacs --batch --eval "(progn (require 'efrit) (message \"OK\"))"
```

## Rules Summary

### ✅ DO:
- Commit and push after EVERY fix
- Use br for all task tracking
- Verify changes compile before reporting done
- Keep changes minimal and focused

### ❌ DO NOT:
- Batch commits until end of session
- Add client-side intelligence
- Create files without reading existing code first
- Skip compilation verification

---

**Remember**: Efrit is a Pure Executor. Claude thinks, Efrit executes.
