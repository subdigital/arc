# Spec Delta

## Purpose

Lets AI agents read and change Arc data as fully as the user can. Access is through a scriptable `arc` CLI, an MCP server that the CLI provides, and an installable skill that explains the workflow.

## ADDED Requirements

### Requirement: arc command-line tool
The system SHALL provide an `arc` executable with these subcommands:

| Area | Subcommands |
| --- | --- |
| Projects | `project list`, `project create`, `project update`, `project archive`, `project unarchive` |
| Tickets | `list`, `show`, `create`, `update`, `comment`, `delete` |
| Agent integration | `mcp`, `skill install` |

Every subcommand prints usage help when given `--help`.

#### Scenario: Help output
- **WHEN** the user runs `arc create --help`
- **THEN** usage text describing every `create` option is printed and the exit status is 0

### Requirement: Machine-readable output
Every data command SHALL accept `--json`. With `--json`, the result is printed to stdout as one JSON document, and errors are printed as `{"error": {"code": ..., "message": ...}}`. Without `--json`, output is a compact, human-readable table or summary.

#### Scenario: JSON ticket output
- **WHEN** the agent runs `arc show ARC-5 --json`
- **THEN** stdout contains a single JSON object for ARC-5 with these fields: identifier, kind, title, description, status, priority, project, epic, parent, subtasks, comments, createdAt, updatedAt and completedAt

### Requirement: Exit status
`arc` SHALL exit with status 0 on success and a non-zero status on any error.

#### Scenario: Not found
- **WHEN** the agent runs `arc show ARC-99999 --json` and that ticket does not exist
- **THEN** the exit status is non-zero and stdout contains an error object with code `not_found`

### Requirement: Flexible references
The CLI and MCP tools SHALL accept these references:
- tickets: an identifier, ignoring case, or a bare number
- projects: a name, ignoring case
- statuses: `backlog`, `todo`, `in_progress`, `in_review`, `done`, `canceled`, ignoring case and allowing spaces or hyphens instead of underscores
- priorities: `none`, `urgent`, `high`, `medium`, `low`

#### Scenario: Human-style status
- **WHEN** the agent runs `arc update arc-5 --status "In Progress"`
- **THEN** ARC-5's status becomes In Progress

#### Scenario: Unknown project
- **WHEN** the agent runs `arc create --project Nope --title X`
- **THEN** the command fails with code `not_found`, and the message lists the names of the existing projects

### Requirement: Listing tickets from the CLI
`arc list` SHALL support filters for project, kind, status, priority, epic, parent and a text query, plus a limit. By default it returns only open tickets; `--all` includes Done and Canceled. Results are ordered by status in workflow order, then by manual order.

#### Scenario: Default excludes closed
- **WHEN** a project has 2 Todo tasks and 3 Done tasks and the agent runs `arc list --project Website --json`
- **THEN** only the 2 Todo tasks are returned

### Requirement: Creating and updating tickets from the CLI
`arc create` SHALL require a title and a project. The project can be omitted when `--parent` is given, because a subtask takes its parent's project. `arc create` and `arc update` accept kind, epic, parent, status and priority. The description can be given inline or read from stdin with `--description -`. On success, the command prints the resulting ticket, including its identifier.

#### Scenario: Create subtask without project
- **WHEN** the agent runs `arc create --parent ARC-5 --title "Add tests" --json`
- **THEN** a subtask is created in ARC-5's project and its identifier is printed

#### Scenario: Description from stdin
- **WHEN** the agent pipes Markdown text into `arc update ARC-5 --description -`
- **THEN** ARC-5's description is replaced with the piped text

### Requirement: Comments from the CLI
`arc comment <ticket> <body>` SHALL add a comment attributed to source `agent`. The body can also be read from stdin with `-`.

#### Scenario: Agent progress note
- **WHEN** the agent runs `arc comment ARC-5 "Parser done, starting tests"`
- **THEN** ARC-5 has a new comment with that body and author source `agent`

### Requirement: Guarded deletion
`arc delete <ticket>` SHALL refuse to delete unless `--yes` is passed. The MCP server SHALL NOT offer a delete tool; agents close unwanted work by setting it to Canceled.

#### Scenario: Delete without confirmation
- **WHEN** the agent runs `arc delete ARC-5` without `--yes`
- **THEN** nothing is deleted and the command fails with a message saying `--yes` is required

### Requirement: MCP server
`arc mcp` SHALL run a Model Context Protocol server over stdio. It identifies itself as "arc" and provides usage instructions that describe the ticket hierarchy and workflow.

#### Scenario: Register with an agent
- **WHEN** the user runs `claude mcp add arc -- arc mcp` and starts an agent session
- **THEN** the agent can list and call Arc's tools

### Requirement: MCP tools
The MCP server SHALL expose these tools, with the same validation and reference rules as the CLI:
- `list_projects`
- `create_project`
- `list_tickets` (with the same filters as `arc list`, and `include_closed` defaulting to false)
- `get_ticket`
- `create_ticket`
- `update_ticket`
- `add_comment` (author source `agent`)

Each tool's input schema documents every parameter. Each tool returns JSON text content.

#### Scenario: Create via MCP
- **WHEN** an agent calls `create_ticket` with title "Add OAuth" and project "API"
- **THEN** the tool result contains the new ticket's identifier and the ticket appears in the app

#### Scenario: Validation error via MCP
- **WHEN** an agent calls `create_ticket` with kind `subtask` and a parent that is an epic
- **THEN** the tool result is marked as an error and its message explains that subtasks can only belong to tasks

### Requirement: Agent skill
The system SHALL ship an agent skill: a `SKILL.md` file with name and description frontmatter. It explains:
- what Arc is and the ticket hierarchy
- the identifier format
- the statuses
- the recommended workflow: find work, set it to In Progress, add progress comments, set it to In Review or Done
- examples using both the MCP tools and the `arc` CLI with `--json`

#### Scenario: Skill content
- **WHEN** the installed `SKILL.md` is read
- **THEN** it contains frontmatter with name `arc` and step-by-step instructions for picking up and completing a ticket

### Requirement: Skill installation
`arc skill install` SHALL write the skill to `~/.claude/skills/arc/SKILL.md` by default, or to `<dir>/arc/SKILL.md` when `--dir <dir>` is given. Without `--force`, it does not overwrite a skill file whose content differs from the shipped version.

#### Scenario: Install skill
- **WHEN** the user runs `arc skill install` and no skill is installed yet
- **THEN** `~/.claude/skills/arc/SKILL.md` exists with the shipped skill content and the command prints the path

### Requirement: CLI installation from the app
The app's Settings window SHALL have an "Agents" pane with:
- a button that installs the bundled `arc` executable by creating a symbolic link at `/usr/local/bin/arc`, falling back to `~/.local/bin/arc`
- the MCP registration command, ready to copy
- a button that installs the skill

#### Scenario: Install CLI
- **WHEN** the user clicks "Install Command Line Tool" in the Agents pane
- **THEN** a symbolic link to the bundled `arc` is created, and the pane shows the installed path and whether that directory is on `PATH`
