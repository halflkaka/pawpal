# Testing & Validation Design

## Goal

Hybrid test suite that runs after every major change. Fast unit tests cover validation logic; targeted XCUITests cover critical end-to-end paths. Total runtime ~2 min.

## Unit Tests

Added to `PawPalTests/ValidationTests.swift`. No network, no simulator — runs in ~5s.

| Group | What's tested |
|---|---|
| Auth | Empty email throws, empty password throws |
| Pet | `normalizeRequired` with empty/whitespace → nil; `normalizeOptional` empty → nil |
| Post | `canPost` false with no pet; false with empty caption; true when both present |
| Profile | Empty username throws "Username is required." |

Auth service guards throw before hitting the network, so no mocking needed. Pet normalization helpers made `internal` to be accessible from tests.

## XCUITests

Added to `PawPalUITests/PawPalUITests.swift`. 4 tests only.

1. `testAppLaunchShowsAuthScreen` — verify auth UI is visible on cold launch
2. `testLoginWithValidCredentials` — sign in, verify feed loads
3. `testLoginWithWrongPassword` — bad password, verify error message appears
4. `testPostButtonDisabledWithoutCaption` — log in, go to Create tab, leave caption empty, verify post button disabled

Screenshot captured after each test.

## Credentials

Stored in `PawPalUITests/TestConfig.swift` (gitignored). Never committed.

## Run Command

```bash
xcodebuild test -project PawPal.xcodeproj -scheme PawPal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

## When to Run

After every major change before considering work done.
