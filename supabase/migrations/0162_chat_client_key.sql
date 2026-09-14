-- 0162 — chat messages carry a client idempotency key, and the same key cannot land twice
--
-- The client's send path is a direct INSERT under RLS (0114 「messages party send」). When the
-- response is lost after the row committed, the client cannot know whether it sent, and a
-- naive retry double-posts. The UI session named this in its round-3 wave (2b63484: chat.tsx
-- carried only a COMMENT saying the server half was owed). This is that half.
--
-- Shape: a nullable `client_key uuid` (legacy writers and rows are untouched) + a PARTIAL unique
-- index on (thread_id, client_key) where the key is present. A retry with the same key raises
-- SQLSTATE 23505, which the client maps to success (api.ts sendChatMessage / sendChatPhoto).
-- The key is thread-scoped so one client's uuid space cannot collide across threads by accident,
-- and NULL keys are never compared (partial index), so nothing that does not send a key changes.
--
-- No policy change: the INSERT policy gates on sender/party, not on a column list. No
-- SECURITY DEFINER function is touched. Nothing here moves money or widens a read.

alter table public.chat_messages add column if not exists client_key uuid;

create unique index if not exists chat_messages_thread_client_key_uni
  on public.chat_messages (thread_id, client_key)
  where client_key is not null;

comment on column public.chat_messages.client_key is
  '0162: client-minted idempotency key, one per user send attempt; unique per thread when present.';
