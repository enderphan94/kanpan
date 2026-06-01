# Kanpan

A tidy, **Markdown-native** Kanban task board for macOS. Track projects through
**Not Started → In Progress → On Hold → Completed**, break big projects into
sub-tasks with roll-up progress, and keep everything in a plain folder of `.md`
files you fully own — back it up, sync it with iCloud, or edit it in Obsidian.

No account. No team features. No cloud. Just your tasks, as Markdown.

<p align="center"><img src="docs/icon.png" width="120" alt="Kanpan icon"></p>

---

## Why Kanpan

It takes the genuinely good ideas from **Microsoft Planner** — a small, opinionated
task model; a one-click complete on the card; quiet cards that only show an icon
when a field is actually set; drag-a-card-to-change-its-status — and fixes
Planner's biggest weakness: its flat, 20-item **checklist** is useless when a big
project contains many smaller sub-projects. (See [docs/RESEARCH.md](docs/RESEARCH.md)
for the full research write-up.)

Kanpan's answer: **one level of real sub-tasks**, each with its own status, due
date, and notes, with an **automatic roll-up progress bar** on the parent and
**drill-in** navigation — the pattern Asana, Linear, and Notion all converge on.

---

## Features

| Area | What you get |
|---|---|
| **Two views** | **Board** (Kanban) and **Grid** (sortable table) — toggle in the toolbar (⌘1 / ⌘2). |
| **Status columns** | `Not Started · In Progress · On Hold · Completed`, each a distinct, calm color. Marking a task **Done** lands it in the **Completed** column. |
| **Drag to change status** | Drag a card between columns to set its status; drop on a card to reorder within a column. |
| **One-click complete** | A checkmark on every card — complete without opening it. |
| **Sub-projects done right** | Open a card to add sub-tasks (status + due date + notes each). The parent shows a live **x / y** progress bar. **Drill in** to any sub-task via the breadcrumb, or **promote** one to a top-level card / its own board. |
| **Priority** | Urgent / Important / Medium / Low. Only above-normal priorities show a flag, so boards stay scannable. |
| **Labels** | Colored, multi-select labels with stable auto-assigned colors. |
| **Due dates** | Start + due dates; overdue shows red. |
| **Markdown notes** | Each task has a Markdown notes body with a **Write / Preview** toggle. |
| **Vault** | Obsidian-style: your data is a folder of `.md` files. Create, open, or switch vaults; reveal in Finder; reload from disk. |
| **Search** | Filter the current board by title, notes, or label. |

---

## Install

1. Download / open `dist/Kanpan-1.0.0.dmg`.
2. Drag **Kanpan** onto **Applications**.
3. **First launch:** right-click **Kanpan → Open → Open** (the app is unsigned,
   so Gatekeeper needs a one-time confirmation).
4. Choose where to keep your **Vault** (or use the suggested location).

> The app is ad-hoc signed, not notarized. To distribute without the right-click
> step, sign with a Developer ID and notarize.

---

## How your data is stored

A **vault** is one directory. Each **board** is a folder inside it; each **task**
is a single `.md` file — YAML-style front-matter plus a Markdown notes body:

```
My Vault/
├─ My Board/
│  ├─ Redesign landing page.md      ← a task
│  └─ Build hero section.md         ← a sub-task (front-matter has `parent:`)
└─ Personal/
   └─ Taxes.md
```

A task file looks like this — fully human-readable and editable anywhere:

```markdown
---
id: 7F3A2C...
title: Redesign landing page
status: in-progress
priority: important
due: 2026-06-15
labels: [Design, Frontend]
order: 2
created: 2026-06-01T10:00:00Z
updated: 2026-06-01T11:30:00Z
---

# Goals

- Hero section
- **Bold** copy
```

- **Identity** is the `id` in front-matter, so renaming a task (which renames its
  file) never breaks links or sub-task relationships.
- **Sub-tasks** point at their parent via `parent:`. Hierarchy is capped at one
  level by design.
- A plain `.md` file with no front-matter is still imported as a task (titled by
  its filename), so an existing vault stays readable.
- A hidden `.kanpan.json` holds only non-content UI prefs (board order); all task
  data lives in the Markdown.

Because it's just files: back up with a folder copy, sync via iCloud/Dropbox, and
edit in Obsidian, VS Code, or vim.

---

## Build from source

Requirements: macOS 14+, Xcode command-line tools (Swift 5.9+). No package
dependencies.

```bash
./build.sh        # → dist/Kanpan.app  (compiles, makes the icon, signs)
./make_dmg.sh     # → dist/Kanpan-1.0.0.dmg
```

The app is a SwiftUI application compiled directly with `swiftc` (no `.xcodeproj`
needed) and assembled into a bundle by the scripts.

---

## Project layout

```
Kanpan/
├─ Sources/
│  ├─ Model.swift            # TaskStatus, Priority, KTask, Board
│  ├─ Markdown.swift         # front-matter (de)serialization + safe file names
│  ├─ Vault.swift            # filesystem store (boards, tasks, prefs)
│  ├─ Store.swift            # AppStore: app state + persistence orchestration
│  ├─ Theme.swift            # status / priority / label colors
│  ├─ Components.swift       # shared chips, badges, menus
│  ├─ MarkdownView.swift     # lightweight Markdown preview renderer
│  ├─ App.swift              # @main + menu commands
│  ├─ WelcomeView.swift      # first-launch vault chooser
│  ├─ MainView.swift         # sidebar + toolbar + content shell
│  ├─ BoardView.swift        # the Kanban board
│  ├─ TaskCardView.swift     # a board card
│  ├─ GridView.swift         # the table view
│  └─ TaskDetailView.swift   # detail sheet + sub-task manager
├─ scripts/make_icon.swift   # generates the app icon (CoreGraphics)
├─ build.sh                  # compile + bundle + sign
├─ make_dmg.sh               # package the .dmg
└─ docs/RESEARCH.md          # Planner + sub-task nesting research
```

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘N | New task |
| ⇧⌘N | New board |
| ⌘1 / ⌘2 | Board / Grid view |
| ⌘R | Reload vault from disk |
| ⌘F | Search |
