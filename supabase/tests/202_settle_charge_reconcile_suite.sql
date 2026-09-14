-- ═══ 202 — the settle-charge RECOVERY CHAIN is scheduled (0172) — 0172-S1 … 0172-S3, tag `scr` ═══
--
-- 🔴 READ THIS HEADER BEFORE READING THIS FILE'S GREENS. 0172 is NOT the sweep its claim commit
-- promised, and this suite is not the suite that claim implied. The sweep codex deploy-gate HIGH #1
-- asked for **already exists** (`sweep_settled_without_payments`, `0080:569` §G extended at
-- `0116:60` §A, cron `sweep-settled-charges` `2-57/5`), and it was MEASURED recovering exactly the
-- `CHARGE LOST` state — through the real settle path, not a hand-written fixture row. 0172's header
-- carries the full measurement and the reason the brief's own `bookings.status` + `ledger_items`
-- predicate would have MINTED A CHARGE FOR A CANCELLED BOOKING (`0080 §K`).
--
-- ⚠ SO THE RECOVERY BEHAVIOUR ITSELF IS NOT PINNED HERE, AND THAT IS DELIBERATE — it is already
--   owned, three different ways, and a fourth copy would be manufactured coverage:
--     · `116 C9`   — settled booking with no row gets exactly one, at the basis table's amount;
--                    second sweep adds nothing (the idempotence arm).
--     · `116 C22`  — the FLAG GATE: charging off ⇒ the sweep mints 0; flipped ⇒ pre-cutover runs
--                    stay free forever and only post-cutover runs are charged.
--     · `116 C24`  — the two blind spots (kind-less widget debris cannot blind it; an unmeasured
--                    run is skipped rather than priced), each with its positive control.
--     · `119 R10`  — the same thing END-TO-END through `end_run_tx` → `confirm_return_tx` ×2, with
--                    the charged amount read from `compute_owner_charge` rather than a literal.
--     · `151 B1`   — the `settled_at` anchor and the deliberately-wider existence predicate.
--   Writing an `0172-S_` that re-asserts any of those would be a pin whose green licenses nothing
--   the harness did not already have. What NOTHING in this repo asserts is the proposition below.
--
-- ═══ THE PROPOSITION THIS FILE OWNS ═══════════════════════════════════════════════════════════
-- 「the sweep EXISTS」 and 「the sweep RUNS」 are two claims and only the first was ever checked.
-- Both jobs of the recovery chain were registered under the swallowing form `0157 §A` condemned —
-- `exception when others then raise notice` around `cron.schedule` (`0080:643`, `0080:1259`) — so
-- a failed install COMMITTED as a successful migration. Swept: before 0172 the only cron readbacks
-- in the repo were 0157's own (`revoke-billing-keys`) and 0168's (`finalize-stopped-runs`).
--
-- ⚠ TWO DIFFERENT ARTIFACTS, AND NEITHER IS EVIDENCE FOR THE OTHER — the `check-definer-acl`
--   division, restated:
--     · **0172's VERIFY block** is what runs on the PRODUCTION apply and aborts it if the chain is
--       not scheduled — the load-bearing half. The harness can SIMULATE the absence (plant A below
--       deletes the registrations and the apply aborts), but it cannot reproduce the real-world
--       CAUSE: the shim's `cron.schedule` (`00_shim.sql:102`) cannot fail, so 「pg_cron absent /
--       the role lacks rights in `cron`」 — the state 0157 §A was written for — is unreachable
--       here. Plant A measures that the VERIFY fires on a missing row, not that it fires on the
--       failure that would produce one in production.
--     · **These pins** are the STANDING guard: they redden if a later file unschedules a job,
--       renames one, or re-registers it running something else — a state the harness CAN produce
--       and a production VERIFY that already ran cannot see.
--
-- ⚠ HOW THESE PINS FAIL, MEASURED — and the first thing measured corrected a claim this header
--   originally made from reasoning. **Removing 0080's registration alone reddens NOTHING**
--   (1220/0, and the apply does NOT abort): 0172 §A re-registers the same job unconditionally, so
--   after this file lands 0172 is the file that OWNS the registration and 0080's is redundant. A
--   VERIFY that reads back a row its own file just wrote is testing its own setup (the `175 V2`
--   law) — so the plant has to remove BOTH.
--     **A** 0080's AND 0172 §A's registrations removed ⇒ the **APPLY ABORTS**:
--          `0172 VERIFY FAILED: … found sweep-settled-charges=0 dispatch-due-charges=1`.
--          That measures the VERIFY, not this suite (0131-G4's distinction).
--     **B** A + the VERIFY demoted to a notice so the suite can speak ⇒ **1218 / 2 fail**:
--          `0172-S1` (` 활성 작업 수=0 (이름만 일치하는 행=0)` — the defect by name, and the
--          name-only diagnostic distinguishing 「gone」 from 「renamed」) and `0172-S3`
--          (`NO-SUBJECT`). ⚠ The S3 cascade is CORRECT and is the point of writing it that way:
--          its subject IS the row S1 asserts, so with the row gone the control REFUSES rather than
--          passing over an empty world (0151's absence-pin lesson). `0172-S2` stayed GREEN.
--     **C** the same two removals for `dispatch-due-charges` + the demoted VERIFY ⇒ **1219 / 1**,
--          `0172-S2` alone. S1 and S3 green — so S1 and S2 are two measurements, not one.
-- ⚠ AND `0172-S3` IS WHY S1/S2 MEAN ANYTHING AT ALL. A count-equals-1 pin over a registry that
--   always contains the row cannot distinguish 「the detector works」 from 「the detector always says
--   yes」. S3 manufactures the absence by VALUE (whole-row snapshot → delete → re-read → restore)
--   and asserts the detector reports 0, then that the row went back byte-identical.
-- 🔴 NAMED GAP, measured rather than reasoned (plant **D**): dropping `and active` from **S1's own**
--   query reddens **NOTHING** (1220/0). The cause is not a blind pin — it is that **nothing in the
--   migration chain ever sets `active = false`**, so the harness cannot reach a state where that
--   conjunct matters. S3 proves the detector SHAPE rejects an inactive job, using its own copy of
--   the query; it does NOT prove S1's copy carries the conjunct. Written down as a gap rather than
--   repaired by reshaping a pin around the mutation, which would manufacture coverage.
set client_min_messages = warning;

do $$
declare
  v_bad text := ''; v_msg text;
  v_n int;
  v_has_cron boolean;
  v_row jsonb; v_cur jsonb;
begin
  ------------------------------------------------------------------------------------------
  -- Shared precondition, asserted as a VALUE and not assumed. `to_regclass` returns NULL for an
  -- absent relation rather than raising, so absence is a value here — and every arm below is
  -- written `is not true` / `is distinct from`, never a bare `IF`, because a NULL predicate makes
  -- a plpgsql `IF` silent and every pin in this file exists to notice that something is MISSING.
  select to_regclass('cron.job') is not null into v_has_cron;

  ------------------------------------------------------------------------------------------
  -- [0172-S1] the MINT half is scheduled — `sweep_settled_without_payments` is the answer to
  -- codex deploy-gate HIGH #1 and it is worth nothing if nobody calls it.
  v_bad := '';
  if v_has_cron is not true then
    v_bad := v_bad || ' NO-CRON-REGISTRY(cron.job absent — 00_shim.sql:90 is the fixture)';
  else
    select count(*)::int into v_n
      from cron.job
     where jobname = 'sweep-settled-charges'
       and active
       and command = 'select sweep_settled_without_payments()';
    if v_n is distinct from 1 then
      v_bad := v_bad || ' sweep-settled-charges 활성 작업 수=' || coalesce(v_n::text, 'NULL');
      -- Say WHICH of the two failure shapes it is, because 「renamed」 and 「running something
      -- else」 need different repairs and a bare count cannot tell them apart.
      select count(*)::int into v_n from cron.job where jobname = 'sweep-settled-charges';
      v_bad := v_bad || ' (이름만 일치하는 행=' || coalesce(v_n::text, 'NULL') || ')';
    end if;
  end if;
  if v_bad = '' then call _pass('scr','0172-S1 정산 청구 복구 스윕이 실제로 예약돼 있다 — cron.job 에 active 한 sweep-settled-charges 가 정확히 1개, 그 command 가 sweep_settled_without_payments() (HIGH #1 의 답은 존재하는 것만으로는 부족하고 돌아야 한다)');
  else v_msg := v_bad; call _fail('scr','0172-S1 정산 청구 복구 스윕이 실제로 예약돼 있다', v_msg); end if;

  ------------------------------------------------------------------------------------------
  -- [0172-S2] the COLLECT half. A minted `pending` row nothing dispatches is the same revenue
  -- outcome as a row never minted — the owner is not charged — and it arrives through the same
  -- swallowed registration (`0080:1259`). Both links or the chain claim is false.
  v_bad := '';
  if v_has_cron is not true then
    v_bad := v_bad || ' NO-CRON-REGISTRY(cron.job absent)';
  else
    select count(*)::int into v_n
      from cron.job
     where jobname = 'dispatch-due-charges'
       and active
       and command = 'select dispatch_due_charges()';
    if v_n is distinct from 1 then
      v_bad := v_bad || ' dispatch-due-charges 활성 작업 수=' || coalesce(v_n::text, 'NULL');
      select count(*)::int into v_n from cron.job where jobname = 'dispatch-due-charges';
      v_bad := v_bad || ' (이름만 일치하는 행=' || coalesce(v_n::text, 'NULL') || ')';
    end if;
  end if;
  if v_bad = '' then call _pass('scr','0172-S2 청구 발송 크론이 실제로 예약돼 있다 — active 한 dispatch-due-charges 가 정확히 1개, command 가 dispatch_due_charges() (민팅만 돌고 발송이 안 돌면 보호자는 똑같이 청구되지 않는다)');
  else v_msg := v_bad; call _fail('scr','0172-S2 청구 발송 크론이 실제로 예약돼 있다', v_msg); end if;

  ------------------------------------------------------------------------------------------
  -- [0172-S3] 🔴 THE CONTROL — S1/S2 CAN REPORT ABSENT.
  -- S1/S2 read a registry that is populated by 0080 on every apply, so on their own they cannot
  -- distinguish 「the detector works」 from 「the detector always says yes」. This arm manufactures
  -- the absence and reads the detector again; then it puts the row back BY VALUE and proves it.
  -- Whole-row jsonb rather than a column list (185 G4's idiom) so a column added to `cron.job`
  -- later is carried without this file being edited.
  -- ⚠ The restore is asserted, not assumed: a failed restore would leave the recovery chain
  --   unscheduled for every suite that runs after this one, and would surface as somebody else's
  --   inexplicable red.
  v_bad := '';
  if v_has_cron is not true then
    v_bad := v_bad || ' NO-CRON-REGISTRY(cron.job absent)';
  else
    select to_jsonb(j) into v_row from cron.job j where j.jobname = 'sweep-settled-charges';
    if v_row is null then
      -- S1 already reported this; the control cannot run without its subject, and saying so is
      -- better than a green produced by having nothing to delete (0151's empty-world lesson).
      v_bad := v_bad || ' NO-SUBJECT(스윕 작업 행이 없어 통제 자체가 불가능)';
    else
      delete from cron.job where jobname = 'sweep-settled-charges';
      select count(*)::int into v_n
        from cron.job
       where jobname = 'sweep-settled-charges'
         and active
         and command = 'select sweep_settled_without_payments()';
      if v_n is distinct from 0 then
        v_bad := v_bad || ' 행을 지웠는데 탐지기가 여전히 ' || coalesce(v_n::text,'NULL') || ' 을 보고한다';
      end if;

      -- and a job present but INACTIVE must also read as absent: `cron.job.active = false` is how
      -- pg_cron parks a job, and a name-only detector would call that scheduled.
      insert into cron.job overriding system value select * from jsonb_populate_record(null::cron.job, v_row);
      update cron.job set active = false where jobname = 'sweep-settled-charges';
      select count(*)::int into v_n
        from cron.job
       where jobname = 'sweep-settled-charges'
         and active
         and command = 'select sweep_settled_without_payments()';
      if v_n is distinct from 0 then
        v_bad := v_bad || ' 비활성 작업을 예약됨으로 셌다=' || coalesce(v_n::text,'NULL'); end if;

      -- restore, by value
      delete from cron.job where jobname = 'sweep-settled-charges';
      insert into cron.job overriding system value select * from jsonb_populate_record(null::cron.job, v_row);
      select to_jsonb(j) into v_cur from cron.job j where j.jobname = 'sweep-settled-charges';
      if v_cur is distinct from v_row then
        v_bad := v_bad || ' 복구된 행이 원본과 다르다(' || coalesce(v_cur::text,'∅') || ')'; end if;
      select count(*)::int into v_n
        from cron.job
       where jobname = 'sweep-settled-charges'
         and active
         and command = 'select sweep_settled_without_payments()';
      if v_n is distinct from 1 then
        v_bad := v_bad || ' 복구 뒤 탐지기=' || coalesce(v_n::text,'NULL'); end if;
    end if;
  end if;
  if v_bad = '' then call _pass('scr','0172-S3 통제 — 탐지기가 「없음」을 보고할 수 있다: 행을 지우면 0, 비활성으로 두어도 0(이름만 보는 탐지기는 여기서 실패한다), 값으로 되돌린 뒤 다시 1이고 행은 원본과 바이트 동일');
  else v_msg := v_bad; call _fail('scr','0172-S3 통제 — 탐지기가 「없음」을 보고할 수 있다', v_msg); end if;

exception when others then
  -- The control DELETES a live registry row. If anything above raises between the delete and the
  -- restore, the recovery chain would be left unscheduled for anything that runs after this file —
  -- so the restore is repeated here rather than trusted to the happy path.
  if v_row is not null then
    delete from cron.job where jobname = 'sweep-settled-charges';
    insert into cron.job overriding system value select * from jsonb_populate_record(null::cron.job, v_row);
  end if;
  v_msg := sqlerrm; call _fail('scr','0172 스위트가 예외로 중단됐다', v_msg);
end $$;
