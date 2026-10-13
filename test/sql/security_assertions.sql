\set ON_ERROR_STOP on
begin;
create schema test;
create function test.assert(p_ok boolean,p_message text) returns void language plpgsql as $$
begin
  if p_ok is distinct from true then raise exception 'FAILED: %',p_message; end if;
  raise notice 'PASS: %',p_message;
end;
$$;
create function test.expect_error(p_sql text,p_state text,p_message text)
returns void language plpgsql as $$
declare v_state text;
begin
  begin execute p_sql; exception when others then get stacked diagnostics v_state = returned_sqlstate; end;
  perform test.assert(v_state = p_state,p_message || ' (expected ' || p_state || ', got ' || coalesce(v_state,'success') || ')');
end;
$$;
create function test.id(p_key text) returns uuid language sql stable as $$
  select current_setting('test.' || p_key)::uuid;
$$;
grant usage on schema test to anon,authenticated,service_role;
grant execute on all functions in schema test to anon,authenticated,service_role;

insert into auth.users(id,email,email_confirmed_at)
select ('00000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,'test' || n || '@example.invalid',
  case when n = 3 then null else now() end
from generate_series(1,13) n;

set local role anon;
select test.expect_error($q$select * from public.bootstrap_organization('Anonymous Shop','Unknown Owner')$q$,'42501','Anonymous bootstrap denied');
select test.expect_error('select * from public.organizations','42501','Anonymous tenant reads denied');
reset role;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
set local role authenticated;
select test.expect_error($q$select * from public.bootstrap_organization('Unverified Shop','Unverified Person')$q$,'42501','Email verification comes from auth.users');
select test.expect_error('select * from auth.users','42501','Client cannot inspect Auth users');
reset role;
select test.assert(not exists (select 1 from public.organizations where owner_user_id = '00000000-0000-4000-8000-000000000003'),'Unverified bootstrap leaves no organization');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select set_config('test.org_a',organization_id::text,true),set_config('test.branch_a',branch_id::text,true),
  set_config('test.owner_membership_a',membership_id::text,true) from public.bootstrap_organization('Shop A','Owner A');
select test.assert((select count(*) from public.organizations) = 1,'Owner sees their organization');
select test.assert((select role from public.organization_memberships where id = test.id('owner_membership_a')) = 'owner','RPC creates backend owner membership');
select test.assert((select full_name from public.profiles where user_id = auth.uid()) = 'Owner A','RPC creates profile');
select test.assert((select name from public.branches where id = test.id('branch_a')) = 'Main Branch','RPC creates Main Branch');
select test.assert((select organization_id from public.bootstrap_organization('A Different Name','A Different Person')) = test.id('org_a'),'Repeated bootstrap returns same IDs');
select test.expect_error($q$select * from public.bootstrap_organization('x','Valid Name')$q$,'22023','Invalid bootstrap names rejected');
select test.expect_error($q$update public.organization_memberships set role = 'admin'$q$,'42501','Owner cannot edit memberships directly');
select test.expect_error($q$insert into public.organizations(business_name,owner_user_id) values ('Spoofed Owner','00000000-0000-4000-8000-000000000002')$q$,'42501','Client cannot choose owner ID');
select test.expect_error($q$update public.profiles set user_id = '00000000-0000-4000-8000-000000000002'$q$,'42501','Column grants protect profile identity');
update public.profiles set phone = '+63-example' where user_id = auth.uid();
select test.assert((select phone from public.profiles where user_id = auth.uid()) = '+63-example','Own permitted profile columns can update');
reset role;
select test.assert((select count(*) from public.organizations where owner_user_id = '00000000-0000-4000-8000-000000000001') = 1,'Bootstrap has one organization');
select test.assert((select count(*) from public.audit_logs where organization_id = test.id('org_a') and action = 'organization.bootstrap') = 1,'Repeated bootstrap has one audit event');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
set local role authenticated;
select set_config('test.org_b',organization_id::text,true),set_config('test.branch_b',branch_id::text,true)
  from public.bootstrap_organization('Shop B','Owner B');
reset role;
select set_config('request.jwt.claim.sub','',true);
insert into public.branches(id,organization_id,name,code)
  values ('20000000-0000-4000-8000-000000000002',test.id('org_a'),'Second Branch','SECOND');
insert into public.organization_memberships(id,organization_id,user_id,role,status,all_branches)
select ('30000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,test.id('org_a'),
  ('00000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  case n when 4 then 'manager' when 5 then 'cashier' when 6 then 'inventory_staff' else 'admin' end,
  case n when 8 then 'pending' when 9 then 'disabled' else 'active' end,n = 10
from generate_series(4,10) n;
insert into public.membership_branches(membership_id,organization_id,branch_id)
select id,organization_id,test.id('branch_a') from public.organization_memberships
  where organization_id = test.id('org_a') and role <> 'owner' and not all_branches;
insert into public.profiles(user_id,full_name) values ('00000000-0000-4000-8000-000000000005','Cashier A');
insert into public.organization_memberships(id,organization_id,user_id,role,status)
  values ('30000000-0000-4000-8000-000000000013',test.id('org_a'),'00000000-0000-4000-8000-000000000013','cashier','active');
insert into public.membership_branches(membership_id,organization_id,branch_id)
  values ('30000000-0000-4000-8000-000000000013',test.id('org_a'),'20000000-0000-4000-8000-000000000002');
insert into public.categories(id,organization_id,name) values
  ('40000000-0000-4000-8000-000000000001',test.id('org_a'),'A Category'),
  ('40000000-0000-4000-8000-000000000002',test.id('org_b'),'B Category');
insert into public.products(id,organization_id,category_id,sku,name,price_minor) values
  ('50000000-0000-4000-8000-000000000001',test.id('org_a'),'40000000-0000-4000-8000-000000000001','A-01','A Product',15000),
  ('50000000-0000-4000-8000-000000000002',test.id('org_b'),'40000000-0000-4000-8000-000000000002','B-01','B Product',20000);
insert into public.employee_invitations(organization_id,normalized_email,full_name,requested_role,invited_by,branch_id,token_digest,expires_at)
  values (test.id('org_a'),'future@example.invalid','Future Employee','cashier','00000000-0000-4000-8000-000000000001',test.id('branch_a'),decode(repeat('ab',32),'hex'),now()+interval '1 day');
insert into public.employee_invitations(organization_id,normalized_email,full_name,requested_role,invited_by,branch_id,token_digest,expires_at)
  values (test.id('org_a'),'otherbranch@example.invalid','Other Branch Employee','cashier','00000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002',decode(repeat('ef',32),'hex'),now()+interval '1 day');
insert into public.audit_logs(organization_id,role,action,entity,branch_id)
  values (test.id('org_a'),'system','test.branch_fixture','test','20000000-0000-4000-8000-000000000002');
insert into public.financial_events(id,organization_id,branch_id,actor_user_id,event_kind,payload_digest,payload)
  values ('60000000-0000-4000-8000-000000000001',test.id('org_a'),test.id('branch_a'),
    '00000000-0000-4000-8000-000000000001','test_fixture',decode(repeat('cd',32),'hex'),'{}');
select test.expect_error($q$insert into public.membership_branches(membership_id,organization_id,branch_id) values ('30000000-0000-4000-8000-000000000005',test.id('org_a'),test.id('branch_b'))$q$,'23503','Composite FK prevents mixed-tenant branch assignment');
select test.expect_error($q$insert into public.organization_memberships(organization_id,user_id,role,status,all_branches) values (test.id('org_b'),'00000000-0000-4000-8000-000000000005','owner','active',true)$q$,'23514','Owner membership must match actual owner identity');

-- Every supported active employee role gets only its assigned branch.
set local role authenticated;
do $$ declare v_n integer; begin
  for v_n in 4..7 loop
    perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-' || lpad(v_n::text,12,'0'),true);
    perform test.assert((select count(*) from public.organizations) = 1,'Active role ' || v_n || ' sees own tenant only');
    perform test.assert((select count(*) from public.branches) = 1,'Active role ' || v_n || ' sees assigned branch only');
    perform test.assert((select count(*) from public.products) = 1,'Active role ' || v_n || ' reads own catalog');
    perform test.assert(not private.can_access_branch(test.id('org_a'),'20000000-0000-4000-8000-000000000002'),'Active role ' || v_n || ' cannot cross branch');
    perform test.assert(not private.can_access_branch(test.id('org_b'),test.id('branch_b')),'Active role ' || v_n || ' cannot cross tenant');
    perform test.expect_error($q$update public.organization_memberships set role = 'owner',all_branches = true where user_id = auth.uid()$q$,'42501','Role ' || v_n || ' cannot self escalate');
    perform test.expect_error($q$insert into public.audit_logs(organization_id,role,action,entity) values (test.id('org_a'),'owner','forged','test')$q$,'42501','Role ' || v_n || ' cannot forge audit actor');
    perform test.expect_error('update public.audit_logs set metadata = ''{}''','42501','Role ' || v_n || ' cannot update audit');
    perform test.expect_error('delete from public.audit_logs','42501','Role ' || v_n || ' cannot delete audit');
    perform test.expect_error('select * from public.financial_events','42501','Role ' || v_n || ' cannot read reserved financial payloads');
    perform test.expect_error('update public.financial_events set payload = ''{}''','42501','Role ' || v_n || ' cannot update financial records');
    perform test.expect_error('delete from public.financial_events','42501','Role ' || v_n || ' cannot delete financial records');
  end loop;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000005',true);
select test.assert((select count(*) from public.organization_memberships) = 1,'Cashier sees only their own membership');
select test.assert((select count(*) from public.audit_logs) = 0,'Cashier cannot inspect administrative audit');
select test.assert((select count(*) from public.employee_invitations) = 0,'Cashier cannot inspect invitations');
select test.expect_error($q$insert into public.products(organization_id,sku,name) values (test.id('org_a'),'CASHIER','Denied')$q$,'42501','Cashier catalog insert denied');
with changed as (update public.products set price_minor = 1 returning id)
  select test.assert((select count(*) from changed) = 0,'Cashier price mutation denied by RLS');
with changed as (update public.profiles set full_name = 'Tampered' where user_id <> auth.uid() returning user_id)
  select test.assert((select count(*) from changed) = 0,'Cannot update another user profile');
select test.expect_error($q$insert into public.employee_invitations(organization_id) values (test.id('org_a'))$q$,'42501','No client employee invitation writes');
select test.expect_error($q$insert into public.financial_events(organization_id) values (test.id('org_a'))$q$,'42501','No client financial acceptance');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000010',true);
select test.assert((select count(*) from public.branches) = 2,'Admin all-branch access requires explicit true flag');
select test.assert((select count(*) from public.employee_invitations) = 2,'All-branch admin can inspect both branches invitations');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000007',true);
select test.assert((select count(*) from public.branches) = 1,'Admin false flag respects exact assignment');
select test.assert(not exists (select 1 from public.membership_branches where branch_id = '20000000-0000-4000-8000-000000000002'),'Scoped admin cannot inspect foreign branch assignments');
select test.assert(not exists (select 1 from public.audit_logs where branch_id = '20000000-0000-4000-8000-000000000002'),'Scoped admin cannot inspect foreign branch audit');
select test.assert((select count(*) from public.employee_invitations) = 1,'Authorized admin can inspect invitation metadata');
select test.expect_error('select token_digest from public.employee_invitations','42501','Invitation token digest is not client-readable');
select test.expect_error($q$insert into public.products(organization_id,category_id,sku,name) values (test.id('org_a'),'40000000-0000-4000-8000-000000000002','MIXED','Mixed Category')$q$,'23503','Catalog composite FK prevents mixed-tenant category');
select test.expect_error($q$insert into public.products(organization_id,sku,name) values (test.id('org_b'),'FORGED','Foreign')$q$,'42501','Admin cannot write a foreign catalog');
update public.products set price_minor = 15500 where id = '50000000-0000-4000-8000-000000000001';
select test.assert((select revision from public.products where id = '50000000-0000-4000-8000-000000000001') = 2,'Server increments catalog revision');
select test.assert(exists (select 1 from public.audit_logs where entity_id = '50000000-0000-4000-8000-000000000001' and action = 'products.update' and role = 'admin' and user_id = auth.uid()),'Price update writes server-derived actor audit');
select test.expect_error('update public.products set revision = 900','42501','Client cannot forge revision');
select test.expect_error('update public.products set organization_id = test.id(''org_b'')','42501','Client cannot relocate tenant data');

do $$ declare v_n integer; begin
  for v_n in 8..9 loop
    perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-' || lpad(v_n::text,12,'0'),true);
    perform test.assert((select count(*) from public.organizations) = 0,'Pending/disabled ' || v_n || ' denied tenant');
    perform test.assert((select count(*) from public.branches) = 0,'Pending/disabled ' || v_n || ' denied branch');
    perform test.assert((select count(*) from public.products) = 0,'Pending/disabled ' || v_n || ' denied catalog');
    perform test.assert((select count(*) from public.membership_branches) = 0,'Pending/disabled ' || v_n || ' denied assignments');
    perform test.assert((select count(*) from public.organization_memberships) = 1,'Pending/disabled can see own access status only');
  end loop;
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
update public.organization_memberships set status = 'disabled' where id = '30000000-0000-4000-8000-000000000007';
select test.assert(exists (select 1 from public.audit_logs where entity_id = '30000000-0000-4000-8000-000000000007' and action = 'membership.security_changed'),'Membership disable writes audit');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000007',true);
select test.assert((select count(*) from public.products) = 0,'Existing JWT loses access immediately after membership disable');
reset role;
update public.organization_memberships set status = 'disabled' where id = test.id('owner_membership_a');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select test.expect_error($q$select * from public.bootstrap_organization('Shop A','Owner A')$q$,'42501','Bootstrap cannot reactivate disabled owner');
select test.assert((select count(*) from public.organizations) = 0,'Disabled owner denied tenant');
reset role;
update public.organization_memberships set status = 'active' where id = test.id('owner_membership_a');
select set_config('request.jwt.claim.sub','',true);
select test.expect_error('update public.audit_logs set metadata = ''{}''','42501','Audit immutable even for trusted database writer');
select test.expect_error('delete from public.audit_logs','42501','Audit cannot be deleted');
select test.expect_error('truncate public.audit_logs','42501','Audit cannot be truncated');
select test.expect_error('update public.financial_events set payload = ''{}''','42501','Reserved financial ledger immutable for trusted writer');
select test.expect_error('delete from public.financial_events','42501','Reserved financial ledger cannot be deleted');
select test.expect_error('truncate public.financial_events','42501','Reserved financial ledger cannot be truncated');
select test.assert(not has_function_privilege('anon','public.bootstrap_organization(text,text)','execute'),'Bootstrap has no anonymous/PUBLIC execute');
select test.assert(not has_function_privilege('authenticated','private.record_catalog_audit()','execute'),'Client cannot invoke audit definer');
select test.assert(not has_function_privilege('authenticated','private.record_membership_change()','execute'),'Client cannot invoke membership audit definer');
select test.assert(not has_function_privilege('anon','private.record_catalog_audit()','execute'),'Anonymous default function grants were revoked');
select test.assert(not has_function_privilege('service_role','private.record_catalog_audit()','execute'),'Service role cannot attach arbitrary audit triggers');
select test.assert(not has_table_privilege('service_role','public.organizations','delete'),'Default destructive service grants were revoked');
select test.assert((select bool_and(proconfig @> array['search_path=""']) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public','private') and p.prosecdef),'Every definer fixes search_path');

-- Failure after inserting the organization must roll back the WHOLE bootstrap.
create function test.fail_bootstrap_audit() returns trigger language plpgsql as $$
begin
  if new.action = 'organization.bootstrap' and new.user_id = '00000000-0000-4000-8000-000000000012' then
    raise exception 'Deliberate test audit failure' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger test_atomic_bootstrap before insert on public.audit_logs for each row execute function test.fail_bootstrap_audit();
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000012',true);
select test.expect_error($q$select * from public.bootstrap_organization('Atomic Shop','Atomic Owner')$q$,'23514','Bootstrap propagates audit failure');
reset role;
select test.assert(not exists (select 1 from public.organizations where owner_user_id = '00000000-0000-4000-8000-000000000012'),'Failed bootstrap rolls back organization');
select test.assert(not exists (select 1 from public.organization_memberships where user_id = '00000000-0000-4000-8000-000000000012'),'Failed bootstrap rolls back membership');
select test.assert(not exists (select 1 from public.profiles where user_id = '00000000-0000-4000-8000-000000000012'),'Failed bootstrap rolls back profile');
drop trigger test_atomic_bootstrap on public.audit_logs;
drop function test.fail_bootstrap_audit();
commit;
