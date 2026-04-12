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

Always follow the template at `docs/pr-template.md`.

Key rules:
- Include a 1-2 sentence Summary with line count (`X files, +Y / -Z lines`)
- Group changes by category (Performance, UI, Bug Fixes, etc.)
- Files Changed table organized by folder
- Validations section with ✅ / ⚠️ / ❌ and the exact test command used

## Changelog

After every PR is merged, add an entry to `CHANGELOG.md` at the repo root.

- Copy the PR description directly — no need to rewrite it
- Add a header: `## YYYY-MM-DD — PR title ([#N](url))`
- Entries go at the top, in reverse chronological order

## Before Starting Work

Before proposing or starting any change:
1. Check `ROADMAP.md` for current phase and direction
2. Check `docs/scope.md` for what is deferred — do not invest in those areas
3. Check `docs/decisions.md` for architectural decisions that must not be undone
4. Check `docs/known-issues.md` for existing problems that may be relevant

## Do Not Break

These flows must work after every change. Verify manually in the simulator if they could be affected:

- **Auth** — sign in and registration complete without errors
- **Feed** — loads posts, images render, like and comment counts are correct
- **Create post** — pet selection, caption, image upload, and submission all work
- **Profile** — pet cards display, post grid loads, follow counts are correct

## Agent Workflows

For larger changes or changes spanning multiple concerns (performance + UI, new feature + tests, etc.), proactively spin up an agent team rather than working sequentially. A typical team:

- **PM** — reads the codebase, understands the problem, produces a direction doc with specific files and priorities
- **Designer** — translates PM direction into exact SwiftUI specs (colors, modifiers, animation params)
- **Dev(s)** — implement in parallel when concerns are independent (e.g. one dev on services, one on views)
- **QA** — runs build, tests, and spot checks after dev work; reports results

Use the configs in `.claude/agents/dev-team.md` for role definitions and handoff order. Default to agent teams for anything touching 3+ files or 2+ concerns.

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
├── decisions.md                    ← architectural and product decisions and their reasoning
├── known-issues.md                 ← known bugs, gaps, and tech debt
├── pr-template.md                  ← PR description standard
├── scope.md                        ← what is in scope, deferred, and off-limits
├── testing.md                      ← QA process and test commands
└── sessions/                       ← dated working docs from agent sessions
```
