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

*Sources:* [Asana — subtasks](https://help.asana.com/s/article/subtasks) and
[when to use them](https://asana.com/resources/asana-tips-subtasks);
[Linear — parent & sub-issues](https://linear.app/docs/parent-and-sub-issues);
[Notion — tasks & sub-items](https://www.notion.com/help/tasks-and-dependencies);
[Atlassian — convert checklist item to card](https://community.atlassian.com/forums/Trello-questions/Converting-a-Checklist-item-automatically-to-a-card/qaq-p/1446104);
[ClickUp — nested subtasks](https://help.clickup.com/hc/en-us/articles/6304431740055-Create-nested-subtasks);
[Interaction Design Foundation — Progressive Disclosure](https://www.interaction-design.org/literature/topics/progressive-disclosure).
