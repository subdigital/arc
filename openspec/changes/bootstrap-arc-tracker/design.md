# Design

## Context

The repository is empty apart from OpenSpec scaffolding. The toolchain on this machine is Xcode 27 with Swift 6.4, running macOS 27. Neither XcodeGen nor Tuist is installed. There is one user and one machine, and all data is local (see proposal.md). The behavioral contract is in the five capability specs; this document covers how to build it.

The main architectural pressure is that **two kinds of process share one data store**: the long-running SwiftUI app, and short-lived `arc` processes started by agents (CLI calls, or `arc mcp` sessions). Both kinds must apply exactly the same domain rules.

## Goals / Non-Goals

**Goals:**
- One domain and persistence library used by the app, the CLI and the MCP server, so that validation is written once.
- The whole project builds, tests and packages from the command line (`swift build`, `swift test`, `scripts/bundle.sh`), so that agents can develop Arc itself without Xcode GUI steps.
- Swift 6 language mode with strict concurrency, from the start.
- The app reflects agent edits within 2 seconds.

**Non-Goals:**
- Mac App Store distribution and App Sandbox.
- Notarization or Developer ID signing. An ad-hoc signature is enough for local use.
- Full-text search indexing. `LIKE` queries are enough at single-user scale.
- Undo/redo beyond what text fields give for free.

## Decisions

### 1. SwiftPM-only repository, with a bundling script

```
Package.swift                 platforms: [.macOS(.v26)], swiftLanguageModes: [.v6]
Sources/ArcCore/              domain model, persistence, services, JSON DTOs
Sources/ArcAgentKit/          CLI command implementations + MCP tool handlers
Sources/arc/                  thin executable: ArgumentParser root -> ArcAgentKit
Sources/ArcMarkdown/          GFM parse -> render model + SwiftUI renderer (library)
Sources/ArcApp/               SwiftUI app (executable target "ArcApp")
Tests/ArcCoreTests/, Tests/ArcAgentKitTests/, Tests/ArcMarkdownTests/
Resources/Info.plist, Resources/AppIcon.icns
skills/arc/SKILL.md           source of truth for the agent skill
scripts/bundle.sh             builds release + assembles build/Arc.app
```

`scripts/bundle.sh` does the following:
1. Runs `swift build -c release`.
2. Assembles `Arc.app/Contents/MacOS/ArcApp`, `Contents/Helpers/arc`, `Info.plist` and the icon.
3. Signs the helper ad hoc, then signs the app ad hoc (`codesign -s -`).

The app executable is called `ArcApp` rather than `Arc`. APFS is case-insensitive by default, so an `Arc` binary and an `arc` binary would collide in `.build/release/`. For the same reason the CLI goes in `Contents/Helpers/` and not next to the app binary.

*Alternatives considered:*
- **An Xcode project:** a hand-written `.pbxproj` is fragile and hard for agents to edit.
- **XcodeGen or Tuist:** adds a tool that is not installed, for little gain, since the app needs no asset catalogs or extensions.

### 2. SQLite through GRDB.swift instead of SwiftData or Core Data

GRDB is a good fit for several reasons:
- It gives explicit control over WAL mode, `busy_timeout`, `BEGIN IMMEDIATE` transactions and `DatabaseMigrator`.
- It has ergonomic `Codable` records and `ValueObservation`.
- It works the same way in a CLI and in an app.

SwiftData does not support safe multi-process writers, and it is awkward without a model container in a command-line tool. Core Data has the same multi-process problems and needs more ceremony.

The database is configured as follows:
- `DatabasePool` with `journal_mode=WAL` and `foreign_keys=ON`.
- `busyMode = .timeout(5)`.
- Write transactions default to `.immediate`, so concurrent writers serialize at `BEGIN` instead of failing at commit time.
- The path is `ARC_DB_PATH`, or `~/Library/Application Support/Arc/arc.sqlite` when that is not set.

### 3. Schema

```
meta(key TEXT PK, value TEXT)                    -- 'next_ticket_number', 'schema' handled by GRDB migrator
project(id TEXT PK uuid, name TEXT, name_key TEXT UNIQUE,   -- name_key = lowercased, trimmed
        description TEXT, color TEXT, archived_at REAL NULL,
        created_at REAL, updated_at REAL)
ticket(id TEXT PK uuid, number INTEGER UNIQUE NOT NULL,
       kind TEXT CHECK(kind IN ('epic','task','subtask')),
       project_id TEXT NOT NULL REFERENCES project ON DELETE CASCADE,
       epic_id   TEXT NULL REFERENCES ticket ON DELETE SET NULL,
       parent_id TEXT NULL REFERENCES ticket ON DELETE CASCADE,
       title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
       status TEXT NOT NULL, priority INTEGER NOT NULL,
       sort_key REAL NOT NULL,
       created_at REAL, updated_at REAL, completed_at REAL NULL)
comment(id TEXT PK uuid, ticket_id TEXT NOT NULL REFERENCES ticket ON DELETE CASCADE,
        body TEXT NOT NULL, author TEXT CHECK(author IN ('user','agent')), created_at REAL)
indexes: ticket(project_id, status, sort_key), ticket(epic_id), ticket(parent_id)
```

The schema relies on foreign-key actions for these behaviors:
- `ON DELETE CASCADE` on `project_id` and `parent_id` implements "deleting a project deletes its tickets" and "deleting a task deletes its subtasks".
- `ON DELETE SET NULL` on `epic_id` implements "deleting an epic keeps its tasks".

The service layer still checks the hierarchy rules, such as "a parent must be a task" and "an epic must be in the same project". Those rules depend on rows other than the one being written, so `CHECK` constraints cannot express them.

**Ticket numbers** come from `meta.next_ticket_number`, incremented inside the same immediate write transaction that inserts the ticket. Using `MAX(number)+1` was rejected because it would reuse the number of a deleted top ticket. The `ARC-` prefix is a display concern only; the number is what gets stored.

**Ordering** uses a fractional `REAL` `sort_key`, scoped by status:
- Insert at the top: `min - 1`.
- Insert between two tickets: the midpoint of their keys.
- When the gap between neighbors falls below `1e-6`, renumber that status bucket to `1, 2, 3, …` in the same transaction.

*Alternatives considered:* string LexoRank keys never need renumbering, but they are more code for no benefit at this scale. Integer positions with shifting would rewrite many rows on every drag.

A subtask stores `epic_id = NULL`. Its epic is derived from its parent when it is displayed.

### 4. Service layer in ArcCore owns all rules

`ArcStore` is a `final class` and `Sendable`. It wraps the `DatabasePool` and exposes async methods:
- `createProject`, `updateProject`, `deleteProject`
- `createTicket(NewTicket)`, `updateTicket(id, TicketPatch)`, `moveTicket(id, status:, before:/after:)`, `deleteTicket`
- `addComment`
- `tickets(matching: TicketQuery)`, `ticketDetail(ref)`, `epicsWithProgress()`

Reference resolution (`ARC-12`, `12`, project names, lenient status strings) lives here too, in `Reference` parsers. The app, the CLI and MCP therefore all accept the same inputs.

Errors are a single `ArcError` with a stable `code`: `not_found`, `invalid_argument`, `conflict`, `database_busy` or `schema_too_new`. It also carries a human-readable message. The CLI and MCP serialize this directly.

The JSON shapes (`TicketDTO`, `ProjectDTO`, `CommentDTO`) are `Codable` structs in ArcCore with camelCase keys. `ProjectDTO` and the epic summary use `{id, name}` and `{identifier, title}` references. The same encoder settings (ISO-8601 dates, sorted keys) are used everywhere, so CLI and MCP output is identical.

### 5. Cross-process change propagation

GRDB's `ValueObservation` sees only commits made through the same `DatabasePool`, so the app combines three signals into a single `ChangeFeed` (`AsyncStream<Void>`):
1. **In-process commits:** a `DatabaseRegionObservation` on all tables.
2. **Distributed notification:** after every successful write, `arc` posts `com.ficklebits.arc.databaseDidChange` through `DistributedNotificationCenter`. The app listens for it.
3. **Polling fallback:** every 1 s, the app reads `PRAGMA data_version`. This value changes when another connection commits. It catches writers that crash before posting, and anything else that edits the file.

View models refetch their query whenever the feed ticks, debounced to 100 ms. At single-user scale, a full refetch of one view's tickets takes well under 10 ms, so diffing is unnecessary.

*Alternatives considered:*
- **A file-system watcher on the WAL file:** noisy, and it fires on checkpoints too.
- **The app as a server that the CLI talks to over XPC:** that would make the CLI depend on the app running, which breaks headless agent use.

### 6. App architecture (SwiftUI, macOS 26)

- **Model layer:** `@Observable @MainActor` models:
  - `AppModel`: store, change feed, sidebar selection.
  - `TicketListModel`: one per sidebar entry; holds the query, filters and grouped results.
  - `TicketDetailModel`.
- **Window structure:** `NavigationSplitView`, with the sidebar (All Tasks, Epics, Projects, Archived) on the left and a `NavigationStack` for the content. Pushing a `TicketRoute` shows the detail page, and the back control and Escape pop it.
- **List:** `List(selection:)` with collapsible `Section`s per status, custom row views, hidden separators and custom row backgrounds. This keeps native keyboard selection and type-to-select, and Theme colors give the Linear look. J/K and S/P are added with `.onKeyPress`.
- **Board:** a horizontal `ScrollView` of fixed-width (280 pt) columns. Each column is a `LazyVStack` of cards. Cards use `.draggable(TicketDragItem)`, where `TicketDragItem` is `Transferable` and carries the ticket ID, and drop zones use `.dropDestination`. The drop position is computed from the card frames to find the before/after neighbor.
- **Detail page:** an `HStack` with a flexible main column and a 260 pt properties panel. The description and comments use `MarkdownView` from ArcMarkdown (Decision 12). Clicking the rendered description swaps it for a `TextEditor` showing the raw source. Edits are saved on blur or Escape, and also after 500 ms of debounce.
- **Persisted view settings:** stored with `@AppStorage`, as a JSON dictionary keyed by sidebar selection. The settings are layout, filters, collapsed groups and "show subtasks/canceled".
- **Dark appearance:** forced with `NSApp.appearance = NSAppearance(named: .darkAqua)` in the app delegate, plus `.preferredColorScheme(.dark)` on every scene, so sheets, menus and popovers inherit it.
- **Settings:** a `Settings` scene with an "Agents" pane. "Install CLI" first tries `/usr/local/bin/arc`. If that directory is not writable, it falls back to `~/.local/bin/arc`. It never escalates privileges.

### 7. Theme and glyphs

A `Theme` namespace holds the color tokens (see the table below) and font tokens: 13 pt regular for rows, 12 pt for metadata, and medium weight for headers.

Status and priority glyphs are custom SwiftUI `Shape`/`Canvas` views, 14×14 pt. SF Symbols are not used because they cannot match Linear's dashed and partly filled circles.

| Token | Hex |
| --- | --- |
| `bgSidebar` | `#0E0E10` |
| `bgContent` | `#121214` |
| `bgElevated` | `#1A1A1E` |
| `bgHover` | `#1F1F24` |
| `bgSelected` | `#26262C` |
| `border` | `#26262B` |
| `textPrimary` | `#E6E6EA` |
| `textSecondary` | `#8A8F98` |
| `textTertiary` | `#5C6068` |
| `accent` | `#5E6AD2` |
| `yellow` | `#F2C94C` |
| `green` | `#4CB782` |
| `urgent` | `#F2994A` |

### 8. CLI with swift-argument-parser

The root command is `AsyncParsableCommand` `arc`, with these subcommands:
- `project (list|create|update|archive|unarchive)`
- `list`, `show`, `create`, `update`, `comment`, `delete`
- `mcp`
- `skill install`

A shared `@OptionGroup GlobalOptions` provides `--json`.

Commands live in ArcAgentKit as plain async functions that return DTOs, so they can be unit-tested in process. The executable maps `ArcError` to JSON on stdout (when `--json` is given) or to a message on stderr, and exits with code 1. Argument-parser usage errors exit with code 64.

Arguments that read from stdin (`--description -`, a comment body of `-`) read all of stdin, up to 1 MB.

### 9. MCP server with the official Swift SDK

`arc mcp` starts a `Server(name: "arc", version:)` from `modelcontextprotocol/swift-sdk`, using `StdioTransport`. The server's `instructions` field summarizes the hierarchy and workflow.

The tools are declared once in ArcAgentKit as a table of name, description, JSON Schema and handler. Each handler decodes the arguments into the same request structs the CLI uses, then calls `ArcStore`. Results come back as `.text(json)`. An `ArcError` becomes a result with `isError: true` and the message.

Nothing else may write to stdout in `arc mcp` mode, and logging goes to stderr.

*Fallback:* if the SDK's current API proves unsuitable, a hand-written JSON-RPC loop is small enough to replace it, because only `initialize`, `tools/list`, `tools/call` and `ping` are needed. The tool table stays the same either way.

### 10. Agent skill packaging

`skills/arc/SKILL.md` is the canonical text. For the CLI to install it without resource-bundle lookups (an executable inside `.app/Contents/Helpers` has no `Bundle.module` next to it), it is also embedded as a Swift string constant in ArcAgentKit. A test asserts that the constant and the file are byte-identical, so they cannot drift apart.

### 11. Testing

All tests use Swift Testing (`@Test`). The tests fall into these groups:
- **ArcCore:** uses a temporary DB per test (`ARC_DB_PATH`-style injection through the `ArcStore(path:)` initializer). Covers number allocation and non-reuse, hierarchy rules, the cascades, moving between projects, ordering and renormalization, epic progress, query filters, lenient reference parsing, and migration from an empty DB.
- **ArcAgentKit:** tests the command functions and the MCP tool handlers in process. Checks the JSON shapes against fixtures.
- **End-to-end:** runs the built `.build/debug/arc` with `Process` and a temporary `ARC_DB_PATH`. Covers exit codes, `--json` errors and stdin input. Also performs one MCP stdio handshake: `initialize`, then `tools/list`, then `tools/call`.
- **ArcMarkdown:** feeds GFM fixtures through the render model and asserts the resulting blocks. Covers each block type, nesting, table alignment, the ranges and toggling of task items, ARC-12 linking (including skipping code and unknown numbers), and raw HTML shown as text.
- **Concurrency:** two `ArcStore` instances on the same file create tickets in parallel tasks, and the test asserts that the numbers are unique and nothing is lost.

The app UI is verified manually against the issue-views and app-appearance scenarios, using `scripts/bundle.sh && open build/Arc.app`.

### 12. Markdown: swift-markdown parser + own SwiftUI renderer

ArcMarkdown parses text with Apple's `swift-markdown`, which wraps cmark-gfm and supports tables, strikethrough, task lists and autolinks. It converts the parse tree into a small `Sendable` render model, `[MarkdownBlock]`:
- blocks: heading, paragraph, list (nested), code block, table, quote, rule, image
- inline runs are `AttributedString`
- each task item carries its **source range**

`MarkdownView` draws the blocks with SwiftUI, using Theme tokens. The model is pure, so all parsing behavior can be unit-tested without UI.

- **Syntax highlighting:** HighlightSwift (highlight.js running in JavaScriptCore; many languages; produces `AttributedString`) with a dark theme mapped to Theme colors. Results are cached by (language, code) hash. Code with no language, or an unknown one, is drawn as plain monospaced text. *Fallback:* Splash, a pure-Swift highlighter, if the JavaScriptCore approach has problems. It has fewer languages but uses the same `CodeHighlighter` protocol.
- **Images:**
  - Remote images are fetched by an `ImageLoader` actor, using `URLSession` with an in-memory `NSCache` that lasts for the session.
  - `file:` URLs and absolute paths are loaded from disk.
  - On failure, an alt-text placeholder is shown.
  - The CLI never links ArcMarkdown, so it makes no network requests.
- **Task toggles:** clicking a checkbox calls `MarkdownSource.toggleTask(at: range)`. This flips only the `[ ]`/`[x]` characters at that range of the stored string, and the result is saved through `updateTicket` or a comment update. If the source has changed since rendering, the range is checked again first.
- **ARC-12 links:** a pass over text nodes that skips code spans and code blocks turns `\bARC-\d+\b` (case-insensitive) into `arc://ticket/<n>` links. These are only added for numbers that exist in a set of known numbers the view model provides. The app handles `arc://` links through the SwiftUI `openURL` environment; other URLs go to `NSWorkspace`.
- **Raw HTML:** shown as literal text. This is safe and predictable, and no WebView is needed.

*Alternatives considered:*
- **MarkdownUI:** in maintenance mode. It gives no source positions, so checkboxes could not be toggled, and it is harder to style like Linear.
- **WKWebView with a JS renderer:** the most complete rendering, but heavy per comment, awkward to size inside SwiftUI, and dark-theme styling is split across CSS.
- **`AttributedString(markdown:)`:** inline formatting only, with no tables or code highlighting.

Comment bodies need an update path for task toggles, so `ArcStore` gains `updateComment(id, body:)`. It is used only by the app; agents do not need it.

## Risks / Trade-offs

- **The MCP Swift SDK is pre-1.0, so its API may change.** → Pin an exact version in `Package.swift` and keep tool definitions independent of the SDK (see the fallback in Decision 9).
- **SwiftUI `List` styling may not fully match Linear** (selection insets, section header chrome). → Rows and headers are custom views. If `List` still cannot get close enough, switch the list to a `ScrollView` + `LazyVStack` with manual focus and selection handling. The `TicketListModel` contract does not change.
- **A SwiftUI block renderer can only select text within one block at a time.** → Acceptable for v1, because code blocks have a copy button and the raw source can be selected in edit mode. If selecting across blocks becomes important, the renderer can draw into a single `NSTextView`, and the render model does not change.
- **The highlighter's JavaScriptCore start-up costs about 50 ms on first use.** → Create it lazily on a background actor and cache its results. Code is shown plain until highlighting finishes.
- **Remote images expose to the image host that a ticket was viewed.** → This is accepted, because you chose to support remote images. No ticket text is sent.
- **`/usr/local/bin` is often not writable.** → Fall back to `~/.local/bin` and show a hint when that directory is not on `PATH`.
- **Ad-hoc signed apps may trigger a Gatekeeper prompt** when copied to another Mac. → This is out of scope (local use only). Document it in the README.
- **Polling `data_version` every second costs a little.** → One cheap pragma on an idle connection. Polling pauses while the app is inactive and resumes on activation, with an immediate check.
- **Two writers at once can briefly make each other wait.** → Immediate transactions plus a 5 s busy timeout. Writes are tiny, so waits are milliseconds.

## Migration Plan

This is the first release, so there is no existing data. Migrations are registered with GRDB's `DatabaseMigrator`, starting at `v1`. Shipped migrations are never edited; later schema changes add new migrations.

The software refuses to open a database whose applied migrations include identifiers it does not know, and reports `schema_too_new`. Rollback means deleting `~/Library/Application Support/Arc/` before any real data exists.

## Open Questions

- The app icon design. A placeholder `.icns` is fine until the icon is designed.
- Whether to auto-register the MCP server in Claude Code's config from the Agents pane, rather than only showing the command to copy. This can be added later without changing the specs.
