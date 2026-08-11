-- 0073 — owner-editable pickup note (addresses.detail), through one narrow definer.
--
-- Sean §D: "special note section editable for owner in preference and always visible in
-- intermediary". Ground truth before writing anything: `addresses.detail` ALREADY exists
-- (0001:122), already reaches the runner (booking_pickup_address, 0060 → widened 0065), and is
-- already rendered on runner/meetup. The only missing half is the WRITE path — api.ts has
-- addAddress / setAddressPin / setDefaultAddress / deleteAddress and **no update**. So the note is
-- write-once at creation: to change '1층 로비에서 인계' the owner had to delete the address and
-- rebuild it, losing the pin and the default flag.
--
-- §1 WHY A DEFINER AND NOT A CLIENT .update()
--   The first draft of this slice proposed a plain PostgREST `.update({detail})` on the grounds
--   that `addresses` already has owner RLS. The Codex review rejected that, correctly:
--   `create policy "addresses owner all" on addresses for all using (owner_id = auth.uid())`
--   (0002:82) is **row**-scoped. Postgres RLS does not restrict columns, and this repo issues **no
--   column grants on `addresses` anywhere** (verified: zero grant/revoke statements for the table
--   in any migration). A TypeScript payload type is not a security boundary — a client holding a
--   session can PATCH any column of its own rows.
--   Two corrections to that finding, from measuring rather than assuming:
--     · `gate_code_enc` is written by **nothing** — no migration, no client file. The column is
--       dead, so today it is an unfilled hole rather than an exposed secret.
--     · The policy has no `WITH CHECK`, so Postgres reuses `USING` as the check on UPDATE. An
--       owner therefore cannot re-home a row to another owner_id. Not a cross-tenant hole.
--   The real risk is integrity, not tenancy: `addresses` rows are referenced by `bookings.address_id`,
--   so an edit silently rewrites every live and future booking pointing at that row — and editing
--   `addr` while keeping `lat/lng` produces a **falsely pinned address on a handoff screen**.
--   Hence: note only. `addr`, `label`, `lat`, `lng`, `is_default`, `gate_code_enc` are untouchable
--   here. Widening the address itself must clear the coordinates atomically and re-run the pin
--   flow — a separate slice, deliberately not started.
--
-- 🔴 §2 WHAT THIS MIGRATION DOES **NOT** FIX — read before assuming the table is sealed.
--   Adding this RPC while broad UPDATE remains granted is, in Codex's words, security theater if
--   sold as a boundary. It is not sold as one. What it buys is real but narrower: one writer for
--   the field, a column whitelist, a length cap, empty→NULL normalisation, and an ownership check
--   that lives in the function instead of in a client type. The actual seal — REVOKE UPDATE on
--   `addresses` from `authenticated` and moving setAddressPin/setDefaultAddress onto their own
--   narrow RPCs — is a **pre-existing** hole that predates this work and touches two shipped write
--   paths. It gets its own slice with its own adversarial cycle. Logged in TODOS as P1 SECURITY.
--   Doing it half-way here (RPC added, grants untouched, hole declared closed) is the failure mode
--   this comment exists to prevent.
--
-- §3 Doctrine compliance: `set search_path = public, pg_temp` in the BODY (98 H1 watches the whole
--   schema; ALTER-applied config is reset by create-or-replace). Party gate before state gate.
--   Absent and foreign ids raise the SAME string (0054:73 enumeration-oracle doctrine).
--   Pins: 111_address_note_suite.sql, mutation-proven.

create or replace function owner_update_address_detail(p_address uuid, p_detail text)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_clean text;
begin
  -- party gate FIRST — an address that is not mine and an address that does not exist are the
  -- same sentence. Anything else lets a caller enumerate other people's address ids.
  if not exists (select 1 from addresses a where a.id = p_address and a.owner_id = auth.uid()) then
    raise exception 'not_owner';
  end if;

  -- normalise: trim, then empty → NULL. '' and NULL must not be two ways to say "no note",
  -- because the runner-side render is `detail ? ... : nothing` and an empty string would draw a
  -- separator with nothing after it.
  v_clean := nullif(btrim(coalesce(p_detail, '')), '');

  -- length cap. The note rides `runner/meetup.tsx`'s single address line (`addr · detail`), so an
  -- unbounded note pushes the address itself off screen at the moment the runner needs it.
  if v_clean is not null and char_length(v_clean) > 60 then
    raise exception 'detail_too_long';
  end if;

  -- the whitelist IS this statement: one column, by id, scoped to the caller.
  update addresses set detail = v_clean where id = p_address and owner_id = auth.uid();
end $$;

revoke execute on function owner_update_address_detail(uuid, text) from public, anon;
grant  execute on function owner_update_address_detail(uuid, text) to authenticated;

comment on function owner_update_address_detail is
  '0073: owner edits ONE column of their own address — addresses.detail, the pickup note the
assigned runner reads (booking_pickup_address). Trims, maps empty to NULL, caps at 60 chars.
Absent and foreign address ids raise the same not_owner (enumeration-oracle doctrine).
⚠ This is a narrow writer, NOT a seal: broad UPDATE on `addresses` is still granted to
authenticated (pre-existing, no column grants exist for this table anywhere). Sealing it —
revoke + narrow RPCs for the pin and default writes — is its own slice, logged P1 in TODOS.
addr/label/lat/lng/is_default/gate_code_enc are deliberately unreachable from here: editing the
address text while keeping coordinates would produce a falsely pinned address on a handoff screen.';
