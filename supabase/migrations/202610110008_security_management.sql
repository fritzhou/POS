-- Phase 5: current-authority device administration and explicit financial risk
-- review. Administrative resolution is not a fabricated device release proof.
begin;

create table private.security_policies (
 organization_id uuid primary key references public.organizations(id),
 revision bigint not null default 1 check(revision between 1 and 9007199254740991),
 idle_lock_minutes integer not null default 5 check(idle_lock_minutes between 1 and 60),
 require_privileged_mfa boolean not null default false,updated_at timestamptz not null default clock_timestamp()
);
create table private.security_policy_history (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 actor_id uuid not null references auth.users(id),revision bigint not null,policy jsonb not null,
 reason text not null,recorded_at timestamptz not null default clock_timestamp(),unique(organization_id,revision)
);
create table private.security_device_labels (
 id uuid primary key default gen_random_uuid(),device_id uuid not null references private.offline_devices(id),
 organization_id uuid not null references public.organizations(id),actor_id uuid not null references auth.users(id),
 device_name text not null check(char_length(btrim(device_name)) between 1 and 120),
 reason text not null,recorded_at timestamptz not null default clock_timestamp()
);
create table private.security_grant_resolutions (
 grant_id uuid primary key references private.offline_grants(id),reviewed_by uuid not null references auth.users(id),
 reason text not null check(char_length(btrim(reason)) between 3 and 1000),
 acknowledged_unknown_paid_events boolean not null check(acknowledged_unknown_paid_events),
 known_last_sequence bigint not null,known_outcome_count integer not null,known_total_minor bigint not null,
 known_outcomes jsonb not null,remaining_exposure_events integer not null,remaining_exposure_minor bigint not null,
 resolved_at timestamptz not null default clock_timestamp()
);
create table private.security_requests (
 organization_id uuid not null references public.organizations(id),actor_id uuid not null references auth.users(id),
 request_id uuid not null,kind text not null,payload jsonb not null,result jsonb not null,
 recorded_at timestamptz not null default clock_timestamp(),primary key(organization_id,actor_id,request_id)
);
create table private.security_notifications (
 id uuid primary key default gen_random_uuid(),audit_id uuid not null unique references public.audit_logs(id),
 organization_id uuid not null references public.organizations(id),branch_id uuid,target_actor_id uuid,
 action text not null,title text not null,message text not null,created_at timestamptz not null,
 foreign key(organization_id,branch_id) references public.branches(organization_id,id)
);
create table private.security_notification_reads (
 notification_id uuid not null references private.security_notifications(id),actor_id uuid not null references auth.users(id),
 read_at timestamptz not null default clock_timestamp(),primary key(notification_id,actor_id)
);
create table private.security_offline_authorizations (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,branch_id uuid not null,actor_id uuid not null references auth.users(id),device_id uuid not null,
 action text not null check(action in ('enroll','prepare','pull','release')),claims jsonb not null,
 authorized_at timestamptz not null default clock_timestamp(),expires_at timestamptz not null,
 foreign key(organization_id,branch_id) references public.branches(organization_id,id)
);
create index security_offline_authorizations_scope on private.security_offline_authorizations(organization_id,branch_id,actor_id,device_id,action,expires_at desc);
create index security_labels_latest on private.security_device_labels(device_id,recorded_at desc,id);
create index security_notifications_scope on private.security_notifications(organization_id,branch_id,created_at desc,id);

-- PostgREST supplies verified JWT claims. No application role can choose the
-- effective role/claims via an RPC parameter. The service bearer is not a user's
-- MFA proof: trusted Edge operations need a user-context authorization step.
create function private.security_assert_context_mfa(p_organization_id uuid,p_actor_id uuid,p_claims jsonb)
returns void language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from private.security_policies where organization_id=p_organization_id and require_privileged_mfa)
  and exists(select 1 from public.organization_memberships where organization_id=p_organization_id and user_id=p_actor_id and status='active' and role in ('owner','admin')) then
  if p_claims->>'sub' is distinct from p_actor_id::text or p_claims->>'aal' is distinct from 'aal2' then
   raise exception 'Verified multi-factor session required' using errcode='42501';
  end if;
 end if;
end; $$;
create function private.security_assert_privileged_mfa(p_organization_id uuid,p_actor_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare claims jsonb;
begin
 begin claims:=coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb;
 exception when invalid_text_representation then raise exception 'Verified multi-factor session required' using errcode='42501'; end;
 perform private.security_assert_context_mfa(p_organization_id,p_actor_id,claims);
end; $$;
alter function private.require_active_member(uuid) rename to require_active_member_without_mfa;
create function private.require_active_member(p_organization_id uuid)
returns public.organization_memberships language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;
begin
 m:=private.require_active_member_without_mfa(p_organization_id);
 perform private.security_assert_privileged_mfa(p_organization_id,m.user_id);
 return m;
end; $$;
create function private.security_member(p_org uuid,p_branch uuid,p_management boolean default false)
returns public.organization_memberships language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;
begin
 m:=private.require_active_member(p_org);
 if p_branch is null or not private.user_can_access_branch(p_org,p_branch,m.user_id) then raise exception 'Current branch access required' using errcode='42501'; end if;
 if p_management and m.role not in ('owner','admin') then raise exception 'Owner or Admin required' using errcode='42501'; end if;
 return m;
end; $$;
create function private.security_reason(p_reason text)
returns text language plpgsql immutable set search_path='' as $$
begin
 if p_reason is null or char_length(btrim(p_reason)) not between 3 and 1000 then raise exception 'A meaningful reason is required' using errcode='22023'; end if;
 return btrim(p_reason);
end; $$;
create function private.security_page(p_offset integer,p_limit integer)
returns void language plpgsql immutable set search_path='' as $$
begin
 if p_offset is null or p_offset not between 0 and 100000 or p_limit is null or p_limit not between 1 and 100 then raise exception 'Invalid security page bounds' using errcode='22023'; end if;
end; $$;
create function private.security_request(p_org uuid,p_request uuid,p_kind text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.security_requests;
begin
 if p_request is null then raise exception 'Stable request identifier required' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('security:'||p_org::text||':'||auth.uid()::text||':'||p_request::text,0));
 select * into r from private.security_requests where organization_id=p_org and actor_id=auth.uid() and request_id=p_request;
 if found then
  if r.kind<>p_kind or r.payload<>p_payload then raise exception 'Security request identifier was reused with changed details' using errcode='23505'; end if;
  return r.result;
 end if;
 return null;
end; $$;
create function private.security_save_request(p_org uuid,p_request uuid,p_kind text,p_payload jsonb,p_result jsonb)
returns void language sql security definer set search_path='' as $$
 insert into private.security_requests(organization_id,actor_id,request_id,kind,payload,result) values(p_org,auth.uid(),p_request,p_kind,p_payload,p_result);
$$;
create function private.security_can_manage_device(p_org uuid,p_device uuid,p_actor uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organization_memberships m join private.offline_devices d on d.organization_id=m.organization_id
  where m.organization_id=p_org and d.id=p_device and m.user_id=p_actor and m.status='active' and (
   m.role='owner' or (m.role='admin' and (d.actor_id=p_actor or not exists(select 1 from public.organization_memberships target where target.organization_id=p_org and target.user_id=d.actor_id and target.role in ('owner','admin')))
    and not exists(select 1 from private.offline_device_branches b where b.device_id=d.id and not private.user_can_access_branch(p_org,b.branch_id,p_actor)))));
$$;
create function private.security_device_json(p_org uuid,p_branch uuid,p_device uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('device_id',d.id,'organization_id',d.organization_id,'branch_id',p_branch,'actor_id',d.actor_id,
  'device_name',coalesce((select l.device_name from private.security_device_labels l where l.device_id=d.id order by l.recorded_at desc,l.id desc limit 1),d.device_name),
  'platform',d.platform,'enrolled_at',private.offline_time(b.enrolled_at),
  'last_sync_at',(select private.offline_time(max(recorded_at)) from private.offline_event_outcomes where device_id=d.id and branch_id=p_branch),
  'revoked_at',private.offline_time(r.revoked_at),'revocation_reason',r.reason,'can_manage',private.security_can_manage_device(p_org,d.id,auth.uid()))
 from private.offline_devices d join private.offline_device_branches b on b.device_id=d.id and b.organization_id=p_org and b.branch_id=p_branch
 left join private.offline_device_revocations r on r.device_id=d.id where d.id=p_device;
$$;
create function private.security_grant_json(p_grant uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('grant_id',g.id,'organization_id',g.organization_id,'branch_id',g.branch_id,'device_id',g.device_id,'actor_id',g.actor_id,'shift_id',g.shift_id,
  'issued_at',private.offline_time(g.issued_at),'expires_at',private.offline_time(g.expires_at),'currency',g.claims->>'currency','max_events',g.max_events,'max_total_minor',g.max_total_minor,
  'last_sequence',s.last_sequence,'total_minor',s.total_minor,'outcome_count',(select count(*) from private.offline_event_outcomes where grant_id=g.id),
  'review_count',(select count(*) from private.offline_event_outcomes where grant_id=g.id and result->>'status'='review'),
  'state',case when a.grant_id is not null then 'administratively_resolved' when r.grant_id is not null then 'released' when proof.grant_id is null then 'unsigned' when g.expires_at<=clock_timestamp() then 'expired' else 'active' end,
  'released_at',private.offline_time(r.released_at),'administratively_resolved_at',private.offline_time(a.resolved_at),
  'blocks_shift_close',r.grant_id is null and a.grant_id is null and not exists(select 1 from private.offline_grant_abandonments where grant_id=g.id),
  'remaining_exposure_events',case when r.grant_id is not null or proof.grant_id is null then 0 else greatest(0,g.max_events-(select count(*) from private.offline_event_outcomes where grant_id=g.id)) end,
  'remaining_exposure_minor',case when r.grant_id is not null or proof.grant_id is null then 0 else greatest(0,g.max_total_minor-s.total_minor) end,
  'can_review',a.grant_id is null and r.grant_id is null and proof.grant_id is not null and g.expires_at<=clock_timestamp()
   and exists(select 1 from private.offline_device_revocations where device_id=g.device_id)
   and private.security_can_manage_device(g.organization_id,g.device_id,auth.uid()))
 from private.offline_grants g join private.offline_grant_states s on s.grant_id=g.id
 left join private.offline_grant_releases r on r.grant_id=g.id left join private.security_grant_resolutions a on a.grant_id=g.id
 left join private.offline_grant_signatures proof on proof.grant_id=g.id where g.id=p_grant;
$$;

create function public.authorize_offline_operation(p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_action text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;claims jsonb;expiry timestamptz;
begin
 m:=private.security_member(p_organization_id,p_branch_id);
 if m.role not in ('owner','admin','manager','cashier') or p_device_id is null or p_action is null or p_action not in ('enroll','prepare','pull','release') then raise exception 'Invalid offline operation authorization' using errcode='22023';end if;
 if exists(select 1 from private.offline_devices where id=p_device_id and (organization_id<>p_organization_id or actor_id<>auth.uid())) then raise exception 'Device belongs to another actor' using errcode='42501';end if;
 begin claims:=coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb;
 exception when invalid_text_representation then raise exception 'Verified Auth claims required' using errcode='42501';end;
 -- PostgREST's claims are source data; retaining only the needed fields avoids
 -- persisting tokens or broad JWT claims in the authorization history.
 claims:=jsonb_build_object('sub',auth.uid(),'aal',claims->>'aal','session_id',claims->>'session_id');
 expiry:=clock_timestamp()+interval '2 minutes';
 insert into private.security_offline_authorizations(organization_id,branch_id,actor_id,device_id,action,claims,expires_at)
  values(p_organization_id,p_branch_id,auth.uid(),p_device_id,p_action,claims,expiry);
 return jsonb_build_object('authorized',true,'expires_at',private.offline_time(expiry));
end; $$;
create function private.security_assert_offline_service(p_actor uuid,p_org uuid,p_branch uuid,p_device uuid,p_action text)
returns void language plpgsql security definer set search_path='' as $$
declare claims jsonb;
begin
 if exists(select 1 from private.security_policies where organization_id=p_org and require_privileged_mfa)
  and exists(select 1 from public.organization_memberships where organization_id=p_org and user_id=p_actor and status='active' and role in ('owner','admin')) then
  select a.claims into claims from private.security_offline_authorizations a
   where a.organization_id=p_org and a.branch_id=p_branch and a.actor_id=p_actor and a.device_id=p_device and a.action=p_action and a.expires_at>clock_timestamp()
   order by a.authorized_at desc,a.id desc limit 1;
  if not found then raise exception 'Fresh verified user-context authorization required' using errcode='42501';end if;
  perform private.security_assert_context_mfa(p_org,p_actor,claims);
 end if;
end; $$;

create function public.get_security_policy(p_organization_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 -- Discovery remains available at AAL1 so the user can enroll/step up.
 perform private.require_active_member_without_mfa(p_organization_id);
 return coalesce((select jsonb_build_object('organization_id',organization_id,'revision',revision,'idle_lock_minutes',idle_lock_minutes,'require_privileged_mfa',require_privileged_mfa) from private.security_policies where organization_id=p_organization_id),
  jsonb_build_object('organization_id',p_organization_id,'revision',1,'idle_lock_minutes',5,'require_privileged_mfa',false));
end; $$;
create function public.update_security_policy(p_organization_id uuid,p_request_id uuid,p_expected_revision bigint,p_idle_lock_minutes integer,p_require_privileged_mfa boolean,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;payload jsonb;result jsonb;reason text;v_revision bigint;claims jsonb;
begin
 m:=private.require_active_member(p_organization_id);
 if m.role not in ('owner','admin') then raise exception 'Owner or Admin required' using errcode='42501'; end if;
 reason:=private.security_reason(p_reason);
 if p_expected_revision is null or p_expected_revision not between 1 and 9007199254740990 or p_idle_lock_minutes is null or p_idle_lock_minutes not between 1 and 60 or p_require_privileged_mfa is null then raise exception 'Invalid security policy' using errcode='22023'; end if;
 if p_require_privileged_mfa then
  begin claims:=coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb;
  exception when invalid_text_representation then raise exception 'Verify MFA before requiring it' using errcode='42501'; end;
  if claims->>'sub' is distinct from auth.uid()::text or claims->>'aal' is distinct from 'aal2' then raise exception 'Verify MFA before requiring it' using errcode='42501'; end if;
 end if;
 payload:=jsonb_build_object('expected_revision',p_expected_revision,'idle_lock_minutes',p_idle_lock_minutes,'require_privileged_mfa',p_require_privileged_mfa,'reason',reason);
 result:=private.security_request(p_organization_id,p_request_id,'security.policy_update',payload);if result is not null then return result;end if;
 perform pg_advisory_xact_lock(hashtextextended('security-policy:'||p_organization_id::text,0));
 select revision into v_revision from private.security_policies where organization_id=p_organization_id for update;
 v_revision:=coalesce(v_revision,1);
 if p_expected_revision<>v_revision then raise exception 'Security policy changed; reload before saving' using errcode='40001'; end if;
 insert into private.security_policies(organization_id,revision,idle_lock_minutes,require_privileged_mfa) values(p_organization_id,v_revision+1,p_idle_lock_minutes,p_require_privileged_mfa)
  on conflict(organization_id) do update set revision=excluded.revision,idle_lock_minutes=excluded.idle_lock_minutes,require_privileged_mfa=excluded.require_privileged_mfa,updated_at=clock_timestamp();
 result:=public.get_security_policy(p_organization_id);
 insert into private.security_policy_history(organization_id,actor_id,revision,policy,reason) values(p_organization_id,auth.uid(),v_revision+1,result,reason);
 perform private.append_action_audit(p_organization_id,'security.policy_updated','security_policy',p_organization_id,null,reason,result);
 perform private.security_save_request(p_organization_id,p_request_id,'security.policy_update',payload,result);return result;
end; $$;
create function public.list_security_devices(p_organization_id uuid,p_branch_id uuid,p_offset integer default 0,p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;
begin
 m:=private.security_member(p_organization_id,p_branch_id);perform private.security_page(p_offset,p_limit);
 return coalesce((select jsonb_agg(row_json order by enrolled_at desc,id) from (select private.security_device_json(p_organization_id,p_branch_id,d.id) row_json,b.enrolled_at,d.id
  from private.offline_devices d join private.offline_device_branches b on b.device_id=d.id
  where b.organization_id=p_organization_id and b.branch_id=p_branch_id and (m.role in ('owner','admin') or d.actor_id=auth.uid())
  order by b.enrolled_at desc,d.id offset p_offset limit p_limit) rows),'[]'::jsonb);
end; $$;
create function public.update_security_device(p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_request_id uuid,p_device_name text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;result jsonb;reason text;
begin
 perform private.security_member(p_organization_id,p_branch_id,true);reason:=private.security_reason(p_reason);
 perform 1 from private.offline_devices d join private.offline_device_branches b on b.device_id=d.id where d.id=p_device_id and b.organization_id=p_organization_id and b.branch_id=p_branch_id;
 if not found or not private.security_can_manage_device(p_organization_id,p_device_id,auth.uid()) then raise exception 'Device management unavailable' using errcode='42501'; end if;
 if p_device_name is null or char_length(btrim(p_device_name)) not between 1 and 120 then raise exception 'Invalid device name' using errcode='22023'; end if;
 payload:=jsonb_build_object('branch_id',p_branch_id,'device_id',p_device_id,'device_name',btrim(p_device_name),'reason',reason);
 result:=private.security_request(p_organization_id,p_request_id,'security.device_rename',payload);if result is not null then return result;end if;
 perform 1 from private.offline_devices where id=p_device_id for update;
 insert into private.security_device_labels(device_id,organization_id,actor_id,device_name,reason) values(p_device_id,p_organization_id,auth.uid(),btrim(p_device_name),reason);
 perform private.append_action_audit(p_organization_id,'security.device_renamed','offline_devices',p_device_id,p_branch_id,reason,jsonb_build_object('target_actor_id',(select actor_id from private.offline_devices where id=p_device_id),'device_name',btrim(p_device_name)));
 result:=private.security_device_json(p_organization_id,p_branch_id,p_device_id);
 perform private.security_save_request(p_organization_id,p_request_id,'security.device_rename',payload,result);return result;
end; $$;
create or replace function public.revoke_offline_device(p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d private.offline_devices;r private.offline_device_revocations;reason text;
begin
 perform private.security_member(p_organization_id,p_branch_id,true);reason:=private.security_reason(p_reason);
 select devices.* into d from private.offline_devices devices join private.offline_device_branches b on b.device_id=devices.id
  where b.organization_id=p_organization_id and b.branch_id=p_branch_id and devices.id=p_device_id for update of devices;
 if not found or not private.security_can_manage_device(p_organization_id,d.id,auth.uid()) then raise exception 'Device management unavailable' using errcode='42501'; end if;
 select * into r from private.offline_device_revocations where device_id=d.id;
 if not found then
  insert into private.offline_device_revocations(device_id,revoked_by,reason) values(d.id,auth.uid(),reason) returning * into r;
  perform private.append_action_audit(p_organization_id,'security.device_revoked','offline_devices',d.id,p_branch_id,reason,jsonb_build_object('target_actor_id',d.actor_id,'device_id',d.id,'all_branch_bindings',true));
 end if;
 return jsonb_build_object('device_id',d.id,'revoked_at',private.offline_time(r.revoked_at));
end; $$;
create function public.revoke_security_device(p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_request_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;result jsonb;reason text;
begin
 perform private.security_member(p_organization_id,p_branch_id,true);reason:=private.security_reason(p_reason);
 if not private.security_can_manage_device(p_organization_id,p_device_id,auth.uid()) then raise exception 'Device management unavailable' using errcode='42501'; end if;
 payload:=jsonb_build_object('branch_id',p_branch_id,'device_id',p_device_id,'reason',reason);
 result:=private.security_request(p_organization_id,p_request_id,'security.device_revoke',payload);if result is not null then return result;end if;
 perform public.revoke_offline_device(p_organization_id,p_branch_id,p_device_id,reason);
 result:=private.security_device_json(p_organization_id,p_branch_id,p_device_id);
 perform private.security_save_request(p_organization_id,p_request_id,'security.device_revoke',payload,result);return result;
end; $$;
create function public.list_security_grants(p_organization_id uuid,p_branch_id uuid,p_offset integer default 0,p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;
begin
 m:=private.security_member(p_organization_id,p_branch_id);perform private.security_page(p_offset,p_limit);
 return coalesce((select jsonb_agg(row_json order by issued_at desc,id) from (select private.security_grant_json(g.id) row_json,g.issued_at,g.id
  from private.offline_grants g where g.organization_id=p_organization_id and g.branch_id=p_branch_id and (m.role in ('owner','admin') or g.actor_id=auth.uid())
  order by g.issued_at desc,g.id offset p_offset limit p_limit) rows),'[]'::jsonb);
end; $$;
create function public.review_offline_grant(p_organization_id uuid,p_branch_id uuid,p_grant_id uuid,p_request_id uuid,p_reason text,p_acknowledge_unknown_paid_events boolean,
 p_expected_last_sequence bigint,p_expected_outcome_count integer,p_expected_total_minor bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare g private.offline_grants;s private.offline_grant_states;payload jsonb;result jsonb;reason text;known jsonb;outcomes integer;
begin
 perform private.security_member(p_organization_id,p_branch_id,true);reason:=private.security_reason(p_reason);
 if p_acknowledge_unknown_paid_events is distinct from true then raise exception 'Explicit acknowledgement of unknown paid events is required' using errcode='22023'; end if;
 select * into g from private.offline_grants where id=p_grant_id and organization_id=p_organization_id and branch_id=p_branch_id;
 if not found or not private.security_can_manage_device(p_organization_id,g.device_id,auth.uid()) then raise exception 'Grant review unavailable' using errcode='42501'; end if;
 payload:=jsonb_build_object('branch_id',p_branch_id,'grant_id',p_grant_id,'reason',reason,'acknowledge_unknown_paid_events',true,
  'expected_last_sequence',p_expected_last_sequence,'expected_outcome_count',p_expected_outcome_count,'expected_total_minor',p_expected_total_minor);
 result:=private.security_request(p_organization_id,p_request_id,'security.grant_review',payload);if result is not null then return result;end if;
 perform 1 from private.offline_devices where id=g.device_id for share;
 select * into g from private.offline_grants where id=p_grant_id for update;
 if g.expires_at>clock_timestamp() or not exists(select 1 from private.offline_device_revocations where device_id=g.device_id)
  or not exists(select 1 from private.offline_grant_signatures where grant_id=g.id) or exists(select 1 from private.offline_grant_releases where grant_id=g.id) then
  raise exception 'Review requires an expired signed grant on a revoked device' using errcode='23514'; end if;
 if exists(select 1 from private.security_grant_resolutions where grant_id=g.id) then raise exception 'Grant already has an immutable administrative review' using errcode='23505'; end if;
 select * into s from private.offline_grant_states where grant_id=g.id for update;
 select count(*),coalesce(jsonb_agg(jsonb_build_object('event_id',e.event_id,'sequence',e.sequence,'status',e.result->>'status','total_minor',e.event->'payload'->'total_minor') order by e.sequence),'[]'::jsonb)
  into outcomes,known from private.offline_event_outcomes e where e.grant_id=g.id;
 if p_expected_last_sequence is distinct from s.last_sequence or p_expected_outcome_count is distinct from outcomes or p_expected_total_minor is distinct from s.total_minor then
  raise exception 'Paid outcomes changed; reload the grant before review' using errcode='40001'; end if;
 insert into private.security_grant_resolutions(grant_id,reviewed_by,reason,acknowledged_unknown_paid_events,known_last_sequence,known_outcome_count,known_total_minor,known_outcomes,remaining_exposure_events,remaining_exposure_minor)
   values(g.id,auth.uid(),reason,true,s.last_sequence,outcomes,s.total_minor,known,g.max_events-outcomes,g.max_total_minor-s.total_minor);
 perform private.append_action_audit(p_organization_id,'security.grant_administratively_resolved','offline_grants',g.id,p_branch_id,reason,
  jsonb_build_object('target_actor_id',g.actor_id,'device_id',g.device_id,'known_last_sequence',s.last_sequence,'known_outcome_count',outcomes,'known_total_minor',s.total_minor,
   'remaining_exposure_events',g.max_events-outcomes,'remaining_exposure_minor',g.max_total_minor-s.total_minor,'unknown_paid_events_acknowledged',true,'device_release_signature_created',false));
 result:=private.security_grant_json(g.id);
 perform private.security_save_request(p_organization_id,p_request_id,'security.grant_review',payload,result);return result;
end; $$;

-- A resolved grant keeps its original financial exposure and can receive late
-- paid evidence. It stops blocking the original shift only after this explicit
-- revoked + expired + audited administrative decision.
create or replace function private.offline_guard_shift_close()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform private.offline_abandon_expired_unsigned(new.organization_id);
 if exists(select 1 from private.offline_grants g where g.shift_id=new.shift_id
  and not exists(select 1 from private.offline_grant_releases r where r.grant_id=g.id)
  and not exists(select 1 from private.offline_grant_abandonments a where a.grant_id=g.id)
  and not exists(select 1 from private.security_grant_resolutions a where a.grant_id=g.id)) then
  raise exception 'Synchronize and release every grant, or explicitly review a revoked expired grant, before closing the shift' using errcode='23514';
 end if;
 return new;
end; $$;

-- Retained paid evidence has a narrower authority than current business data.
-- Revocation denies future enrollment/capture/current catalog but does not erase
-- cryptographically verified money already captured with the retained key.
create function private.security_retained_device_require(p_actor uuid,p_org uuid,p_branch uuid,p_device uuid)
returns private.offline_devices language plpgsql security definer set search_path='' as $$
declare d private.offline_devices;
begin
 perform private.offline_require(p_actor,p_org,p_branch);
 select devices.* into d from private.offline_devices devices join private.offline_device_branches binding on binding.device_id=devices.id
  where binding.organization_id=p_org and binding.branch_id=p_branch and binding.actor_id=p_actor and devices.id=p_device for share of devices,binding;
 if not found then raise exception 'Retained enrolled device required' using errcode='42501'; end if;
 return d;
end; $$;

create or replace function public.get_offline_verification_context(p_actor_id uuid,p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_grant_id uuid default null,p_challenge_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d private.offline_devices;c private.offline_device_challenges;g private.offline_grants;r jsonb;
begin
 perform private.offline_require(p_actor_id,p_organization_id,p_branch_id);
 if p_challenge_id is not null then
  select * into c from private.offline_device_challenges where id=p_challenge_id and organization_id=p_organization_id and branch_id=p_branch_id and actor_id=p_actor_id and device_id=p_device_id;
  if not found or c.expires_at<=clock_timestamp() then raise exception 'Enrollment challenge unavailable or expired' using errcode='42501'; end if;
  return jsonb_build_object('public_key',c.public_key,'challenge',jsonb_build_object('challenge_id',c.id,'nonce',c.nonce,'organization_id',c.organization_id,'branch_id',c.branch_id,
   'device_id',c.device_id,'actor_id',c.actor_id,'public_key',c.public_key,'expires_at',private.offline_time(c.expires_at)));
 end if;
 if p_grant_id is null then d:=private.offline_device_require(p_actor_id,p_organization_id,p_branch_id,p_device_id);
 else d:=private.security_retained_device_require(p_actor_id,p_organization_id,p_branch_id,p_device_id); end if;
 r:=jsonb_build_object('public_key',d.public_key);
 if p_grant_id is not null then
  select * into g from private.offline_grants where id=p_grant_id and organization_id=p_organization_id and branch_id=p_branch_id and actor_id=p_actor_id and device_id=p_device_id;
  if not found or not exists(select 1 from private.offline_grant_signatures where grant_id=g.id) then raise exception 'Signed grant unavailable' using errcode='42501'; end if;
  r:=r||jsonb_build_object('grant',jsonb_build_object('claims',g.claims,'signature',(select signature from private.offline_grant_signatures where grant_id=g.id)));
 end if;
 return r;
end; $$;

create or replace function public.ingest_offline_event(p_actor_id uuid,p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_event jsonb,p_digest text,p_authorization jsonb,p_signature text)
returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
<<vars>>
declare
 m public.organization_memberships;g private.offline_grants;state private.offline_grant_states;previous private.offline_event_outcomes;s public.shifts;
 payload jsonb;item jsonb;product jsonb;pay jsonb;evidence jsonb;lines jsonb:='[]'::jsonb;line jsonb;event_id uuid;sale_id uuid;grant_id uuid;sequence bigint;
 qty bigint;price bigint;line_subtotal numeric;line_tax numeric;subtotal numeric:=0;tax_total numeric:=0;total bigint;paid numeric:=0;cash_paid numeric:=0;
 amount bigint;tendered bigint;method text;reference text;occurred timestamptz;receipt_number bigint;code text;reconciliation_id uuid;
 accepted timestamptz;result jsonb;impacts jsonb;product_row public.products;
begin
 m:=private.offline_require(p_actor_id,p_organization_id,p_branch_id);
 perform private.security_retained_device_require(p_actor_id,p_organization_id,p_branch_id,p_device_id);
 perform private.offline_counter_lock(p_organization_id);
 perform private.offline_check_keys(p_event,array['actor_id','branch_id','device_id','event_id','event_type','occurred_at','organization_id','payload','schema_version']);
 perform private.offline_check_keys(p_authorization,array['grant_id','sequence','payment_evidence']);
 if octet_length(p_event::text)>262144 or p_digest is null or p_digest !~ '^[0-9a-f]{64}$' or private.offline_digest(p_event)<>p_digest
  or p_signature is null or p_signature !~ '^[A-Za-z0-9_-]{86}$' then raise exception 'Invalid immutable event digest or proof' using errcode='22023'; end if;
 if p_event->>'actor_id' is distinct from p_actor_id::text or p_event->>'organization_id' is distinct from p_organization_id::text
  or p_event->>'branch_id' is distinct from p_branch_id::text or p_event->>'device_id' is distinct from p_device_id::text
  or p_event->>'event_type' is distinct from 'sale.created' or p_event->'schema_version' is distinct from '1'::jsonb then raise exception 'Event identity does not match verified scope' using errcode='42501'; end if;
 grant_id:=private.offline_uuid(p_authorization->'grant_id');sequence:=private.phase3_integer(p_authorization->'sequence',1,1000);
 event_id:=private.offline_uuid(p_event->'event_id');payload:=p_event->'payload';sale_id:=private.offline_uuid(payload->'id');
 select * into g from private.offline_grants where id=grant_id and organization_id=p_organization_id and branch_id=p_branch_id and actor_id=p_actor_id and device_id=p_device_id for update;
 if not found or not exists(select 1 from private.offline_grant_signatures where grant_id=g.id) or m.id<>g.membership_id then raise exception 'Retained signed grant unavailable' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('offline-event:'||event_id::text,0));
 select * into previous from private.offline_event_outcomes e where e.event_id=vars.event_id;
 if found then
  if previous.organization_id<>p_organization_id or previous.branch_id<>p_branch_id or previous.actor_id<>p_actor_id or previous.device_id<>p_device_id
   or previous.grant_id<>grant_id or previous.sequence<>sequence or previous.event<>p_event or previous.digest<>p_digest or previous.authorization_payload<>p_authorization or previous.signature<>p_signature then
   raise exception 'Event identifier replay has changed immutable content' using errcode='23505';
  end if;
  return previous.result;
 end if;
 if exists(select 1 from private.offline_grant_releases where grant_id=g.id) then raise exception 'Grant already released' using errcode='23514'; end if;
 select * into state from private.offline_grant_states where grant_id=g.id for update;
 if sequence>g.max_events then raise exception 'Grant event count exceeds authorization' using errcode='22023'; end if;
 if sequence<>state.last_sequence+1 and not exists(select 1 from private.security_grant_resolutions where grant_id=g.id) then
  raise exception 'Grant events must arrive in uninterrupted sequence before administrative risk review' using errcode='23505';
 end if;
 if exists(select 1 from private.offline_event_outcomes e where e.grant_id=g.id and e.sequence=vars.sequence) then
  raise exception 'Grant sequence already binds another immutable event' using errcode='23505';
 end if;
 if jsonb_typeof(p_event->'occurred_at') is distinct from 'string' then raise exception 'UTC event observation is required' using errcode='22023'; end if;
 occurred:=(p_event->>'occurred_at')::timestamptz;
 if p_event->>'occurred_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|\+00:00)$' or occurred<g.issued_at or occurred>=g.expires_at
  or (clock_timestamp()>g.expires_at+interval '72 hours' and not exists(select 1 from private.security_grant_resolutions where grant_id=g.id)) or occurred>clock_timestamp()+interval '5 minutes' then raise exception 'Event observation or ingestion is outside bounded grant lifetime' using errcode='42501'; end if;
 if exists(select 1 from private.offline_device_revocations where device_id=g.device_id and occurred>=revoked_at) then raise exception 'Revoked device cannot capture new events' using errcode='42501'; end if;
 perform private.offline_check_keys(payload,array['id','shift_id','customer_id','receipt_number','currency','subtotal_minor','discount_minor','tax_minor','total_minor','items','payments']);
 if payload->>'shift_id' is distinct from g.shift_id::text or payload->>'currency' is distinct from g.claims->>'currency'
  or payload->'customer_id' is distinct from 'null'::jsonb or payload->'discount_minor' is distinct from '0'::jsonb
  or jsonb_typeof(payload->'receipt_number') is distinct from 'string' or char_length(payload->>'receipt_number') not between 1 and 120 then raise exception 'Offline sale must use own shift, signed currency, no customer and no discounts' using errcode='22023'; end if;
 if jsonb_typeof(payload->'items') is distinct from 'array' or jsonb_array_length(payload->'items') not between 1 and 100
  or (select count(distinct (x->>'product_id')::uuid) from jsonb_array_elements(payload->'items') x)<>jsonb_array_length(payload->'items')
  or (select count(distinct (x->>'id')::uuid) from jsonb_array_elements(payload->'items') x)<>jsonb_array_length(payload->'items') then raise exception 'One to 100 unique immutable product lines required' using errcode='22023'; end if;
 for item in select value from jsonb_array_elements(payload->'items') order by (value->>'product_id')::uuid loop
  perform private.offline_check_keys(item,array['id','product_id','sku_snapshot','name_snapshot','quantity','unit_price_minor','discount_minor','tax_minor','line_total_minor']);
  perform private.offline_uuid(item->'id');perform private.offline_uuid(item->'product_id');
  select value into product from jsonb_array_elements(g.snapshot->'products') where value->>'id'=item->>'product_id';
  if not found or item->>'sku_snapshot' is distinct from product->>'sku' or item->>'name_snapshot' is distinct from product->>'name'
   or item->'unit_price_minor' is distinct from product->'price_minor' or item->'discount_minor' is distinct from '0'::jsonb then raise exception 'Line differs from signed catalog snapshot' using errcode='22023'; end if;
  qty:=private.phase3_integer(item->'quantity',1,1000000);price:=private.phase3_integer(item->'unit_price_minor',0,9007199254740991);
  line_subtotal:=qty::numeric*price;line_tax:=div(line_subtotal*(g.claims->>'tax_bps')::integer+5000,10000);
  if private.phase3_integer(item->'tax_minor',0,9007199254740991)<>line_tax or private.phase3_integer(item->'line_total_minor',0,9007199254740991)<>line_subtotal+line_tax then raise exception 'Offline line tax and total must match exact snapshot math' using errcode='22023'; end if;
  subtotal:=subtotal+line_subtotal;tax_total:=tax_total+line_tax;
  lines:=lines||jsonb_build_array(item||jsonb_build_object('line_subtotal_minor',line_subtotal,'product_revision',product->'revision','unit',product->'unit'));
 end loop;
 total:=private.phase3_integer(payload->'total_minor',1,g.max_total_minor);
 if private.phase3_integer(payload->'subtotal_minor',1,9007199254740991)<>subtotal or private.phase3_integer(payload->'tax_minor',0,9007199254740991)<>tax_total or total::numeric<>subtotal+tax_total
  or state.total_minor::numeric+total>g.max_total_minor then raise exception 'Offline totals or cumulative grant amount exceed authorization' using errcode='22023'; end if;
 if jsonb_typeof(payload->'payments') is distinct from 'array' or jsonb_array_length(payload->'payments') not between 1 and 5
  or jsonb_typeof(p_authorization->'payment_evidence') is distinct from 'object'
  or (select count(*) from jsonb_object_keys(p_authorization->'payment_evidence'))<>jsonb_array_length(payload->'payments')
  or (select count(distinct (x->>'id')::uuid) from jsonb_array_elements(payload->'payments') x)<>jsonb_array_length(payload->'payments') then raise exception 'One to five unique payments with matching manual evidence required' using errcode='22023'; end if;
 for pay in select value from jsonb_array_elements(payload->'payments') loop
  perform private.offline_check_keys(pay,array['id','method','amount_minor','verification_mode','reference']);
  perform private.offline_uuid(pay->'id');
  evidence:=p_authorization->'payment_evidence'->(pay->>'id');method:=pay->>'method';amount:=private.phase3_integer(pay->'amount_minor',1,9007199254740991);paid:=paid+amount;
  if method='cash' then
   perform private.offline_check_keys(evidence,array['tendered_minor']);
   tendered:=private.phase3_integer(evidence->'tendered_minor',amount,9007199254740991);cash_paid:=cash_paid+amount;
   if pay->>'verification_mode' is distinct from 'cash' or pay->'reference' is distinct from 'null'::jsonb then raise exception 'Cash snapshot has invalid evidence' using errcode='22023'; end if;
  elsif method in ('card','gcash','maya','other') then
   perform private.offline_check_keys(evidence,array['manual_confirmed']);reference:=pay->>'reference';
   if evidence->'manual_confirmed' is distinct from 'true'::jsonb or pay->>'verification_mode' is distinct from 'manual' or reference is null or char_length(btrim(reference)) not between 3 and 120 then raise exception 'Offline digital tender requires manually confirmed reference' using errcode='22023'; end if;
  else raise exception 'Unsupported offline payment method' using errcode='22023'; end if;
 end loop;
 if paid<>total then raise exception 'Payment allocations must equal immutable paid total' using errcode='22023'; end if;
 -- Closed shifts and changed/deleted product identities preserve paid events as
 -- explicit review outcomes rather than mutating historical closure totals.
 select * into s from public.shifts where id=g.shift_id for update;
 if exists(select 1 from private.security_grant_resolutions where grant_id=g.id) then code:='GRANT_ADMINISTRATIVELY_RESOLVED';
 elsif exists(select 1 from private.offline_device_revocations where device_id=g.device_id) then code:='DEVICE_REVOKED';end if;
 if exists(select 1 from public.shift_closures where shift_id=g.shift_id) then code:=coalesce(code,'SHIFT_CLOSED'); end if;
 if exists(select 1 from public.sales where id=sale_id) or exists(select 1 from private.offline_event_outcomes where document_id=sale_id) then raise exception 'Local document identity already has another source' using errcode='23505'; end if;
 for line in select value from jsonb_array_elements(lines) order by (value->>'product_id')::uuid loop
  select * into product_row from public.products where organization_id=p_organization_id and id=(line->>'product_id')::uuid for update;
  if not found then code:=coalesce(code,'PRODUCT_UNAVAILABLE'); end if;
  if exists(select 1 from public.sale_items where id=(line->>'id')::uuid) then code:=coalesce(code,'ITEM_ID_CONFLICT'); end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(payload->'payments') x join public.sale_payments p on p.id=(x->>'id')::uuid) then code:=coalesce(code,'PAYMENT_ID_CONFLICT'); end if;
 if private.phase3_expected_cash(s.id)::numeric+cash_paid not between -9007199254740991 and 9007199254740991 then code:=coalesce(code,'CASH_LIMIT'); end if;
 accepted:=clock_timestamp();
 result:=jsonb_build_object('status',case when code is null then 'accepted' else 'review' end,'organization_id',p_organization_id,'branch_id',p_branch_id,'actor_id',p_actor_id,
  'device_id',p_device_id,'grant_id',g.id,'sequence',sequence,'event_id',event_id,'digest',p_digest,'document_id',sale_id);
 if code is not null then
  insert into private.offline_reconciliation_cases(organization_id,branch_id,actor_id,device_id,event_id,grant_id,code,details)
   values(p_organization_id,p_branch_id,p_actor_id,p_device_id,event_id,g.id,code,jsonb_build_object('paid_total_minor',total,'provisional_receipt',payload->>'receipt_number')) returning id into reconciliation_id;
  result:=result||jsonb_build_object('reconciliation_code',code,'reconciliation_id',reconciliation_id,'recorded_at',private.offline_time(accepted));
  insert into public.audit_logs(organization_id,user_id,role,action,entity,entity_id,branch_id,device_id,reason,metadata) values(p_organization_id,p_actor_id,m.role,'security.offline_paid_event_review','offline_events',event_id,p_branch_id,p_device_id,'Original paid evidence retained for review',jsonb_build_object('target_actor_id',p_actor_id,'grant_id',g.id,'event_id',event_id,'total_minor',total,'reconciliation_code',code));
 else
  insert into private.receipt_sequences(organization_id,branch_id,next_number) values(p_organization_id,p_branch_id,1)
   on conflict(organization_id,branch_id) do update set next_number=private.receipt_sequences.next_number+1 returning next_number into receipt_number;
  insert into public.sales(id,organization_id,branch_id,shift_id,actor_user_id,receipt_sequence,receipt_number,currency,business_snapshot,settings_revision,subtotal_minor,discount_minor,tax_bps,tax_minor,total_minor,created_at)
  values(sale_id,p_organization_id,p_branch_id,g.shift_id,p_actor_id,receipt_number,(g.snapshot->'context'->>'branch_code')||'-'||case when receipt_number<1000000 then lpad(receipt_number::text,6,'0') else receipt_number::text end,
   g.claims->>'currency',(g.snapshot->'context')-(array['organization_id','branch_id','currency','tax_bps','settings_revision']::text[]),(g.claims->>'settings_revision')::bigint,subtotal::bigint,0,
   (g.claims->>'tax_bps')::integer,tax_total::bigint,total,occurred);
  insert into private.offline_sale_sources(sale_id,event_id,grant_id,organization_id,branch_id,actor_id,provisional_receipt)
   values(sale_id,event_id,g.id,p_organization_id,p_branch_id,p_actor_id,payload->>'receipt_number');
  for line in select value from jsonb_array_elements(lines) order by (value->>'product_id')::uuid loop
   insert into public.sale_items(id,organization_id,sale_id,product_id,product_name,sku,unit,product_revision,quantity,unit_price_minor,line_subtotal_minor,discount_minor,tax_minor,line_total_minor)
   values((line->>'id')::uuid,p_organization_id,sale_id,(line->>'product_id')::uuid,line->>'name_snapshot',line->>'sku_snapshot',line->>'unit',(line->>'product_revision')::bigint,
    (line->>'quantity')::bigint,(line->>'unit_price_minor')::bigint,(line->>'line_subtotal_minor')::bigint,0,(line->>'tax_minor')::bigint,(line->>'line_total_minor')::bigint);
   insert into public.stock_movements(organization_id,branch_id,product_id,actor_user_id,quantity_delta,balance_after,sale_id)
    values(p_organization_id,p_branch_id,(line->>'product_id')::uuid,p_actor_id,-(line->>'quantity')::bigint,0,sale_id);
  end loop;
  for pay in select value from jsonb_array_elements(payload->'payments') loop
   method:=pay->>'method';amount:=(pay->>'amount_minor')::bigint;evidence:=p_authorization->'payment_evidence'->(pay->>'id');
   insert into public.sale_payments(id,organization_id,sale_id,method,amount_minor,tendered_minor,change_minor,reference,manual_confirmed)
   values((pay->>'id')::uuid,p_organization_id,sale_id,method,amount,case when method='cash' then (evidence->>'tendered_minor')::bigint end,
    case when method='cash' then (evidence->>'tendered_minor')::bigint-amount end,case when method<>'cash' then pay->>'reference' end,method<>'cash');
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('product_id',product_id,'revision',stock_revision) order by product_id),'[]'::jsonb) into impacts from public.stock_movements m where m.sale_id=vars.sale_id;
  if exists(select 1 from public.stock_movements m where m.sale_id=vars.sale_id and m.balance_after<0) then
   code:='STOCK_DEFICIT';
   insert into private.offline_reconciliation_cases(organization_id,branch_id,actor_id,device_id,event_id,grant_id,code,details)
    values(p_organization_id,p_branch_id,p_actor_id,p_device_id,event_id,g.id,code,jsonb_build_object('stock_impacts',impacts,'paid_total_minor',total)) returning id into reconciliation_id;
  end if;
  result:=result||jsonb_build_object('server_receipt_id',sale_id,'accepted_at',private.offline_time(accepted),'receipt',private.phase3_sale_json(sale_id)||jsonb_build_object('request_id',event_id),'stock_impacts',impacts);
  if code is not null then result:=result||jsonb_build_object('reconciliation_code',code,'reconciliation_id',reconciliation_id); end if;
  insert into public.audit_logs(organization_id,user_id,role,action,entity,entity_id,branch_id,device_id,reason,metadata)
   values(p_organization_id,p_actor_id,m.role,'sale.offline_accepted','sales',sale_id,p_branch_id,p_device_id,'Verified offline sale',jsonb_build_object('grant_id',g.id,'event_id',event_id,'total_minor',total,'provisional_receipt',payload->>'receipt_number','reconciliation_code',code));
 end if;
 insert into public.financial_events(id,organization_id,branch_id,actor_user_id,event_kind,payload_digest,payload)
  values(event_id,p_organization_id,p_branch_id,p_actor_id,'sale.created',decode(p_digest,'hex'),p_event);
 insert into private.offline_event_outcomes(event_id,organization_id,branch_id,actor_id,device_id,grant_id,sequence,document_id,event,digest,authorization_payload,signature,result)
  values(event_id,p_organization_id,p_branch_id,p_actor_id,p_device_id,g.id,sequence,sale_id,p_event,p_digest,p_authorization,p_signature,result);
 update private.offline_grant_states set last_sequence=greatest(last_sequence,sequence),total_minor=total_minor+total where grant_id=g.id;
 return result;
exception when invalid_text_representation or numeric_value_out_of_range or datetime_field_overflow or invalid_datetime_format then raise exception 'Invalid offline identifier, time or exact amount' using errcode='22023';
end; $$;


create function private.security_audit_notification()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_title text;v_message text;v_target uuid;
begin
 case new.action
 when 'security.device_renamed' then v_title:='Device name changed';v_message:='An administrator changed an enrolled device name.';
 when 'security.device_revoked' then v_title:='Device revoked';v_message:='An administrator revoked offline capture for an enrolled device. Original paid evidence remains eligible for review.';
 when 'security.policy_updated' then v_title:='Security policy changed';v_message:='An administrator changed the idle lock or privileged MFA policy.';
 when 'security.grant_administratively_resolved' then v_title:='Offline grant reviewed';v_message:='An expired grant on a revoked device was administratively resolved. Unknown paid-event exposure remains open for reconciliation.';
 when 'security.offline_paid_event_review' then v_title:='Paid offline event needs review';v_message:='Original paid evidence was retained for reconciliation without changing the closed or revoked shift.';
 when 'employee.pin_set' then v_title:='Employee PIN configured';v_message:='An authenticated employee configured their online PIN.';
 when 'employee.pin_changed' then v_title:='Employee PIN changed';v_message:='An authenticated employee changed their online PIN.';
 when 'employee.pin_reset' then v_title:='Employee PIN reset';v_message:='An administrator reset an employee PIN. The employee must configure a new PIN.';
 when 'employee.pin_denied' then
  if new.metadata->'locked' is distinct from 'true'::jsonb then return new;end if;
  v_title:='Employee PIN temporarily locked';v_message:='Repeated unsuccessful online PIN attempts triggered the server lockout.';
 else return new;
 end case;
 if new.metadata ? 'target_actor_id' then v_target:=(new.metadata->>'target_actor_id')::uuid;end if;
 if v_target is null and new.entity='organization_memberships' then select user_id into v_target from public.organization_memberships where organization_id=new.organization_id and id=new.entity_id;end if;
 insert into private.security_notifications(audit_id,organization_id,branch_id,target_actor_id,action,title,message,created_at)
  values(new.id,new.organization_id,new.branch_id,v_target,new.action,v_title,v_message,new.occurred_at);
 return new;
end; $$;
create trigger security_audit_notifications after insert on public.audit_logs for each row execute function private.security_audit_notification();
create function private.security_notification_visible(p_org uuid,p_branch uuid,p_id uuid,p_actor uuid,p_role text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.security_notifications n join public.audit_logs a on a.id=n.audit_id
  where n.id=p_id and n.organization_id=p_org and (n.branch_id is null or n.branch_id=p_branch)
  and ((p_role in ('owner','admin') and private.can_read_audit(a.organization_id,a.branch_id,a.entity,a.entity_id,a.action,a.metadata))
   or n.target_actor_id=p_actor or (n.target_actor_id is null and n.action='security.policy_updated')));
$$;
create function public.list_security_notifications(p_organization_id uuid,p_branch_id uuid,p_offset integer default 0,p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;
begin
 m:=private.security_member(p_organization_id,p_branch_id);perform private.security_page(p_offset,p_limit);
 return coalesce((select jsonb_agg(row_json order by created_at desc,id) from (select jsonb_build_object('id',n.id,'organization_id',n.organization_id,'branch_id',n.branch_id,
  'action',n.action,'title',n.title,'message',n.message,'created_at',private.offline_time(n.created_at),'read_at',private.offline_time(r.read_at)) row_json,n.created_at,n.id
  from private.security_notifications n left join private.security_notification_reads r on r.notification_id=n.id and r.actor_id=auth.uid()
  where private.security_notification_visible(p_organization_id,p_branch_id,n.id,auth.uid(),m.role)
  order by n.created_at desc,n.id offset p_offset limit p_limit) rows),'[]'::jsonb);
end; $$;
create function public.mark_security_notification_read(p_organization_id uuid,p_branch_id uuid,p_notification_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;r private.security_notification_reads;
begin
 m:=private.security_member(p_organization_id,p_branch_id);
 if not private.security_notification_visible(p_organization_id,p_branch_id,p_notification_id,auth.uid(),m.role) then raise exception 'Notification unavailable' using errcode='42501';end if;
 insert into private.security_notification_reads(notification_id,actor_id) values(p_notification_id,auth.uid()) on conflict do nothing;
 select * into r from private.security_notification_reads where notification_id=p_notification_id and actor_id=auth.uid();
 return jsonb_build_object('id',r.notification_id,'read_at',private.offline_time(r.read_at));
end; $$;

alter function public.complete_offline_device_enrollment(uuid,uuid,uuid,uuid,uuid,text) set schema private;
alter function private.complete_offline_device_enrollment(uuid,uuid,uuid,uuid,uuid,text) rename to offline_security_base_complete_offline_device_enrollment;
create function public.complete_offline_device_enrollment(p_actor_id uuid,p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_challenge_id uuid,p_signature text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.offline_require(p_actor_id,p_organization_id,p_branch_id);
 perform private.security_assert_offline_service(p_actor_id,p_organization_id,p_branch_id,p_device_id,'enroll');
 return private.offline_security_base_complete_offline_device_enrollment(p_actor_id,p_organization_id,p_branch_id,p_device_id,p_challenge_id,p_signature);
end; $$;
revoke all on function private.offline_security_base_complete_offline_device_enrollment(uuid,uuid,uuid,uuid,uuid,text),public.complete_offline_device_enrollment(uuid,uuid,uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.complete_offline_device_enrollment(uuid,uuid,uuid,uuid,uuid,text) to service_role;
alter function public.prepare_offline_grant(uuid,uuid,uuid,uuid,uuid,text,text) set schema private;
alter function private.prepare_offline_grant(uuid,uuid,uuid,uuid,uuid,text,text) rename to offline_security_base_prepare_offline_grant;
create function public.prepare_offline_grant(p_actor_id uuid,p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_request_id uuid,p_issuer text,p_key_id text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.offline_require(p_actor_id,p_organization_id,p_branch_id);
 perform private.security_assert_offline_service(p_actor_id,p_organization_id,p_branch_id,p_device_id,'prepare');
 return private.offline_security_base_prepare_offline_grant(p_actor_id,p_organization_id,p_branch_id,p_device_id,p_request_id,p_issuer,p_key_id);
end; $$;
revoke all on function private.offline_security_base_prepare_offline_grant(uuid,uuid,uuid,uuid,uuid,text,text),public.prepare_offline_grant(uuid,uuid,uuid,uuid,uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function public.prepare_offline_grant(uuid,uuid,uuid,uuid,uuid,text,text) to service_role;
alter function public.finalize_offline_grant(uuid,uuid,uuid,uuid,uuid,jsonb,text) set schema private;
alter function private.finalize_offline_grant(uuid,uuid,uuid,uuid,uuid,jsonb,text) rename to offline_security_base_finalize_offline_grant;
create function public.finalize_offline_grant(p_actor_id uuid,p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_grant_id uuid,p_claims jsonb,p_signature text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.offline_require(p_actor_id,p_organization_id,p_branch_id);
 perform private.security_assert_offline_service(p_actor_id,p_organization_id,p_branch_id,p_device_id,'prepare');
 return private.offline_security_base_finalize_offline_grant(p_actor_id,p_organization_id,p_branch_id,p_device_id,p_grant_id,p_claims,p_signature);
end; $$;
revoke all on function private.offline_security_base_finalize_offline_grant(uuid,uuid,uuid,uuid,uuid,jsonb,text),public.finalize_offline_grant(uuid,uuid,uuid,uuid,uuid,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.finalize_offline_grant(uuid,uuid,uuid,uuid,uuid,jsonb,text) to service_role;
alter function public.pull_offline_changes(uuid,uuid,uuid,uuid,bigint,integer) set schema private;
alter function private.pull_offline_changes(uuid,uuid,uuid,uuid,bigint,integer) rename to offline_security_base_pull_offline_changes;
create function public.pull_offline_changes(p_actor_id uuid,p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_cursor bigint,p_limit integer default 100) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.offline_require(p_actor_id,p_organization_id,p_branch_id);
 perform private.security_assert_offline_service(p_actor_id,p_organization_id,p_branch_id,p_device_id,'pull');
 return private.offline_security_base_pull_offline_changes(p_actor_id,p_organization_id,p_branch_id,p_device_id,p_cursor,p_limit);
end; $$;
revoke all on function private.offline_security_base_pull_offline_changes(uuid,uuid,uuid,uuid,bigint,integer),public.pull_offline_changes(uuid,uuid,uuid,uuid,bigint,integer) from public,anon,authenticated,service_role;
grant execute on function public.pull_offline_changes(uuid,uuid,uuid,uuid,bigint,integer) to service_role;
alter function public.release_offline_grant(uuid,uuid,uuid,uuid,uuid,bigint,text) set schema private;
alter function private.release_offline_grant(uuid,uuid,uuid,uuid,uuid,bigint,text) rename to offline_security_base_release_offline_grant;
create function public.release_offline_grant(p_actor_id uuid,p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_grant_id uuid,p_final_sequence bigint,p_signature text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.offline_require(p_actor_id,p_organization_id,p_branch_id);
 perform private.security_assert_offline_service(p_actor_id,p_organization_id,p_branch_id,p_device_id,'release');
 return private.offline_security_base_release_offline_grant(p_actor_id,p_organization_id,p_branch_id,p_device_id,p_grant_id,p_final_sequence,p_signature);
end; $$;
revoke all on function private.offline_security_base_release_offline_grant(uuid,uuid,uuid,uuid,uuid,bigint,text),public.release_offline_grant(uuid,uuid,uuid,uuid,uuid,bigint,text) from public,anon,authenticated,service_role;
grant execute on function public.release_offline_grant(uuid,uuid,uuid,uuid,uuid,bigint,text) to service_role;

alter function public.prepare_offline_device_challenge(uuid,uuid,uuid,text,text,text) set schema private;
alter function private.prepare_offline_device_challenge(uuid,uuid,uuid,text,text,text) rename to offline_security_base_challenge;
create function public.prepare_offline_device_challenge(p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_public_key text,p_device_name text,p_platform text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.require_active_member(p_organization_id);
 return private.offline_security_base_challenge(p_organization_id,p_branch_id,p_device_id,p_public_key,p_device_name,p_platform);
end; $$;
revoke all on function private.offline_security_base_challenge(uuid,uuid,uuid,text,text,text),public.prepare_offline_device_challenge(uuid,uuid,uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.prepare_offline_device_challenge(uuid,uuid,uuid,text,text,text) to authenticated;

-- All new tables are private and source-backed. History cannot be rewritten by
-- any API, including the trusted service boundary.
do $$ declare t text;f record;begin
 foreach t in array array['security_policies','security_policy_history','security_device_labels','security_grant_resolutions','security_requests','security_notifications','security_notification_reads','security_offline_authorizations'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
  if t<>'security_policies' then
   execute format('create trigger immutable_history before update or delete on private.%I for each row execute function private.reject_immutable_mutation()',t);
   execute format('create trigger immutable_no_truncate before truncate on private.%I for each statement execute function private.reject_immutable_mutation()',t);
  end if;
 end loop;
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and (p.proname like 'security_%' or p.proname in ('require_active_member','require_active_member_without_mfa')) loop
  execute 'revoke all on function '||f.signature||' from public,anon,authenticated,service_role';
 end loop;
end; $$;
revoke all on function public.authorize_offline_operation(uuid,uuid,uuid,text),public.get_security_policy(uuid),public.update_security_policy(uuid,uuid,bigint,integer,boolean,text),
 public.list_security_devices(uuid,uuid,integer,integer),public.update_security_device(uuid,uuid,uuid,uuid,text,text),
 public.revoke_security_device(uuid,uuid,uuid,uuid,text),public.list_security_grants(uuid,uuid,integer,integer),
 public.review_offline_grant(uuid,uuid,uuid,uuid,text,boolean,bigint,integer,bigint),public.list_security_notifications(uuid,uuid,integer,integer),
 public.mark_security_notification_read(uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.authorize_offline_operation(uuid,uuid,uuid,text),public.get_security_policy(uuid),public.update_security_policy(uuid,uuid,bigint,integer,boolean,text),
 public.list_security_devices(uuid,uuid,integer,integer),public.update_security_device(uuid,uuid,uuid,uuid,text,text),
 public.revoke_security_device(uuid,uuid,uuid,uuid,text),public.list_security_grants(uuid,uuid,integer,integer),
 public.review_offline_grant(uuid,uuid,uuid,uuid,text,boolean,bigint,integer,bigint),public.list_security_notifications(uuid,uuid,integer,integer),
 public.mark_security_notification_read(uuid,uuid,uuid) to authenticated;

-- Direct PostgREST table reads have the same assurance requirement as RPCs.
-- Restrictive policies intersect all existing tenant/branch/role policies;
-- they cannot grant a row which the original policies deny.
create function private.security_business_assurance(p_org uuid)
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 perform private.security_assert_privileged_mfa(p_org,auth.uid());
 return true;
exception when insufficient_privilege then return false;
end; $$;
create function private.security_own_membership(p_membership uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organization_memberships where id=p_membership and user_id=auth.uid());
$$;
create function private.security_profile_assurance(p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select p_user=auth.uid() or exists(select 1 from public.organization_memberships actor
  join public.organization_memberships target on target.organization_id=actor.organization_id and target.user_id=p_user
  where actor.user_id=auth.uid() and actor.status='active' and private.security_business_assurance(actor.organization_id));
$$;
revoke all on function private.security_business_assurance(uuid),private.security_own_membership(uuid),private.security_profile_assurance(uuid) from public,anon,authenticated,service_role;
grant execute on function private.security_business_assurance(uuid),private.security_own_membership(uuid),private.security_profile_assurance(uuid) to authenticated;
do $$ declare t record;begin
 for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  join pg_attribute a on a.attrelid=c.oid and a.attname='organization_id' and not a.attisdropped
  where n.nspname='public' and c.relkind='r' and c.relrowsecurity
   and c.relname not in ('organizations','branches','organization_memberships','membership_branches') loop
  execute format('create policy security_mfa_assurance on public.%I as restrictive for all to authenticated using(private.security_business_assurance(organization_id)) with check(private.security_business_assurance(organization_id))',t.relname);
 end loop;
end; $$;
create policy security_mfa_assurance on public.organization_memberships as restrictive for all to authenticated
 using(user_id=auth.uid() or private.security_business_assurance(organization_id))
 with check(user_id=auth.uid() or private.security_business_assurance(organization_id));
create policy security_mfa_assurance on public.membership_branches as restrictive for all to authenticated
 using(private.security_own_membership(membership_id) or private.security_business_assurance(organization_id))
 with check(private.security_own_membership(membership_id) or private.security_business_assurance(organization_id));
create policy security_mfa_assurance on public.profiles as restrictive for all to authenticated
 using(private.security_profile_assurance(user_id)) with check(private.security_profile_assurance(user_id));

commit;
