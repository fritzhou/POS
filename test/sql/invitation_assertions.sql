\set ON_ERROR_STOP on
-- Disposable database only. This transaction leaves earlier phase fixtures intact.
begin;
insert into auth.users(id,email,email_confirmed_at,encrypted_password)
select ('80000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,'inv' || n || '@example.invalid',
  case when n = 11 then null else now() end,case when n = 6 then null else 'fixture-password-hash' end
from generate_series(1,14) n;
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select set_config('test.inv_org',organization_id::text,true),set_config('test.inv_branch',branch_id::text,true)
  from public.bootstrap_organization('Invitation Test Shop','Invitation Owner');
reset role;
insert into public.branches(id,organization_id,name,code) values
  ('ffffffff-ffff-4fff-bfff-ffffffffffff',test.id('inv_org'),'Second Invitation Branch','INV-SECOND');
insert into public.organization_memberships(id,organization_id,user_id,role,status,all_branches) values
  ('83000000-0000-4000-8000-000000000002',test.id('inv_org'),'80000000-0000-4000-8000-000000000002','admin','active',false);
insert into public.membership_branches(membership_id,organization_id,branch_id) values
  ('83000000-0000-4000-8000-000000000002',test.id('inv_org'),test.id('inv_branch'));
insert into public.profiles(user_id,full_name,phone) values
  ('80000000-0000-4000-8000-000000000003','Existing Profile','Existing Phone');

create function test.prepare_inv(p_n integer,p_role text default 'cashier',p_branches uuid[] default null,p_all boolean default false)
returns uuid language sql as $$
  select (public.prepare_employee_invitation(test.id('inv_org'),
    ('81000000-0000-4000-8000-' || lpad(p_n::text,12,'0'))::uuid,'inv' || p_n || '@example.invalid',
    'Invited Employee ' || p_n,p_role,coalesce(p_branches,array[test.id('inv_branch')]),p_all,
    'INV-' || p_n,null,'Add employee for invitation validation')->>'id')::uuid;
$$;
create function test.send_inv(p_id uuid) returns void language plpgsql as $$
declare v_claim jsonb;
begin
  v_claim := public.claim_invitation_delivery(p_id);
  perform public.finish_invitation_delivery(p_id,(v_claim->>'claim_id')::uuid,true,null);
end;
$$;
grant execute on function test.prepare_inv(integer,text,uuid[],boolean),test.send_inv(uuid) to authenticated,service_role;

set local role anon;
select test.expect_error('select public.list_pending_invitations()','42501','Anonymous cannot discover pending employee invitations');
select test.expect_error('select public.claim_invitation_delivery(gen_random_uuid())','42501','Anonymous cannot claim invitation email');
reset role;
set local role authenticated;
select test.expect_error($q$select test.prepare_inv(3,'owner')$q$,'42501','Owner role cannot be invited');
select test.expect_error($q$select test.prepare_inv(3,'cashier',array[test.id('inv_branch'),test.id('inv_branch')])$q$,'22023','Duplicate invitation branches rejected');
select test.expect_error($q$select test.prepare_inv(3,'cashier','{}'::uuid[])$q$,'42501','Lower-role invitation requires active branches');
select test.expect_error($q$select test.prepare_inv(3,'cashier','{}'::uuid[],true)$q$,'42501','Lower-role cannot gain all-branch authority');
select test.expect_error($q$select test.prepare_inv(3,'admin',array[test.id('inv_branch')],true)$q$,'22023','All-branch invitation requires canonical empty branch array');
select set_config('test.inv_main',test.prepare_inv(3,'cashier',array[test.id('inv_branch'),'ffffffff-ffff-4fff-bfff-ffffffffffff'])::text,true);
select test.assert(test.prepare_inv(3,'cashier',array['ffffffff-ffff-4fff-bfff-ffffffffffff'::uuid,test.id('inv_branch')]) = test.id('inv_main'),
  'Identical request ID with reordered branches returns original invitation');
select test.expect_error($q$select test.prepare_inv(3,'manager',array[test.id('inv_branch'),'ffffffff-ffff-4fff-bfff-ffffffffffff'])$q$,
  '23505','Request ID cannot silently change role or payload');
select test.expect_error($q$select public.prepare_employee_invitation(test.id('inv_org'),gen_random_uuid(),'inv3@example.invalid',
  'Duplicate Invite','cashier',array[test.id('inv_branch')],false,null,null,'Avoid duplicate dispatch')$q$,'23505','Another request ID cannot duplicate an active email invitation');
select test.expect_error('select public.claim_invitation_delivery(test.id(''inv_main''))','42501','Authenticated owner cannot claim delivery');
select test.expect_error('select public.finish_invitation_delivery(test.id(''inv_main''),gen_random_uuid(),true,null)','42501','Authenticated owner cannot forge a sent receipt');
select test.expect_error('select delivery_claim_id from public.employee_invitations','42501','Delivery claims are not client-readable');
select test.expect_error($q$update public.employee_invitations set delivery_state = 'sent'$q$,'42501','Clients cannot write sent state directly');
select test.expect_error($q$select public.accept_employee_invitation(test.id('inv_main'))$q$,'42501','Invitation UUID does not authorize an unrelated owner');

select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000002',true);
select test.expect_error($q$select test.prepare_inv(7,'admin')$q$,'42501','Admin cannot invite another Admin');
select test.expect_error($q$select test.prepare_inv(8,'cashier',array['ffffffff-ffff-4fff-bfff-ffffffffffff'::uuid])$q$,'42501','Admin invitation is limited to assigned branches');
select set_config('test.inv_admin_created',test.prepare_inv(8)::text,true);
select test.assert(not exists(select 1 from public.employee_invitations where id = test.id('inv_main')),'Scoped Admin cannot read multi-branch invitation metadata');
select test.assert((select count(*) from public.invitation_branches where invitation_id = test.id('inv_main')) = 0,'Scoped Admin cannot inspect multi-branch invitation assignments');
select test.assert(not exists(select 1 from public.audit_logs where entity_id = test.id('inv_main')),
  'Scoped Admin cannot inspect multi-branch invitation prepared audit through authorized first branch');
select test.assert(exists(select 1 from public.audit_logs where entity_id = test.id('inv_admin_created')),
  'Scoped Admin can inspect its authorized single-branch invitation audit');
select test.assert(not exists(select 1 from jsonb_array_elements(public.list_audit_logs(p_organization_id=>test.id('inv_org'),p_limit=>101)) a
  where a->>'entity_id' = test.id('inv_main')::text),'Audit RPC cannot expose multi-branch invitation metadata through first branch');
reset role;
select test.assert((select count(*) from public.audit_logs where entity_id = test.id('inv_main') and action = 'invitation.prepared') = 1,
  'Idempotent preparation appends one server-derived audit');
select test.assert((select invited_by from public.employee_invitations where id = test.id('inv_admin_created')) = '80000000-0000-4000-8000-000000000002',
  'Inviter identity comes from JWT subject');

select set_config('request.jwt.claim.sub','',true);
set local role service_role;
select set_config('test.inv_claim',(public.claim_invitation_delivery(test.id('inv_main'))->>'claim_id'),true);
select test.assert(public.claim_invitation_delivery(test.id('inv_main')) is null,'Atomic sending claim cannot be reclaimed or dispatched twice');
select test.expect_error('select public.finish_invitation_delivery(test.id(''inv_main''),gen_random_uuid(),true,null)','23514','Different delivery claim cannot finish another operation');
select test.assert((public.finish_invitation_delivery(test.id('inv_main'),test.id('inv_claim'),false,'auth_delivery_rejected')->>'delivery_state') = 'failed',
  'Known provider rejection records failed');
select test.expect_error('select public.claim_invitation_delivery(test.id(''inv_main''))','NX002','Known rejected email cannot be retried during cooldown');
update public.employee_invitations set delivery_finished_at = now()-interval '11 seconds',delivery_claimed_at = now()-interval '12 seconds'
  where id = test.id('inv_main');
select set_config('test.inv_claim_retry',(public.claim_invitation_delivery(test.id('inv_main'))->>'claim_id'),true);
select test.assert(test.id('inv_claim_retry') <> test.id('inv_claim'),'Definitive failure retry receives a fresh claim');
select test.assert((public.finish_invitation_delivery(test.id('inv_main'),test.id('inv_claim_retry'),true,null)->>'delivery_state') = 'sent',
  'Only current server claim records confirmed Auth acceptance');
select test.assert((public.finish_invitation_delivery(test.id('inv_main'),test.id('inv_claim_retry'),true,null)->>'delivery_state') = 'sent',
  'Replaying identical confirmed delivery receipt is idempotent');
select test.assert(public.claim_invitation_delivery(test.id('inv_main')) is null,'Sent delivery cannot be claimed again');
select test.send_inv(test.id('inv_admin_created'));
reset role;
select test.assert((select count(*) from public.audit_logs where entity_id = test.id('inv_main') and action = 'invitation.email_accepted') = 1,
  'Repeated delivery finish does not duplicate accepted audit');

set local role authenticated;
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000004',true);
select test.assert(public.list_pending_invitations() = '[]'::jsonb,'Verified unrelated email cannot list invitations');
select test.expect_error('select public.accept_employee_invitation(test.id(''inv_main''))','42501','Knowing another invitation UUID cannot accept it');
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000003',true);
select test.assert(jsonb_array_length(public.list_pending_invitations()) = 1,'Verified matching email can list only its sent invitation');
select test.assert((public.list_pending_invitations()->0->>'requires_password') = 'false','Existing password is retained and does not require reset');
select test.assert(jsonb_array_length(public.list_pending_invitations()->0->'branch_names') = 2,'Pending invitation exposes authorized branch names without granting membership');
select test.assert((select count(*) from public.organization_memberships) = 0,'Pending recipient has no organization authority');
select set_config('test.inv_accepted_member',(public.accept_employee_invitation(test.id('inv_main'))->>'membership_id'),true);
select test.assert((select role from public.organization_memberships where id = test.id('inv_accepted_member')) = 'cashier','Acceptance creates exactly server-stored requested role');
select test.assert((select count(*) from public.membership_branches where membership_id = test.id('inv_accepted_member')) = 2,'Acceptance creates all and only invited branch assignments');
select test.assert((select full_name from public.profiles where user_id = auth.uid()) = 'Existing Profile','Acceptance preserves an existing user profile');
select test.assert(public.list_pending_invitations() = '[]'::jsonb,'Accepted invitation leaves pending list');
select test.expect_error('select public.accept_employee_invitation(test.id(''inv_main''))','42501','Acceptance is single use and replay is denied');
reset role;
select test.assert((select count(*) from public.audit_logs where entity_id = test.id('inv_main') and action = 'invitation.accepted'
  and user_id = '80000000-0000-4000-8000-000000000003' and role = 'cashier') = 1,'Acceptance audit derives authenticated employee and assigned role');

-- Prepare distinct future recipients under the Owner, then exercise failures.
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select set_config('test.inv_password',test.prepare_inv(6)::text,true);
select set_config('test.inv_owner_admin',test.prepare_inv(7,'admin','{}'::uuid[],true)::text,true);
select set_config('test.inv_revoked',test.prepare_inv(9)::text,true);
select set_config('test.inv_expired',test.prepare_inv(10)::text,true);
select set_config('test.inv_unverified',test.prepare_inv(11)::text,true);
select set_config('test.inv_email_changed',test.prepare_inv(13)::text,true);
select set_config('test.inv_atomic',test.prepare_inv(14)::text,true);
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role service_role;
select test.send_inv(test.id('inv_password'));
select test.send_inv(test.id('inv_owner_admin'));
select test.send_inv(test.id('inv_revoked'));
select test.send_inv(test.id('inv_expired'));
select test.send_inv(test.id('inv_unverified'));
select test.send_inv(test.id('inv_email_changed'));
select test.send_inv(test.id('inv_atomic'));
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000006',true);
select test.assert((public.list_pending_invitations()->0->>'requires_password') = 'true','Auth-invited account without password sees required setup');
select test.expect_error('select public.accept_employee_invitation(test.id(''inv_password''))','42501','Server rejects acceptance before password setup');
reset role;
update auth.users set encrypted_password = 'fixture-new-password-hash' where id = '80000000-0000-4000-8000-000000000006';
set local role authenticated;
select test.assert((public.accept_employee_invitation(test.id('inv_password'))->>'role') = 'cashier','Password setup unlocks verified invitation acceptance');
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000007',true);
select test.assert((public.accept_employee_invitation(test.id('inv_owner_admin'))->>'all_branches') = 'true','Owner-created Admin receives explicit all-branch permission');
reset role;

-- Revocation, expiry, verification and email changes cannot be bypassed.
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select test.assert((public.revoke_employee_invitation(test.id('inv_org'),test.id('inv_revoked'),'Invitation no longer needed')->>'revoked') = 'true',
  'Authorized Owner can revoke a pending invitation');
select test.assert((public.revoke_employee_invitation(test.id('inv_org'),test.id('inv_revoked'),'Repeated revocation request')->>'revoked') = 'true',
  'Revocation is idempotent');
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000009',true);
select test.expect_error('select public.accept_employee_invitation(test.id(''inv_revoked''))','42501','Revoked invitation cannot create membership');
reset role;
update public.employee_invitations set created_at = now()-interval '2 days',expires_at = now()-interval '1 day' where id = test.id('inv_expired');
update auth.users set email = 'changed13@example.invalid' where id = '80000000-0000-4000-8000-000000000013';
set local role authenticated;
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000010',true);
select test.expect_error('select public.accept_employee_invitation(test.id(''inv_expired''))','42501','Expired invitation cannot create membership');
select test.assert(public.list_pending_invitations() = '[]'::jsonb,'Expired invitation disappears from recipient list');
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000011',true);
select test.expect_error('select public.list_pending_invitations()','42501','Unverified email cannot discover pending invitations');
select test.expect_error('select public.accept_employee_invitation(test.id(''inv_unverified''))','42501','Unverified email cannot accept invitation');
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000013',true);
select test.assert(public.list_pending_invitations() = '[]'::jsonb,'Changing verified email removes old-email invitation visibility');
select test.expect_error('select public.accept_employee_invitation(test.id(''inv_email_changed''))','42501','Current verified email must match stored invitation email');
reset role;

-- Persisted inviter authority is rechecked, not copied from creation time.
update public.organization_memberships set status = 'disabled' where id = '83000000-0000-4000-8000-000000000002';
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000008',true);
set local role authenticated;
select test.assert(public.list_pending_invitations() = '[]'::jsonb,'Disabled inviter removes pending invitation eligibility');
select test.expect_error('select public.accept_employee_invitation(test.id(''inv_admin_created''))','42501','Disabled inviter cannot confer membership later');
reset role;
update public.organization_memberships set status = 'active',role = 'manager' where id = '83000000-0000-4000-8000-000000000002';
set local role authenticated;
select test.expect_error('select public.accept_employee_invitation(test.id(''inv_admin_created''))','42501','Inviter demotion removes invitation authority');
reset role;
update public.organization_memberships set role = 'admin' where id = '83000000-0000-4000-8000-000000000002';
delete from public.membership_branches where membership_id = '83000000-0000-4000-8000-000000000002';
set local role authenticated;
select test.expect_error('select public.accept_employee_invitation(test.id(''inv_admin_created''))','42501','Revoked inviter branch assignment invalidates acceptance');
reset role;
insert into public.membership_branches(membership_id,organization_id,branch_id) values
  ('83000000-0000-4000-8000-000000000002',test.id('inv_org'),test.id('inv_branch'));
update public.branches set active = false where id = test.id('inv_branch');
set local role authenticated;
select test.expect_error('select public.accept_employee_invitation(test.id(''inv_admin_created''))','42501','Deactivated target branch invalidates acceptance');
reset role;
update public.branches set active = true where id = test.id('inv_branch');

-- Any audit failure must roll back profile, membership, assignments and consumption.
create function test.fail_invitation_audit() returns trigger language plpgsql as $$
begin
  if new.action = 'invitation.accepted' and new.user_id = '80000000-0000-4000-8000-000000000014' then
    raise exception 'Deliberate invitation audit fixture failure' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger test_invitation_atomic before insert on public.audit_logs for each row execute function test.fail_invitation_audit();
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000014',true);
set local role authenticated;
select test.expect_error('select public.accept_employee_invitation(test.id(''inv_atomic''))','23514','Invitation acceptance propagates immutable audit failure');
reset role;
select test.assert(not exists(select 1 from public.organization_memberships where user_id = '80000000-0000-4000-8000-000000000014'),'Audit failure rolls back membership');
select test.assert(not exists(select 1 from public.profiles where user_id = '80000000-0000-4000-8000-000000000014'),'Audit failure rolls back newly created profile');
select test.assert((select accepted_at is null from public.employee_invitations where id = test.id('inv_atomic')),'Audit failure leaves invitation unconsumed');
drop trigger test_invitation_atomic on public.audit_logs;
drop function test.fail_invitation_audit();

-- New request limits coordinate the entire organization, not one actor/JWT.
select set_config('request.jwt.claim.sub','80000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select set_config('test.inv_rate_retry',test.prepare_inv(100)::text,true);
do $$ declare v_count integer; v_n integer; begin
  select count(*) into v_count from public.employee_invitations i where i.organization_id = test.id('inv_org')
    and i.created_at > now()-interval '10 minutes';
  for v_n in 101..(100+20-v_count) loop perform test.prepare_inv(v_n); end loop;
end $$;
select test.assert(test.prepare_inv(100) = test.id('inv_rate_retry'),'Known idempotent invitation still returns at burst request limit');
select test.expect_error('select test.prepare_inv(400)','NX001','Twenty new invitations per organization per ten minutes limit further requests');
reset role;
update public.employee_invitations set created_at = now()-interval '1 hour'
  where organization_id = test.id('inv_org') and created_at > now()-interval '10 minutes';
insert into public.employee_invitations(organization_id,normalized_email,full_name,requested_role,invited_by,branch_id,created_at,expires_at)
select test.id('inv_org'),'daily-rate-' || n || '@example.invalid','Daily Rate Fixture','cashier',
  '80000000-0000-4000-8000-000000000001',test.id('inv_branch'),now()-interval '1 hour',now()+interval '1 day'
from generate_series(1,200-(select count(*)::integer from public.employee_invitations i
  where i.organization_id = test.id('inv_org') and i.created_at > now()-interval '24 hours')) n;
set local role authenticated;
select test.assert(test.prepare_inv(100) = test.id('inv_rate_retry'),'Known idempotent invitation still returns at daily request limit');
select test.expect_error('select test.prepare_inv(500)','NX001','Two hundred invitations per rolling organization day limit requests even outside burst window');
select test.expect_error('select public.list_pending_invitations(101)','22023','Pending invitation list enforces maximum result bound');
reset role;

select test.assert(not has_function_privilege('authenticated','private.assert_invitation_authority(uuid,uuid,text,boolean,uuid[])','execute'),
  'Clients cannot invoke explicit-identity authority helper');
select test.assert(not has_function_privilege('service_role','public.prepare_employee_invitation(uuid,uuid,text,text,text,uuid[],boolean,text,text,text)','execute'),
  'Service credential cannot substitute for verified inviter prepare context');
select test.assert(not has_function_privilege('service_role','public.accept_employee_invitation(uuid)','execute'),'Service credential cannot accept on behalf of another identity');
select test.assert(not has_function_privilege('anon','private.invitation_snapshot(uuid)','execute'),'Anonymous cannot inspect invitation snapshots');
select test.assert((select bool_and(proconfig @> array['search_path=""']) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public','private') and p.prosecdef),'Invitation definer functions all fix search_path');
rollback;
