# QA & Testing Guide

This guide defines how to validate changes in PawPal. Run this after every major change before considering work done.

---

## When to Run

- After any change touching a view, service, or model
- Before opening a PR
- After merging another branch into your working branch
- Any time the build or test suite has not been run in the current session

---

## Step 1 — Build

Always start with a clean build. A failing build means nothing else matters.

```bash
xcodebuild -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

If it fails, fix all errors before proceeding. Warnings are okay but worth noting if they are new.

---

## Step 2 — Unit Tests

Run the unit test suite. These are fast (~5s) and require no simulator interaction.

```bash
xcodebuild test -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PawPalTests 2>&1 | grep -E "(PASS|FAIL|error:)" | head -20
```

**Current tests and what they cover:**

| Test | Covers |
|---|---|
| `remotePostImageSortsByPosition` | Image ordering in posts |
| `remotePostImageURLsFilterInvalid` | URL validation in `RemotePost.imageURLs` |
| `likeCount` | Like counter and `isLiked(by:)` logic |
| `commentCount` | Comment count on posts |
| `remotePetAgeAccessor` | Pet age property getter/setter |

All 5 should pass. A failure here is a regression — fix before merging.

---

## Step 3 — UI Tests

Run the UI test suite. These launch the simulator and test real interactions.

```bash
xcodebuild test -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PawPalUITests 2>&1 | grep -E "(PASS|FAIL|error:)" | head -20
```

**Current tests:**

| Test | Status | Notes |
|---|---|---|
| `testLaunch` | ✅ Should pass | App launches and renders auth screen |
| `testLaunchPerformance` | ✅ Should pass | Launch time baseline |
| `testCanAddPetAndSeeItInProfilesAndHome` | ⚠️ Pre-existing gap | Requires Supabase mock; not a regression |

If `testLaunch` or `testLaunchPerformance` fail, that is a regression — investigate before merging.

---

## Step 4 — Manual Spot Checks

For changes touching views, do a quick pass in the simulator after running tests:

| Area changed | What to check |
|---|---|
| Feed | Scrolls smoothly, images load, likes and comments work |
| Create Post | Mood picker, image selection, post submits |
| Profile | Pet cards show correctly, empty state renders if no posts |
| Auth | Login and registration complete without errors |
| Navigation | Tab switching works, no broken navigation states |

---

## Reporting Results

Use this format in PR descriptions and commit messages:

```
- ✅ Clean build
- ✅ Unit tests — 5/5 pass
- ✅ UI tests — launch and performance pass
- ⚠️ testCanAddPetAndSeeItInProfilesAndHome — pre-existing gap, not a regression
```

**Signal meanings:**
- ✅ Passed as expected
- ⚠️ Known gap or caveat — document it, do not treat as blocking unless it is new
- ❌ Failing — must be fixed or explicitly accepted before merging

---

## Adding New Tests

When adding a new feature or fixing a bug, add a corresponding test:

- **Pure logic** (model methods, validation, normalization) → unit test in `PawPalTests/`
- **UI flows** (navigation, form submission, screen states) → UI test in `PawPalUITests/`
- Use accessibility identifiers (`.accessibilityIdentifier("name")`) to make UI elements testable
- New UI tests that require auth should use launch arguments (`UI_TESTING`) rather than live Supabase calls
