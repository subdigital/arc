# Tasks

## 1. Repository scaffolding

- [x] 1.1 Initialize the git repository. Add a `.gitignore` covering `.build/`, `build/` and `.swiftpm/`, plus a README stub with build and run instructions. Verify that `git status` is clean after the first commit.
- [x] 1.2 Create `Package.swift` with:
  - macOS 26, Swift 6 language mode
  - targets `ArcCore`, `ArcAgentKit`, `ArcMarkdown`, `arc` (executable) and `ArcApp` (executable), plus test targets `ArcCoreTests`, `ArcAgentKitTests` and `ArcMarkdownTests`
  - pinned dependencies: GRDB.swift, swift-argument-parser, modelcontextprotocol/swift-sdk, swift-markdown and HighlightSwift

  Add a placeholder source file to each target. Verify that `swift build` and `swift test` succeed.

## 2. Persistence foundation (ArcCore)

- [x] 2.1 Implement database opening:
  - Resolve the path from `ARC_DB_PATH`, defaulting to `~/Library/Application Support/Arc/arc.sqlite`.
  - Create the directory if it does not exist.
  - Configure `DatabasePool` with WAL, `foreign_keys`, a 5 s busy timeout and immediate write transactions.

  Verify with tests that the file is created at the override path and that `PRAGMA journal_mode` returns `wal`.
- [x] 2.2 Write migration `v1` with the `meta`, `project`, `ticket` and `comment` tables, their indexes and foreign-key actions, as given in design.md §3. Seed `next_ticket_number = 1`. Verify with a migration test on an empty DB.
- [x] 2.3 Refuse to open a database with unknown applied migrations, returning `ArcError.schemaTooNew`. Verify with a test that inserts a fake future migration ID.
- [x] 2.4 Define the `ArcError` codes and the `Codable` DTOs (`ProjectDTO`, `TicketDTO`, `CommentDTO`, epic progress) with a shared JSON encoder (ISO-8601 dates, sorted keys). Verify with a snapshot test of encoded fixtures.

## 3. Domain rules and services (ArcCore)

- [x] 3.1 Implement the project service: create, update, archive/unarchive and delete, with case-insensitive unique names. Verify with tests covering a duplicate-name `conflict` and that delete cascades to tickets and comments.
- [x] 3.2 Implement ticket creation:
  - Allocate a global number from `meta` inside the write transaction.
  - Default the status to Todo and the priority to None.
  - Reject blank titles and missing projects.
  - Validate the epic (same project) and the parent (must be a task; the subtask takes the parent's project).

  Verify with tests covering consecutive numbers across projects and every validation error.
- [x] 3.3 Implement ticket update with a `TicketPatch`. It sets `updated_at`, sets `completed_at` on entering Done/Canceled and clears it on reopening. Moving a task between projects moves its subtasks and clears a cross-project epic; moving an epic moves its tasks. Verify with tests for each spec scenario in the work-items move and completion requirements.
- [x] 3.4 Implement manual ordering with fractional `sort_key`: top on status change, before/after a neighbor, and renormalizing the bucket when the gap falls below 1e-6. Verify with tests for the reorder scenario and forced renormalization.
- [x] 3.5 Implement deletion. Deleting a task cascades to its subtasks, deleting an epic clears its tasks' `epic_id`, and numbers are never reused. Verify with tests: deleting ARC-9 means the next ticket is ARC-10.
- [x] 3.6 Implement comments: add a comment with author `user` or `agent`, reject blank bodies, and list oldest first. Add `updateComment(id, body:)` for task-list toggles; it also rejects blank bodies. Verify with tests.
- [x] 3.7 Implement `TicketQuery` filters:
  - project(s), kind, statuses, priorities, epic and parent
  - a text query over title, description and identifier
  - include-closed and limit
  - ordering by status order, then `sort_key`

  Also implement epic progress, which excludes Canceled. Verify with tests for each filter and the progress example (2 of 3).
- [x] 3.8 Implement lenient reference parsing:
  - tickets: `ARC-12`, `arc-12` or `12`
  - projects: names, ignoring case
  - statuses: `In Progress`, `in-progress` or `in_progress`
  - priorities

  A `not_found` for a project lists the existing project names. Verify with table-driven tests.
- [x] 3.9 Add a concurrency test: two `ArcStore` instances on the same file create 100 tickets in parallel tasks. Verify that all 200 exist with unique numbers 1–200.

## 4. CLI (`arc`)

- [x] 4.1 Implement the ArgumentParser root command, `GlobalOptions --json` and the output layer. In JSON mode, output is DTOs on stdout. In human mode, output is compact tables. Errors exit with code 1 (and print an error object in JSON mode); usage errors exit with code 64. Verify with an end-to-end test that runs `.build/debug/arc` with a temporary `ARC_DB_PATH`.
- [x] 4.2 Implement the `project list|create|update|archive|unarchive` commands. Verify with end-to-end tests and their JSON output.
- [x] 4.3 Implement `list` (all filters, `--all`, `--limit`) and `show`. Verify with tests that closed tickets are excluded by default and that `show` prints every field in the agent-interface JSON scenario.
- [x] 4.4 Implement `create` and `update`, including subtask creation with only `--parent`, and `--description -` reading stdin. Verify with end-to-end tests that pipe stdin.
- [x] 4.5 Implement `comment` (author `agent`, `-` reads stdin) and `delete`, which requires `--yes`. Verify with end-to-end tests, including that delete is refused without `--yes`.
- [x] 4.6 After each successful write, post the `com.ficklebits.arc.databaseDidChange` distributed notification. Verify with a test that observes the notification while running a CLI write.

## 5. MCP server and agent skill

- [ ] 5.1 Build the tool table in ArcAgentKit with the name, description, JSON Schema and handler for each tool: `list_projects`, `create_project`, `list_tickets`, `get_ticket`, `create_ticket`, `update_ticket` and `add_comment`. There is no delete tool. Verify with in-process handler tests, including `isError` for an invalid subtask parent.
- [ ] 5.2 Implement `arc mcp` using the SDK `Server` and `StdioTransport`, with server instructions, and write logs only to stderr. Verify with an end-to-end stdio test: `initialize`, then `tools/list` returns 7 tools, then `tools/call create_ticket` succeeds.
- [ ] 5.3 Write `skills/arc/SKILL.md`. It has `name: arc` frontmatter and covers the hierarchy, identifiers, statuses, the pick-up → In Progress → comment → In Review/Done workflow, a note that descriptions and comments are GitHub Flavored Markdown (task lists, code blocks with language tags, `ARC-12` references), and examples using both MCP and the CLI. Embed it as a constant in ArcAgentKit. Verify with a test that the constant matches the file byte for byte.
- [ ] 5.4 Implement `arc skill install [--dir] [--force]`. It defaults to `~/.claude/skills/arc/SKILL.md` and refuses to overwrite a different file without `--force`. Verify with tests using a temporary `--dir`.
- [ ] 5.5 Document CLI usage, MCP registration (`claude mcp add arc -- arc mcp`) and skill installation in the README. Verify that each documented command runs as written against a temporary DB.

## 6. App shell and theme (ArcApp)

- [ ] 6.1 Create the `@main` App with an app delegate that forces `darkAqua`, `.preferredColorScheme(.dark)` on every scene, and `AppModel` holding the `ArcStore`. Verify that the app launches dark while macOS is in Light mode.
- [ ] 6.2 Implement the `Theme` color and font tokens from design.md §7, plus the custom status and priority glyph views. Verify with a SwiftUI preview or debug gallery that shows all 6 status glyphs and 5 priority glyphs matching the app-appearance tables.
- [ ] 6.3 Implement `ChangeFeed`: in-process `DatabaseRegionObservation`, the distributed notification listener, and the `PRAGMA data_version` poll every 1 s (paused while inactive), debounced to 100 ms. Verify with a unit test that a write from a second `ArcStore` makes the feed tick within 2 s.
- [ ] 6.4 Implement the window layout:
  - `NavigationSplitView` with the sidebar (All Tasks, Epics, active projects sorted alphabetically, and a collapsed Archived section)
  - project create, rename and archive from the sidebar context menu
  - the first-run empty state with "Create Project"

  Verify manually against the sidebar and empty-state scenarios.
- [ ] 6.5 Implement `scripts/bundle.sh`. It builds a release, assembles `build/Arc.app` with `Contents/MacOS/ArcApp`, `Contents/Helpers/arc`, `Info.plist` (bundle ID `com.ficklebits.arc`) and a placeholder icon, then signs it ad hoc. Verify that `scripts/bundle.sh && open build/Arc.app` launches the app.

## 7. Markdown rendering (ArcMarkdown)

- [ ] 7.1 Build the render model: parse with swift-markdown (GFM) into `Sendable` `[MarkdownBlock]` covering headings, paragraphs, nested lists, task items with source ranges, code blocks with language, tables with alignment, quotes, rules and images. Inline runs are `AttributedString` (bold, italic, strikethrough, code, links, autolinks). Raw HTML is kept as literal text. Verify with `ArcMarkdownTests` fixtures for each block type, nesting and alignment.
- [ ] 7.2 Implement task toggling with `MarkdownSource.toggleTask(at:)`, which flips only the `[ ]`/`[x]` at the range and checks the range again if the source has changed. Verify with tests that the rest of the source is byte-identical after a toggle, including nested and numbered task items.
- [ ] 7.3 Implement ARC identifier linking. It turns `ARC-\d+` (any case) into `arc://ticket/<n>` links, only for known numbers and never inside code spans or blocks. Verify with tests covering a known ID, an unknown ID, inline code and a fenced block.
- [ ] 7.4 Implement the `CodeHighlighter` protocol with a HighlightSwift backend: lazy, off the main actor, cached by (language, code), with a dark theme mapped to Theme tokens, and a plain fallback for no or unknown language. Verify with tests that `swift` produces several colored runs and that `nosuchlang` returns plain text.
- [ ] 7.5 Implement the `ImageLoader` actor: `URLSession` plus an `NSCache` for the session, with `file:` URLs and absolute paths read from disk. Verify with tests using a `file:` fixture and a URL that fails, which must produce a failure state for the alt-text placeholder.
- [ ] 7.6 Implement `MarkdownView` in SwiftUI with Markdown styling from the Theme:
  - headings stepping down in size, links in the accent color
  - code blocks on the elevated surface, scrolling horizontally, with a copy button
  - tables with thin borders, blockquotes with a left bar
  - images scaled to fit, with an alt-text placeholder
  - clickable checkboxes that call back with a toggle
  - `arc://` links routed through `openURL`, and other URLs sent to the default browser

  Verify with a debug gallery of a GFM kitchen-sink document checked against the issue-views Markdown scenarios and the app-appearance Markdown styling scenario.

## 8. Ticket views (ArcApp)

- [ ] 8.1 Implement `TicketListModel`: the query built from the sidebar selection plus filters (projects in All Tasks, epic, priority, show subtasks/canceled), refetching on `ChangeFeed`. View settings are kept per sidebar entry in `@AppStorage`. Verify with unit tests of query construction and the persistence round-trip.
- [ ] 8.2 Implement the status-grouped list:
  - collapsible headers with glyph and count, hiding empty groups, with Done and Canceled collapsed by default
  - Linear-style rows with the fields in spec order and indented subtasks
  - hover and selection styling

  Verify manually against the issue-views list scenarios and the row-density scenario.
- [ ] 8.3 Implement the board: status columns (Canceled hidden by default), cards, and drag and drop with a before/after position that calls `moveTicket`. Verify manually that dragging ARC-5 to the top of In Progress updates both its status and its order.
- [ ] 8.4 Implement the filter bar and the layout toggle (toolbar control + Cmd-B), keeping filters across the toggle. Verify manually against the toggle and filter-persistence scenarios.
- [ ] 8.5 Implement the Epics overview, grouped by project with progress bars, and the epic drill-down list. Verify manually that an epic with 2 Done, 1 Todo and 1 Canceled shows 2/3.
- [ ] 8.6 Implement the ticket detail page:
  - editable title, and a Markdown description using `MarkdownView` (click to edit the raw source; Escape or blur saves)
  - subtasks with inline add
  - comments rendered with `MarkdownView`, showing an author badge, with a Markdown composer
  - task-list toggles in descriptions and comments saved through `updateTicket` and `updateComment`
  - a properties panel with menus for status, priority, project, epic and parent
  - navigation to the parent

  Verify manually against the detail and Markdown editing scenarios, and that ticking a checkbox in a comment saves the change to the stored text.
- [ ] 8.7 Implement the creation sheet (C or toolbar; Cmd-Return to save, Escape to cancel; defaults to the current project), keyboard navigation (arrows, J/K, Return, S, P, Cmd-Delete with confirmation, Escape back) and the row/card context menus (including Copy ID). Verify manually against the keyboard, create and context-menu scenarios.

## 9. Agent settings pane (ArcApp)

- [ ] 9.1 Implement the Settings "Agents" pane:
  - "Install Command Line Tool": a symbolic link to `/usr/local/bin/arc`, falling back to `~/.local/bin/arc`, with an indicator of whether the directory is on PATH
  - the MCP command, ready to copy
  - an "Install Skill" button

  Verify manually from the bundled app that `which arc` resolves and `arc list` works.

## 10. Integration verification

- [ ] 10.1 Run the full suite with `swift test`. Verify that it passes with no warnings under Swift 6 strict concurrency.
- [ ] 10.2 With the bundled app open on the board, have an agent session (MCP registered) create a ticket, move it to In Progress and comment on it. Verify that each change appears in the app within 2 seconds and that the comment shows the agent badge.
- [ ] 10.3 Walk through the issue-views and app-appearance spec scenarios in the bundled app. Fix any mismatches and record the results in the PR description.
