-- 0165, ruling 4. Real authenticated/anon boundaries, not helper-only promises.
-- Mutation targets: reader writes (W2), expiry ignored (E2), payment clock-bound (E3),
-- public phone leak (P2), consent bypass (P4), storage policy removed (P3).
set client_min_messages = warning;
do $suite$
declare
 h uuid; r uuid; paid uuid; reader uuid; stranger uuid; c uuid; s uuid;
 dp uuid; dr uuid; bp uuid; ids uuid[]; tiers text[] := array['none','reader','participant'];
 i int; n int; denied boolean; j jsonb; hold_deadline timestamptz; phflag timestamptz;
 path text; unknown_path text; ok boolean; f text;
begin
 h := t_user('tier_host','runner');
 r := t_user('tier_runner','runner'); update runners set tier='veteran' where profile_id=r;
 paid := t_user('tier_paid','owner'); reader := t_user('tier_reader','owner'); stranger := t_user('tier_stranger','owner');
 perform set_config('request.jwt.claim.sub',h::text,true);
 c := club_request_district('Tier'||substr(gen_random_uuid()::text,1,7)); perform club_claim_host(c);
 s := club_create_session(c,now()+interval '90 minutes','Tier meeting',t_route('Tier route'),8,'mixed');
 perform session_runner_commit(s);
 perform set_config('request.jwt.claim.sub',r::text,true); perform session_runner_commit(s);
 perform set_config('request.jwt.claim.sub',paid::text,true); dp := session_delegate_dog(s,t_dog(paid,'Paid dog'),t_consent());
 perform set_config('request.jwt.claim.sub',reader::text,true); dr := session_delegate_dog(s,t_dog(reader,'Reader dog'),t_consent());
 perform set_config('request.jwt.claim.sub',h::text,true); perform session_approve_dog(dp,true); perform session_approve_dog(dr,true);
 select hold_expires_at into hold_deadline from session_dogs where id=dr;
 if hold_deadline is not distinct from now()+interval '20 minutes' then call _pass('tier','A1 real approval stamps one 20-minute deadline');
 else call _fail('tier','A1 approval clock',hold_deadline::text); end if;
 perform set_config('request.jwt.claim.sub',paid::text,true); bp := session_pay_delegation(dp,'tier-paid',true);
 insert into club_chat_messages(session_id,sender_id,body) values(s,h,'Tier seed');
 ids := array[stranger,reader,paid];
 for i in 1..3 loop
   perform set_config('request.jwt.claim.sub',ids[i]::text,true);
   set local role authenticated;
   f := club_my_session_tier(s);
   select count(*) into n from club_chat_messages where session_id=s and audience='group';
   reset role;
   if f is not distinct from tiers[i] and (n>0) is not distinct from (i>1) then call _pass('tier','R'||i||' chat read '||tiers[i]);
   else call _fail('tier','R'||i||' chat read',coalesce(f,'NULL')||' rows='||n); end if;
   denied := false;
   begin
     set local role authenticated;
     insert into club_chat_messages(session_id,sender_id,body) values(s,ids[i],'Tier write');
     reset role;
   exception when insufficient_privilege then reset role; denied:=true;
   end;
   if denied is not distinct from (i<3) then call _pass('tier','W'||i||' chat write '||tiers[i]);
   else call _fail('tier','W'||i||' chat write','denied='||denied); end if;
   set local role authenticated; j:=club_session_roster(s); reset role;
   if (jsonb_array_length(j->'people')>0 and jsonb_array_length(j->'dogs')=2) is true then call _pass('tier','O'||i||' public roster '||tiers[i]);
   else call _fail('tier','O'||i||' roster',j::text); end if;
 end loop;
 update session_dogs set hold_expires_at=now()+interval '1 minute' where id=dr;
 if (_club_session_tier(s,reader)='reader' and _club_delegated_reserved(s)=2) is true then call _pass('tier','E1 19 minutes: reader and reserved');
 else call _fail('tier','E1 19 minutes','tier or reserved mismatch'); end if;
 update session_dogs set hold_expires_at=now()-interval '1 minute' where id=dr;
 perform set_config('request.jwt.claim.sub',reader::text,true); set local role authenticated;
 select count(*) into n from club_chat_messages where session_id=s and audience='group'; reset role;
 if (_club_session_tier(s,reader)='none' and _club_delegated_reserved(s)=1 and n=0) is true then call _pass('tier','E2 21 minutes: reader and slot expire together');
 else call _fail('tier','E2 expiry','tier, slot or chat mismatch'); end if;
 update session_dogs set hold_expires_at=now()-interval '1 day' where id=dp;
 if (_club_session_tier(s,paid)='participant' and _club_delegated_reserved(s)=1) is true then call _pass('tier','E3 paid participant ignores hold clock');
 else call _fail('tier','E3 paid control','paid changed with clock'); end if;
 -- Same owner, multiple dogs: a paid sibling must never renew an expired dog's slot.
 update session_dogs set owner_profile_id=paid where id=dr;
 if (_club_session_tier(s,paid)='participant' and _club_delegated_reserved(s)=1) is true then call _pass('tier','E4 paid sibling cannot reserve expired dog');
 else call _fail('tier','E4 sibling','slot borrowed another dog tier'); end if;
 update session_dogs set owner_profile_id=reader where id=dr;
 if (_club_incident_can_open(s,reader)=false and _club_incident_can_open(s,paid)=true and _club_incident_can_open(s,h)=true) is true then call _pass('tier','I1 safety case standing requires participation');
 else call _fail('tier','I1 incident','wrong standing'); end if;
 update session_dogs set hold_expires_at=now()+interval '1 minute' where id=dr;
 if _club_incident_can_open(s,reader) is distinct from false then call _fail('tier','I2 reader incident','unpaid reader has standing');
 else call _pass('tier','I2 active unpaid reader cannot open safety case'); end if;
 -- Check the EFFECTIVE 0171 helper through this 0165 roster after all migrations apply.
 select phone_collection_live_since into phflag from ops_flags;
 update profiles set phone='01012345678' where id in(h,paid);
 update ops_flags set phone_collection_live_since=null;
 perform set_config('request.jwt.claim.sub',h::text,true); j:=club_session_roster(s);
 if not exists(select 1 from jsonb_array_elements(j->'people') e where e->>'phone' is not null) then call _pass('tier','P1 effective phone rollout gate remains closed');
 else call _fail('tier','P1 phone gate','closed flag disclosed phone'); end if;
 update ops_flags set phone_collection_live_since=now()-interval '1 minute';
 j:=club_session_roster(s);
 if exists(select 1 from jsonb_array_elements(j->'people') e where e->>'profileId'=paid::text and e->>'phone'='01012345678') then call _pass('tier','P1b host phone positive control when flag open');
 else call _fail('tier','P1b phone control','host lost authorized phone'); end if;
 perform set_config('request.jwt.claim.sub','',true); set local role anon; j:=club_session_roster(s); reset role;
 if (jsonb_array_length(j->'people')>0 and j->'capacityMeter'='null'::jsonb) is true
   and not exists(select 1 from jsonb_array_elements(j->'people') e where e->>'phone' is not null)
   and not exists(select 1 from jsonb_array_elements(j->'dogs') e where e->'detail' is distinct from 'null'::jsonb or e->>'chargeLabel' is not null)
 then call _pass('tier','P2 anon public roster excludes phone notes emergency and money');
 else call _fail('tier','P2 public privacy',j::text); end if;
 update ops_flags set phone_collection_live_since=phflag;
 path:=r::text||'/runs/'||bp::text||'/tier.jpg'; unknown_path:=r::text||'/chat/private.jpg';
 insert into runs(booking_id,photos) values(bp,array[path]) on conflict(booking_id) do update set photos=excluded.photos;
 insert into storage.objects(bucket_id,name,owner) values('media',path,r),('media',unknown_path,r);
 update delegation_consents set photo_consent=true where session_dog_id=dp;
 set local role anon; j:=club_session_roster(s);
 select count(*) into n from storage.objects where bucket_id='media' and name in(path,unknown_path); reset role;
 if (j->'pictures' @> jsonb_build_array(path) and n=1) is true then call _pass('tier','P3 anon sees consented session picture and can sign its exact object');
 else call _fail('tier','P3 public picture',j::text||' objects='||n); end if;
 update delegation_consents set photo_consent=false where session_dog_id=dp;
 set local role anon; j:=club_session_roster(s);
 select count(*) into n from storage.objects where bucket_id='media' and name=path; reset role;
 if (j->'pictures'='[]'::jsonb and n=0) is true then call _pass('tier','P4 withdrawn consent seals public list and object');
 else call _fail('tier','P4 consent',j::text||' objects='||n); end if;
 -- ACL positive and negative controls: public doors explicit, arbitrary-uid helpers private.
 ok:=true;
 foreach f in array array['club_session_roster(uuid)','club_run_photo_allowed(uuid)','club_public_photo_path(text)'] loop
   ok:=ok and has_function_privilege('anon',f,'execute') is true and has_function_privilege('public',f,'execute') is false;
 end loop;
 foreach f in array array['_club_session_tier(uuid,uuid)','_club_delegation_tier(session_dogs)'] loop
   ok:=ok and has_function_privilege('authenticated',f,'execute') is false and has_function_privilege('anon',f,'execute') is false;
 end loop;
 if ok is true then call _pass('tier','A2 exact public doors and private arbitrary identity helpers');
 else call _fail('tier','A2 ACL','wrong execute grants'); end if;
end $suite$;
