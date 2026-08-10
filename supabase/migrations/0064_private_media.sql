-- ═══ 0064: private media bucket — dog/run/chat photos leave the world-readable avatars bucket ═══
--
-- Problem (privacy audit): 0006 created `avatars` with public = true and a bucket-wide anon
-- select policy, and EVERY upload path in the app routed through it — including dog photos,
-- run photos (routes, 인증샷) and chat photos. Paths follow {uid}/..., so a stranger with a
-- known profile id could fetch another user's dog photos and run-photo evidence with no auth.
--
-- Split decision (stated, not implied):
--   STAYS PUBLIC in `avatars` — deliberately self-published storefront content:
--     · profiles.avatar_url   ({uid}/avatar.jpg)      — shown to prospective counterparties pre-booking
--     · runners.photos        ({uid}/gallery/*)       — runner marketing gallery
--     · runner_gear.photo_url ({uid}/gear/*)          — gear proof IS the storefront trust signal
--                                                       (runner_gear has `select using (true)` by design;
--                                                        0019 check constraint verified_at ⇒ photo_url untouched)
--     · clubs.photo_url       ({uid}/club-{id}.jpg)   — club discovery branding
--   MOVES PRIVATE to `media` — content about someone's private life, not their storefront:
--     · dogs.photo_url             {uid}/dogs/{dogId}.jpg
--     · runs.photos[]              {uid}/runs/{bookingId}/{ts}.jpg
--     · chat_messages.media_path   {uid}/chat/{threadId}/{ts}.jpg
--     · club_chat_messages.media_path {uid}/clubchat/{sessionId}/{ts}.jpg
--
-- Read model: private objects are addressed by bare storage path in the DB columns; clients
-- resolve them to short-TTL signed URLs (app/src/lib/media.tsx). Legacy rows keep full http
-- URLs into the still-public avatars bucket and render unchanged until the one-shot backfill
-- (scripts/migrate-private-media.mjs) copies objects and rewrites rows one at a time.
--
-- Access model (party gate first; visibility of a photo = visibility of a row referencing it):
--   · own folder            — full CRUD, nothing else may write outside its own {uid}/ prefix
--   · dogs/*                — any signed-in user. This mirrors actual product semantics: dog
--                             photos appear on district leaderboards (0012 definer RPCs) and
--                             open-pool request cards shown to every runner. Party-scoping the
--                             storage object while a definer RPC hands the path to everyone would
--                             just render broken images app-wide. The win over 0006 is real and
--                             is what this migration claims: no anonymous/world access, no
--                             crawlable permanent URLs, TTL-bound links.
--   · runs/*                — booking party (delegated to runs RLS "runs party read" =
--                             is_booking_party), OR anyone once the owner explicitly shared the
--                             photo to the public feed (feed_posts row referencing the path).
--   · chat/*                — thread party (delegated to chat_messages RLS).
--   · clubchat/*            — exactly whoever can see the message row (delegated to
--                             club_chat_messages RLS: group = full/host shell access, host
--                             channel = host + the applicant it addresses); a deleted message
--                             (club_chat_delete RPC) seals its photo even if the best-effort
--                             storage removal failed.
-- Delegation runs the referencing tables' own RLS as the caller (subqueries in policies are
-- invoker-rights) — no new definer functions, so no new search_path/grant surface.
-- No enumeration oracle: select governs list; a caller only ever sees objects whose referencing
-- row its existing RLS already shows it.

insert into storage.buckets (id, name, public)
values ('media', 'media', false)
on conflict (id) do nothing;

-- ---------- write: own {uid}/ folder only (NULL-safe: auth.uid() is null ⇒ no row passes) ----------
drop policy if exists "media owner insert" on storage.objects;
create policy "media owner insert" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'media'
    and auth.uid() is not null
    and (storage.foldername(objects.name))[1] = auth.uid()::text
  );

drop policy if exists "media owner update" on storage.objects;
create policy "media owner update" on storage.objects
  for update to authenticated using (
    bucket_id = 'media'
    and auth.uid() is not null
    and (storage.foldername(objects.name))[1] = auth.uid()::text
  );

drop policy if exists "media owner delete" on storage.objects;
create policy "media owner delete" on storage.objects
  for delete to authenticated using (
    bucket_id = 'media'
    and auth.uid() is not null
    and (storage.foldername(objects.name))[1] = auth.uid()::text
  );

-- ---------- read: owner, or the counterparty whose row-level view already includes the photo ----------
drop policy if exists "media party read" on storage.objects;
create policy "media party read" on storage.objects
  for select to authenticated using (
    bucket_id = 'media'
    and auth.uid() is not null
    and (
      (storage.foldername(objects.name))[1] = auth.uid()::text
      or case (storage.foldername(objects.name))[2]
           -- dog photos: any signed-in user (leaderboards/open-pool cards show them by design)
           when 'dogs' then true
           -- run photos: booking party via runs RLS, or explicitly feed-shared by the owner
           when 'runs' then
             exists (select 1 from public.runs r where r.photos @> array[objects.name])
             or exists (select 1 from public.feed_posts fp where fp.photo_url = objects.name)
           -- 1:1 booking chat: thread party via chat_messages RLS
           when 'chat' then
             exists (select 1 from public.chat_messages m where m.media_path = objects.name)
           -- club session chat: message-level visibility via club_chat_messages RLS;
           -- deleted messages seal their photo
           when 'clubchat' then
             exists (select 1 from public.club_chat_messages m
                      where m.media_path = objects.name and m.deleted_at is null)
           else false
         end
    )
  );

-- ---------- lookup indexes for the delegation subqueries (signing hits these per request) ----------
create index if not exists chat_messages_media_path_idx
  on chat_messages (media_path) where media_path is not null;
create index if not exists club_chat_messages_media_path_idx
  on club_chat_messages (media_path) where media_path is not null;
create index if not exists feed_posts_photo_url_idx
  on feed_posts (photo_url) where photo_url is not null;
create index if not exists runs_photos_gin_idx on runs using gin (photos);
