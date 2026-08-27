-- 0140 — 「1 dog per person」 becomes a rule the SERVER keeps, not a drawing the UI keeps.
--
-- Sean, 2026-08-27, verbatim: 「1 dog per person」. Found unenforced by session b6, measured:
-- `owner_handled_dog_limit` (0048:20) had ZERO readers anywhere — config as decoration, the
-- 「한 번도 쓰인 적 없는 빈 껍데기」 shape. The add-dog button hiding after one dog is a drawing;
-- `session_rsvp`'s with-dog path and `session_add_my_dog` both accepted a second dog from any
-- direct caller.
--
-- MECHANISM, and why a TRIGGER rather than editing both doors: the two writers share one table,
-- and a per-door gate is a rule copied N times — fixable N-1 times (this repo's own law). A
-- BEFORE trigger on `session_dogs` binds every current and future 동반 writer at the only point
-- they all must pass. It also covers the UPDATE flip (custody → 'owner_handled'), which no
-- door-side gate would see.
-- ⚠ Ordering with `club_v1_axes_sync` (also BEFORE): irrelevant by construction — this guard
-- reads only NEW.custody/session/owner, none of which axes rewrites. Concurrency: both doors
-- serialize same-session writes via `for update` on club_sessions (0134 §B's own comment), so
-- count-then-insert cannot race through them; a future writer without that lock races at worst
-- into one extra dog, and the trigger still holds the steady state.

begin;

-- A. the ruling lands in config: 2 → 1, and the 미확정 tag comes off
-- ⚠ columns are (name, value_num, note) — the first draft guessed value/comment and would have
-- died at apply; checked against 0048:6-13 before running anything.
update club_config
   set value_num = 1,
       note = '[Sean 확정 2026-08-27 「1 dog per person」] 참석 보호자당 동반견 한도'
 where name = 'owner_handled_dog_limit';

create or replace function public._club_owner_dog_limit_tg()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_limit int; v_have int;
begin
  if new.custody <> 'owner_handled' then return new; end if;
  v_limit := coalesce(club_cfg('owner_handled_dog_limit')::int, 1);
  select count(*) into v_have from session_dogs sd
   where sd.session_id = new.session_id
     and sd.owner_profile_id = new.owner_profile_id
     and sd.custody = 'owner_handled'
     and sd.service_state is distinct from 'ended'
     and sd.id is distinct from new.id;     -- UPDATE flip counts the OTHERS, not itself
  if v_have >= v_limit then raise exception 'dog_limit'; end if;
  return new;
end $$;

revoke all on function public._club_owner_dog_limit_tg() from public, anon;

drop trigger if exists club_owner_dog_limit on public.session_dogs;
create trigger club_owner_dog_limit
  before insert or update of custody on public.session_dogs
  for each row execute function public._club_owner_dog_limit_tg();

-- D. VERIFY — value, trigger present AND enabled (tgenabled is the STATE; the def is only the
-- shape — the law learned on club_v1_axes_sync), function sealed.
do $$
declare v numeric; n int; v_en char; v_pub boolean;
begin
  select value_num into v from club_config where name = 'owner_handled_dog_limit';
  if v is distinct from 1 then raise exception '0140 D: limit is %, expected 1', v; end if;
  select count(*), min(tgenabled) into n, v_en from pg_trigger
   where tgrelid = 'public.session_dogs'::regclass and tgname = 'club_owner_dog_limit';
  if n <> 1 or v_en <> 'O' then raise exception '0140 D: trigger n=% enabled=%', n, v_en; end if;
  select has_function_privilege('anon', 'public._club_owner_dog_limit_tg()', 'execute') into v_pub;
  if v_pub then raise exception '0140 D: guard fn anon-executable'; end if;
end $$;

commit;
