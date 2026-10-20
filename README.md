# Arc

A lightweight native macOS issue tracker for one person and their coding agents.

- **Projects** contain **tickets**; any ticket can have a **parent** (to any depth), so there are no separate epics, tasks or subtasks.
- Every ticket gets a permanent identifier (`ARC-1`, `ARC-2`, …) from one global counter. Tickets imported from another tracker keep their own key (`FIC-123`).
- One local SQLite database is shared by the app and the `arc` command-line tool, so what an agent does shows up in the app within a couple of seconds.
- Agents work through the `arc` CLI, an MCP server (`arc mcp`) or an installable skill.

## Requirements

- macOS 26+
- Swift 6 toolchain (Xcode 26 or newer)

## Build and run

```sh
swift build            # build everything
swift test             # run the test suite
scripts/bundle.sh      # assemble build/Arc.app
open build/Arc.app
```

For development, `scripts/dev.sh` watches `Sources/`, rebuilds on each change and relaunches the debug app. The app remembers the screen you were on, so a change is a short blink. If a build fails, the running app stays up and the errors are printed.

The app is signed ad hoc for local use. If you copy it to another Mac, Gatekeeper will ask for confirmation the first time.

## Data location

All data lives in one SQLite file: `~/Library/Application Support/Arc/arc.sqlite`. Set `ARC_DB_PATH` to use a different file (both the app and the CLI honor it), which is handy for trying things out:

```sh
export ARC_DB_PATH=/tmp/arc-demo/arc.sqlite
```

## Command-line tool

Install it from the app (Settings → Agents → Install Command Line Tool), or put `.build/debug/arc` / `Arc.app/Contents/Helpers/arc` on your `PATH`.

Tickets are referred to as `ARC-12`, `arc-12` or just `12` (imported tickets keep their own key, e.g. `FIC-123`); projects by name (any case). Statuses are `backlog`, `todo`, `in_progress`, `in_review`, `done`, `canceled` (`"In Progress"` and `in-progress` work too); priorities are `none`, `urgent`, `high`, `medium`, `low`.

```sh
arc project create Website --description "Marketing site"
arc project list
arc project update Website --name Site
arc project archive Site
arc project unarchive Site

arc create --project Site --title "Fix footer" --priority high
arc create --project Site --title "Launch"
arc create --parent ARC-2 --title "Hero image"      # child of ARC-2; the project comes from the parent
arc list --project Site                            # open tickets only
arc list --project Site --status "In Progress"
arc list --all --limit 20                          # include Done and Canceled
arc show ARC-1
arc update ARC-1 --status "In Progress"
arc update ARC-1 --parent none
arc comment ARC-1 "Parser done, starting tests"    # recorded as written by an agent
arc create --project Site --title "Fix nav" --label bug --label mobile   # labels are created when first used
arc relate ARC-1 blocks ARC-2                      # blocks, blocked_by, related, duplicate_of, duplicated_by
arc attach ARC-1 --url https://github.com/org/repo/pull/7 --title "PR"
arc attach ARC-1 --file ~/Desktop/screenshot.png   # copied next to the database
arc milestone create Site "Beta" --target 2026-12-31
arc list --project Site --label bug --milestone Beta
arc delete ARC-4 --yes
```

Long text can be piped in with `-`:

```sh
echo "Steps to reproduce..." | arc update ARC-1 --description -
echo "Multi-line note" | arc comment ARC-1 -
```

Add `--json` to any data command for machine-readable output. Errors then look like `{"error": {"code": "not_found", "message": "..."}}` on stdout. Exit status is 0 on success, 1 on errors and 64 on usage errors. Run `arc --help` or `arc <command> --help` for every option.

## MCP server

`arc mcp` runs a [Model Context Protocol](https://modelcontextprotocol.io) server over stdio. Register it with Claude Code:

```sh
claude mcp add arc -- arc mcp
```

Tools: `list_projects`, `create_project`, `list_tickets`, `get_ticket`, `create_ticket`, `update_ticket`, `add_comment`, `add_relation`, `remove_relation` and `add_link`. There is deliberately no delete tool; agents cancel unwanted work instead.

## Agent skill

The skill (`skills/arc/SKILL.md`) teaches an agent the ticket hierarchy and the workflow: pick up a ticket, set it to In Progress, leave progress comments, finish in In Review or Done.

```sh
arc skill install                  # writes ~/.claude/skills/arc/SKILL.md
arc skill install --dir ./skills   # writes ./skills/arc/SKILL.md
arc skill install --force          # overwrite a different, existing file
```

The skill text is embedded in the `arc` binary. After editing `skills/arc/SKILL.md`, run `scripts/embed-skill.sh` to regenerate `Sources/ArcAgentKit/SkillText.swift` (a test fails if they drift apart).

## Importing from Linear

`arc import linear <folder>` reads an export folder (`projects.json`, `teams.json` and `issues-*.json`, as written by the export step described in `openspec`/the project notes) and creates projects, milestones, labels, tickets with their original keys (`FIC-123`), parents, relations, comments with their threads, link attachments and downloaded uploads.

It is safe to run again:

```sh
arc import linear import/linear --dry-run   # report only; nothing is written
arc import linear import/linear             # create new, update changed, skip unchanged
arc import linear import/linear --force     # also overwrite tickets you edited in Arc since the last import
arc import linear --reset --yes             # remove everything an import created, then start over
```

Every imported item carries an external id and a content fingerprint. A re-run leaves tickets you edited in Arc alone (and says so), never removes comments, labels or relations you added yourself, and ends with a verification pass that compares the database with the export; the exit status is 1 if anything does not match. Uploads hosted by Linear are saved under `attachments/linear` next to the database.
