# Scope & Guardrails

What is actively being worked on, what is deferred, and what to avoid investing in prematurely. Consult this before proposing or starting new work.

---

## Currently In Scope

Based on ROADMAP.md phases 1–3, which are the active focus:

- Feed and post surfaces — loading, creation, images, likes, comments
- Follow/unfollow and social graph
- Discovery / explore screen
- Profile and pet management
- **1:1 chat (text MVP)** — promoted out of deferred in #45. Migration 016 backs `conversations` + `messages`; `ChatService` owns inbox/thread loads + optimistic send. Scope limited to text-only DMs between two users; the UI entry point for starting a new thread is still TBD (see known-issues.md).
- Performance and polish on the above

---

## Deferred — Do Not Invest Here Yet

- **Chat realtime, stickers, reactions, unread, presence** — #45 shipped the text-DM MVP, but typing indicators, online dots, sticker tray, per-message reactions, and unread badges are intentionally out of scope. The `messages` schema doesn't carry `last_read_at` / `read_by` yet; grow the schema before adding UI.
- **Push notifications** — Phase 6. No infrastructure exists for this yet.
- **Pet-specific follow** — Phase 4. Current follow graph is user-to-user only.
- **App Store / TestFlight prep** — Phase 6. Not a current concern.
- **Feed algorithm** — Phase 6. Feed is chronological for now; do not add ranking logic.
- **Passive virtual-pet decay** — #45 persisted the game loop, but there's no scheduled decay yet. Stats only change when the owner taps 喂食 / 玩耍 / 摸摸. A periodic RPC to nudge `pet_state` toward the time-derived baseline is an intentional follow-up.

---

## Guardrails

- Check `ROADMAP.md` and this file before starting any new feature work
- If a proposed change touches a deferred area, flag it and confirm before proceeding
- Prefer depth over breadth — finish and polish existing surfaces before adding new ones

---

_Update this file when phases shift or priorities change._
