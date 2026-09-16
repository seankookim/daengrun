-- 0163: refuse rules outside the editor's bounds, preserving boundary writes.
set client_min_messages = warning;

do $suite$
declare
  v_runner uuid := t_user('runner_rules_checks', 'runner');
  v_value integer;
  v_constraint text;
  v_bad text;
begin
  insert into runner_booking_rules (runner_id) values (v_runner);

  -- Catch the specific CHECK, not an unrelated FK/RLS/NOT NULL refusal.
  v_bad := '';
  foreach v_value in array array[-1, 121] loop
    begin
      update runner_booking_rules set rest_after_min = v_value where runner_id = v_runner;
      v_bad := v_bad || ' accepted rest=' || v_value;
    exception when check_violation then
      get stacked diagnostics v_constraint = constraint_name;
      if v_constraint is distinct from 'runner_booking_rules_rest_after_min_bounds' then
        v_bad := v_bad || ' wrong constraint=' || coalesce(v_constraint, 'NULL');
      end if;
    end;
  end loop;
  if v_bad = '' then call _pass('rrcheck', '0163-R1 rest bounds reject -1 and 121');
  else call _fail('rrcheck', '0163-R1 rest bounds', v_bad); end if;

  v_bad := '';
  foreach v_value in array array[0, 9] loop
    begin
      update runner_booking_rules set max_sessions_per_day = v_value where runner_id = v_runner;
      v_bad := v_bad || ' accepted daily=' || v_value;
    exception when check_violation then
      get stacked diagnostics v_constraint = constraint_name;
      if v_constraint is distinct from 'runner_booking_rules_max_sessions_per_day_bounds' then
        v_bad := v_bad || ' wrong constraint=' || coalesce(v_constraint, 'NULL');
      end if;
    end;
  end loop;
  if v_bad = '' then call _pass('rrcheck', '0163-R2 daily bounds reject 0 and 9');
  else call _fail('rrcheck', '0163-R2 daily bounds', v_bad); end if;

  begin
    update runner_booking_rules set rest_after_min = 0, max_sessions_per_day = 1
      where runner_id = v_runner;
    if (select (rest_after_min, max_sessions_per_day) = (0, 1)
        from runner_booking_rules where runner_id = v_runner) is distinct from true then
      raise exception 'lower boundary was not saved';
    end if;
    update runner_booking_rules set rest_after_min = 120, max_sessions_per_day = 8
      where runner_id = v_runner;
    if (select (rest_after_min, max_sessions_per_day) = (120, 8)
        from runner_booking_rules where runner_id = v_runner) is distinct from true then
      raise exception 'upper boundary was not saved';
    end if;
    call _pass('rrcheck', '0163-R3 both inclusive boundary pairs are saved');
  exception when others then
    call _fail('rrcheck', '0163-R3 inclusive boundary writes', sqlstate || ': ' || sqlerrm);
  end;

  delete from runner_booking_rules where runner_id = v_runner;
end $suite$;
