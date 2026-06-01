# Research notes

Two questions drove Kanpan's design. This is the condensed write-up; it directly
informed the data model and UI.

---

## 1. How Microsoft Planner works (and what to copy / fix)

**Data model:** `Plan → Bucket (column) → Task`. A task has a small, fixed field
set: title, notes, start/due date, **priority** (Urgent / Important / Medium / Low,
default Medium), **progress** (Not started / In progress / Completed), colored
**labels** (multi-select), one **checklist** (max 20 items), attachments.

**Progress / completion.** Progress is a 3-state enum, not a percentage. Marking a
task **Completed** hides it at the bottom of its list under a "Show completed"
toggle; there's no dedicated Completed board *unless* you "Group by Progress",
which lays the board out as Not started / In progress / Completed columns and lets
you **drag between them to change status**.

**Views.** Board (Kanban, default grouped by Bucket), Grid/List, Schedule
(calendar), Charts. The strongest idea is **Group by** — the *same* task set
re-projected into columns by bucket, progress, due date, priority, or label.

**Cards are quiet by default.** Footer icons (due date, priority flag, checklist
`x/y`, attachment) appear only when the underlying field is set. Medium priority
and empty checklists render nothing, keeping boards scannable.

**The weakness to beat — the checklist.** One flat list, hard-capped at 20 items,
no nesting, and items carry no status/due date/notes of their own. It cannot model
"a big project made of many small sub-projects."

### What Kanpan took from Planner
- A small, opinionated task model (no custom-field sprawl).
- **One-click complete** on the card.
- **Drag-to-change-status** (Kanpan makes *status itself* the columns, so "Done"
  literally lands in the **Completed** column).
- **Quiet cards** (icons only when a field is set).
- Inline "add a task" at the top/bottom of each column.

### What Kanpan deliberately changed
- Stripped all people / assignment / comment UI (single-user app).
- Replaced the flat checklist with **real one-level sub-tasks** (below).
- **Grid view also reflects every field**, with inline editing.

*Sources:* Microsoft Learn — [Planner limits](https://learn.microsoft.com/en-us/planner/planner-limits);
Microsoft Support — [Set and update task progress](https://support.microsoft.com/en-us/planner/set-and-update-task-progress),
[Organize your project in Board view](https://support.microsoft.com/en-us/office/organize-your-project-in-board-view-1c318425-81ee-441a-83dd-6fe8606275d6),
[Create task priorities](https://support.microsoft.com/en-us/office/create-task-priorities-using-planner-a5f2e3db-8c04-4cfa-b54e-24ae0c4b4f1b);
[Computerworld — Planner cheat sheet](https://www.computerworld.com/article/1638502/microsoft-planner-cheat-sheet.html).

---

## 2. Managing small projects inside a big project card

Surveyed Asana, Trello, Notion, ClickUp, Jira, and Linear. They **converge** on
one pattern:

- **Children are real records**, not checklist text — each sub-task has its own
  status, due date, and notes.
- **Keep nesting shallow.** Asana's official guidance is *never more than one
  layer* ("if it needs to go deeper, it's a project, not a sub-task"). Linear
  keeps it to sub-issues and tells you to promote anything bigger to a Project.
  ClickUp/Notion *allow* ~7 levels and it gets messy (rollups miscompute, UX
  degrades).
- **Automatic progress roll-up** — the parent's % complete = children done ÷ total,
  computed live. (Notion makes you wire this up manually; that's friction worth
  removing.)
- **Two UX patterns at the right depths:** *inline expand* for the shallow list of
  children, and *drill-in with a breadcrumb* to open a single child as a full
  record.
- **Promote, don't pre-decide.** Trello's "convert checklist item → card" and
  Asana's "make it a task/project" let a lightweight item grow into a full
  sub-card only when it needs to.

### What Kanpan implemented
- **Exactly one level** of sub-tasks; each is a real card (status + due + notes).
- A parent card shows a **roll-up progress bar** and an `x / y` badge.
- Open a card → manage sub-tasks inline; **drill into** any sub-task via the
  breadcrumb (`Board ▸ Parent ▸ Sub-task`) to edit it fully.
- **Promote to top-level** turns a sub-task into its own card when it outgrows the
  parent — the escape valve instead of deeper nesting.

### What Kanpan implemented (added v1.0.1)
- **Finder-style surface layering** so light (and dark) mode look native, using
  only solid semantic colors that adapt automatically.

*Sources:* [Asana — subtasks](https://help.asana.com/s/article/subtasks) and
[when to use them](https://asana.com/resources/asana-tips-subtasks);
[Linear — parent & sub-issues](https://linear.app/docs/parent-and-sub-issues);
[Notion — tasks & sub-items](https://www.notion.com/help/tasks-and-dependencies);
[Atlassian — convert checklist item to card](https://community.atlassian.com/forums/Trello-questions/Converting-a-Checklist-item-automatically-to-a-card/qaq-p/1446104);
[ClickUp — nested subtasks](https://help.clickup.com/hc/en-us/articles/6304431740055-Create-nested-subtasks);
[Interaction Design Foundation — Progressive Disclosure](https://www.interaction-design.org/literature/topics/progressive-disclosure).

---

## 3. macOS light mode (Finder) colors

Light mode looked "weird" because the app used the wrong system background
colors. macOS layers a few **semantic** surfaces; using them solid (no opacity)
makes both light and dark mode correct for free.

| Role | NSColor / SwiftUI | Light | Dark |
|---|---|---|---|
| Window **canvas** | `windowBackgroundColor` | #ECECEC gray | #323232 |
| **Card / content** | `controlBackgroundColor` / `.background` | #FFFFFF white | ~#1E1E1E |
| Behind a page (**don't** use as a bg) | `underPageBackgroundColor` | ~#969696 dark gray | #282828 |
| Hairline / border | `separatorColor` / `.quaternary` | black @ ~10% | white @ ~10% |
| Sidebar | a **material** (`.listStyle(.sidebar)` / `NSVisualEffectView`) | translucent | translucent |
| Text | `.primary` / `.secondary` / `.tertiary` | black @ 80/50/20% | white @ 80/50/20% |

**The bug:** the board canvas used `underPageBackgroundColor` (a dark gray meant
to sit *behind* a page) and columns used `windowBackgroundColor.opacity(0.55)`
(applying opacity to a semantic color blends into muddy grays). HIG: *never hard
code system color values, and choose materials by semantic role, not apparent
color.*

**The recipe (what Kanpan now does):** light-gray **canvas**
(`windowBackgroundColor`) → faint recessed **lanes** (adaptive `primary @ 4.5%`)
→ white **cards** (`controlBackgroundColor`) with a subtle status tint, an
adaptive **hairline** border (`primary @ 8%`), and a soft shadow. The sidebar
keeps `.listStyle(.sidebar)` for the translucent Finder material. Centralized in
`Theme.canvas / .surface / .lane / .hairline`.

*Sources:* Apple HIG — [Color](https://developer.apple.com/design/human-interface-guidelines/color),
[Materials](https://developer.apple.com/design/human-interface-guidelines/materials),
[Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode);
Apple docs — [windowBackgroundColor](https://developer.apple.com/documentation/appkit/nscolor/1528630-windowbackgroundcolor),
[controlBackgroundColor](https://developer.apple.com/documentation/appkit/nscolor/controlbackgroundcolor),
[underPageBackgroundColor](https://developer.apple.com/documentation/appkit/nscolor/underpagebackgroundcolor),
[Material](https://developer.apple.com/documentation/swiftui/material).

---

## 4. One file per project (single-file storage)

Storing each task — parent *and* every sub-task — as its own `.md` file made the
vault sprawl once there were 10+ projects. Researched single-file conventions for
"a task + nested sub-tasks, each with metadata **and** multi-line notes":

- **YAML front-matter array-of-objects** (sub-tasks as a list, notes as block
  scalars `|`): rejected — indentation-sensitive, breaks on a stray space or a
  `:`/`#` in prose, and Obsidian renders front-matter as a properties table so the
  notes wouldn't show as Markdown.
- **`###` headings as sub-task separators**: rejected — collides with headings
  users legitimately write inside notes.
- **Emacs Org-mode** (`:PROPERTIES:` drawer + free body under each headline) is the
  gold standard for "one file = a tree of tasks with state + properties + notes."
  Not Markdown, but the *pattern* — hard-delimited machine fields + free notes
  body — is exactly what to copy.

**Chosen format (implemented v1.1.0):** parent YAML front-matter + parent notes,
then each sub-task introduced by a reserved **`<!-- kanpan:subtask -->`** HTML
comment carrying the same `key: value` fields, followed by free Markdown notes.
HTML comments are hidden in Obsidian's reading view and never collide with prose,
so the split is unambiguous; the parser tracks fenced code blocks so a ``` ``` ```
or `---` inside notes can't break it. Opening an old multi-file vault auto-migrates
to this layout after a backup. A board of 10 projects → 10 files.

*Sources:* [Org Manual — Property Syntax](https://orgmode.org/manual/Property-Syntax.html);
[Obsidian Tasks — Emoji format](https://publish.obsidian.md/tasks/Reference/Task+Formats/Tasks+Emoji+Format);
[Dataview inline fields](https://blacksmithgu.github.io/obsidian-dataview/annotation/add-metadata/);
[TaskPaper guide](https://guide.taskpaper.com/getting-started/);
[Jekyll front matter](https://jekyllrb.com/docs/front-matter/);
[Obsidian — comments in reading view](https://forum.obsidian.md/t/comments-in-reading-mode/55613).

---

## 5. In-app auto-update (GitHub Releases)

Modeled on the MarkView desktop app's updater (`desktop/main.py`). Flow:

1. **Check:** `GET https://api.github.com/repos/<repo>/releases/latest`, read
   `tag_name`, find the first `.dmg` asset's `browser_download_url`, and compare
   the tag to the bundle's `CFBundleShortVersionString` (versions normalized to a
   padded 3-int tuple so `v1.2` == `1.2.0`). Anonymous API = 60 req/hour, plenty
   for one check per launch.
2. **Prompt:** on launch, if a newer release exists, ask the user
   (Update Now / Release Notes / Later). Also available in **About Kanpan** with a
   "Check for Updates" button.
3. **Install in place:** download the `.dmg` → `hdiutil attach` → spawn a
   *detached* bash helper that waits for the app to quit, copies the new
   `Kanpan.app` beside the old one, strips `com.apple.quarantine` (so Gatekeeper
   doesn't re-prompt the already-trusted bundle id), atomically swaps it in,
   detaches the DMG, and relaunches. Logs to
   `~/Library/Application Support/Kanpan/update.log`. Refuses to run when launched
   from the DMG mount (`/Volumes/…`).

Implemented in `Updater.swift` (native Swift port of the MarkView helper script).
