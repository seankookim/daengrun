# 댕런 DaengRun

반려견 러닝 매칭 서비스 — 바쁜 보호자를 위해 검증된 러너가 반려견과 함께 달립니다.

> Working name. Rename freely.

## What's here

- `app/` — the real app: Expo (React Native) + TypeScript + Supabase
- `prototype/index.html` — clickable UI prototype (open in browser)
- `docs/product-notes.md` — product decisions, open questions, roadmap

## Run the app

```bash
cd app
npm install
cp .env.example .env   # fill in Supabase keys (supabase.com → free project)
npx expo start         # scan QR with Expo Go on your phone
```

## Prototype

Single-file HTML, no build step. Open `prototype/index.html` in any browser.
Demo jump buttons on the left let you skip to any flow.

## Core concept

- Two-sided app: 보호자 (owner) / 러너 (runner), role toggle at signup
- Trust stack: 신원인증, 펫보험, live GPS, bodycam live feed, photo check-ins
- Hybrid matching: preference-based auto-recommendation (residency-match style) + browsable alternatives for both sides
- Revenue: booking commission, premium add-ons (river-view routes, dirt-only, snack breaks, dog meetups), shop, membership
