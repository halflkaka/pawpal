# PawPal App Context

## Current Product Direction

The app started as a local-first pet health / symptom checker iOS app, then pivoted toward a **pet social / pet life app**.

The current design reference is **WeChat Moments (朋友圈)**, not Instagram.

That means the app should feel:
- simple
- personal
- diary-like
- local-first
- softer and less creator/platform-like

## Core Product Shape

The app is now moving toward:
- **Moments**: a local feed of pet updates
- **Post**: create a pet moment/post
- **Pets**: manage pet profiles
- **Care**: pet health / AI help / symptom checking
- **Vets**: nearby veterinarian finder

The health feature is no longer the whole product. It is now just one part of a broader pet-life app.

## Current Technical Setup

Repo:
- `/Users/canjie/Documents/PawPal`

GitHub:
- `https://github.com/halflkaka/pet-health`

Local app architecture:
- SwiftUI
- SwiftData
- local-first storage
- FastAPI backend for AI pet care/symptom analysis

Backend path:
- `/Users/canjie/Documents/PawPal/pet-health-backend`

## Current UX Principles

- Keep it local-first and lightweight
- Avoid unnecessary cloud/account complexity for now
- Keep the UI more like WeChat Moments than Instagram
- Prefer simple, obvious interactions over clever ones
- Fix broken behavior first, then polish UI
- When the user says "yes" or "do it", that means actually make the change now, not just discuss it

## Features Already Started

### Social / Moments
- Bottom tab bar with Moments / Post / Pets / Care / Vets
- Local posts feed
- Create Post flow
- Local photo picking for moments posts
- Feed displays saved local images

### Pets
- Multiple pet profiles
- Selected pet state
- Pet profiles stored locally
- Ongoing UX iteration needed to keep the Pets flow obvious and reliable

### Care
- Symptom checking flow still exists
- Local symptom history
- OpenAI-backed analysis backend
- Vet finder still available

## Important Product Intent

This should feel like a **pet life app with care tools**, not a clinical medical app.

Better framing:
- pet moments
- pet profile
- pet journal
- pet care helper
- nearby vets

Not:
- a pure AI diagnosis app

## Current Iteration Direction

Short-term iteration priorities:
1. Make Moments feel even more like WeChat Moments
2. Improve post composer and feed visual language
3. Keep Pets flow extremely obvious and reliable
4. Integrate Care more naturally into the broader app
5. Continue local-first until a real need for cloud/social backend exists

## Notes For Future Iteration

- Broken flows should be reproduced and verified, not just visually guessed at
- Add tests when behavior is repeatedly breaking
- During this prototype stage, local data resets due to SwiftData schema evolution are acceptable if needed
- Prefer real commits/builds over status talk
