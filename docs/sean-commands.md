# Every command Sean needs — 2026-08-10

Ordered. Each step says WHY it precedes the next and how to undo it. Run from `~/dev/daengrun`
unless noted. Marked **[claude-able]** where I can run it for you (see §0).

## 0. What I can and cannot run for you

`CLAUDE.md` currently says `supabase db push`, `supabase functions deploy`, and `git push` are
Sean-only. That is your rule, so I have not touched them. If you want me to take them over, say so
and I will (and update CLAUDE.md so the law and the practice match — a law nobody follows is worse
than no law). What I genuinely **cannot** do regardless:

- Anything needing the **APNs `.p8` key**, App Store Connect, or your Apple account — I must never
  handle credentials.
- 사업자등록, 위치기반서비스 신고, 변리사/변호사 review, owner interviews.
- Physical-device smoke (I have the **simulator**, which covers most UI but not real GPS movement,
  real APNs delivery, or battery/thermal).

---

## 1. Ship the database — do this first

```bash
supabase db push
```
Carries **0063** (owner Live Activity) and **0064** (private media). Everything below depends on
schema that only exists after this.
⚠ Run it from the main checkout only. Never from a worktree that has an unfinished migration in
it — push applies every pending local file.
**Undo:** each migration file applies atomically; on failure nothing partial lands. If history
records a version you want to drop: `supabase migration repair --status reverted <ver>`.

```bash
supabase functions deploy transition-booking
```
Picks up the enroute exactly-once fix. Nothing else changed server-side this wave.
**Undo:** `git checkout ac936f5 -- supabase/functions/transition-booking && supabase functions deploy transition-booking`

## 2. Prove the seal is live and unexploited (2 queries, dashboard SQL editor)

```sql
select tgname from pg_trigger
where tgrelid = 'runners'::regclass and tgname = '_guard_runner_insert_cols';
```
Expect **1 row**. This is the P0 privilege-escalation seal. If it is missing, 0061 did not really
apply and everything below is built on sand.

```sql
select oid::regprocedure from pg_proc
where prosecdef and has_function_privilege('anon', oid, 'execute');
```
Expect **0 rows**. Any result is a definer function reachable by the anon key in your app bundle.

*(I already ran the exploitation check on 2026-08-10: 9 privileged runner rows, all accounted for
— 6 seed + 2 e2e + your own. Zero exploitation. Re-run only if you want a fresh read.)*

## 3. Decide the seed runners — before any real owner opens the app

Production has **6 fabricated certified/veteran/master runners** with `identity_verified: true`,
and **zero real runners**. `safety.tsx` now tells owners an operator personally verified each one
on video. That sentence is false while these exist.

```sql
-- Option A: demote (keeps the rows, kills the false claim)
update runners set tier = 'applicant', identity_verified = false, online = false
where profile_id in (select id from auth.users where email like '%@daengrun.seed');
```
```sql
-- Option B: delete (cascades their bookings/runs — only if you want the data gone)
delete from auth.users where email like '%@daengrun.seed';
```
**Recommend A** — reversible, and you may still want them for demos with the claim removed.

## 4. Native rebuild + simulator/device **[claude-able — I am running the prebuild now]**

```bash
cd app && npx expo prebuild -p ios --clean
```
Required by: background GPS (`UIBackgroundModes`, expo-task-manager) and both Live Activities
(`enablePushNotifications`, which I just added to app.json).
**Undo:** `app/ios` is gitignored build output; delete and re-run.

```bash
cd app && npx expo run:ios --device
```
Simulator build is `npx expo run:ios` with no flag — that one I can drive.

## 5. Owner Live Activity — the part only you can finish

The push path is built and sealed, but it has no relay yet. Three steps:

1. Write `supabase/functions/live-activity-push` — receives
   `{token, environment, event, activity, props, dismiss_sec, booking_id}` with
   `Authorization: Bearer <relay_secret>`, signs an ES256 JWT with your APNs `.p8`, POSTs to
   `api.push.apple.com` (or `api.sandbox.push.apple.com` when `environment = development`) with
   `apns-topic: com.seankookim.daengrun.push-type.liveactivity` and
   `apns-push-type: liveactivity`.
   Secrets: `supabase secrets set APNS_KEY_ID=... APNS_TEAM_ID=... APNS_P8="$(cat AuthKey_XXX.p8)"`
   **I can write this function for you — I just cannot hold the key.**
2. `supabase functions deploy live-activity-push`
3. Point the DB at it (service role, dashboard SQL):
   ```sql
   insert into owner_la_push_config (id, relay_url, relay_secret)
   values (true, '<function url>', '<a long random string>');
   ```
   Until this row exists the composer is a deliberate silent no-op — no phantom pipeline.

Also confirm `pg_cron` and `pg_net` are enabled on the hosted project (Database → Extensions).
The 90-second staleness sweep needs pg_cron; the push composer needs pg_net.

## 6. Media backfill — legacy photos are still public until this runs

```bash
node scripts/migrate-private-media.mjs            # dry run, shows what would move
node scripts/migrate-private-media.mjs --yes      # copy + rewrite DB rows (originals stay)
# verify photos still render in the app, then:
node scripts/migrate-private-media.mjs --yes --purge   # delete the public originals
```
New uploads are already private. **Existing dog/run/chat photos stay world-readable until the
purge step.** The privacy policy cannot claim "private" before then.
**Undo:** before purge, nothing is destructive — originals remain and rows can be pointed back.
After purge the originals are gone; the private copies are the only ones.

## 7. Push the code

```bash
git push
```
7 commits ahead of origin. Nothing here has left your machine yet.

## 8. Verify — the smoke list that actually matters

Full lists live in the handoff. The five that would each be a bug you ship if skipped:
1. **Lock the screen, pocket the phone, walk 500 m, unlock** — distance must reflect all of it.
2. Far-out confirmed job shows **no address and no red error strip** (the RPC's 24h window).
3. Dog-less pay tap → routes to `/owner/dog` and creates **no** dogs row.
4. After the backfill, dog and run photos still render (they are signed URLs now).
5. Owner Live Activity appears at handoff and **goes grey with "위치가 갱신되지 않았어요"** when
   updates stop — that state is the honesty contract, not a nicety.

## 9. Off the machine entirely

- 변호사: `docs/legal/privacy-policy.md` + `terms-of-service.md` (open questions marked inline)
- 위치기반서비스사업 신고 (방통위)
- 사업자등록 ⟷ 예비창업패키지 2027 fork, then PG
- 15-20 owner interviews + the two anchor-free price questions
- App Store Connect privacy labels (`docs/appstore-privacy-answers.md`), then
  `eas build --profile testflight -p ios` → `eas submit -p ios`
