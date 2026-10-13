-- PINs supplement an existing online authenticated account; they never create
-- sessions, elevate roles, or authorize a checkout/refund. Server hashing only.
begin;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
-- Respect an existing pgcrypto installation's schema instead of moving it.
do $migration$ declare n text;begin
 select ns.nspname into n from pg_extension e join pg_namespace ns on ns.oid=e.extnamespace where e.extname='pgcrypto';
 execute format('create function private.employee_pin_crypt(text,text) returns text language sql immutable strict security definer set search_path='''' as %L',format('select %I.crypt($1,$2)',n));
 execute format('create function private.employee_pin_salt() returns text language sql volatile security definer set search_path='''' as %L',format('select %I.gen_salt(''bf'',12)',n));
end; $migration$;

create table private.employee_pin_secrets (
 membership_id uuid primary key references public.organization_memberships(id),
 organization_id uuid not null references public.organizations(id),
 user_id uuid not null references auth.users(id),
 pin_hash text,
 reset_required boolean not null default true,
 revision bigint not null default 1 check(revision>0),
 failed_attempts integer not null default 0 check(failed_attempts between 0 and 5),
 locked_until timestamptz,
 changed_at timestamptz,
 unique(organization_id,user_id),
 check((pin_hash is null and reset_required) or (pin_hash is not null and not reset_required))
);
create table private.employee_pin_operations (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 membership_id uuid not null references public.organization_memberships(id),
 actor_id uuid not null references auth.users(id),
 request_id uuid not null,
 action text not null check(action in ('set','verify')),
 expected_revision bigint not null check(expected_revision>0),
 actor_claims jsonb not null,
 expires_at timestamptz not null default clock_timestamp()+interval '2 minutes',
 result jsonb,
 unique(organization_id,actor_id,request_id)
);
create table private.employee_pin_reset_requests (
 organization_id uuid not null references public.organizations(id),
 actor_id uuid not null references auth.users(id),
 request_id uuid not null,
 target_membership_id uuid not null references public.organization_memberships(id),
 expected_revision bigint not null,
 reason text not null,
 result jsonb not null,
 primary key(organization_id,actor_id,request_id)
);
alter table private.employee_pin_secrets enable row level security;
alter table private.employee_pin_operations enable row level security;
alter table private.employee_pin_reset_requests enable row level security;
revoke all on private.employee_pin_secrets,private.employee_pin_operations,private.employee_pin_reset_requests from public,anon,authenticated,service_role;

create function private.employee_pin_actor(p_organization_id uuid,p_actor_id uuid)
returns public.organization_memberships language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;
begin
 select * into m from public.organization_memberships where organization_id=p_organization_id
  and user_id=p_actor_id and status='active' for share;
 if not found or not exists(select 1 from auth.users u where u.id=p_actor_id and u.email_confirmed_at is not null)
  or not ((m.role in ('owner','admin') and m.all_branches) or exists(
   select 1 from public.membership_branches mb join public.branches b on b.id=mb.branch_id
    and b.organization_id=mb.organization_id where mb.membership_id=m.id and b.active)) then
  raise exception 'PIN access unavailable' using errcode='42501';
 end if;
 return m;
end;
$$;
create function private.employee_pin_can_reset(p_organization_id uuid,p_target_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare a public.organization_memberships;t public.organization_memberships;
begin
 a:=private.require_active_member(p_organization_id);
 select * into t from public.organization_memberships where organization_id=p_organization_id and id=p_target_id and status='active' for share;
 if not found then return false; end if;
 if a.role='owner' then return true; end if;
 return ((a.role='admin' and t.role in ('manager','cashier','inventory_staff'))
  or (a.role='manager' and t.role in ('cashier','inventory_staff')))
  and not t.all_branches and exists(select 1 from public.membership_branches where membership_id=t.id)
  and not exists(select 1 from public.membership_branches mb where mb.membership_id=t.id
    and not private.can_access_branch(p_organization_id,mb.branch_id));
end;
$$;
create function private.employee_pin_status(p_membership_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('membership_id',p_membership_id,'configured',coalesce(s.pin_hash is not null,false),
  'reset_required',coalesce(s.reset_required,true),'revision',coalesce(s.revision,1),
  'locked_until',s.locked_until,'changed_at',s.changed_at)
 from (select p_membership_id id) x left join private.employee_pin_secrets s on s.membership_id=x.id;
$$;
create function public.get_employee_pin_status(p_organization_id uuid,p_membership_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;target_id uuid;
begin
 m:=private.require_active_member_without_mfa(p_organization_id);
 target_id:=coalesce(p_membership_id,m.id);
 if target_id<>m.id then
  perform private.security_assert_privileged_mfa(p_organization_id,m.user_id);
  if not private.employee_pin_can_reset(p_organization_id,target_id) then
   raise exception 'PIN status unavailable' using errcode='42501';
  end if;
 end if;
 return private.employee_pin_status(target_id);
end;
$$;
create function public.list_employee_pin_reset_targets(p_organization_id uuid,p_offset integer default 0,p_limit integer default 51)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;v_result jsonb;
begin
 m:=private.require_active_member(p_organization_id);
 if m.role not in ('owner','admin','manager') then raise exception 'PIN management unavailable' using errcode='42501'; end if;
 if p_offset is null or p_limit is null or p_offset not between 0 and 100000 or p_limit not between 1 and 101 then
  raise exception 'Invalid PIN target page' using errcode='22023';
 end if;
 select coalesce(jsonb_agg(v),'[]'::jsonb) into v_result from(
  select t.id membership_id,coalesce(p.full_name,'Employee') full_name,t.role,
   private.employee_pin_status(t.id) status
  from public.organization_memberships t left join public.profiles p on p.user_id=t.user_id
  where t.organization_id=p_organization_id and t.status='active' and private.employee_pin_can_reset(p_organization_id,t.id)
  order by coalesce(p.full_name,'Employee'),t.id offset p_offset limit p_limit
 )v;
 return v_result;
end;
$$;
create function public.prepare_employee_pin_operation(p_organization_id uuid,p_request_id uuid,p_action text,p_expected_revision bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;s private.employee_pin_secrets;o private.employee_pin_operations;c jsonb;
begin
 m:=private.require_active_member(p_organization_id);
 if p_request_id is null or p_action is null or p_action not in ('set','verify') or p_expected_revision is null or p_expected_revision<1 then
  raise exception 'Invalid PIN operation' using errcode='22023';
 end if;
 c:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb);
 if exists(select 1 from jsonb_array_elements(coalesce(c->'amr','[]'::jsonb)) a where a->>'method'='recovery') then
  raise exception 'PIN access unavailable' using errcode='42501';
 end if;
 c:=jsonb_build_object('sub',m.user_id,'aal',c->'aal','session_id',c->'session_id','amr',c->'amr','exp',c->'exp');
 insert into private.employee_pin_secrets(membership_id,organization_id,user_id) values(m.id,m.organization_id,m.user_id) on conflict do nothing;
 select * into s from private.employee_pin_secrets where membership_id=m.id for update;
 select * into o from private.employee_pin_operations where organization_id=p_organization_id and actor_id=m.user_id and request_id=p_request_id for update;
 if found then
  if o.action<>p_action or o.expected_revision<>p_expected_revision then raise exception 'PIN request changed' using errcode='23505'; end if;
  if o.result is not null then
   update private.employee_pin_operations set actor_claims=c where id=o.id;
   return jsonb_build_object('id',o.id,'actor_id',o.actor_id,'expires_at',o.expires_at);
  end if;
  if s.revision<>p_expected_revision then raise exception 'PIN state changed' using errcode='40001'; end if;
  -- A fresh authenticated retry can renew an unconsumed capability, never a result.
  update private.employee_pin_operations set actor_claims=c,expires_at=clock_timestamp()+interval '2 minutes' where id=o.id returning * into o;
 else
  if s.revision<>p_expected_revision then raise exception 'PIN state changed' using errcode='40001'; end if;
  if (select count(*) from private.employee_pin_operations where membership_id=m.id and result is null and expires_at>clock_timestamp())>=10 then
   raise exception 'Too many pending PIN operations' using errcode='NX001';
  end if;
  insert into private.employee_pin_operations(organization_id,membership_id,actor_id,request_id,action,expected_revision,actor_claims)
   values(m.organization_id,m.id,m.user_id,p_request_id,p_action,p_expected_revision,c) returning * into o;
 end if;
 return jsonb_build_object('id',o.id,'actor_id',o.actor_id,'expires_at',o.expires_at);
end;
$$;
create function public.complete_employee_pin_operation(p_operation_id uuid,p_actor_id uuid,p_pin text,p_current_pin text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare o private.employee_pin_operations;m public.organization_memberships;s private.employee_pin_secrets;
 v_result jsonb;accepted boolean:=false;branches jsonb;previous_configured boolean;
begin
 -- Only the Edge gateway can consume this server-stored actor-bound capability.
 select * into o from private.employee_pin_operations where id=p_operation_id;
 if not found or p_actor_id is distinct from o.actor_id then raise exception 'PIN operation unavailable' using errcode='42501'; end if;
 m:=private.employee_pin_actor(o.organization_id,o.actor_id);
 -- Match preparation lock order: membership, secret, operation.
 select * into s from private.employee_pin_secrets where membership_id=o.membership_id for update;
 select * into o from private.employee_pin_operations where id=p_operation_id for update;
 perform private.security_assert_context_mfa(o.organization_id,o.actor_id,o.actor_claims);
 if o.result is not null then return o.result; end if;
 if o.expires_at<=clock_timestamp() then raise exception 'PIN operation expired' using errcode='42501'; end if;
 if jsonb_typeof(o.actor_claims->'exp')='number' and (o.actor_claims->>'exp')::numeric<=extract(epoch from clock_timestamp()) then
  raise exception 'PIN authorization expired' using errcode='42501';
 end if;
 if p_pin is null or p_pin !~ '^[0-9]{6,12}$' or (p_current_pin is not null and p_current_pin !~ '^[0-9]{6,12}$') then
  raise exception 'PIN format invalid' using errcode='22023';
 end if;
 if s.revision<>o.expected_revision then raise exception 'PIN state changed' using errcode='40001'; end if;
 if s.locked_until is not null and s.locked_until>clock_timestamp() then
  v_result:=jsonb_build_object('accepted',false,'status',private.employee_pin_status(m.id));
  update private.employee_pin_operations set result=v_result where id=o.id;
  return v_result;
 end if;
 if s.locked_until is not null then
  update private.employee_pin_secrets set failed_attempts=0,locked_until=null where membership_id=m.id returning * into s;
 end if;
 previous_configured:=s.pin_hash is not null;
 if o.action='verify' then
  accepted:=s.pin_hash is not null and private.employee_pin_crypt(p_pin,s.pin_hash)=s.pin_hash;
 else
  if p_pin ~ '^([0-9])\1+$' or p_pin in ('123456','654321','12345678','87654321','1234567890') then
   raise exception 'Choose a less predictable PIN' using errcode='22023';
  end if;
  accepted:=s.pin_hash is null or (p_current_pin is not null and private.employee_pin_crypt(p_current_pin,s.pin_hash)=s.pin_hash);
 end if;
 select coalesce(jsonb_agg(branch_id order by branch_id),'[]'::jsonb) into branches from public.membership_branches where membership_id=m.id;
 if accepted then
  if o.action='set' then
   update private.employee_pin_secrets set pin_hash=private.employee_pin_crypt(p_pin,private.employee_pin_salt()),reset_required=false,
    revision=revision+1,failed_attempts=0,locked_until=null,changed_at=clock_timestamp() where membership_id=m.id;
  else update private.employee_pin_secrets set failed_attempts=0,locked_until=null where membership_id=m.id;
  end if;
 else
  update private.employee_pin_secrets set failed_attempts=least(failed_attempts+1,5),
   locked_until=case when failed_attempts+1>=5 then clock_timestamp()+interval '15 minutes' else null end where membership_id=m.id;
 end if;
 insert into public.audit_logs(organization_id,user_id,role,action,entity,entity_id,reason,metadata)
  values(m.organization_id,m.user_id,m.role,
   case when accepted and o.action='set' then case when previous_configured then 'employee.pin_changed' else 'employee.pin_set' end
    when accepted then 'employee.pin_verified' else 'employee.pin_denied' end,
   'organization_memberships',m.id,'Online authenticated PIN operation',
   jsonb_build_object('role',m.role,'previous_role',m.role,'all_branches',m.all_branches,'previous_all_branches',m.all_branches,
    'branch_ids',branches,'previous_branch_ids',branches,'request_id',o.request_id,'operation',o.action,
    'locked',not accepted and s.failed_attempts=4));
 v_result:=jsonb_build_object('accepted',accepted,'status',private.employee_pin_status(m.id));
 update private.employee_pin_operations set result=v_result where id=o.id;
 return v_result;
end;
$$;
create function public.reset_employee_pin(p_organization_id uuid,p_membership_id uuid,p_request_id uuid,p_expected_revision bigint,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.organization_memberships;t public.organization_memberships;s private.employee_pin_secrets;
 prior private.employee_pin_reset_requests;v_result jsonb;branches jsonb;
begin
 a:=private.require_active_member(p_organization_id);
 if exists(select 1 from jsonb_array_elements(coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->'amr','[]'::jsonb)) x where x->>'method'='recovery') then
  raise exception 'PIN access unavailable' using errcode='42501';
 end if;
 if p_request_id is null or p_expected_revision is null or p_expected_revision<1 or p_reason is null
  or char_length(btrim(p_reason)) not between 8 and 500 or p_reason ~ '[[:cntrl:]]' then
  raise exception 'A reset reason and revision are required' using errcode='22023';
 end if;
 if not private.employee_pin_can_reset(p_organization_id,p_membership_id) then raise exception 'PIN reset unavailable' using errcode='42501'; end if;
 select * into t from public.organization_memberships where id=p_membership_id and organization_id=p_organization_id for share;
 insert into private.employee_pin_secrets(membership_id,organization_id,user_id) values(t.id,t.organization_id,t.user_id) on conflict do nothing;
 select * into s from private.employee_pin_secrets where membership_id=t.id for update;
 select * into prior from private.employee_pin_reset_requests where organization_id=p_organization_id and actor_id=a.user_id and request_id=p_request_id;
 if found then
  if prior.target_membership_id<>t.id or prior.expected_revision<>p_expected_revision or prior.reason<>btrim(p_reason) then
   raise exception 'PIN reset request changed' using errcode='23505';
  end if;
  return prior.result;
 end if;
 if s.revision<>p_expected_revision then raise exception 'PIN state changed' using errcode='40001'; end if;
 update private.employee_pin_secrets set pin_hash=null,reset_required=true,revision=revision+1,failed_attempts=0,locked_until=null,changed_at=clock_timestamp() where membership_id=t.id;
 select coalesce(jsonb_agg(branch_id order by branch_id),'[]'::jsonb) into branches from public.membership_branches where membership_id=t.id;
 insert into public.audit_logs(organization_id,user_id,role,action,entity,entity_id,reason,metadata)
  values(p_organization_id,a.user_id,a.role,'employee.pin_reset','organization_memberships',t.id,btrim(p_reason),
   jsonb_build_object('role',t.role,'previous_role',t.role,'all_branches',t.all_branches,'previous_all_branches',t.all_branches,
    'branch_ids',branches,'previous_branch_ids',branches,'request_id',p_request_id));
 v_result:=private.employee_pin_status(t.id);
 insert into private.employee_pin_reset_requests values(p_organization_id,a.user_id,p_request_id,t.id,p_expected_revision,btrim(p_reason),v_result);
 return v_result;
end;
$$;
revoke all on function private.employee_pin_actor(uuid,uuid),private.employee_pin_can_reset(uuid,uuid),private.employee_pin_status(uuid) from public,anon,authenticated,service_role;
revoke all on function private.employee_pin_crypt(text,text),private.employee_pin_salt() from public,anon,authenticated,service_role;
revoke all on function public.get_employee_pin_status(uuid,uuid),public.prepare_employee_pin_operation(uuid,uuid,text,bigint),
 public.list_employee_pin_reset_targets(uuid,integer,integer),public.complete_employee_pin_operation(uuid,uuid,text,text),public.reset_employee_pin(uuid,uuid,uuid,bigint,text) from public,anon,authenticated,service_role;
grant execute on function public.get_employee_pin_status(uuid,uuid),public.list_employee_pin_reset_targets(uuid,integer,integer),public.prepare_employee_pin_operation(uuid,uuid,text,bigint),public.reset_employee_pin(uuid,uuid,uuid,bigint,text) to authenticated;
grant execute on function public.complete_employee_pin_operation(uuid,uuid,text,text) to service_role;
commit;
