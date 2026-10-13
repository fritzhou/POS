\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,email_confirmed_at,encrypted_password)
select ('c8000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'managed-inv-'||n||'@example.invalid',
 case when n=8 then null else now() end,'fixture-password-present' from generate_series(1,14)n;
set local role authenticated;
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000001';
select set_config('test.d6_org',organization_id::text,true),set_config('test.d6_branch',branch_id::text,true)
 from public.bootstrap_organization('Managed Invitation Shop','Managed Invitation Owner');
reset role;
insert into public.branches(id,organization_id,name,code) values('c8300000-0000-4000-8000-000000000001',test.id('d6_org'),'Invitation Archive','D6-ARCHIVE');
insert into public.organization_memberships(id,organization_id,user_id,role,status,all_branches) values
 ('c8200000-0000-4000-8000-000000000002',test.id('d6_org'),'c8000000-0000-4000-8000-000000000002','admin','active',false),
 ('c8200000-0000-4000-8000-000000000003',test.id('d6_org'),'c8000000-0000-4000-8000-000000000003','admin','active',false),
 ('c8200000-0000-4000-8000-000000000004',test.id('d6_org'),'c8000000-0000-4000-8000-000000000004','manager','active',false),
 ('c8200000-0000-4000-8000-000000000008',test.id('d6_org'),'c8000000-0000-4000-8000-000000000008','admin','active',true);
insert into public.membership_branches(organization_id,membership_id,branch_id) values
 (test.id('d6_org'),'c8200000-0000-4000-8000-000000000002',test.id('d6_branch')),
 (test.id('d6_org'),'c8200000-0000-4000-8000-000000000002','c8300000-0000-4000-8000-000000000001'),
 (test.id('d6_org'),'c8200000-0000-4000-8000-000000000003',test.id('d6_branch')),
 (test.id('d6_org'),'c8200000-0000-4000-8000-000000000004',test.id('d6_branch'));
create function test.d6_prepare(p_n integer,p_branches uuid[] default null,p_role text default 'cashier',p_all boolean default false)
returns uuid language sql as $$
 select (public.prepare_employee_invitation(test.id('d6_org'),('c8100000-0000-4000-8000-'||lpad(p_n::text,12,'0'))::uuid,
  'managed-inv-'||p_n||'@example.invalid','Managed Employee '||p_n,p_role,
  coalesce(p_branches,array[test.id('d6_branch')]),p_all,'D6-'||p_n,'+639001234567','Original reason for employee '||p_n)->>'id')::uuid;
$$;
grant execute on function test.d6_prepare(integer,uuid[],text,boolean) to authenticated;
set local role authenticated;
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000001';
select set_config('test.d6_main',test.d6_prepare(10,array[test.id('d6_branch'),'c8300000-0000-4000-8000-000000000001'])::text,true);
select set_config('test.d6_admin',test.d6_prepare(9,'{}'::uuid[],'admin',true)::text,true);
select set_config('test.d6_accept',test.d6_prepare(5)::text,true);
select set_config('test.d6_sending',test.d6_prepare(11)::text,true);
select set_config('test.d6_failed',test.d6_prepare(12)::text,true);
select set_config('test.d6_expired',test.d6_prepare(13)::text,true);
select set_config('test.d6_atomic',test.d6_prepare(14)::text,true);
select set_config('test.d6_original_detail',public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_main'))::text,true);
select test.assert(current_setting('test.d6_original_detail')::jsonb->>'revision'='1','New invitation administration exposes revision one');
select test.assert(current_setting('test.d6_original_detail')::jsonb->>'status'='pending','Prepared invitation is pending business access');
select test.assert(current_setting('test.d6_original_detail')::jsonb->>'can_retry_delivery'='true','Original author can retry a prepared original request');
select test.assert(current_setting('test.d6_original_detail')::jsonb->'retry_input'->>'request_id'='c8100000-0000-4000-8000-000000000010','Safe retry retains original create UUID');
select test.assert(current_setting('test.d6_original_detail')::jsonb->'retry_input'->>'reason'='Original reason for employee 10' and current_setting('test.d6_original_detail')::jsonb->'retry_input'->>'phone'='+639001234567','Safe retry retains original reason and phone exactly');
select test.assert(not (current_setting('test.d6_original_detail')::jsonb ?|array['delivery_claim_id','accepted_by','request_payload','token_digest','encrypted_password']),'Managed document excludes private delivery and Auth fields');
select test.assert(current_setting('test.d6_original_detail')::jsonb->>'invited_by'='c8000000-0000-4000-8000-000000000001','Safe original-author identifier binds exact retry to its creator');
select test.assert(jsonb_array_length(public.list_managed_employee_invitations(test.id('d6_org'),0,2))=2,'Invitation history is bounded and paginated');
select test.assert(jsonb_array_length(public.list_managed_employee_invitations(test.id('d6_org'),0,51,'Employee 10','pending'))=1,'Literal invitation search and status select authorized original records');
select test.assert(public.list_managed_employee_invitations(test.id('d6_org'),0,51,'%')='[]'::jsonb,'Invitation search treats percent as a literal character');
select test.assert(not (public.list_managed_employee_invitations(test.id('d6_org'))->0 ? 'retry_input'),'Invitation list omits original creation payload');
select test.expect_error($q$select public.list_managed_employee_invitations(test.id('d6_org'),-1,51)$q$,'22023','Invitation pagination rejects negative offset');
select test.expect_error($q$select public.list_managed_employee_invitations(test.id('d6_org'),0,101)$q$,'22023','Invitation pagination rejects oversized page');
select test.expect_error($q$select public.list_managed_employee_invitations(test.id('d6_org'),0,51,null,'sent')$q$,'22023','Delivery state cannot masquerade as business acceptance status');
select test.expect_error($q$select public.get_managed_employee_invitation(gen_random_uuid(),test.id('d6_main'))$q$,'42501','Foreign organization invitation lookup fails closed');
select test.expect_error($q$select public.get_managed_employee_invitation(test.id('d6_org'),gen_random_uuid())$q$,'42501','Unknown invitation lookup reveals no metadata');
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000002';
select test.assert(public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_main'))->>'can_retry_delivery'='false','Another authorized admin cannot retry another author request');
select test.assert(public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_main'))->'retry_input'='null'::jsonb,'Another author receives no exact original creation reason');
select test.expect_error($q$select public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_admin'))$q$,'42501','Scoped Admin cannot inspect all-branch invitation');
select set_config('test.d6_admin_owned',test.d6_prepare(6)::text,true);
select test.assert(public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_admin_owned'))->>'can_retry_delivery'='true','Scoped original author retries within its current creation authority');
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000003';
select test.expect_error($q$select public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_main'))$q$,'42501','Partial branch assignment cannot reveal multi-branch invitation');
select test.assert(not exists(select 1 from jsonb_array_elements(public.list_managed_employee_invitations(test.id('d6_org')))i where i->>'id'=test.id('d6_main')::text),'Partial admin list hides the entire multi-branch document');
select test.expect_error($q$select public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_main'),gen_random_uuid(),1,'Revoke outside full scope')$q$,'42501','Partial branch assignment cannot revoke multi-branch invitation');
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000004';
select test.expect_error($q$select public.list_managed_employee_invitations(test.id('d6_org'))$q$,'42501','Manager cannot inspect invitation administration');
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000008';
select test.expect_error($q$select public.list_managed_employee_invitations(test.id('d6_org'))$q$,'42501','Unverified Admin cannot inspect invitation administration');
reset role;
set local role service_role;
select set_config('test.d6_send_claim',public.claim_invitation_delivery(test.id('d6_sending'))->>'claim_id',true);
select test.assert(public.claim_invitation_delivery(test.id('d6_sending')) is null,'Unknown sending is never reclaimed for another email');
select set_config('test.d6_fail_claim',public.claim_invitation_delivery(test.id('d6_failed'))->>'claim_id',true);
select public.finish_invitation_delivery(test.id('d6_failed'),test.id('d6_fail_claim'),false,'auth_delivery_rejected');
select set_config('test.d6_accept_claim',public.claim_invitation_delivery(test.id('d6_accept'))->>'claim_id',true);
select public.finish_invitation_delivery(test.id('d6_accept'),test.id('d6_accept_claim'),true,null);
reset role;
set local role authenticated;
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000001';
select test.assert(public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_sending'))->>'delivery_state'='sending' and public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_sending'))->>'can_retry_delivery'='false','Unknown sending stays pending without resend capability');
select test.assert(public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_sending'))->>'revision'='2','Server delivery claim increments invitation revision');
select set_config('test.d6_unknown_detail',public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_sending'))::text,true);
select test.assert(public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_failed'))->>'delivery_state'='failed' and public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_failed'))->>'can_retry_delivery'='true','Authoritative rejection exposes only original-action retry');
select test.assert(public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_accept'))->>'status'='pending' and public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_accept'))->>'can_retry_delivery'='false','Confirmed email remains pending business acceptance and cannot resend');
select test.expect_error($q$select public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_sending'),gen_random_uuid(),1,'Revoke stale delivery view')$q$,'40001','Delivery state races are guarded by invitation revision');
select test.expect_error($q$select public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_main'),gen_random_uuid(),9007199254740992,'Unsafe revision')$q$,'22023','Invitation revision respects exact transport bounds');
select test.expect_error($q$select public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_main'),gen_random_uuid(),1,E'Bad\nreason')$q$,'22023','Invitation revocation reason rejects control characters');
select set_config('test.d6_send_revoke',public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_sending'),'c8400000-0000-4000-8000-000000000001',2,'Cancel unknown invitation access')::text,true);
select test.assert(current_setting('test.d6_send_revoke')::jsonb->'invitation'->>'status'='revoked','Revocation cancels business acceptance even during unknown mail');
reset role;
set local role service_role;
select public.finish_invitation_delivery(test.id('d6_sending'),test.id('d6_send_claim'),true,null);
reset role;
set local role authenticated;
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000001';
select test.assert(public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_sending'))->>'status'='revoked' and public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_sending'))->>'delivery_state'='sent','Later provider finish preserves delivery evidence and terminal revocation');
select test.assert(public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_sending'),'c8400000-0000-4000-8000-000000000001',2,'Cancel unknown invitation access')=current_setting('test.d6_send_revoke')::jsonb,'Lost revocation response replays the exact original snapshot after delivery changes');
select test.expect_error($q$select public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_sending'),'c8400000-0000-4000-8000-000000000001',2,'Changed reason after revocation')$q$,'23505','Revocation UUID cannot change original reason');
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000011';
select test.expect_error($q$select public.accept_employee_invitation(test.id('d6_sending'))$q$,'42501','Mail arriving after revocation cannot confer membership');
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000005';
select public.accept_employee_invitation(test.id('d6_accept'));
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000001';
select test.assert(public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_accept'))->>'status'='accepted' and public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_accept'))->>'revision'='4','Old acceptance remains authoritative and updates revision');
select test.expect_error($q$select public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_accept'),gen_random_uuid(),4,'Cannot revoke accepted access')$q$,'23514','Accepted membership is not silently revoked through invitation history');
reset role;
update public.employee_invitations set created_at=now()-interval '8 days',expires_at=now()-interval '1 day' where id=test.id('d6_expired');
insert into public.employee_invitations(organization_id,normalized_email,full_name,requested_role,invited_by,branch_id,expires_at)
 values(test.id('d6_org'),'legacy-empty@example.invalid','Legacy Empty Scope','cashier','c8000000-0000-4000-8000-000000000001',test.id('d6_branch'),now()+interval '1 day');
select set_config('test.d6_legacy',(select id::text from public.employee_invitations where normalized_email='legacy-empty@example.invalid'),true);
update public.branches set active=false where id='c8300000-0000-4000-8000-000000000001';
set local role authenticated;
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000001';
select test.assert(public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_expired'))->>'status'='expired' and public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_expired'))->>'can_retry_delivery'='false','Expired invitation is historical without resend capability');
select test.assert(public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_legacy'))->>'can_revoke'='false' and public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_legacy'))->>'can_retry_delivery'='false','Incomplete legacy branch scope is visible but read only for Owner');
select test.expect_error($q$select public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_legacy'),gen_random_uuid(),1,'No fabricated legacy scope')$q$,'42501','Missing legacy branch snapshot cannot authorize revocation');
select test.assert(public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_main'))->>'can_retry_delivery'='false','Inactive original target branch removes creation retry authority');
reset role;
select set_config('test.d6_failed_payload',(select request_payload::text from public.employee_invitations where id=test.id('d6_failed')),true);
update public.employee_invitations set request_payload=request_payload||'{"forbidden_delivery_credential":"private-fixture-value"}'::jsonb where id=test.id('d6_failed');
set local role authenticated;
select test.assert(public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_failed'))->'retry_input'='null'::jsonb and public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_failed'))->>'can_retry_delivery'='false','Unexpected original payload fields disable canonical delivery retry');
select test.assert(position('private-fixture-value' in public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_failed'))::text)=0,'Arbitrary private request fields never escape managed detail');
reset role;
update public.employee_invitations set request_payload=current_setting('test.d6_failed_payload')::jsonb where id=test.id('d6_failed');
set local role authenticated;
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000002';
select test.assert(jsonb_array_length(public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_main'))->'branches')=2,'Full raw assignments retain inactive original branch history');
select test.assert(exists(select 1 from public.audit_logs where entity_id=test.id('d6_main') and action='invitation.prepared'),'Inactive branch still retains full-scope invitation audit visibility');
select set_config('test.d6_main_revoke',public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_main'),'c8400000-0000-4000-8000-000000000002',1,'Cancel original inactive-branch invitation')::text,true);
select test.assert(current_setting('test.d6_main_revoke')::jsonb->'invitation'->>'revision'='2','Raw historical authority can revoke before inaccessible branch acceptance');
select test.assert(public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_main'),'c8400000-0000-4000-8000-000000000002',1,'Cancel original inactive-branch invitation')=current_setting('test.d6_main_revoke')::jsonb,'Inactive original-branch revocation replays exact durable action');
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000003';
select test.assert(not exists(select 1 from public.audit_logs where entity_id=test.id('d6_main')),'Partial assignments do not expose inactive multi-branch audit');
reset role;
delete from public.membership_branches where membership_id='c8200000-0000-4000-8000-000000000002' and branch_id='c8300000-0000-4000-8000-000000000001';
set local role authenticated;
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000002';
select test.expect_error($q$select public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_main'),'c8400000-0000-4000-8000-000000000002',1,'Cancel original inactive-branch invitation')$q$,'42501','Original successful action replay rechecks current full branch assignments');
reset role;
insert into public.membership_branches(organization_id,membership_id,branch_id) values(test.id('d6_org'),'c8200000-0000-4000-8000-000000000002','c8300000-0000-4000-8000-000000000001');
update public.organization_memberships set all_branches=true where id='c8200000-0000-4000-8000-000000000002';
set local role authenticated;
select test.assert(public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_admin'))->>'can_revoke'='false','All-branch Admin may view Admin-target history without superior revocation');
select test.expect_error($q$select public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_admin'),gen_random_uuid(),1,'Admin cannot revoke Admin')$q$,'42501','All-branch scope never overrides target role hierarchy');
reset role;
update public.organization_memberships set role='manager',all_branches=false where id='c8200000-0000-4000-8000-000000000002';
set local role authenticated;
select test.expect_error($q$select public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_main'),'c8400000-0000-4000-8000-000000000002',1,'Cancel original inactive-branch invitation')$q$,'42501','Demoted original actor cannot replay previously accepted revocation');
reset role;
update public.organization_memberships set role='admin',all_branches=true,status='disabled' where id='c8200000-0000-4000-8000-000000000002';
set local role authenticated;
select test.expect_error($q$select public.list_managed_employee_invitations(test.id('d6_org'))$q$,'42501','Disabled Admin cannot inspect retained invitation history');
reset role;
update public.organization_memberships set status='active' where id='c8200000-0000-4000-8000-000000000002';
create function test.d6_fail_audit() returns trigger language plpgsql as $$
begin if new.entity_id=test.id('d6_atomic') and new.action='invitation.revoked' then raise exception 'Disposable deliberate invitation audit failure' using errcode='23514';end if;return new;end;$$;
create trigger d6_test_audit before insert on public.audit_logs for each row execute function test.d6_fail_audit();
set local role authenticated;
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000001';
select test.expect_error($q$select public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_atomic'),'c8400000-0000-4000-8000-000000000003',1,'Atomic invitation cancellation')$q$,'23514','Revocation audit failure rolls back the entire business action');
reset role;
select test.assert((select revoked_at is null and revision=1 from public.employee_invitations where id=test.id('d6_atomic')),'Failed audit does not consume invitation or revision');
select test.assert(not exists(select 1 from private.operation_requests where request_id='c8400000-0000-4000-8000-000000000003'),'Failed audit does not retain a false request receipt');
drop trigger d6_test_audit on public.audit_logs;
drop function test.d6_fail_audit();
set local role authenticated;
set local "request.jwt.claim.sub"='c8000000-0000-4000-8000-000000000001';
select set_config('test.d6_atomic_revoke',public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_atomic'),'c8400000-0000-4000-8000-000000000003',1,'Atomic invitation cancellation')::text,true);
select 'D6_INVITATION_FIXTURE='||jsonb_build_object('organization_id',test.id('d6_org'),'actor_id','c8000000-0000-4000-8000-000000000001','branch_id',test.id('d6_branch'),
 'pending_detail',current_setting('test.d6_original_detail')::jsonb,'sending_detail',current_setting('test.d6_unknown_detail')::jsonb,
 'revoked_delivery_detail',public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_sending')),
 'failed_detail',public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_failed')),'accepted_detail',public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_accept')),
 'expired_detail',public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_expired')),'revoke_action',current_setting('test.d6_atomic_revoke')::jsonb,
 'inactive_revoke_action',current_setting('test.d6_main_revoke')::jsonb,'list',public.list_managed_employee_invitations(test.id('d6_org')))::text;
set local "request.jwt.claims"='{"sub":"c8000000-0000-4000-8000-000000000001","aal":"aal2"}';
select public.update_security_policy(test.id('d6_org'),gen_random_uuid(),1,10,true,'Require invitation management assurance');
set local "request.jwt.claims"='{"sub":"c8000000-0000-4000-8000-000000000001","aal":"aal1"}';
select test.expect_error($q$select public.list_managed_employee_invitations(test.id('d6_org'))$q$,'42501','Invitation history independently enforces current configured MFA');
select test.expect_error($q$select public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_failed'))$q$,'42501','Original delivery retry input requires current MFA');
select test.expect_error($q$select public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_atomic'),'c8400000-0000-4000-8000-000000000003',1,'Atomic invitation cancellation')$q$,'42501','Successful revocation replay cannot bypass current configured MFA');
set local "request.jwt.claims"='{"sub":"c8000000-0000-4000-8000-000000000001","aal":"aal2"}';
select test.assert(public.revoke_employee_invitation_action(test.id('d6_org'),test.id('d6_atomic'),'c8400000-0000-4000-8000-000000000003',1,'Atomic invitation cancellation')=current_setting('test.d6_atomic_revoke')::jsonb,'Current verified AAL2 can recover exact original revocation');
reset role;
select test.assert((select count(*) from public.audit_logs where organization_id=test.id('d6_org') and action='invitation.revoked')=3,'Stable revocation retries append exactly one audit per accepted intent');
select test.assert(not has_table_privilege('authenticated','private.invitation_admin_actions','SELECT') and not has_table_privilege('service_role','private.invitation_admin_actions','INSERT'),'Private immutable actions are not directly readable or writable');
select test.assert(not has_function_privilege('authenticated','private.invitation_admin_retry_input(uuid)','EXECUTE'),'Original retry payload helper is not a public escape hatch');
set local role anon;
select test.expect_error($q$select public.list_managed_employee_invitations(test.id('d6_org'))$q$,'42501','Anonymous cannot enumerate invitation administration');
reset role;
set local role service_role;
select test.expect_error($q$select public.get_managed_employee_invitation(test.id('d6_org'),test.id('d6_main'))$q$,'42501','Service credential cannot substitute for verified administrator history');
rollback;
