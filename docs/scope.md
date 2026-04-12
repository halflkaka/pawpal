# Scope & Guardrails

What is actively being worked on, what is deferred, and what to avoid investing in prematurely. Consult this before proposing or starting new work.

---

## Currently In Scope

Based on ROADMAP.md phases 1–3, which are the active focus:

- Feed and post surfaces — loading, creation, images, likes, comments
- Follow/unfollow and social graph
- Discovery / explore screen
- Profile and pet management
- Performance and polish on the above

---

## Deferred — Do Not Invest Here Yet

- **Chat / messaging** — `ChatListView` exists as a shell only; wiring it to Supabase Realtime is Phase 5. Do not add logic or UI to this screen beyond the stub.
- **Push notifications** — Phase 6. No infrastructure exists for this yet.
- **Pet-specific follow** — Phase 4. Current follow graph is user-to-user only.
- **App Store / TestFlight prep** — Phase 6. Not a current concern.
- **Feed algorithm** — Phase 6. Feed is chronological for now; do not add ranking logic.

---

## Guardrails

- Check `ROADMAP.md` and this file before starting any new feature work
- If a proposed change touches a deferred area, flag it and confirm before proceeding
- Prefer depth over breadth — finish and polish existing surfaces before adding new ones

---

_Update this file when phases shift or priorities change._
