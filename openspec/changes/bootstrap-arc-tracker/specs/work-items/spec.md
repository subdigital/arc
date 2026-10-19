# Spec Delta

## Purpose

Defines Arc's domain model: projects, epics, tasks and subtasks, plus their identifiers, workflow states, priorities, ordering and comments. The app and agents both work with tickets according to these rules.

## ADDED Requirements

### Requirement: Projects
The system SHALL let the user create, rename, describe, archive, unarchive and delete projects. Each project has a name, an optional description, and a color.

#### Scenario: Create a project
- **WHEN** the user creates a project named "Website"
- **THEN** the project appears in the project list with that name and is not archived

#### Scenario: Archive a project
- **WHEN** the user archives the project "Website"
- **THEN** the project is hidden from the active project list
- **AND** its tickets remain stored and can still be retrieved by identifier

### Requirement: Project names are unique
Two non-deleted projects SHALL NOT have the same name, compared case-insensitively.

#### Scenario: Duplicate name rejected
- **WHEN** a project named "Website" exists and the user tries to create a project named "website"
- **THEN** the system rejects the request with an error stating that the name is already in use

### Requirement: Deleting a project deletes its tickets
Deleting a project SHALL permanently delete every ticket in that project, together with those tickets' comments.

#### Scenario: Delete project with tickets
- **WHEN** the user deletes a project that contains 3 tasks and 1 epic
- **THEN** the project and all 4 tickets no longer exist
- **AND** looking up any of their identifiers reports that the ticket was not found

### Requirement: Ticket kinds
The system SHALL support three kinds of ticket: epic, task and subtask. Every ticket belongs to exactly one project.

#### Scenario: Ticket requires a project
- **WHEN** a ticket is created without a project
- **THEN** the system rejects the request with an error stating that a project is required

### Requirement: Task to epic relationship
A task MAY belong to at most one epic. That epic MUST be in the same project as the task.

#### Scenario: Assign task to epic
- **WHEN** the user sets the epic of a task to an epic in the same project
- **THEN** the task is listed among that epic's tasks

#### Scenario: Cross-project epic rejected
- **WHEN** the user tries to set a task's epic to an epic in a different project
- **THEN** the system rejects the change with an error

### Requirement: Subtask parent rules
Every subtask MUST have exactly one parent, and the parent MUST be a task. Epics and subtasks SHALL NOT have subtasks. A subtask always belongs to its parent's project.

#### Scenario: Create subtask under a task
- **WHEN** the user creates a subtask under task ARC-5
- **THEN** the subtask is listed among ARC-5's subtasks and has ARC-5's project

#### Scenario: Nested subtask rejected
- **WHEN** a subtask is created with another subtask as its parent
- **THEN** the system rejects the request with an error stating that subtasks can only belong to tasks

### Requirement: Global ticket identifiers
Every ticket SHALL get an identifier of the form `ARC-<n>` when it is created. `<n>` comes from one global counter shared by all projects and all ticket kinds. The identifier never changes.

#### Scenario: Sequential identifiers across projects
- **WHEN** the user creates a task in project A and then an epic in project B
- **THEN** the two tickets receive consecutive numbers, for example ARC-7 and ARC-8

#### Scenario: Identifier survives project move
- **WHEN** task ARC-7 is moved from project A to project B
- **THEN** its identifier remains ARC-7

### Requirement: Identifiers are never reused
The system SHALL NOT assign a number that was used before, even if the ticket that had it was deleted.

#### Scenario: Deleted number not reused
- **WHEN** ARC-9 is the most recently created ticket and is then deleted
- **THEN** the next ticket created receives ARC-10

### Requirement: Identifier lookup is lenient
Lookups by identifier SHALL ignore case and SHALL accept a bare number.

#### Scenario: Case-insensitive lookup
- **WHEN** a ticket is looked up as "arc-12" or as "12"
- **THEN** the system returns ticket ARC-12

### Requirement: Ticket fields
Every ticket SHALL have a title (required, non-blank), a Markdown description (optional), a status, a priority, a creation timestamp and an update timestamp.

#### Scenario: Blank title rejected
- **WHEN** a ticket is created with a title made only of whitespace
- **THEN** the system rejects the request with an error stating that a title is required

#### Scenario: Update timestamp changes
- **WHEN** a ticket's title is edited
- **THEN** its update timestamp is set to the time of the edit

### Requirement: Default status and priority
A newly created ticket SHALL have status Todo and priority None unless other values are given.

#### Scenario: Create with defaults
- **WHEN** a task is created with only a title and a project
- **THEN** its status is Todo and its priority is None

### Requirement: Workflow statuses
Every ticket SHALL have exactly one of these statuses, in this order: Backlog, Todo, In Progress, In Review, Done, Canceled. Done and Canceled are closed statuses; the others are open.

#### Scenario: Any transition allowed
- **WHEN** a ticket in Backlog is set directly to Done
- **THEN** the change is accepted

### Requirement: Completion timestamp
The system SHALL record when a ticket enters a closed status and SHALL clear that record when the ticket returns to an open status.

#### Scenario: Completion recorded
- **WHEN** a ticket's status changes from In Progress to Done
- **THEN** its completion timestamp is set to the time of the change

#### Scenario: Reopening clears completion
- **WHEN** a Done ticket is set back to Todo
- **THEN** its completion timestamp is cleared

### Requirement: Priorities
Every ticket SHALL have exactly one of these priorities: None, Urgent, High, Medium, Low. When sorting by priority, the order is Urgent, High, Medium, Low, None.

#### Scenario: Sort by priority
- **WHEN** tickets with priorities Low, None, Urgent are sorted by priority
- **THEN** the order is Urgent, Low, None

### Requirement: Manual ordering within a status
Tickets SHALL keep a user-defined order within each status. The user can move a ticket before or after another ticket, or to the top or bottom of a status. Other tickets do not change position relative to each other.

#### Scenario: Reorder within status
- **WHEN** the Todo tickets are ordered ARC-1, ARC-2, ARC-3 and ARC-3 is moved before ARC-1
- **THEN** the Todo order becomes ARC-3, ARC-1, ARC-2

#### Scenario: Status change places ticket at top
- **WHEN** a ticket's status is changed without a target position
- **THEN** the ticket appears first in its new status

### Requirement: Moving a task between projects
Moving a task to another project SHALL move all of its subtasks with it. If the task's epic is in a different project from the target, the task's epic SHALL be cleared.

#### Scenario: Move task with subtasks
- **WHEN** task ARC-5, which has epic ARC-2 and subtasks ARC-6 and ARC-7, is moved to another project
- **THEN** ARC-5, ARC-6 and ARC-7 all belong to the new project
- **AND** ARC-5 no longer has an epic

### Requirement: Moving an epic between projects
Moving an epic to another project SHALL move all of its tasks, and their subtasks, with it.

#### Scenario: Move epic with tasks
- **WHEN** an epic with 2 tasks is moved to another project
- **THEN** the epic and both tasks belong to the new project and the tasks still belong to the epic

### Requirement: Deleting tickets
Deleting a task SHALL also delete its subtasks. Deleting an epic SHALL NOT delete its tasks; their epic is cleared instead. Deleting any ticket also deletes its comments.

#### Scenario: Delete task cascades to subtasks
- **WHEN** task ARC-5 with subtasks ARC-6 and ARC-7 is deleted
- **THEN** ARC-5, ARC-6 and ARC-7 no longer exist

#### Scenario: Delete epic keeps tasks
- **WHEN** epic ARC-2 with task ARC-5 is deleted
- **THEN** ARC-5 still exists and has no epic

### Requirement: Epic progress
For each epic, the system SHALL report how many of its tasks exist and how many are Done. Canceled tasks are left out of both numbers.

#### Scenario: Progress excludes canceled
- **WHEN** an epic has 4 tasks: 2 Done, 1 Todo and 1 Canceled
- **THEN** the epic's progress is 2 of 3

### Requirement: Comments
The system SHALL let anyone add comments to any ticket. A comment has a Markdown body, a creation timestamp and an author source: either `user` or `agent`. Comments are listed oldest first.

#### Scenario: Agent comment attributed
- **WHEN** an agent adds the comment "Implemented the parser" to ARC-5
- **THEN** ARC-5's comments include that body with author source `agent`

#### Scenario: Empty comment rejected
- **WHEN** a comment with a blank body is added
- **THEN** the system rejects the request with an error

### Requirement: Ticket search and filtering
The system SHALL let tickets be filtered by any combination of:
- project
- kind
- status, one or more
- priority, one or more
- epic
- parent
- a free-text query matched case-insensitively against the title, description and identifier

#### Scenario: Filter by project and status
- **WHEN** tickets are requested for project "Website" with statuses Todo and In Progress
- **THEN** only tickets in "Website" with one of those statuses are returned

#### Scenario: Text query matches identifier
- **WHEN** tickets are searched with the query "arc-12"
- **THEN** ticket ARC-12 is included in the results
