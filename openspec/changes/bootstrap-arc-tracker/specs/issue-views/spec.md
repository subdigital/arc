# Spec Delta

## Purpose

Defines the Arc main window: navigation, the status-grouped list, the board, the epics overview, the ticket detail page, and the ways the user creates and edits tickets with mouse and keyboard.

## ADDED Requirements

### Requirement: Sidebar navigation
The main window SHALL have a sidebar with an "All Tasks" entry, an "Epics" entry, and an alphabetical list of active projects. Archived projects are in a collapsed "Archived" section. Selecting "All Tasks" shows tasks from every active project. Selecting a project shows only that project's tickets.

#### Scenario: Select a project
- **WHEN** the user clicks the project "Website" in the sidebar
- **THEN** the content area shows only tickets from "Website" and the window title shows "Website"

### Requirement: Project filter in All Tasks
In the "All Tasks" view, the user SHALL be able to filter to one or more projects. Each row then shows which project the ticket belongs to.

#### Scenario: Filter All Tasks by project
- **WHEN** the user selects the projects "Website" and "API" in the All Tasks project filter
- **THEN** only tasks from those two projects are shown

### Requirement: View filters
The list and the board SHALL offer filters for epic and priority. They also have a "Show subtasks" toggle, which is on by default. The filters apply to whichever layout is showing. The filters and the chosen layout are remembered separately for each sidebar entry, and restored when the app is relaunched.

#### Scenario: Hide subtasks
- **WHEN** the user turns off "Show subtasks"
- **THEN** subtasks disappear from the list and the board, and their parent rows show a subtask count

#### Scenario: Filters remembered per project
- **WHEN** the user filters the "Website" board to High priority, switches to "API", and then returns to "Website"
- **THEN** the "Website" board is still filtered to High priority

### Requirement: Status-grouped list view
The list view SHALL group tickets under a header for each status, in workflow order. Each header shows the status glyph, the status name and the number of tickets. Groups with no tickets are hidden. Done and Canceled groups start collapsed.

#### Scenario: Grouped list
- **WHEN** a project has 2 Todo tasks and 1 In Progress task and the list view is shown
- **THEN** the list shows an "In Progress 1" group above a "Todo 2" group and no other groups

#### Scenario: Collapse a group
- **WHEN** the user clicks the "Todo" group header
- **THEN** the Todo rows are hidden and the header remains visible with its count

### Requirement: List row content
Each list row SHALL show, from left to right:
1. a priority glyph
2. the identifier
3. a status glyph
4. the title
5. the epic name, if any
6. the subtask progress (for example "1/3"), if the ticket has subtasks
7. the project name, only in All Tasks
8. the last-updated date

A subtask row is indented under its parent when the parent is in the same group.

#### Scenario: Subtask row nested
- **WHEN** task ARC-5 and its subtask ARC-6 are both in Todo
- **THEN** ARC-6 appears directly below ARC-5 and is indented

### Requirement: Board view
The board view SHALL show one column per status, in workflow order. Each column header shows the status glyph, the name and the count. Each card shows the identifier, title, priority glyph, epic name if any, and subtask progress if the ticket has subtasks. The Canceled column is hidden by default and can be shown from the view options.

#### Scenario: Board columns
- **WHEN** the user switches a project to the board view
- **THEN** columns for Backlog, Todo, In Progress, In Review and Done are shown with that project's tickets

### Requirement: Drag and drop on the board
Dragging a card to another column SHALL change the ticket's status to that column's status. Dropping a card between two cards places it at that position.

#### Scenario: Drag to change status
- **WHEN** the user drags ARC-5 from Todo and drops it at the top of In Progress
- **THEN** ARC-5's status becomes In Progress and it is the first card in that column

### Requirement: Switching layout
The user SHALL be able to switch between list and board with a toolbar control or the shortcut Cmd-B. The current filters stay as they are.

#### Scenario: Toggle layout with shortcut
- **WHEN** the list view is showing and the user presses Cmd-B
- **THEN** the board view is shown with the same filters applied

### Requirement: Epics overview
The "Epics" view SHALL list epics grouped by project. Each row shows the epic's identifier, status glyph, title, a progress bar, and the number of done tasks out of all tasks. Selecting an epic opens a list of its tasks, grouped by status.

#### Scenario: Open an epic
- **WHEN** the user selects epic ARC-2 in the Epics view
- **THEN** a status-grouped list of ARC-2's tasks is shown, with ARC-2's title as the header

### Requirement: Ticket detail page
Opening a ticket SHALL show a detail page.
- The main column has the editable title, the description rendered as Markdown (editable in place), the subtasks with their status glyphs, and the comments rendered as Markdown with a composer that accepts Markdown.
- A properties panel shows status, priority, project, epic and parent. Each can be changed from a menu.
- The page has a back control that returns to the previous view.

#### Scenario: Edit status from detail
- **WHEN** the user opens ARC-5 and chooses In Review from the status menu
- **THEN** ARC-5's status becomes In Review and the change appears in the list and board views

#### Scenario: Navigate to parent
- **WHEN** the user is viewing subtask ARC-6 and clicks its parent ARC-5
- **THEN** the detail page for ARC-5 is shown

### Requirement: Markdown rendering
Ticket descriptions and comment bodies SHALL be rendered as GitHub Flavored Markdown with full block and inline support, wherever their content is shown:
- headings (levels 1–6) and paragraphs
- bold, italic, strikethrough and inline code
- links and bare URLs
- bulleted and numbered lists, nested to any depth
- task lists
- fenced and indented code blocks
- tables with column alignment
- blockquotes
- horizontal rules
- images

#### Scenario: Block elements rendered
- **WHEN** a description contains a level-2 heading, a nested bulleted list, a blockquote and a horizontal rule
- **THEN** each is drawn as its formatted element, and no Markdown syntax characters are shown

#### Scenario: Table rendered
- **WHEN** a comment contains a GFM table whose second column is right-aligned
- **THEN** the comment shows a table with a header row and cell borders, and the second column is right-aligned

#### Scenario: Links open externally
- **WHEN** the user clicks a link to `https://example.com` in a rendered description
- **THEN** the URL opens in the default browser

#### Scenario: Unsupported HTML shown as text
- **WHEN** a description contains raw HTML such as `<div>`
- **THEN** the HTML is shown as literal text and is not interpreted

### Requirement: Code blocks
Fenced code blocks SHALL be syntax highlighted when a known language is given in the info string. Code blocks without a language, or with an unknown one, are shown in a monospaced font without highlighting. Every code block has a copy button and scrolls horizontally instead of wrapping.

#### Scenario: Swift code highlighted
- **WHEN** a description contains a fenced block marked `swift`
- **THEN** keywords, strings and comments are drawn in distinct colors

#### Scenario: Copy code
- **WHEN** the user clicks the copy button on a code block
- **THEN** the clipboard contains the block's code, without the fence lines

### Requirement: Images in Markdown
Markdown images SHALL be rendered inline and scaled to fit the content width. Supported sources are `http(s)` URLs, `file` URLs and absolute local paths. Remote images are fetched on demand and cached for the session. While an image is loading, or if it fails to load, a placeholder showing the alt text is shown.

#### Scenario: Remote image
- **WHEN** a description contains `![diagram](https://example.com/d.png)`
- **THEN** the image is shown inline, no wider than the content column

#### Scenario: Image unavailable
- **WHEN** an image URL cannot be loaded, for example while offline
- **THEN** a placeholder with the text "diagram" is shown and the rest of the description renders normally

### Requirement: Interactive task lists
Clicking a task-list checkbox in a rendered description or comment SHALL toggle it. The change is saved by flipping `[ ]` and `[x]` in the stored Markdown source, and the rest of the text is left unchanged.

#### Scenario: Tick a checkbox
- **WHEN** ARC-5's description contains `- [ ] Write tests` and the user clicks that checkbox
- **THEN** the stored description contains `- [x] Write tests` and the checkbox is shown ticked

### Requirement: Ticket identifier links
Ticket identifiers such as `ARC-12` in rendered Markdown SHALL be shown as links. Clicking one opens that ticket's detail page. Identifiers inside code spans or code blocks, and identifiers for tickets that do not exist, are shown as plain text.

#### Scenario: Follow ticket link
- **WHEN** a comment on ARC-5 says "Blocked by ARC-12" and the user clicks "ARC-12"
- **THEN** the detail page for ARC-12 is shown

#### Scenario: Identifier in code not linked
- **WHEN** a description contains `` `ARC-12` `` as inline code
- **THEN** it is shown as code and is not a link

### Requirement: Editing Markdown
Clicking a rendered description SHALL switch it to a plain-text editor showing the raw Markdown source. Pressing Escape, or moving focus away, saves the text and switches back to the rendered view. Clicking a link, checkbox or copy button does not enter edit mode. The comment composer edits raw Markdown and renders the comment once it is posted.

#### Scenario: Edit then render
- **WHEN** the user clicks the description, types `## Notes`, and presses Escape
- **THEN** the description is saved and "Notes" is shown as a level-2 heading

### Requirement: Create tickets
Pressing C, or using the "New Task" toolbar button, SHALL open a creation sheet with these fields: title, description, kind, project, epic, parent, status and priority.
- Project defaults to the currently selected project.
- Status defaults to Todo.
- Cmd-Return saves.
- Escape cancels.
- From a ticket's detail page, the user can also add a subtask inline.

#### Scenario: Quick create in project
- **WHEN** the "Website" list is showing and the user presses C, types "Fix footer", and presses Cmd-Return
- **THEN** a Todo task "Fix footer" is created in "Website" and appears in the list

#### Scenario: Add subtask inline
- **WHEN** the user types "Write tests" in the add-subtask field on ARC-5's detail page and presses Return
- **THEN** a subtask "Write tests" is created under ARC-5

### Requirement: Keyboard navigation and shortcuts
In the list and board, the arrow keys and J/K SHALL move the selection, and Return opens the selected ticket. On the selected ticket:
- S opens the status menu.
- P opens the priority menu.
- Cmd-Delete asks for confirmation and then deletes the ticket.
- Escape on the detail page goes back.

#### Scenario: Change priority by keyboard
- **WHEN** ARC-5 is selected in the list and the user presses P, then chooses Urgent
- **THEN** ARC-5's priority becomes Urgent

### Requirement: Context menu actions
Right-clicking a ticket row or card SHALL show a menu with these actions: change status, change priority, change epic, move to project, copy identifier, copy title with identifier, and delete.

#### Scenario: Copy identifier
- **WHEN** the user right-clicks ARC-5 and chooses "Copy ID"
- **THEN** the clipboard contains "ARC-5"

### Requirement: Empty states
When a view has no tickets, the content area SHALL show a short message and a button to create a ticket. When no projects exist, the app SHALL prompt the user to create the first project.

#### Scenario: First run
- **WHEN** the app opens with an empty database
- **THEN** the content area shows a prompt with a "Create Project" button
