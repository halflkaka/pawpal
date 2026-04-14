---
name: retro-pr
description: Retrospectively bring a merged PR and project docs up to standard. Invoke with a PR number, e.g. /retro-pr 13. Skips work where standards are already met.
user-invocable: true
---

# Retro PR

Bring a merged PR and its associated docs up to the project's standards.
Invoked as `/retro-pr <number>` (e.g. `/retro-pr 13`).

## Step 1 — Fetch PR context

Run in parallel:
- `gh pr view <N> --json number,title,body,files,mergedAt,url` — get PR metadata and file list
- `git log --oneline origin/main | head -20` — confirm latest state of main

## Step 2 — Triage (exit early if already compliant)

Check the PR title and body against `docs/conventions/pr-template.md`.

A compliant PR description has ALL of the following:
- **Summary** section with a 1-2 sentence description and `X files, +Y / -Z lines`
- **Changes** section grouped by category with `**Name** — explanation` bullets
- **Files Changed** table grouped by folder
- **Validations** section with ✅/⚠️/❌ items and the exact test command

Check docs for existing entries:
- `CHANGELOG.md` — does it already have a `## YYYY-MM-DD — <title> (#N)` entry for this PR?
- `ROADMAP.md` — are phase statuses accurate against the actual code changes in this PR?
- `docs/known-issues.md` — did this PR fix any listed issue? Is the issue still listed?
- `docs/decisions.md` — did this PR make a notable architectural choice not yet documented?

**If the PR description is compliant AND all docs are up to date → report "PR #N already meets standards, nothing to do" and stop.**

Only proceed to the steps below where there are actual gaps.

## Step 3 — Read the changed files

For each file in the PR's file list, read enough of the diff (or the current file) to understand:
- What was changed and why
- Whether it fixes a known issue
- Whether it introduces a notable architectural decision
- The actual line counts (+additions / -deletions)

Use `gh api repos/halflkaka/pawpal/pulls/<N>/files` for the full diff if needed.

## Step 4 — Update the PR description (if non-compliant)

Rewrite the PR body to match the template in `docs/conventions/pr-template.md`:

```
## Summary
<1-2 sentences: what and why>
X files changed, +Y / -Z lines.

## Changes
### [Category]
- **Name** — what changed and why

## Files Changed
| Folder | Files |
|---|---|
| `path/` | `File.swift` |

## Validations
- ✅ / ⚠️ / ❌ **Check** — result or note

Tested with: `<command>`
```

Apply with: `gh pr edit <N> --title "<title>" --body "..."`

Keep the original title if it's already descriptive. Rewrite only if it's too vague or only a conventional-commit prefix with no context.

For Validations: if you cannot determine actual test results, use ⚠️ with a note like "build and test results not available for retrospective PRs".

## Step 5 — Update CHANGELOG.md (if missing entry)

Add at the top of `CHANGELOG.md`, below any existing entries:

```
## YYYY-MM-DD — <PR title> ([#N](<PR url>))

<paste the updated PR description here>
```

Use the PR's `mergedAt` date for YYYY-MM-DD.

## Step 6 — Check and update other docs (only if gaps exist)

**ROADMAP.md** — read the current file and compare phase statuses against what the PR actually changed. Update only if a status marker is wrong (e.g. a completed feature is still marked 🔲).

**docs/known-issues.md** — if the PR resolves a listed issue, remove that entry.

**docs/decisions.md** — if the PR introduced a non-obvious architectural choice (new pattern, tech selection, significant tradeoff), add an entry. Skip for routine feature work.

**docs/scope.md** — if deferred items became active or active items were dropped, update accordingly.

## Step 7 — Commit doc changes to main

Stage only the doc files that were actually changed:

```bash
git checkout main && git pull
git add <only changed doc files>
git commit -m "docs: retro update for PR #N — <short description>"
git push
```

Use a short, descriptive commit message. Do not amend — always a new commit.

## Step 8 — Report

Summarize what was done (or skipped and why):
- PR description: updated / already compliant
- CHANGELOG: added entry / already present
- ROADMAP: updated / already accurate
- known-issues / decisions / scope: updated / no changes needed
