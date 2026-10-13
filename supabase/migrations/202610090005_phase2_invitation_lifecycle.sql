-- Supabase Auth owns email action credentials. A business invitation ID is
-- never an acceptance credential; verified identity and current SQL authority
-- are required. No application role can dispatch or forge delivery receipts.
begin;
alter table public.employee_invitations drop column token_digest;
alter table public.employee_invitations
  add column request_id uuid not null default gen_random_uuid(),
  add column request_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(request_payload) = 'object'),
  add column employee_id text check (employee_id is null or char_length(btrim(employee_id)) between 1 and 64),
  add column phone text check (phone is null or char_length(phone) <= 40),
  add column delivery_state text not null default 'prepared' check (delivery_state in ('prepared','sending','sent','failed')),
  add column delivery_claim_id uuid,
  add column delivery_claimed_at timestamptz,
  add column delivery_finished_at timestamptz,
  add column delivery_error_code text check (delivery_error_code is null or delivery_error_code = 'auth_delivery_rejected'),
  add column accepted_by uuid references auth.users(id),
  add unique (organization_id,invited_by,request_id),
  add unique (organization_id,id);
create index invitation_pending_email on public.employee_invitations(normalized_email,expires_at)
  where accepted_at is null and revoked_at is null;
create index invitation_rate_window on public.employee_invitations(organization_id,created_at);
create table public.invitation_branches (
  invitation_id uuid not null,organization_id uuid not null,branch_id uuid not null,
  primary key (invitation_id,branch_id),
  foreign key (organization_id,invitation_id) references public.employee_invitations(organization_id,id),
  foreign key (organization_id,branch_id) references public.branches(organization_id,id)
);
insert into public.invitation_branches(invitation_id,organization_id,branch_id)
  select id,organization_id,branch_id from public.employee_invitations where branch_id is not null;
alter table public.invitation_branches enable row level security;

create function private.invitation_branch_ids(p_invitation_id uuid)
returns uuid[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(ib.branch_id order by ib.branch_id),'{}'::uuid[])
  from public.invitation_branches ib where ib.invitation_id = p_invitation_id;
$$;
revoke all on function private.invitation_branch_ids(uuid) from public,anon,authenticated,service_role;

create function private.assert_invitation_authority(p_organization_id uuid,p_actor uuid,p_role text,
  p_all_branches boolean,p_branch_ids uuid[])
returns public.organization_memberships language plpgsql security definer set search_path = '' as $$
declare v_actor public.organization_memberships; v_branch uuid;
begin
  if not exists (select 1 from auth.users u where u.id = p_actor and u.email_confirmed_at is not null) then
    raise exception 'Verified inviter authority is required' using errcode = '42501';
  end if;
  select m.* into v_actor from public.organization_memberships m
    where m.organization_id = p_organization_id and m.user_id = p_actor and m.status = 'active' for share;
  if not found or v_actor.role not in ('owner','admin') or p_role is null or
    p_role not in ('admin','manager','cashier','inventory_staff') or
    (p_role = 'admin' and v_actor.role <> 'owner') or
    (p_all_branches and (p_role <> 'admin' or not v_actor.all_branches or cardinality(p_branch_ids) <> 0)) or
    (not p_all_branches and coalesce(cardinality(p_branch_ids),0) = 0) then
    raise exception 'Invitation role or branch authority is unavailable' using errcode = '42501';
  end if;
  if p_all_branches and not exists (select 1 from public.branches b where b.organization_id = p_organization_id and b.active) then
    raise exception 'An active branch is required' using errcode = '42501';
  end if;
  foreach v_branch in array p_branch_ids loop
    perform 1 from public.branches b where b.id = v_branch and b.organization_id = p_organization_id and b.active for share;
    if not found or not private.user_can_access_branch(p_organization_id,v_branch,p_actor) then
      raise exception 'Invitation is outside current branch authority' using errcode = '42501';
    end if;
  end loop;
  return v_actor;
end;
$$;
revoke all on function private.assert_invitation_authority(uuid,uuid,text,boolean,uuid[]) from public,anon,authenticated,service_role;

create function private.can_read_invitation_record(p_invitation_id uuid,p_organization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_organization_admin(p_organization_id) and exists (
    select 1 from public.employee_invitations i where i.id = p_invitation_id and i.organization_id = p_organization_id
      and ((i.all_branches and exists (select 1 from public.organization_memberships m
          where m.organization_id = p_organization_id and m.user_id = auth.uid() and m.status = 'active'
            and m.role in ('owner','admin') and m.all_branches))
        or (not i.all_branches and exists (select 1 from public.invitation_branches ib where ib.invitation_id = i.id)
          and not exists (select 1 from public.invitation_branches ib where ib.invitation_id = i.id
            and not private.can_access_branch(p_organization_id,ib.branch_id))))
  );
$$;
revoke all on function private.can_read_invitation_record(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function private.can_read_invitation_record(uuid,uuid) to authenticated;
drop policy invitations_read_admin on public.employee_invitations;
create policy invitations_read_admin on public.employee_invitations for select to authenticated
  using (private.can_read_invitation_record(id,organization_id));
create policy invitation_branches_read_admin on public.invitation_branches for select to authenticated
  using (private.can_read_invitation_record(invitation_id,organization_id));
revoke all on public.invitation_branches from public,anon,authenticated,service_role;
grant select on public.invitation_branches to authenticated;
grant select,insert on public.invitation_branches to service_role;
grant select (request_id,employee_id,phone,delivery_state,accepted_by) on public.employee_invitations to authenticated;

create function private.invitation_snapshot(p_invitation_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',i.id,'organization_id',i.organization_id,'normalized_email',i.normalized_email,
    'full_name',i.full_name,'requested_role',i.requested_role,'branch_ids',private.invitation_branch_ids(i.id),
    'all_branches',i.all_branches,'employee_id',i.employee_id,'expires_at',i.expires_at,'delivery_state',i.delivery_state)
  from public.employee_invitations i where i.id = p_invitation_id;
$$;
revoke all on function private.invitation_snapshot(uuid) from public,anon,authenticated,service_role;

create function public.prepare_employee_invitation(p_organization_id uuid,p_request_id uuid,p_email text,
  p_full_name text,p_role text,p_branch_ids uuid[],p_all_branches boolean,p_employee_id text,p_phone text,p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor public.organization_memberships; v_existing public.employee_invitations;
  v_email text; v_branches uuid[]; v_payload jsonb; v_id uuid;
begin
  v_actor := private.require_active_member(p_organization_id);
  if p_request_id is null or p_all_branches is null or p_branch_ids is null or
    cardinality(p_branch_ids) > 100 or array_position(p_branch_ids,null) is not null or
    (p_all_branches and cardinality(p_branch_ids) <> 0) or
    p_email is null or char_length(btrim(p_email)) not between 3 and 254 or
    btrim(p_email) !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or
    p_full_name is null or char_length(btrim(p_full_name)) not between 2 and 120 or
    p_full_name ~ '[[:cntrl:]]' or
    (p_employee_id is not null and char_length(btrim(p_employee_id)) not between 1 and 64) or
    (p_phone is not null and char_length(btrim(p_phone)) not between 1 and 40) or
    p_reason is null or char_length(btrim(p_reason)) not between 2 and 500 or p_reason ~ '[[:cntrl:]]' then
    raise exception 'Invalid invitation input' using errcode = '22023';
  end if;
  select coalesce(array_agg(distinct b order by b),'{}'::uuid[]) into v_branches from unnest(p_branch_ids) b;
  if cardinality(v_branches) <> cardinality(p_branch_ids) then
    raise exception 'Duplicate branches are not permitted' using errcode = '22023';
  end if;
  perform private.assert_invitation_authority(p_organization_id,auth.uid(),p_role,p_all_branches,v_branches);
  v_email := lower(btrim(p_email));
  v_payload := jsonb_build_object('email',v_email,'full_name',btrim(p_full_name),'role',p_role,
    'branch_ids',v_branches,'all_branches',p_all_branches,'employee_id',nullif(btrim(p_employee_id),''),
    'phone',nullif(btrim(p_phone),''),'reason',btrim(p_reason));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_organization_id::text || ':' || auth.uid()::text || ':' || p_request_id::text,0));
  select i.* into v_existing from public.employee_invitations i
    where i.organization_id = p_organization_id and i.invited_by = auth.uid() and i.request_id = p_request_id for update;
  if found then
    if v_existing.request_payload <> v_payload then
      raise exception 'The request ID already has a different payload' using errcode = '23505';
    end if;
    if v_existing.revoked_at is not null or v_existing.accepted_at is not null or v_existing.expires_at <= now() then
      raise exception 'Invitation is no longer pending' using errcode = '23514';
    end if;
    return private.invitation_snapshot(v_existing.id);
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_organization_id::text || ':' || v_email,0));
  if exists (select 1 from public.employee_invitations i where i.organization_id = p_organization_id
      and i.normalized_email = v_email and i.accepted_at is null and i.revoked_at is null and i.expires_at > now()) or
    exists (select 1 from public.organization_memberships m join auth.users u on u.id = m.user_id
      where m.organization_id = p_organization_id and lower(btrim(u.email)) = v_email) then
    raise exception 'Business access or an invitation already exists' using errcode = '23505';
  end if;
  if p_employee_id is not null and exists (select 1 from public.organization_memberships m
      where m.organization_id = p_organization_id and m.employee_id = btrim(p_employee_id)) then
    raise exception 'Employee ID is already in use' using errcode = '23505';
  end if;
  -- Organization-wide serialization prevents concurrent actors/request IDs from
  -- bypassing the rolling limits. Known idempotent requests returned above.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('invitation-rate:' || p_organization_id::text,0));
  if (select count(*) from public.employee_invitations i where i.organization_id = p_organization_id
        and i.created_at > now()-interval '10 minutes') >= 20 or
    (select count(*) from public.employee_invitations i where i.organization_id = p_organization_id
        and i.created_at > now()-interval '24 hours') >= 200 then
    raise exception 'Invitation request limit reached' using errcode = 'NX001';
  end if;
  insert into public.employee_invitations(organization_id,normalized_email,full_name,requested_role,
    invited_by,branch_id,all_branches,request_id,request_payload,employee_id,phone,expires_at)
    values (p_organization_id,v_email,btrim(p_full_name),p_role,auth.uid(),v_branches[1],p_all_branches,
      p_request_id,v_payload,nullif(btrim(p_employee_id),''),nullif(btrim(p_phone),''),now()+interval '7 days') returning id into v_id;
  insert into public.invitation_branches(invitation_id,organization_id,branch_id)
    select v_id,p_organization_id,b from unnest(v_branches) b;
  perform private.append_action_audit(p_organization_id,'invitation.prepared','employee_invitations',v_id,
    v_branches[1],btrim(p_reason),jsonb_build_object('requested_role',p_role,'branch_ids',v_branches,'all_branches',p_all_branches));
  return private.invitation_snapshot(v_id);
end;
$$;
revoke all on function public.prepare_employee_invitation(uuid,uuid,text,text,text,uuid[],boolean,text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.prepare_employee_invitation(uuid,uuid,text,text,text,uuid[],boolean,text,text,text) to authenticated;

create function public.claim_invitation_delivery(p_invitation_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_invitation public.employee_invitations; v_claim uuid;
begin
  select i.* into v_invitation from public.employee_invitations i where i.id = p_invitation_id for update;
  if not found or v_invitation.revoked_at is not null or v_invitation.accepted_at is not null or v_invitation.expires_at <= now() then
    raise exception 'Invitation is no longer pending' using errcode = '23514';
  end if;
  perform private.assert_invitation_authority(v_invitation.organization_id,v_invitation.invited_by,
    v_invitation.requested_role,v_invitation.all_branches,private.invitation_branch_ids(v_invitation.id));
  if v_invitation.delivery_state in ('sending','sent') then return null; end if;
  if v_invitation.delivery_state = 'failed' and
    coalesce(v_invitation.delivery_finished_at,v_invitation.delivery_claimed_at) > now()-interval '10 seconds' then
    raise exception 'Wait before retrying rejected delivery' using errcode = 'NX002';
  end if;
  v_claim := gen_random_uuid();
  update public.employee_invitations set delivery_state = 'sending',delivery_claim_id = v_claim,
    delivery_claimed_at = now(),delivery_finished_at = null,delivery_error_code = null where id = v_invitation.id;
  return private.invitation_snapshot(v_invitation.id) || jsonb_build_object('claim_id',v_claim);
end;
$$;
revoke all on function public.claim_invitation_delivery(uuid) from public,anon,authenticated,service_role;
grant execute on function public.claim_invitation_delivery(uuid) to service_role;

create function public.finish_invitation_delivery(p_invitation_id uuid,p_claim_id uuid,p_succeeded boolean,p_error_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_invitation public.employee_invitations;
begin
  if p_claim_id is null or p_succeeded is null or
    (p_succeeded and p_error_code is not null) or
    (not p_succeeded and p_error_code is distinct from 'auth_delivery_rejected') then
    raise exception 'Invalid delivery receipt' using errcode = '22023';
  end if;
  select i.* into v_invitation from public.employee_invitations i where i.id = p_invitation_id for update;
  if not found or v_invitation.delivery_claim_id is distinct from p_claim_id then
    raise exception 'Delivery claim is unavailable' using errcode = '23514';
  end if;
  if v_invitation.delivery_state <> 'sending' then
    if (p_succeeded and v_invitation.delivery_state = 'sent') or
      (not p_succeeded and v_invitation.delivery_state = 'failed') then return private.invitation_snapshot(v_invitation.id); end if;
    raise exception 'Delivery receipt conflicts with its recorded result' using errcode = '23514';
  end if;
  update public.employee_invitations set delivery_state = case when p_succeeded then 'sent' else 'failed' end,
    delivery_finished_at = now(),delivery_error_code = p_error_code where id = v_invitation.id;
  insert into public.audit_logs(organization_id,role,action,entity,entity_id,branch_id,metadata)
    values (v_invitation.organization_id,'system',case when p_succeeded then 'invitation.email_accepted' else 'invitation.email_rejected' end,
      'employee_invitations',v_invitation.id,v_invitation.branch_id,jsonb_build_object('delivery_state',case when p_succeeded then 'sent' else 'failed' end,
        'branch_ids',private.invitation_branch_ids(v_invitation.id),'all_branches',v_invitation.all_branches));
  return private.invitation_snapshot(v_invitation.id);
end;
$$;
revoke all on function public.finish_invitation_delivery(uuid,uuid,boolean,text) from public,anon,authenticated,service_role;
grant execute on function public.finish_invitation_delivery(uuid,uuid,boolean,text) to service_role;

create function public.list_pending_invitations(p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_email text; v_password text; v_invitation public.employee_invitations; v_result jsonb := '[]'::jsonb;
  v_names jsonb; v_branch_name text;
begin
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception 'Invitation list limit must be between 1 and 100' using errcode = '22023';
  end if;
  select lower(btrim(u.email)),u.encrypted_password into v_email,v_password from auth.users u
    where u.id = auth.uid() and u.email_confirmed_at is not null;
  if not found then raise exception 'A verified account is required' using errcode = '42501'; end if;
  for v_invitation in select i.* from public.employee_invitations i where i.normalized_email = v_email
    and i.accepted_at is null and i.revoked_at is null and i.expires_at > now() and i.delivery_state = 'sent'
    order by i.created_at,i.id limit p_limit loop
    begin
      perform private.assert_invitation_authority(v_invitation.organization_id,v_invitation.invited_by,
        v_invitation.requested_role,v_invitation.all_branches,private.invitation_branch_ids(v_invitation.id));
    exception when insufficient_privilege then continue;
    end;
    select coalesce(jsonb_agg(b.name order by b.id),'[]'::jsonb),coalesce(string_agg(b.name,', ' order by b.id),'')
      into v_names,v_branch_name from public.branches b
      where b.organization_id = v_invitation.organization_id and b.active and
        (v_invitation.all_branches or b.id = any(private.invitation_branch_ids(v_invitation.id)));
    v_result := v_result || jsonb_build_array(jsonb_build_object('id',v_invitation.id,'invitation_id',v_invitation.id,'organization_id',v_invitation.organization_id,
      'business_name',(select o.business_name from public.organizations o where o.id = v_invitation.organization_id),
      'full_name',v_invitation.full_name,'requested_role',v_invitation.requested_role,
      'branch_ids',private.invitation_branch_ids(v_invitation.id),'branch_names',v_names,'branch_name',v_branch_name,
      'employee_id',v_invitation.employee_id,'all_branches',v_invitation.all_branches,
      'requires_password',coalesce(v_password,'') = '', 'expires_at',v_invitation.expires_at));
  end loop;
  return v_result;
end;
$$;
revoke all on function public.list_pending_invitations(integer) from public,anon,authenticated,service_role;
grant execute on function public.list_pending_invitations(integer) to authenticated;

create function public.accept_employee_invitation(p_invitation_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_invitation public.employee_invitations; v_email text; v_password text; v_member uuid; v_branches uuid[];
begin
  select lower(btrim(u.email)),u.encrypted_password into v_email,v_password from auth.users u
    where u.id = auth.uid() and u.email_confirmed_at is not null for share;
  if not found then raise exception 'A verified account is required' using errcode = '42501'; end if;
  if coalesce(v_password,'') = '' then raise exception 'Password setup is required' using errcode = '42501'; end if;
  select i.* into v_invitation from public.employee_invitations i where i.id = p_invitation_id for update;
  if not found or v_invitation.normalized_email is distinct from v_email or v_invitation.delivery_state <> 'sent' or
    v_invitation.accepted_at is not null or v_invitation.revoked_at is not null or v_invitation.expires_at <= now() then
    raise exception 'Invitation is unavailable for this account' using errcode = '42501';
  end if;
  v_branches := private.invitation_branch_ids(v_invitation.id);
  perform private.assert_invitation_authority(v_invitation.organization_id,v_invitation.invited_by,
    v_invitation.requested_role,v_invitation.all_branches,v_branches);
  if exists (select 1 from public.organization_memberships m where m.organization_id = v_invitation.organization_id and m.user_id = auth.uid()) then
    raise exception 'Organization membership already exists' using errcode = '23505';
  end if;
  insert into public.profiles(user_id,full_name,phone) values (auth.uid(),v_invitation.full_name,v_invitation.phone)
    on conflict (user_id) do nothing;
  insert into public.organization_memberships(organization_id,user_id,role,status,all_branches,employee_id)
    values (v_invitation.organization_id,auth.uid(),v_invitation.requested_role,'active',v_invitation.all_branches,v_invitation.employee_id)
    returning id into v_member;
  insert into public.membership_branches(membership_id,organization_id,branch_id)
    select v_member,v_invitation.organization_id,b from unnest(v_branches) b;
  update public.employee_invitations set accepted_at = now(),accepted_by = auth.uid() where id = v_invitation.id;
  perform private.append_action_audit(v_invitation.organization_id,'invitation.accepted','employee_invitations',v_invitation.id,
    v_invitation.branch_id,'Verified account accepted business invitation',jsonb_build_object('membership_id',v_member,
      'requested_role',v_invitation.requested_role,'branch_ids',v_branches,'all_branches',v_invitation.all_branches,'invited_by',v_invitation.invited_by));
  return jsonb_build_object('organization_id',v_invitation.organization_id,'membership_id',v_member,'role',v_invitation.requested_role,
    'branch_ids',v_branches,'all_branches',v_invitation.all_branches);
end;
$$;
revoke all on function public.accept_employee_invitation(uuid) from public,anon,authenticated,service_role;
grant execute on function public.accept_employee_invitation(uuid) to authenticated;

create function public.revoke_employee_invitation(p_organization_id uuid,p_invitation_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_invitation public.employee_invitations;
begin
  perform private.require_active_member(p_organization_id);
  if p_reason is null or char_length(btrim(p_reason)) not between 2 and 500 then
    raise exception 'An action reason is required' using errcode = '22023';
  end if;
  select i.* into v_invitation from public.employee_invitations i where i.id = p_invitation_id and i.organization_id = p_organization_id for update;
  if not found then raise exception 'Invitation is unavailable' using errcode = '42501'; end if;
  perform private.assert_invitation_authority(p_organization_id,auth.uid(),v_invitation.requested_role,
    v_invitation.all_branches,private.invitation_branch_ids(v_invitation.id));
  if v_invitation.accepted_at is not null then raise exception 'Accepted membership needs its own administration operation' using errcode = '23514'; end if;
  if v_invitation.revoked_at is null then
    update public.employee_invitations set revoked_at = now() where id = v_invitation.id;
    perform private.append_action_audit(p_organization_id,'invitation.revoked','employee_invitations',v_invitation.id,
      v_invitation.branch_id,btrim(p_reason),jsonb_build_object('branch_ids',private.invitation_branch_ids(v_invitation.id),
        'all_branches',v_invitation.all_branches));
  end if;
  return jsonb_build_object('invitation_id',v_invitation.id,'revoked',true);
end;
$$;
revoke all on function public.revoke_employee_invitation(uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.revoke_employee_invitation(uuid,uuid,text) to authenticated;
commit;
