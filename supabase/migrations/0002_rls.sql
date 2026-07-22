-- RLS + hygiene triggers. Principle: clients read/write only their own world;
-- state transitions & money move through server functions (service role) later.

-- ---------- updated_at ----------
create or replace function touch_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

create trigger t_profiles_touch before update on profiles for each row execute function touch_updated_at();
create trigger t_dogs_touch     before update on dogs     for each row execute function touch_updated_at();
create trigger t_runners_touch  before update on runners  for each row execute function touch_updated_at();
create trigger t_bookings_touch before update on bookings for each row execute function touch_updated_at();

-- ---------- helpers ----------
create or replace function is_booking_party(b_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from bookings b
    where b.id = b_id
      and (b.owner_id = auth.uid() or b.runner_id = auth.uid())
  );
$$;

-- ---------- enable RLS ----------
alter table profiles enable row level security;
alter table dogs enable row level security;
alter table runners enable row level security;
alter table runner_documents enable row level security;
alter table runner_availability_rules enable row level security;
alter table runner_availability_exceptions enable row level security;
alter table runner_booking_rules enable row level security;
alter table addresses enable row level security;
alter table gate_code_access_log enable row level security;
alter table routes enable row level security;
alter table recurring_series enable row level security;
alter table bookings enable row level security;
alter table slot_holds enable row level security;
alter table runs enable row level security;
alter table reviews enable row level security;
alter table ledger_items enable row level security;
alter table bank_accounts enable row level security;
alter table payouts enable row level security;
alter table miles_ledger enable row level security;
alter table drops enable row level security;
alter table boosts enable row level security;
alter table gear_claims enable row level security;
alter table cards_owned enable row level security;
alter table notifications enable row level security;
alter table chat_threads enable row level security;
alter table chat_messages enable row level security;
alter table emergency_contacts enable row level security;
alter table incidents enable row level security;

-- ---------- profiles ----------
create policy "profiles self read" on profiles for select using (auth.uid() = id);
create policy "profiles public runner read" on profiles for select using (
  exists (select 1 from runners r where r.profile_id = profiles.id and r.tier <> 'applicant')
);
create policy "profiles self write" on profiles for update using (auth.uid() = id);
create policy "profiles self insert" on profiles for insert with check (auth.uid() = id);

-- ---------- dogs ----------
create policy "dogs owner all" on dogs for all using (owner_id = auth.uid());
create policy "dogs runner read via booking" on dogs for select using (
  exists (select 1 from bookings b where b.dog_id = dogs.id and b.runner_id = auth.uid())
);

-- ---------- runners (public storefront) ----------
create policy "runners public read" on runners for select using (tier <> 'applicant' or profile_id = auth.uid());
create policy "runners self write" on runners for update using (profile_id = auth.uid());
create policy "runners self insert" on runners for insert with check (profile_id = auth.uid());

create policy "runner docs self" on runner_documents for all using (
  exists (select 1 from runners r where r.profile_id = auth.uid() and r.profile_id = runner_documents.runner_id)
);
create policy "avail rules self all" on runner_availability_rules for all using (runner_id = auth.uid());
create policy "avail rules public read" on runner_availability_rules for select using (true);
create policy "avail exc self all" on runner_availability_exceptions for all using (runner_id = auth.uid());
create policy "booking rules self all" on runner_booking_rules for all using (runner_id = auth.uid());

-- ---------- addresses: gate code NEVER selected directly by runners ----------
create policy "addresses owner all" on addresses for all using (owner_id = auth.uid());
-- 러너는 배정 세션 중 서버 함수(security definer)로만 복호 조회 — 직접 select 불가.
create policy "gate log owner read" on gate_code_access_log for select using (
  exists (select 1 from addresses a where a.id = gate_code_access_log.address_id and a.owner_id = auth.uid())
);

-- ---------- routes: certified catalog is public ----------
create policy "routes public read" on routes for select using (active);

-- ---------- bookings ----------
create policy "bookings party read" on bookings for select using (
  owner_id = auth.uid() or runner_id = auth.uid()
);
create policy "bookings owner insert" on bookings for insert with check (owner_id = auth.uid() and status = 'draft');
-- 상태 전이는 booking_transition 트리거가 검증; 필드 변경 권한은 파티에 한정
create policy "bookings party update" on bookings for update using (
  owner_id = auth.uid() or runner_id = auth.uid()
);

create policy "series owner all" on recurring_series for all using (owner_id = auth.uid());
create policy "holds self" on slot_holds for all using (owner_id = auth.uid());
create policy "holds runner read" on slot_holds for select using (runner_id = auth.uid());

-- ---------- runs ----------
create policy "runs party read" on runs for select using (is_booking_party(booking_id));
create policy "runs runner write" on runs for insert with check (
  exists (select 1 from bookings b where b.id = booking_id and b.runner_id = auth.uid())
);
create policy "runs runner update" on runs for update using (
  exists (select 1 from bookings b where b.id = booking_id and b.runner_id = auth.uid())
);

-- ---------- reviews: platform_only hidden from everyone but author ----------
create policy "reviews public read" on reviews for select using (
  visibility = 'public' and is_booking_party(booking_id)
);
create policy "reviews author read" on reviews for select using (author_id = auth.uid());
create policy "reviews author insert" on reviews for insert with check (
  author_id = auth.uid() and is_booking_party(booking_id)
);

-- ---------- money: runner reads own; writes are server-only ----------
create policy "ledger self read" on ledger_items for select using (runner_id = auth.uid());
create policy "bank self all" on bank_accounts for all using (runner_id = auth.uid());
create policy "payouts self read" on payouts for select using (runner_id = auth.uid());
create policy "miles self read" on miles_ledger for select using (profile_id = auth.uid());

-- ---------- rewards ----------
create policy "drops self read" on drops for select using (runner_id = auth.uid());
create policy "drops self open" on drops for update using (runner_id = auth.uid());
create policy "boosts self read" on boosts for select using (runner_id = auth.uid());
create policy "gear self read" on gear_claims for select using (profile_id = auth.uid());
create policy "gear self claim" on gear_claims for update using (profile_id = auth.uid());
create policy "cards self read" on cards_owned for select using (profile_id = auth.uid());

-- ---------- comms & safety ----------
create policy "noti self" on notifications for select using (profile_id = auth.uid());
create policy "noti self update" on notifications for update using (profile_id = auth.uid());

create policy "threads party" on chat_threads for select using (is_booking_party(booking_id));
create policy "messages party read" on chat_messages for select using (
  exists (select 1 from chat_threads t where t.id = thread_id and is_booking_party(t.booking_id))
);
create policy "messages party send" on chat_messages for insert with check (
  sender_id = auth.uid()
  and exists (select 1 from chat_threads t where t.id = thread_id and is_booking_party(t.booking_id))
);

create policy "contacts self all" on emergency_contacts for all using (profile_id = auth.uid());
create policy "incidents party" on incidents for select using (
  reporter_id = auth.uid() or (booking_id is not null and is_booking_party(booking_id))
);
create policy "incidents report" on incidents for insert with check (reporter_id = auth.uid());
