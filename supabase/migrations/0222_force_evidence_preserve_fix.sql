-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0222 — the 0218 §C repair preserves EVERY non-NULL historical payload into the sealed journal,
--        regardless of whether it happens to equal the public composer's output
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 253_force_evidence_preserve_fix_suite.sql (tag `fep`) — 0222-P1 · P2 · P3 · S1
--
-- ═══ §0a WHAT THIS FILE IS — codex 2026-09-25 #2 (medium), correct-forward, READ → REPRODUCED ═══
-- `docs/reviews/2026-09-25-0216-0220-codex-verdict.md` finding #2, on `0218:430-439`:
--
--   0218 §C ③ (PRESERVE) fills a force-kind journal row whose `evidence` is still NULL from what
--   `bookings.return_force_evidence` holds — but SKIPS the row when that payload EQUALS
--   `_force_evidence_public(r.from_status, r.runner_stamped, r.owner_stamped, b.return_forced_at)`,
--   on the reasoning that such a payload must be server-composed. Equality does not establish
--   provenance: 0205 §B's contract for `p_evidence` was 「any non-empty object」, so a shell caller
--   under 0205's body could legally supply exactly those five keys — `source`, `from_status`,
--   `runner_stamped`, `owner_stamped`, and `forced_at` rendered as the transaction's `now()` — and
--   0205 copied it VERBATIM into the column with no journal `evidence` (the column did not exist).
--   For that row ③ writes nothing, the journal stays NULL, and the CHECK 0218 adds at :492-494
--   (`source = 'ops_resolve_return_tx' or evidence is not null`) then REJECTS the row and the whole
--   0218 apply ABORTS. Constructible historical input, not an observed production row.
--
-- 🔴 MEASURED on trunk (`4ab4396`, harness DB with 0001–0220 applied, inside a rolled-back txn):
--   a force through the shipped body, then the 0205 shape planted by hand — journal `evidence`
--   NULL, column = `_force_evidence_public('active', false, false, return_forced_at)` — and
--     `_seal_force_evidence_0218()` → `{"backfilled":0,"reasons_scrubbed":0,"evidence_preserved":0,"evidence_scrubbed":0}`
--     force-kind journal rows with NULL evidence after the repair → 1
--     `alter table return_resolutions add constraint return_resolutions_evidence_check …`
--       → `ERROR: check constraint "return_resolutions_evidence_check" of relation "return_resolutions" is violated by some row`
--   That ERROR is the abort. 253 0222-P1 re-measures the same mechanism by VALUE on every run.
--   And the other direction, same planted state, same rolled-back txn: 0218's CHECK re-added
--   `not valid`, then THIS FILE applied whole — §B reports `evidence_preserved = 1`, VERIFY ok,
--   zero NULL-evidence force-kind rows — then `alter table … validate constraint
--   return_resolutions_evidence_check` SUCCEEDS. The statement that aborted now passes.
--
-- ═══ §0b WHAT THIS FILE DOES ═════════════════════════════════════════════════════════════════
--   · §A — `_seal_force_evidence_0218()` RE-DECLARED (0218 is NOT edited; one canonical repair,
--     same name, so nothing callable keeps the defective predicate). Three changes, in ③ and ④:
--       ③ PRESERVE drops the equality conjunct: a force-kind journal row with NULL `evidence`
--         receives the column's payload whenever the payload is NOT NULL — full stop. The journal
--         is sealed (RLS on, zero policies, no client grant), so over-preserving a payload that
--         happens to look server-composed costs nothing; under-preserving aborts the apply.
--       ③ keeps `r.evidence is null`, so the FIRST preservation still wins (0218's M9b conjunct,
--         249 0218-E4's re-plant arm) and a second call returns 0.
--       ④ SCRUB is keyed on journal rows that HOLD evidence (`r.evidence is not null` in the
--         `distinct on` set). Every row ③ could fill is filled before ④ runs, so this changes
--         nothing for any row a shipped door can produce. It matters for exactly one hand-made
--         shape — column NULL and journal NULL — where 0218's ④ would compose the column from
--         the journal's facts and the NEXT call's ③ would then copy that composition into the
--         journal as if a caller had typed it. Fabricated provenance across two calls; 253
--         0222-P3 pins that nothing is invented on the first call OR the second.
--     Everything else is 0218's, byte-for-byte: ① BACKFILL, ② re-token, the fixed order
--     ③-before-④, the four counts, the NOTICE, `security definer`, in-body `search_path`, ACL.
--   · §B — run it once at apply (counts as NOTICEs), then VERIFY by VALUE and by SOURCE.
--
-- ═══ §0c WHAT THIS FILE CANNOT DO, IN PROSE ═══════════════════════════════════════════════════
-- 🔴 A correct-forward runs AFTER the file it corrects. If a database holds codex #2's row when
--   0218 applies, 0218 aborts at its CHECK and this file never runs — nothing numbered 0222 can
--   un-abort 0218, and 0218 is on origin so it cannot be edited (the standing law). What bounds
--   the deploy risk is an ARGUMENT, stated here so it can be checked rather than trusted:
--     · production sits at 0202 (0203 onward is one pending push). Codex #2's row is
--       0205-SHAPED — a journal row with `source = 'force_return_tx'` and NULL `evidence` —
--       and only 0205 §B's body writes such a row. That body exists on production for the
--       seconds between 0205 and 0218 applying inside one push; no shell force runs inside a
--       push. Every ops force production holds today has NO journal row and takes ① BACKFILL,
--       which copies the column verbatim with no equality test.
--     · the other NULL that could trip 0218's CHECK — an ops-forced booking whose column is
--       NULL — is refused by every force door since 0083 (`evidence_required`, 0083:1064 ·
--       0089:87 · 0205:234 · 0218:242).
--   Both are reads of migration source, not observations of production. The one-query
--   pre-flight that converts them into observations is Sean's to run before the push:
--     select count(*) from return_resolutions where source = 'force_return_tx' and evidence is null;
--     select count(*) from bookings where return_forced_by = 'ops' and return_force_evidence is null;
--   (the first column does not exist before 0218; on a pre-push production the honest form is
--   `select count(*) from return_resolutions where source = 'force_return_tx'` → expected 0).
--   What 0222 DOES close: any environment that ran 0205's body and reaches 0218 cleanly, any
--   later re-run of the repair (it is service_role-callable by design), and the class itself —
--   the canonical repair no longer decides provenance by equality.
--
-- ═══ §0d WHAT THIS FILE DELIBERATELY DOES NOT DO ═════════════════════════════════════════════
-- - **0218, 0205, 0201, 0193, 0089, 0083 are NOT edited.** 0218's ③ comment (「only if that is not
--   already the composed shape」) stays as written; this header is where a reader learns it was
--   withdrawn and why.
-- - `force_return_tx` and `_force_evidence_public` are NOT re-declared — the live door already
--   journals `p_evidence` in the same INSERT (0218:339-343), so no row it writes can reach ③.
-- - The CHECK is NOT re-issued. It is correct; the defect was that the repair could leave a row
--   for it to refuse.
-- - No client build (`grep -rn return_force_evidence app/src app/app` → 0, 0218's count
--   re-measured). No edge deploy (`grep -rn '_seal_force_evidence\|_force_evidence_public'
--   supabase/functions` → 0). No cron, no enum, no policy.
--
-- ═══ §0e DOCTRINE ════════════════════════════════════════════════════════════════════════════
-- `set search_path = public, pg_temp` in the definer body · ACL restated in THIS file · comments
-- stripped before every `prosrc` match · `is not true` / `is distinct from`, never a bare `IF` on a
-- nullable predicate · pins in `253_force_evidence_preserve_fix_suite.sql`, labels `0222-…`.
--
-- ═══ §0f DEPLOY ══════════════════════════════════════════════════════════════════════════════
--   `supabase db push` — this file, after 0218. Nothing else.

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §A _seal_force_evidence_0218 — re-declared: preserve by presence, never by provenance guess
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Four statements in 0218's FIXED order — ③ before ④ in every run, so no run can scrub what it did
-- not first preserve. ① by 「no journal row」, ② by 「not already a token」, ③ by 「journal evidence
-- still NULL and the column holds something」, ④ by 「the journal holds evidence and the column
-- differs from the value about to be written」 — a second call returns four zeros (253 0222-P2).
create or replace function _seal_force_evidence_0218() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_backfilled int := 0; v_reasons int := 0; v_preserved int := 0; v_scrubbed int := 0;
  -- the closed set of tokens the two ops writers produce (0201 §A's three, 0205 §B's one)
  c_tokens constant text[] := array['ops_forced', 'ops_resolved', 'ops_resolved:strand', 'ops_resolved:review'];
begin
  -- ① BACKFILL — the pre-0205 shell forces (0218 §C, unchanged)
  insert into return_resolutions (booking_id, resolved_by, from_status, runner_stamped, owner_stamped,
                                  memo, source, evidence, created_at)
  select b.id, null, 'active',
         (b.runner_confirmed_return_at is not null),
         (b.owner_confirmed_return_at is not null),
         coalesce(b.return_force_reason, ''),
         'backfill_0218',
         b.return_force_evidence,
         coalesce(b.return_forced_at, now())
    from bookings b
   where b.return_forced_by = 'ops'
     and not exists (select 1 from return_resolutions r where r.booking_id = b.id);
  get diagnostics v_backfilled = row_count;

  -- ② the public REASON of a backfilled booking becomes the force token, unless it already is
  --    one of the known tokens (0218 §C, unchanged; `is not true` so a NULL reason is re-tokened)
  update bookings b
     set return_force_reason = 'ops_forced'
   where b.return_forced_by = 'ops'
     and exists (select 1 from return_resolutions r
                  where r.booking_id = b.id and r.source = 'backfill_0218')
     and (b.return_force_reason = any(c_tokens)) is not true;
  get diagnostics v_reasons = row_count;

  -- ③ PRESERVE — a force-kind journal row with no evidence yet takes whatever `bookings` holds,
  --    whenever it holds anything. 🔴 [0222] NO equality test against the composer: a payload
  --    that equals the five composed keys may have been TYPED by a 0205-era shell caller, and
  --    leaving it out of the journal is what 0218's CHECK then aborts on (codex 2026-09-25 #2,
  --    measured in this file's header). The journal is sealed, so preserving a server-shaped
  --    object costs nothing; not preserving it costs the apply. `r.evidence is null` keeps the
  --    first preservation as the one that stands (249 0218-E4's re-plant arm).
  update return_resolutions r
     set evidence = b.return_force_evidence
    from bookings b
   where b.id = r.booking_id
     and r.source in ('force_return_tx', 'backfill_0218')
     and r.evidence is null
     and b.return_forced_by = 'ops'
     and b.return_force_evidence is not null;
  get diagnostics v_preserved = row_count;

  -- ④ SCRUB — bookings receives the composed shape for every force-kind row whose journal HOLDS
  --    evidence. `distinct on` picks the latest force-kind row per booking (0218's reason: an
  --    UPDATE … FROM over a one-to-many join picks an arbitrary partner). 🔴 [0222] `r.evidence is
  --    not null` is the guard against fabricated provenance: after ③, every row that had anything
  --    to preserve holds it, so the only rows this conjunct leaves alone are column-NULL AND
  --    journal-NULL — a shape no door produces — and for those, composing the column here would
  --    hand the NEXT call's ③ a value to copy into the journal as a caller's object. 253 0222-P3.
  update bookings b
     set return_force_evidence =
         _force_evidence_public(x.from_status, x.runner_stamped, x.owner_stamped, b.return_forced_at)
    from (
      select distinct on (r.booking_id) r.booking_id, r.from_status, r.runner_stamped, r.owner_stamped
        from return_resolutions r
       where r.source in ('force_return_tx', 'backfill_0218')
         and r.evidence is not null
       order by r.booking_id, r.created_at desc
    ) x
   where x.booking_id = b.id
     and b.return_forced_by = 'ops'
     and b.return_force_evidence is distinct from
         _force_evidence_public(x.from_status, x.runner_stamped, x.owner_stamped, b.return_forced_at);
  get diagnostics v_scrubbed = row_count;

  raise notice '_seal_force_evidence_0218: backfilled=% reasons_scrubbed=% evidence_preserved=% evidence_scrubbed=%',
    v_backfilled, v_reasons, v_preserved, v_scrubbed;
  return jsonb_build_object('backfilled', v_backfilled, 'reasons_scrubbed', v_reasons,
                            'evidence_preserved', v_preserved, 'evidence_scrubbed', v_scrubbed);
end $$;

-- ACL restated in THIS file, never inherited (0116:636 — a `create or replace` that finds no
-- function is a plain CREATE, born PUBLIC-executable). BYTE-FOR-BYTE 0218's.
revoke execute on function _seal_force_evidence_0218() from public, anon, authenticated;
grant  execute on function _seal_force_evidence_0218() to service_role;

comment on function _seal_force_evidence_0218 is
  '0218 §C, re-declared by 0222 §A — the idempotent repair for codex 2026-09-25 #3/#4, in a FIXED
order: ① every return_forced_by=''ops'' booking with NO return_resolutions row (a pre-0205 shell
force) gets a sealed source=''backfill_0218'' row carrying its free-text reason as memo, its caller
object as evidence, created_at = return_forced_at; ② that booking''s public reason becomes
ops_forced unless it is already a known token; ③ a force-kind journal row with NULL evidence
receives whatever bookings.return_force_evidence holds, whenever it is not NULL — 🔴 0222: NO
equality test against _force_evidence_public(…), because a 0205-era caller could legally have
typed those five keys and skipping the row aborts 0218''s CHECK (codex 2026-09-25 #2, measured);
④ bookings.return_force_evidence becomes _force_evidence_public(…) wherever it differs, for every
force-kind row whose journal holds evidence (0222: a column-NULL/journal-NULL row is left alone
rather than composed, so no later call can mistake the composition for a caller''s object).
Returns the four counts. A second call returns zeros and changes nothing — 249 0218-E6,
253 0222-P2. Resolver rows (source=ops_resolve_return_tx) are outside every statement''s set.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §B run it — and report, not hope
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- On any database where 0218 applied, 0218's CHECK already guarantees zero NULL-evidence force-kind
-- rows, so this call is expected to report four zeros; it runs so the number is READ, not assumed.
do $$
declare v jsonb;
begin
  v := _seal_force_evidence_0218();
  raise notice '0222 §B repair ran at apply: %', v;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — apply-time, by VALUE and by SOURCE, and NOT a substitute for suite 253
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Apply-time source checks are protected exactly until somebody recreates the function (0131-G4),
-- so 253 owns the standing pins and this block owns 「the file that just ran did what it says」.
-- Comments are STRIPPED before every match: §A's body explains the very predicate it removed, so
-- un-stripped, the absence arm below would be satisfied by the paragraph explaining it.
do $$
declare v_src text; v_raw text; v_bad text := ''; v_n int; v_def text;
begin
  select p.prosrc into v_raw
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_seal_force_evidence_0218';
  if v_raw is null then raise exception '0222 VERIFY: NO-SOURCE(_seal_force_evidence_0218)'; end if;
  v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');

  -- ③ preserves by PRESENCE: the assignment, the NULL-journal conjunct, the not-NULL-column conjunct
  if (v_src ~ 'set evidence\s*=\s*b\.return_force_evidence') is not true
    then v_bad := v_bad || ' 수리 ③: 저널 evidence에 칸 값을 배정하지 않는다;'; end if;
  if (v_src ~ 'r\.evidence is null') is not true
    then v_bad := v_bad || ' 수리 ③: 보존이 이미 보존된 행을 다시 덮는다;'; end if;
  if (v_src ~ 'b\.return_force_evidence is not null') is not true
    then v_bad := v_bad || ' 수리 ③: 칸이 NULL인 행에 NULL을 「보존」한다;'; end if;
  -- 🔴 ③ must NOT decide provenance by equality — the composer called on the JOURNAL row's own
  --    fields (`r.`) beside the column is 0218's skip; ④'s comparison uses the `x.` subquery.
  if (v_src ~ 'return_force_evidence\s+is\s+distinct\s+from\s+_force_evidence_public\(\s*r\.') is not false
    then v_bad := v_bad || ' 🔴 수리 ③: 칸 값이 조합기 출력과 같으면 보존을 건너뛴다 (codex #2 그대로);'; end if;
  -- ④ still compares against the value it writes (idempotent), and is keyed on journal evidence present
  if (v_src ~ 'return_force_evidence is distinct from\s+_force_evidence_public\(x\.') is not true
    then v_bad := v_bad || ' 수리 ④: 스크럽이 쓰려는 값과 비교하지 않는다 (멱등 아님);'; end if;
  if (v_src ~ 'r\.evidence is not null') is not true
    then v_bad := v_bad || ' 수리 ④: 저널 증거 없는 행의 칸을 조합한다 (다음 호출의 ③이 그것을 베낀다);'; end if;
  -- ①/② intact — 0218's arms, re-asserted because this file re-declared the function
  if (v_src ~ '''backfill_0218''') is not true
    then v_bad := v_bad || ' 수리 ①: 백필 행을 쓰지 않는다;'; end if;
  if (v_src ~ 'not exists \(select 1 from return_resolutions') is not true
    then v_bad := v_bad || ' 수리 ①: 「저널 행 없음」 조건이 없다;'; end if;
  if (v_src ~ 'return_forced_by = ''ops''') is not true
    then v_bad := v_bad || ' 수리: ops 마커 조건이 없다;'; end if;
  if (v_src ~ '''ops_resolved:strand''') is not true or (v_src ~ '''ops_resolved:review''') is not true
    then v_bad := v_bad || ' 수리 ②: 알려진 토큰 목록이 빠졌다;'; end if;
  -- crude control: the raw source DOES carry the words the stripped arms look for
  if (v_raw ~ '_force_evidence_public') is not true
    then v_bad := v_bad || ' 대조: 원본 소스에 _force_evidence_public이라는 낱말이 없다;'; end if;
  -- shape + ACL
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = '_seal_force_evidence_0218'
                   and p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%')
    then v_bad := v_bad || ' 수리: definer/search_path 형상 없음;'; end if;
  if has_function_privilege('authenticated', 'public._seal_force_evidence_0218()', 'execute')
    then v_bad := v_bad || ' 수리가 authenticated에 열려 있다;'; end if;
  if has_function_privilege('anon', 'public._seal_force_evidence_0218()', 'execute')
    then v_bad := v_bad || ' 수리가 anon에 열려 있다;'; end if;
  if not has_function_privilege('service_role', 'public._seal_force_evidence_0218()', 'execute')
    then v_bad := v_bad || ' 수리를 service_role이 실행할 수 없다;'; end if;

  -- by VALUE: the repair RAN and the world is in the shape the CHECK demands
  select count(*) into v_n from return_resolutions
   where source in ('force_return_tx', 'backfill_0218') and evidence is null;
  if v_n <> 0 then v_bad := v_bad || ' 수리 뒤 증거 없는 강제 저널 행 ' || v_n || '건;'; end if;
  select count(*) into v_n from bookings b
   where b.return_forced_by = 'ops'
     and not exists (select 1 from return_resolutions r where r.booking_id = b.id);
  if v_n <> 0 then v_bad := v_bad || ' 수리 뒤에도 저널 행 없는 ops 강제 ' || v_n || '건;'; end if;
  select count(*) into v_n from bookings b
   where b.return_forced_by = 'ops'
     and exists (select 1 from return_resolutions r where r.booking_id = b.id
                  and r.source in ('force_return_tx', 'backfill_0218'))
     and (select array_agg(k order by k) from jsonb_object_keys(coalesce(b.return_force_evidence, '{}'::jsonb)) k)
         is distinct from array['forced_at', 'from_status', 'owner_stamped', 'runner_stamped', 'source'];
  if v_n <> 0 then v_bad := v_bad || ' 수리 뒤에도 조합 모양이 아닌 강제 증거 칸 ' || v_n || '건;'; end if;
  -- 0218's CHECK is in place with 0218's definition (this file does not touch it — it must still be there)
  select pg_get_constraintdef(oid) into v_def from pg_constraint
   where conrelid = 'return_resolutions'::regclass and conname = 'return_resolutions_evidence_check';
  if v_def is null then v_bad := v_bad || ' 저널: 증거 CHECK이 없다;';
  elsif (v_def ~ 'evidence IS NOT NULL') is not true
    then v_bad := v_bad || ' 저널: 증거 CHECK의 정의가 다르다=' || v_def || ';'; end if;

  if v_bad <> '' then raise exception '0222 VERIFY FAILED:%', v_bad; end if;
  raise notice '0222 VERIFY: ok — the repair preserves by presence (no equality skip), scrubs only journal-backed rows, ran at apply, and the CHECK stands';
end $$;
