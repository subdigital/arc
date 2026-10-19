# Spec Delta

## Purpose

Defines where Arc keeps its data and how the app and the `arc` CLI/MCP process share that data safely. Changes made by an agent appear in the open app without a manual refresh.

## ADDED Requirements

### Requirement: Single local database
The app and the `arc` tool SHALL store all Arc data in one local database file. By default the file is at `~/Library/Application Support/Arc/arc.sqlite`. If the directory does not exist, it is created on first use.

#### Scenario: First launch creates the store
- **WHEN** the app or the CLI runs for the first time on a machine with no Arc data
- **THEN** the database is created at the default location and is empty except for its schema

#### Scenario: App and CLI see the same data
- **WHEN** the CLI creates a ticket using the default location
- **THEN** the app, also using the default location, shows that ticket

### Requirement: Database location override
If the environment variable `ARC_DB_PATH` is set, the app and the `arc` tool SHALL use the database file at that path instead of the default location.

#### Scenario: Isolated database for tests
- **WHEN** `ARC_DB_PATH` points to a temporary file and the CLI creates a project
- **THEN** the project is written to that file and the default database is not touched

### Requirement: Concurrent multi-process access
The system SHALL allow the app and one or more `arc` processes to read and write the database at the same time. Every write is atomic, and no update is lost or corrupted.

#### Scenario: Simultaneous writers
- **WHEN** the app and an `arc` process each create a ticket at the same moment
- **THEN** both tickets are stored and have different identifiers

#### Scenario: Busy database retried
- **WHEN** a write finds the database locked by another process
- **THEN** the write waits and retries for up to 5 seconds before failing with a "database busy" error

### Requirement: Live refresh of external changes
When another process changes the database, the running app SHALL show the change within 2 seconds, with no user action.

#### Scenario: Agent moves a ticket
- **WHEN** an agent sets ARC-5 to In Progress through the CLI while the board view is open
- **THEN** within 2 seconds ARC-5 appears in the In Progress column

### Requirement: Schema versioning and migration
The database SHALL record its schema version. Opening an older database migrates it forward automatically and keeps all data. If the database is newer than the running software supports, the software refuses to open it and shows an error telling the user to update Arc.

#### Scenario: Newer schema refused
- **WHEN** the CLI opens a database created by a newer version of Arc
- **THEN** it exits with a non-zero status and an error saying the database requires a newer version of Arc

### Requirement: Data stays local
Arc SHALL NOT send ticket data over the network. The only network requests the app makes are to fetch remote images referenced in Markdown. The CLI and MCP server make no network requests.

#### Scenario: No network access
- **WHEN** the app or the CLI runs with networking disabled
- **THEN** all features work normally, and remote Markdown images show their placeholder
