-- Disposable isolated PostgreSQL only. All PINs below are public test fixtures.
begin;
insert into auth.users(id,email,email_confirmed_at)
select ('b5000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'pin-fixture-'||n||'@example.invalid',
 case when n=7 then null else now() end from generate_series(1,9)n;
set local role authenticated;
set local "request.jwt.claim.sub"='b5000000-0000-4000-8000-000000000001';
set local "request.jwt.claims"='{"sub":"b5000000-0000-4000-8000-000000000001","aal":"aal1"}';
select set_config('test.pin_org',organization_id::text,true),set_config('test.pin_branch',branch_id::text,true),
 set_config('test.pin_owner',membership_id::text,true) from public.bootstrap_organization('PIN Boundary Shop','PIN Owner');
reset role;
insert into public.branches(id,organization_id,name,code)values('b5100000-0000-4000-8000-000000000002',test.id('pin_org'),'Other PIN Branch','PIN-OTHER');
insert into public.organization_memberships(id,organization_id,user_id,role,status)
select ('b5200000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,test.id('pin_org'),
 ('b5000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 case n when 2 then 'manager' when 4 then 'admin' when 8 then 'inventory_staff' else 'cashier' end,
 case when n=6 then 'disabled' else 'active' end from generate_series(2,8)n;
insert into public.membership_branches(membership_id,organization_id,branch_id)
select id,organization_id,case when user_id='b5000000-0000-4000-8000-000000000005' then 'b5100000-0000-4000-8000-000000000002'::uuid else test.id('pin_branch') end
 from public.organization_memberships where organization_id=test.id('pin_org') and role<>'owner';
insert into public.profiles(user_id,full_name)select ('b5000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'PIN employee '||n from generate_series(2,8)n;
create function test.pin_prepare(p_n integer,p_action text default 'verify',p_revision bigint default null)returns uuid language sql as $$
 select (public.prepare_employee_pin_operation(test.id('pin_org'),('b5300000-0000-4000-8000-'||lpad(p_n::text,12,'0'))::uuid,p_action,
  coalesce(p_revision,(public.get_employee_pin_status(test.id('pin_org'))->>'revision')::bigint))->>'id')::uuid;
$$;
grant execute on function test.pin_prepare(integer,text,bigint)to authenticated;
set local role anon;
select test.expect_error('select public.get_employee_pin_status(test.id(''pin_org''))','42501','Anonymous cannot read employee PIN status');
select test.expect_error('select public.prepare_employee_pin_operation(test.id(''pin_org''),gen_random_uuid(),''set'',1)','42501','Anonymous cannot prepare PIN mutation');
select test.expect_error('select public.complete_employee_pin_operation(gen_random_uuid(),gen_random_uuid(),''739284'')','42501','Anonymous cannot consume PIN capability');
reset role;
set local role authenticated;
select test.assert((public.get_employee_pin_status(test.id('pin_org'))->>'configured')='false','New account has no invented PIN');
select test.expect_error('select pin_hash from private.employee_pin_secrets','42501','Authenticated Owner cannot retrieve PIN hash');
select test.expect_error('select public.complete_employee_pin_operation(gen_random_uuid(),auth.uid(),''739284'')','42501','Authenticated Owner cannot consume service-only PIN capability');
select test.expect_error('select public.prepare_employee_pin_operation(test.id(''pin_org''),null,''set'',1)','22023','PIN request must have stable operation UUID');
select set_config('test.pin_owner_op',test.pin_prepare(1,'set',1)::text,true);
select test.assert(test.pin_prepare(1,'set',1)=test.id('pin_owner_op'),'Same PIN operation retry retains one bounded capability');
select test.expect_error('select test.pin_prepare(1,''verify'',1)','23505','PIN operation UUID cannot change action');
reset role;
set local role service_role;
select test.expect_error('select public.complete_employee_pin_operation(test.id(''pin_owner_op''),''b5000000-0000-4000-8000-000000000002'',''739284'')','42501','PIN capability cannot be consumed for different actor');
select test.assert((public.complete_employee_pin_operation(test.id('pin_owner_op'),'b5000000-0000-4000-8000-000000000001','739284')->>'accepted')='true','Server-only salted hash sets authenticated actor PIN');
select test.assert((public.complete_employee_pin_operation(test.id('pin_owner_op'),'b5000000-0000-4000-8000-000000000001','849275')->>'status')::jsonb->>'revision'='2','Lost set response replay preserves original one-time result');
reset role;
select test.assert((select pin_hash like '$2a$12$%' and pin_hash<>'739284' from private.employee_pin_secrets where membership_id=test.id('pin_owner')),'Stored PIN uses salted bcrypt cost 12, never plaintext');
select test.assert((select count(*) from public.audit_logs where organization_id=test.id('pin_org') and action='employee.pin_set')=1,'Set replay produces one immutable audit');
select test.assert(not exists(select 1 from public.audit_logs where organization_id=test.id('pin_org') and metadata::text like '%739284%'),'PIN text never appears in server audit metadata');

set local role authenticated;
set local "request.jwt.claim.sub"='b5000000-0000-4000-8000-000000000003';
set local "request.jwt.claims"='{"sub":"b5000000-0000-4000-8000-000000000003","aal":"aal1"}';
select test.expect_error('select public.get_employee_pin_status(test.id(''pin_org''),test.id(''pin_owner''))','42501','Cashier cannot read another actor PIN status');
select test.expect_error('select public.list_employee_pin_reset_targets(test.id(''pin_org''))','42501','Cashier cannot enumerate reset targets');
select set_config('test.pin_cashier_op',test.pin_prepare(2,'set',1)::text,true);
reset role;
set local role service_role;
select test.assert((public.complete_employee_pin_operation(test.id('pin_cashier_op'),'b5000000-0000-4000-8000-000000000003','739284')->>'accepted')='true','Cashier can set own PIN using authenticated authorization');
reset role;
select test.assert((select count(distinct pin_hash) from private.employee_pin_secrets where pin_hash is not null)=2,'Equal fixture PINs get distinct random bcrypt salts');
set local role authenticated;
select set_config('test.pin_bad_change',test.pin_prepare(3,'set',2)::text,true);
reset role;
set local role service_role;
select test.assert((public.complete_employee_pin_operation(test.id('pin_bad_change'),'b5000000-0000-4000-8000-000000000003','849275','999888')->>'accepted')='false','Replacing configured PIN requires correct current PIN');
reset role;
set local role authenticated;
select set_config('test.pin_good_change',test.pin_prepare(4,'set',2)::text,true);
reset role;
set local role service_role;
select test.assert((public.complete_employee_pin_operation(test.id('pin_good_change'),'b5000000-0000-4000-8000-000000000003','849275','739284')->>'accepted')='true','Correct current PIN changes hash atomically');
reset role;
select test.assert((select revision=3 and failed_attempts=0 from private.employee_pin_secrets where user_id='b5000000-0000-4000-8000-000000000003'),'Successful change increments revision and clears failed attempts');
set local role authenticated;
select set_config('test.pin_expired',test.pin_prepare(5,'verify',3)::text,true);
reset role;
update private.employee_pin_operations set expires_at=clock_timestamp()-interval '1 second' where id=test.id('pin_expired');
set local role service_role;
select test.expect_error('select public.complete_employee_pin_operation(test.id(''pin_expired''),''b5000000-0000-4000-8000-000000000003'',''849275'')','42501','Expired PIN capability cannot perform verification');
reset role;
set local role authenticated;
select test.assert(test.pin_prepare(5,'verify',3)=test.id('pin_expired'),'Fresh user authorization renews only unconsumed expired capability');
reset role;
set local role service_role;
select test.assert((public.complete_employee_pin_operation(test.id('pin_expired'),'b5000000-0000-4000-8000-000000000003','849275')->>'accepted')='true','Renewed currently authenticated capability performs exact PIN check');
reset role;

-- Five separate guesses persist across requests; result replay is not a guess.
set local role authenticated;
select set_config('test.pin_guess1',test.pin_prepare(11,'verify',3)::text,true),set_config('test.pin_guess2',test.pin_prepare(12,'verify',3)::text,true),
 set_config('test.pin_guess3',test.pin_prepare(13,'verify',3)::text,true),set_config('test.pin_guess4',test.pin_prepare(14,'verify',3)::text,true),
 set_config('test.pin_guess5',test.pin_prepare(15,'verify',3)::text,true),set_config('test.pin_locked',test.pin_prepare(16,'verify',3)::text,true);
reset role;
set local role service_role;
select test.assert((public.complete_employee_pin_operation(test.id('pin_guess1'),'b5000000-0000-4000-8000-000000000003','777888')->>'accepted')='false','Incorrect PIN check returns generic denial');
select test.assert((public.complete_employee_pin_operation(test.id('pin_guess1'),'b5000000-0000-4000-8000-000000000003','849275')->>'accepted')='false','Consumed failed guess cannot change meaning on replay');
select public.complete_employee_pin_operation(test.id('pin_guess2'),'b5000000-0000-4000-8000-000000000003','777888');
select public.complete_employee_pin_operation(test.id('pin_guess3'),'b5000000-0000-4000-8000-000000000003','777888');
select public.complete_employee_pin_operation(test.id('pin_guess4'),'b5000000-0000-4000-8000-000000000003','777888');
select public.complete_employee_pin_operation(test.id('pin_guess5'),'b5000000-0000-4000-8000-000000000003','777888');
select test.assert((public.complete_employee_pin_operation(test.id('pin_locked'),'b5000000-0000-4000-8000-000000000003','849275')->>'accepted')='false','Correct PIN remains denied during durable fifteen-minute lock');
reset role;
select test.assert((select failed_attempts=5 and locked_until>clock_timestamp()+interval '14 minutes' from private.employee_pin_secrets where user_id='b5000000-0000-4000-8000-000000000003'),'Attempts cap persists once despite consumed failure replay');
select test.assert((select count(*) from private.security_notifications where organization_id=test.id('pin_org') and action='employee.pin_denied')=1,'Only fifth failed attempt creates one source-backed lockout notification');
set local role authenticated;
select test.expect_error('select public.reset_employee_pin(test.id(''pin_org''),test.id(''pin_owner''),gen_random_uuid(),2,''Cashier cannot reset Owner'')','42501','PIN check never elevates Cashier to administrator');
set local "request.jwt.claim.sub"='b5000000-0000-4000-8000-000000000002';
set local "request.jwt.claims"='{"sub":"b5000000-0000-4000-8000-000000000002","aal":"aal1"}';
select test.assert(jsonb_array_length(public.list_employee_pin_reset_targets(test.id('pin_org')))=3,'Manager target list contains only active lower-role accounts entirely in branch scope');
select test.expect_error('select public.reset_employee_pin(test.id(''pin_org''),''b5200000-0000-4000-8000-000000000005'',gen_random_uuid(),1,''Cross-branch reset attempt'')','42501','Manager cannot reset out-of-branch employee');
select test.expect_error('select public.reset_employee_pin(test.id(''pin_org''),''b5200000-0000-4000-8000-000000000004'',gen_random_uuid(),1,''Reset superior admin attempt'')','42501','Manager cannot reset superior Admin');
select test.expect_error('select public.reset_employee_pin(test.id(''pin_org''),''b5200000-0000-4000-8000-000000000003'',gen_random_uuid(),3,''x'')','22023','Manager reset requires meaningful audit reason');
select set_config('test.pin_reset',public.reset_employee_pin(test.id('pin_org'),'b5200000-0000-4000-8000-000000000003','b5400000-0000-4000-8000-000000000001',3,'Employee forgot the previous PIN')::text,true);
select test.assert(public.reset_employee_pin(test.id('pin_org'),'b5200000-0000-4000-8000-000000000003','b5400000-0000-4000-8000-000000000001',3,'Employee forgot the previous PIN')=current_setting('test.pin_reset')::jsonb,'Reset lost-response retry retains original audited result');
select test.expect_error('select public.reset_employee_pin(test.id(''pin_org''),''b5200000-0000-4000-8000-000000000003'',''b5400000-0000-4000-8000-000000000001'',3,''A different reset reason'')','23505','Reset UUID binds immutable employee and reason');
reset role;
select test.assert((select pin_hash is null and reset_required and revision=4 and locked_until is null and failed_attempts=0 from private.employee_pin_secrets where user_id='b5000000-0000-4000-8000-000000000003'),'Reset removes old PIN and lock without inventing a replacement secret');
select test.assert((select count(*) from public.audit_logs where organization_id=test.id('pin_org') and action='employee.pin_reset')=1,'Reset replay produces one audit with authenticated Manager identity');
select test.assert((select target_actor_id='b5000000-0000-4000-8000-000000000003' from private.security_notifications where organization_id=test.id('pin_org') and action='employee.pin_reset'),'Reset notification subject is target employee rather than approving manager');
set local role authenticated;
set local "request.jwt.claim.sub"='b5000000-0000-4000-8000-000000000003';
set local "request.jwt.claims"='{"sub":"b5000000-0000-4000-8000-000000000003","aal":"aal1"}';
select test.assert(not exists(select 1 from jsonb_array_elements(public.list_security_notifications(test.id('pin_org'),test.id('pin_branch')))n where n->>'action'='employee.pin_set' and n->>'message' like '%739284%'),'Employee notifications contain no PIN material');
select test.assert(jsonb_array_length(public.list_security_notifications(test.id('pin_org'),test.id('pin_branch')))=4,'Cashier sees own set, change, lockout and reset notices without Owner PIN event');
set local "request.jwt.claim.sub"='b5000000-0000-4000-8000-000000000004';
set local "request.jwt.claims"='{"sub":"b5000000-0000-4000-8000-000000000004","aal":"aal1"}';
select test.assert(jsonb_array_length(public.list_security_notifications(test.id('pin_org'),test.id('pin_branch')))=4,'Scoped Admin notifications reuse immutable audit scope and exclude Owner PIN event');
set local "request.jwt.claim.sub"='b5000000-0000-4000-8000-000000000003';
set local "request.jwt.claims"='{"sub":"b5000000-0000-4000-8000-000000000003","aal":"aal1"}';
select set_config('test.pin_replacement',test.pin_prepare(20,'set',4)::text,true);
reset role;
set local role service_role;
select test.assert((public.complete_employee_pin_operation(test.id('pin_replacement'),'b5000000-0000-4000-8000-000000000003','675849')->>'accepted')='true','Employee sets replacement after current online Auth authorization');
reset role;
set local role authenticated;
select set_config('test.pin_disabled_op',test.pin_prepare(21,'verify',5)::text,true);
reset role;
update public.organization_memberships set status='disabled' where id='b5200000-0000-4000-8000-000000000003';
set local role service_role;
select test.expect_error('select public.complete_employee_pin_operation(test.id(''pin_disabled_op''),''b5000000-0000-4000-8000-000000000003'',''675849'')','42501','Disabling employee after preparation invalidates PIN capability');
reset role;
update public.organization_memberships set status='active' where id='b5200000-0000-4000-8000-000000000003';
set local role authenticated;
set local "request.jwt.claim.sub"='b5000000-0000-4000-8000-000000000007';
select test.expect_error('select public.get_employee_pin_status(test.id(''pin_org''))','42501','Unverified email cannot read PIN workflow');
set local "request.jwt.claim.sub"='b5000000-0000-4000-8000-000000000009';
select test.expect_error('select public.get_employee_pin_status(test.id(''pin_org''))','42501','Verified unrelated user cannot use known organization UUID');
set local "request.jwt.claim.sub"='b5000000-0000-4000-8000-000000000001';
set local "request.jwt.claims"='{"sub":"b5000000-0000-4000-8000-000000000001","aal":"aal1","amr":[{"method":"recovery"}]}';
select test.expect_error('select test.pin_prepare(30,''set'',2)','42501','Password-recovery proof cannot prepare PIN mutation');
select test.expect_error('select public.reset_employee_pin(test.id(''pin_org''),test.id(''pin_owner''),gen_random_uuid(),2,''Recovery cannot bypass PIN'')','42501','Password-recovery proof cannot reset own PIN');
set local "request.jwt.claims"='{"sub":"b5000000-0000-4000-8000-000000000001","aal":"aal1"}';
select set_config('test.pin_mfa_op',test.pin_prepare(31,'verify',2)::text,true);
reset role;
insert into private.security_policies(organization_id,require_privileged_mfa)values(test.id('pin_org'),true)on conflict(organization_id)do update set require_privileged_mfa=true;
set local role authenticated;
select test.assert((public.get_employee_pin_status(test.id('pin_org'))->>'configured')='true','Own nonsecret PIN status remains available for privileged MFA setup');
select test.expect_error('select public.get_employee_pin_status(test.id(''pin_org''),''b5200000-0000-4000-8000-000000000003'')','42501','Privileged AAL1 cannot read another employee PIN status');
select test.expect_error('select test.pin_prepare(32,''verify'',2)','42501','Privileged PIN preparation requires source-backed AAL2 policy');
select test.expect_error('select public.reset_employee_pin(test.id(''pin_org''),test.id(''pin_owner''),gen_random_uuid(),2,''MFA policy requires step up'')','42501','Owner PIN reset cannot bypass current MFA requirement');
reset role;
set local role service_role;
select test.expect_error('select public.complete_employee_pin_operation(test.id(''pin_mfa_op''),''b5000000-0000-4000-8000-000000000001'',''739284'')','42501','Service PIN completion rechecks new MFA policy against stored actor context');
reset role;
set local role authenticated;
set local "request.jwt.claims"='{"sub":"b5000000-0000-4000-8000-000000000001","aal":"aal2"}';
select test.assert(test.pin_prepare(31,'verify',2)=test.id('pin_mfa_op'),'Current MFA-authenticated retry refreshes unconsumed capability context');
reset role;
set local role service_role;
select test.assert((public.complete_employee_pin_operation(test.id('pin_mfa_op'),'b5000000-0000-4000-8000-000000000001','739284')->>'accepted')='true','Verified AAL2 completes supplemental PIN check without changing role');
reset role;
rollback;
