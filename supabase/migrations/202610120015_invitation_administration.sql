-- Phase 6D: safe historical invitation administration and durable revocation.
-- Auth owns delivery credentials. Sending means unknown provider outcome and is
-- never reclaimed or presented as confirmed delivery by these administration RPCs.
begin;
alter table public.employee_invitations add column revision bigint not null default 1
 check(revision between 1 and 9007199254740991);
create function private.invitation_admin_revision() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (to_jsonb(new)-'revision') is distinct from (to_jsonb(old)-'revision') then
  if old.revision>=9007199254740991 then raise exception 'Invitation revision limit reached' using errcode='22023';end if;
  new.revision:=old.revision+1;
 else new.revision:=old.revision;end if;
 return new;
end;$$;
create trigger invitation_revision before update on public.employee_invitations for each row execute function private.invitation_admin_revision();
create table private.invitation_admin_actions(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 invitation_id uuid not null,actor_id uuid not null references auth.users(id),request_id uuid not null,
 document jsonb not null check(jsonb_typeof(document)='object'),
 foreign key(organization_id,invitation_id) references public.employee_invitations(organization_id,id));
alter table private.invitation_admin_actions enable row level security;
revoke all on private.invitation_admin_actions from public,anon,authenticated,service_role;
create trigger immutable_history before update or delete on private.invitation_admin_actions for each row execute function private.reject_immutable_mutation();
create trigger immutable_no_truncate before truncate on private.invitation_admin_actions for each statement execute function private.reject_immutable_mutation();

-- Historical assignments are evaluated against the entire stored invitation
-- branch set, including inactive branches. Active branches remain mandatory in
-- the unchanged creation, delivery-claim and acceptance authority helpers.
create function private.invitation_admin_scope(p_org uuid,p_invitation uuid,p_mutation boolean default false)
returns public.organization_memberships language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;i public.employee_invitations;
begin
 m:=private.require_active_member(p_org);
 if m.role not in ('owner','admin') then raise exception 'Invitation administration required' using errcode='42501';end if;
 select * into i from public.employee_invitations where organization_id=p_org and id=p_invitation;
 if not found or (p_mutation and ((i.requested_role='admin' and m.role<>'owner') or
   (not i.all_branches and not exists(select 1 from public.invitation_branches where invitation_id=i.id)))) or
  (not m.all_branches and (i.all_branches or not exists(select 1 from public.invitation_branches where invitation_id=i.id)
   or exists(select 1 from public.invitation_branches b where b.invitation_id=i.id and
    not exists(select 1 from public.membership_branches a where a.organization_id=p_org and a.membership_id=m.id and a.branch_id=b.branch_id)))) then
  raise exception 'Invitation outside current administration scope' using errcode='42501';
 end if;
 return m;
end;$$;
create function private.invitation_admin_can_read(p_org uuid,p_invitation uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
begin perform private.invitation_admin_scope(p_org,p_invitation);return true;
exception when insufficient_privilege then return false;end;$$;
create function private.invitation_admin_retry_input(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare i public.employee_invitations;payload jsonb;
begin
 select * into i from public.employee_invitations where id=p_id;
 if not found or i.invited_by is distinct from auth.uid() or i.accepted_at is not null or i.revoked_at is not null
  or i.expires_at<=now() or i.delivery_state not in ('prepared','failed') then return null;end if;
 begin
  perform private.assert_invitation_authority(i.organization_id,auth.uid(),i.requested_role,i.all_branches,private.invitation_branch_ids(i.id));
 exception when insufficient_privilege then return null;end;
 -- Explicit original business parameters only. Never expose a delivery claim,
 -- private Auth field, arbitrary request_payload key, or reconstructed reason.
 if jsonb_typeof(i.request_payload->'reason') is distinct from 'string' or
  char_length(i.request_payload->>'reason') not between 2 and 500 or (i.request_payload->>'reason')~'[[:cntrl:]]' then return null;end if;
 payload:=jsonb_build_object('email',i.normalized_email,'full_name',i.full_name,'role',i.requested_role,
  'branch_ids',private.invitation_branch_ids(i.id),'all_branches',i.all_branches,'employee_id',i.employee_id,
  'phone',i.phone,'reason',i.request_payload->>'reason');
 if i.request_payload<>payload then return null;end if;
 return payload||jsonb_build_object('organization_id',i.organization_id,'request_id',i.request_id);
end;$$;
create function private.invitation_admin_document(p_id uuid,p_detail boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare i public.employee_invitations;m public.organization_memberships;retry_input jsonb;result jsonb;v_status text;
begin
 select * into i from public.employee_invitations where id=p_id;
 m:=private.invitation_admin_scope(i.organization_id,p_id);
 v_status:=case when i.accepted_at is not null then 'accepted' when i.revoked_at is not null then 'revoked' when i.expires_at<=now() then 'expired' else 'pending' end;
 retry_input:=private.invitation_admin_retry_input(p_id);
 result:=jsonb_build_object('id',i.id,'organization_id',i.organization_id,'revision',i.revision,
  'normalized_email',i.normalized_email,'full_name',i.full_name,'requested_role',i.requested_role,'invited_by',i.invited_by,
  'employee_id',i.employee_id,'phone',i.phone,'all_branches',i.all_branches,'branch_ids',private.invitation_branch_ids(i.id),
  'branches',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'active',b.active) order by b.id)
   from public.invitation_branches a join public.branches b on b.organization_id=a.organization_id and b.id=a.branch_id where a.invitation_id=i.id),'[]'::jsonb),
  'created_at',private.offline_time(i.created_at),'expires_at',private.offline_time(i.expires_at),
  'accepted_at',case when i.accepted_at is not null then private.offline_time(i.accepted_at) end,
  'revoked_at',case when i.revoked_at is not null then private.offline_time(i.revoked_at) end,
  'delivery_state',i.delivery_state,'delivery_claimed_at',case when i.delivery_claimed_at is not null then private.offline_time(i.delivery_claimed_at) end,
  'delivery_finished_at',case when i.delivery_finished_at is not null then private.offline_time(i.delivery_finished_at) end,
  'status',v_status,'can_revoke',v_status='pending' and (i.requested_role<>'admin' or m.role='owner')
   and (i.all_branches or exists(select 1 from public.invitation_branches where invitation_id=i.id)),
  'can_retry_delivery',retry_input is not null);
 if p_detail then result:=result||jsonb_build_object('retry_input',retry_input);end if;
 return result;
end;$$;
create function public.list_managed_employee_invitations(p_organization_id uuid,p_offset integer default 0,p_limit integer default 51,p_search text default null,p_status text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;result jsonb;search text:=nullif(btrim(p_search),'');
begin
 m:=private.require_active_member(p_organization_id);
 if m.role not in ('owner','admin') then raise exception 'Invitation administration required' using errcode='42501';end if;
 perform private.security_page(p_offset,p_limit);
 if char_length(search)>254 or search~'[[:cntrl:]]' or (p_status is not null and p_status not in ('pending','accepted','revoked','expired')) then raise exception 'Invalid invitation filters' using errcode='22023';end if;
 select coalesce(jsonb_agg(private.invitation_admin_document(i.id) order by i.created_at desc,i.id),'[]'::jsonb) into result from
 (select x.* from public.employee_invitations x where x.organization_id=p_organization_id
  and private.invitation_admin_can_read(p_organization_id,x.id)
  and (search is null or position(lower(search) in lower(x.normalized_email))>0 or position(lower(search) in lower(x.full_name))>0 or position(lower(search) in lower(coalesce(x.employee_id,'')))>0)
  and (p_status is null or p_status=case when x.accepted_at is not null then 'accepted' when x.revoked_at is not null then 'revoked' when x.expires_at<=now() then 'expired' else 'pending' end)
  order by x.created_at desc,x.id offset p_offset limit p_limit)i;
 return result;
end;$$;
create function public.get_managed_employee_invitation(p_organization_id uuid,p_invitation_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin perform private.invitation_admin_scope(p_organization_id,p_invitation_id);return private.invitation_admin_document(p_invitation_id,true);end;$$;
create function public.revoke_employee_invitation_action(p_organization_id uuid,p_invitation_id uuid,p_request_id uuid,p_expected_revision bigint,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare i public.employee_invitations;payload jsonb;result_id uuid;result jsonb;v_reason text:=btrim(p_reason);
begin
 -- Current verified membership, MFA, target-role and full historical branch
 -- authority precede even an immutable successful lost-response replay.
 perform private.invitation_admin_scope(p_organization_id,p_invitation_id,true);
 perform private.offline_counter_lock(p_organization_id);
 payload:=jsonb_build_object('invitation_id',p_invitation_id,'expected_revision',p_expected_revision,'reason',v_reason);
 result_id:=private.phase3_request(p_organization_id,p_request_id,'invitation.revoke',payload);
 if result_id is not null then return(select document from private.invitation_admin_actions where id=result_id);end if;
 if p_expected_revision is null or p_expected_revision not between 1 and 9007199254740991 or v_reason is null
  or char_length(v_reason) not between 2 and 500 or v_reason~'[[:cntrl:]]' then raise exception 'Invalid invitation revision or reason' using errcode='22023';end if;
 select * into i from public.employee_invitations where organization_id=p_organization_id and id=p_invitation_id for update;
 if i.accepted_at is not null then raise exception 'Accepted membership needs its own administration operation' using errcode='23514';end if;
 if i.revision<>p_expected_revision then raise exception 'Invitation changed; reload before revoking' using errcode='40001';end if;
 if i.revoked_at is not null or i.expires_at<=now() then raise exception 'Invitation is no longer pending' using errcode='23514';end if;
 update public.employee_invitations set revoked_at=now() where id=i.id;
 result_id:=gen_random_uuid();
 result:=jsonb_build_object('request_id',p_request_id,'organization_id',p_organization_id,'actor_id',auth.uid(),
  'kind','invitation.revoke','invitation',private.invitation_admin_document(i.id,true));
 insert into private.invitation_admin_actions values(result_id,p_organization_id,i.id,auth.uid(),p_request_id,result);
 perform private.phase3_save_request(p_organization_id,p_request_id,'invitation.revoke',payload,result_id);
 perform private.append_action_audit(p_organization_id,'invitation.revoked','employee_invitations',i.id,i.branch_id,v_reason,
  jsonb_build_object('branch_ids',private.invitation_branch_ids(i.id),'all_branches',i.all_branches,'requested_role',i.requested_role,'revision',i.revision+1));
 return result;
end;$$;

-- Invitation audit access uses the immutable event snapshot. A branch becoming
-- inactive does not erase historical authority, and partial assignments never
-- expose the remainder through the event's first branch.
alter function private.can_read_audit(uuid,uuid,text,uuid,text,jsonb) rename to invitation_admin_prior_can_read_audit;
create function private.can_read_audit(p_org uuid,p_branch uuid,p_entity text,p_id uuid,p_action text,p_metadata jsonb) returns boolean language plpgsql stable security definer set search_path='' as $$
declare m public.organization_memberships;v_branch uuid;
begin
 if p_entity='employee_invitations' then
  m:=private.require_active_member(p_org);
  if m.role not in ('owner','admin') then return false;end if;
  if m.all_branches then return true;end if;
  if p_metadata->'all_branches' is distinct from 'false'::jsonb or jsonb_typeof(p_metadata->'branch_ids') is distinct from 'array'
   or jsonb_array_length(p_metadata->'branch_ids')=0 then return false;end if;
  for v_branch in select value::uuid from jsonb_array_elements_text(p_metadata->'branch_ids') loop
   if not exists(select 1 from public.membership_branches where organization_id=p_org and membership_id=m.id and branch_id=v_branch) then return false;end if;
  end loop;return true;
 end if;
 return private.invitation_admin_prior_can_read_audit(p_org,p_branch,p_entity,p_id,p_action,p_metadata);
exception when insufficient_privilege or invalid_text_representation then return false;
end;$$;
drop policy audit_read_authorized on public.audit_logs;
create policy audit_read_authorized on public.audit_logs for select to authenticated using(private.can_read_audit(organization_id,branch_id,entity,entity_id,action,metadata));
do $$declare f record;begin
 for f in select p.oid::regprocedure signature,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where
 (n.nspname='private' and (p.proname like 'invitation_admin_%'))
 or (n.nspname='public' and p.proname in ('list_managed_employee_invitations','get_managed_employee_invitation','revoke_employee_invitation_action')) loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
 if f.nspname='public' then execute format('grant execute on function %s to authenticated',f.signature);end if;
 end loop;
end;$$;
revoke all on function private.can_read_audit(uuid,uuid,text,uuid,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.can_read_audit(uuid,uuid,text,uuid,text,jsonb) to authenticated;
commit;
