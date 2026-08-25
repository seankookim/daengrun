-- 0125_route_km_corrections.sql
-- Three 0078 seeds advertise a length the drawn line does not have (record: awaiting-sean.md
-- §0-octodecies — "THREE ROUTE NAMES ADVERTISE A LENGTH THE LINE DOES NOT HAVE"; ruling:
-- console #18, Sean 2026-08-25 "the three route-name lengths corrected" = the record's option A,
-- rename the trailing km token to the measured length).
--
-- Measured lengths (the record's own _route_dist_m re-measurement of the seeded geometry):
--   서리풀–몽마르뜨 종주 5km   measured 4.84 km  → token 4.8km, km 4.8
--   한강 반포–잠원 7km          measured 6.72 km  → token 6.7km, km 6.7
--   반포한강 그랜드 루프        measured 4.78 km  → name carries NO token, km moves alone → 4.8
--
-- Mechanics (0100_route_name_km_agrees.sql:60-82): `routes_name_km_agrees` requires
-- round(_route_name_km_token(name), 1) = km whenever the name ends in a `<number>km` token, so
-- for the first two rows name and km MUST move in the same statement — moving either alone is
-- refused by the CHECK, which is exactly why this is a migration and not an ad-hoc row edit.
-- Uniqueness: routes_town_name_key is UNIQUE(town, name); neither corrected name collides with
-- any seeded 반포동 name. Live rows re-checked at deploy time (see the fail-loud block: a count
-- mismatch aborts the whole file rather than skipping a drifted row).
--
-- FAIL-LOUD, NOT IDEMPOTENT-SILENT: each UPDATE must hit exactly one row. Zero means production
-- drifted from the seeds (renamed or deleted) and the correction needs re-scouting — silently
-- applying a partial correction would leave the catalog half-renamed with nothing red anywhere.

do $$
declare
  v_n int;
begin
  update public.routes
     set name = '서리풀–몽마르뜨 종주 4.8km', km = 4.8
   where town = '반포동' and name = '서리풀–몽마르뜨 종주 5km';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'route_km_correction_miss: 서리풀–몽마르뜨 종주 5km matched % rows (want 1)', v_n;
  end if;

  update public.routes
     set name = '한강 반포–잠원 6.7km', km = 6.7
   where town = '반포동' and name = '한강 반포–잠원 7km';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'route_km_correction_miss: 한강 반포–잠원 7km matched % rows (want 1)', v_n;
  end if;

  update public.routes
     set km = 4.8
   where town = '반포동' and name = '반포한강 그랜드 루프';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'route_km_correction_miss: 반포한강 그랜드 루프 matched % rows (want 1)', v_n;
  end if;
end $$;
