# PawPal — Claude Instructions

## Project

SwiftUI iOS pet social app. Backend is Supabase (PostgreSQL, Auth, Storage). Main language is Swift. UI is Chinese-first with a warm, playful design system (`PawPalDesignSystem.swift`).

## Build & Test

```bash
# Build
xcodebuild -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Test
xcodebuild test -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Run the full test suite after every major change before considering work done. Follow the process in `docs/testing.md` — build, unit tests, UI tests, manual spot checks, then report results in the PR.

## Branch Naming

Use short kebab-case names scoped to the change:
- `feature/add-pet-profiles`
- `fix/feed-image-loading`
- `docs/pr-conventions`

Never commit directly to `main`.

## Pull Requests

Always follow the template at `docs/conventions/pr-template.md`.

Key rules:
- Include a 1-2 sentence Summary with line count (`X files, +Y / -Z lines`)
- Group changes by category (Performance, UI, Bug Fixes, etc.)
- Files Changed table organized by folder
- Validations section with ✅ / ⚠️ / ❌ and the exact test command used

## Agent Workflows

When running multi-agent tasks (PM → designer → dev → QA), use the configs in `.claude/agents/`. These define roles, responsibilities, and handoff structure for each agent type.

## Code Conventions

- Follow existing patterns in each file before adding new ones
- SwiftUI views: keep body lean, extract subviews and helper methods
- Design tokens live in `PawPalDesignSystem.swift` — add new ones there, never hardcode colors or spacing inline
- Haptic feedback: `UIImpactFeedbackGenerator(style: .light)` for navigation, `.medium` for primary actions
- Animations: `.spring(response: 0.35, dampingFraction: 0.6)` as the default for interactive elements

## Docs Structure

```
CLAUDE.md                           ← you are here
.claude/
├── skills/                         ← project-specific workflows
└── agents/                         ← agent team role configs
docs/
├── database.md                     ← schema design and table guide
├── pr-template.md                  ← PR description standard
├── testing.md                      ← QA process and test commands
└── sessions/                       ← dated working docs from agent sessions
```
