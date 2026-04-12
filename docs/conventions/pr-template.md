# PR Description Template

Every PR should follow this structure. Keep each section concise — the goal is for a reviewer to understand what changed, why, and whether it's safe to merge in under 2 minutes.

---

## Template

```
## Summary

1-2 sentences: what this PR does and why.
X files changed, +Y / -Z lines.

## Changes

### [Category]
- **Name** — what changed and why

### [Category]
- **Name** — what changed and why

## Files Changed

| Folder | Files |
|---|---|
| `path/to/folder/` | `File1.swift`, `File2.swift` |

## Validations

- ✅ / ⚠️ / ❌ **Check name** — one line result or note

Tested with: `<command>`
```

---

## Section Guide

**Summary**
- What the PR does in plain language — no jargon
- Include the scope: `X files changed, +Y / -Z lines`

**Changes**
- Group by category (e.g. Performance, UI, Bug Fixes, Refactor, Docs)
- Each bullet: `**Short name** — what changed and why it matters`
- One bullet per distinct change — don't bundle unrelated things

**Files Changed**
- Group files by folder, listed as a table
- No need to re-describe changes here — that's what the Changes section is for

**Validations**
- ✅ passed, ⚠️ known gap or caveat, ❌ failing (explain why it's okay to merge)
- Always include the exact test command so results are reproducible
- Be honest about gaps — note pre-existing issues separately from regressions

---

## Example

```
## Summary

Performance and visual polish pass on the feed, create post, and profile screens.
Fixes a batched query bottleneck that was firing N network calls per feed load.

9 files changed, +237 / -58 lines.

## Changes

### Performance
- **Batched comment count refresh** — replaced per-post network loop with a single `.in()` query; reduces N round-trips to 1 after every feed load
- **Stable ForEach identity** — added `id: \.id` to feed post list; prevents full-list redraws when likes or comment counts update

### UI
- **Like button feedback** — fires medium haptic on tap, switches to red gradient capsule when liked
- **Mood emoji picker** — replaced free-text field with horizontal emoji row; reduces friction and makes selection more visual

### Bug Fixes
- **URL validation** — `RemotePost.imageURLs` now requires a valid scheme; fixes incorrect image rendering

## Files Changed

| Folder | Files |
|---|---|
| `PawPal/Models/` | `RemotePost.swift` |
| `PawPal/Services/` | `PostsService.swift` |
| `PawPal/Views/` | `FeedView.swift`, `CreatePostView.swift` |

## Validations

- ✅ **Clean build** — no errors
- ✅ **Unit tests** — 5/5 pass
- ⚠️ **`testCanAddPetAndSeeItInProfilesAndHome`** — pre-existing gap; requires Supabase mock, not a regression

Tested with: `xcodebuild test -project PawPal.xcodeproj -scheme PawPal -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
```
