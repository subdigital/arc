# Proposal

## Why

Linear is more tool than a single person needs, it is web-based, and AI agents cannot easily work with it on the local machine. Arc is a lightweight native Mac issue tracker for one person, built so that the person and their coding agents work from the same board. This repository is empty, so this change sets up the whole first version.

## What Changes

- New native macOS app ("Arc"), built with SwiftUI. It always uses a dark theme and closely follows Linear's look: a dense sidebar, status and priority glyphs, and keyboard-first interaction.
- A work hierarchy: **Projects** contain **Epics** and **Tasks**. A task can optionally belong to an epic. A task can have **Subtasks** (one level deep).
- Every ticket (epic, task or subtask) gets a permanent, globally unique, readable identifier from one shared counter: `ARC-1`, `ARC-2`, and so on. Identifiers are never reused.
- A fixed, Linear-style workflow: Backlog, Todo, In Progress, In Review, Done, Canceled. Linear-style priorities: None, Urgent, High, Medium, Low.
- Comments on tickets, each recording whether it came from the user or an agent, so agents can leave progress notes.
- Full GitHub Flavored Markdown rendering for descriptions and comments:
  - headings, lists, tables, blockquotes and images
  - code blocks with syntax highlighting
  - task-list checkboxes that can be clicked
  - `ARC-12` identifiers that link to their tickets
- Views:
  - A **list view** grouped by status that can be filtered by project.
  - A **board view** with one column per status and drag-and-drop to change status and order.
  - A ticket detail page.
  - An epics overview with progress.
- A single local SQLite database. The app and the agent tooling share it, and the app updates live when an agent makes a change.
- Agent-first access through one `arc` command-line tool:
  - Scriptable commands with `--json` output.
  - `arc mcp`, a Model Context Protocol server over stdio.
  - An installable agent skill (`SKILL.md`) that teaches agents the workflow.
- Out of scope for v1: multiple users, assignment, labels, cycles, due dates, custom workflows, sync or iCloud, notifications, attachments, a command palette, and light mode.

## Capabilities

### New Capabilities

- `work-items`: Projects, epics, tasks and subtasks. Covers their fields, how they nest, statuses and priorities, global ticket identifiers, ordering, comments, and the rules for deleting and moving items.
- `local-storage`: The on-disk database. Covers its location and override, safe access from the app and the CLI at the same time, schema migrations, and notifying the app when another process changes data.
- `issue-views`: The app's main window. Covers sidebar navigation, the status-grouped list, project filtering, the board, the epics overview, the ticket detail page, Markdown rendering and editing, creating and editing tickets, and keyboard shortcuts.
- `app-appearance`: The forced dark theme and the Linear-like visual language: colors, typography, density, the status and priority glyphs, and Markdown styling.
- `agent-interface`: The `arc` CLI, the `arc mcp` server and its tools, the agent skill and how to install it, and how agents identify projects and tickets.

### Modified Capabilities

None. This is the first change in the repository.

## Impact

- New Swift package at the repository root, with three parts:
  - `ArcCore`: the domain model and persistence library.
  - `Arc`: the SwiftUI app.
  - `arc`: the CLI and MCP server executable.
- A script assembles the signed `.app` bundle.
- New dependencies:
  - GRDB.swift (SQLite)
  - swift-argument-parser
  - the official MCP Swift SDK (`modelcontextprotocol/swift-sdk`)
  - Apple's `swift-markdown` (a GFM parser)
  - a syntax-highlighting library
- Requires macOS 26+ and the Swift 6 toolchain. The app is not sandboxed, so that it and the CLI can share one database in `~/Library/Application Support/Arc/`.
