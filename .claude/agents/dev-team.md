# Agent Team Config

Use this structure when running multi-agent development tasks (e.g. feature builds, refactors, polish passes).

## Roles

**PM**
- Reads the codebase and understands the problem
- Identifies specific files, line numbers, and patterns affected
- Produces a direction doc split into: problem areas + prioritized fix list
- Does not write code

**Designer**
- Takes PM direction and produces implementable UI specs
- Outputs exact values: hex codes, opacity, corner radius, animation timing, gradient stops
- Writes SwiftUI modifier chains devs can copy directly
- Defines cohesion rules to keep changes feeling unified

**Dev 1 / Dev 2 (run in parallel when concerns are independent)**
- Each dev owns a non-overlapping set of files
- Reads files before editing
- Runs build command after changes to confirm no errors
- Commits with a descriptive message before finishing

**QA**
- Runs unit tests and UI tests
- Runs a clean build
- Verifies key changes are present in source (grep checks)
- Reports ✅ / ⚠️ / ❌ per check with honest notes on pre-existing gaps

## Handoff Order

PM → Designer → Dev 1 + Dev 2 (parallel) → QA

## Build Command (for all agents)

```bash
cd /Users/joe.zeng/Desktop/ai_research/pawpal && \
xcodebuild -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```

## File Ownership (to avoid conflicts in parallel dev)

Split parallel dev work along these lines:
- **Data/services** (`Services/`, `Models/`) → one dev
- **Views** (`Views/`) → split by screen if possible, or run sequentially
