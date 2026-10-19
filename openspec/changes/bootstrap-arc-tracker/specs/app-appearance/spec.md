# Spec Delta

## Purpose

Defines Arc's visual language: a permanent dark theme, closely modeled on Linear, with dense layouts and consistent status and priority glyphs, so the app feels familiar to Linear users.

## ADDED Requirements

### Requirement: Always dark
The app SHALL always use a dark appearance, whatever the macOS system appearance is. There is no light mode in v1.

#### Scenario: System in light mode
- **WHEN** macOS is set to Light appearance and the app is opened
- **THEN** every Arc window, sheet, menu and popover is drawn with dark colors

### Requirement: Linear-like palette
The app SHALL use a near-black neutral palette:
- The content background is darker than the panel and card surfaces.
- The sidebar background is darker than or equal to the content background.
- Dividers are thin, low-contrast lines.
- Primary text is off-white and secondary text is mid-gray.
- One indigo accent color (approximately #5E6AD2) marks selection, focus and primary buttons.

#### Scenario: Selected row highlight
- **WHEN** a list row is selected
- **THEN** its background is a subtle lighter fill and the focus indicator uses the indigo accent

### Requirement: Dense typography
The app SHALL use the system sans-serif font: 13 pt for row and card text, and 12 pt for metadata. Identifiers and other metadata use secondary text color. List rows are at most 36 pt tall.

#### Scenario: Row density
- **WHEN** a list with 20 tickets is shown in a window 900 pt tall
- **THEN** at least 20 rows are visible without scrolling, not counting group headers

### Requirement: Status glyphs
Each status SHALL have a distinct circular glyph, used everywhere that status appears:

| Status | Glyph |
| --- | --- |
| Backlog | dashed gray circle |
| Todo | empty gray circle |
| In Progress | yellow half-filled circle |
| In Review | green circle, three-quarters filled |
| Done | filled indigo circle with a check mark |
| Canceled | filled gray circle with an X |

#### Scenario: Consistent glyphs
- **WHEN** a ticket in In Progress is shown in the list, on the board and on the detail page
- **THEN** all three show the same yellow half-filled circle glyph

### Requirement: Priority glyphs
Each priority SHALL have a distinct glyph:

| Priority | Glyph |
| --- | --- |
| Urgent | orange-red filled square with an exclamation mark |
| High | three bars |
| Medium | two bars |
| Low | one bar |
| None | three faint dashes |

For High, Medium and Low, the bars that are not lit are dimmed.

#### Scenario: Priority glyph shown
- **WHEN** a ticket with priority Medium is shown in a list row
- **THEN** its priority glyph shows two lit bars and one dimmed bar

### Requirement: Markdown styling
Rendered Markdown SHALL use the dark palette:
- Body text is 13–14 pt in primary text color, and headings step down in size from level 1 to level 6.
- Links use the accent color.
- Inline code and code blocks use a monospaced font on an elevated surface.
- Syntax highlighting uses a dark color scheme that is readable on that surface.
- Blockquotes have a left bar and secondary text color.
- Tables use thin, low-contrast borders.

#### Scenario: Code block on dark surface
- **WHEN** a description with a fenced code block is shown
- **THEN** the block has a background distinct from the page, in the elevated surface color, and the highlighted tokens contrast clearly with it

### Requirement: Restrained chrome
The app SHALL use a full-height sidebar and a slim toolbar. Controls are flat, with no heavy borders. Hover states are a subtle background fill. Menus and popovers use the same dark surface color as cards.

#### Scenario: Hover feedback
- **WHEN** the pointer moves over a list row
- **THEN** the row's background lightens slightly and no border or shadow appears
