# App Store Connect privacy answers + Google Play Data Safety

Written 2026-08-08 from a code audit of the actual data paths, not from intent. Every row cites
where the data is written or read. Use this to fill the App Store Connect privacy questionnaire
and the Play Data Safety form, and as the factual base for 개인정보처리방침.

Re-audit this file whenever a new table, bucket, or third-party SDK lands. A privacy label that
does not match behavior is a rejection risk on review and a compliance problem after launch.

## Headline answers

- **Do you collect data?** Yes.
- **Do you use data to track users** (Apple's definition: linking to third-party data for ads or
  sharing with data brokers)? **No.** `[verified]` — package.json has no analytics, ad, attribution,
  or crash SDK: no Sentry, Firebase, Amplitude, Mixpanel, Segment, Facebook, AdMob, AppsFlyer,
  Adjust, or Branch. So no App Tracking Transparency prompt is required.
- **Third parties that receive data:** Supabase (backend host, processor) · Expo push service
  `exp.host` (push token + notification title/body, via the `pg_net` trigger in `0024_push.sql`)
  · Naver Maps SDK (map rendering, client id in `app.json`). All processors, not brokers.

## Data inventory

| Apple category | Collected | Linked to user | Purpose | Where in code |
|---|---|---|---|---|
| Email address | Yes | Yes | Account auth | `auth.users` (Supabase OTP) |
| Name | Yes | Yes | App functionality — shown to the other party | `profiles.name` (0001:29) |
| Phone number | Optional | Yes | App functionality — contact during handoff **and during an open incident** | `profiles.phone` (0001:30, nullable) · `incident_contact(booking)` (0088 §E) |
| **Precise location** | **Yes** | **Yes** | **App functionality — the core product** | `geo.ts` watchPositionAsync → `runs.trace`, live sharing |
| Photos | Yes | Yes | App functionality — dog profile, run photos, gear proof | `avatars` bucket via `api.ts` (see the warning below) |
| Other user content | Yes | Yes | App functionality — chat, reviews, dog memos | `chat_messages`, `reviews`, `dogs.memo` |
| User ID | Yes | Yes | App functionality | `profiles.id` (uuid) |
| Device ID | Yes | Yes | Push delivery | `push_tokens.token` (Expo token, 0024) |
| Purchase history | Yes (once PG lands) | Yes | App functionality — booking and settlement records | `bookings`, `ledger_items` |
| Crash / diagnostics | No | — | — | no crash SDK installed |
| Health & Fitness | **No** | — | — | fitness metrics describe the **dog**, not the user. Do not tick Apple's Health category; it means the user's own health data. |

## Two things to fix or disclose before submitting

1. **The `avatars` bucket is public-read and holds far more than avatars.** `0006_avatars.sql:5`
   creates it with `public = true`, and `api.ts` routes profile photos, dog photos, run photos,
   gear proof photos, and 인증샷 through the same bucket. Anyone with a URL can read it without
   auth, and paths follow `{uid}/...`, so they are partly guessable. Two options: (a) declare it
   accurately in the privacy policy as publicly-accessible media, or (b) move non-avatar media to
   a private bucket with signed URLs — that is a breaking change and needs its own slice.
   **Decide before the policy is published, since the policy has to describe whichever is true.**
2. ~~`RECORD_AUDIO` was declared on Android with nothing using the microphone~~ — removed
   2026-08-08. Nothing in the app records audio or video (no expo-av, no video capture), so the
   permission was pure liability: a scary install prompt and a Data Safety row for a feature that
   does not exist. Re-add only if a real audio feature ships.

## iOS permission strings currently declared (`app.json`)

- `NSLocationWhenInUseUsageDescription` — "러닝 거리 측정과 보호자 실시간 지도를 위해 위치를 사용해요."
- `NSCameraUsageDescription` — "러닝 중 반려견의 순간을 촬영해 보호자에게 보내기 위해 카메라를 사용해요."
- Photo library strings come from the `expo-image-picker` plugin config.

**Background location is not declared yet.** When the background-GPS fix lands it adds
`NSLocationAlwaysAndWhenInUseUsageDescription` plus the `location` background mode, and Apple
reviews that closely — expect to justify it in the review notes. Suggested justification: runs
last 30-60 minutes with the phone pocketed; without background location the distance the owner
is charged for and the route shown to them would both be wrong. That is an honest and
reviewable reason.

## Review notes to include in the submission

- Demo account with a booking already in `confirmed` state, plus a second account for the runner
  side, so the reviewer can walk the handoff without needing two devices.
- Explain that money movement is real-world service payment (dog running), not digital content,
  so IAP does not apply — the same category as ride-hailing or food delivery.
- If bodycam wording still appears in any store metadata, remove it: there is no bodycam pipeline
  (see the launch checklist's closing note).
