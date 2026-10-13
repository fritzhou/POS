-- Phase 6B: audited branch maintenance. No branch or financial history deletion.
begin;
alter table public.branches add column revision bigint not null default 1 check(revision between 1 and 9007199254740991);
revoke insert,update,delete,truncate on public.branches from service_role;
revoke update(name,code,address,active) on public.branches from service_role;
-- Catalog writes must use the existing counter-before-product RPCs.
revoke insert,update,delete,truncate on public.products,public.categories from service_role;
create table private.branch_actions(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 branch_id uuid not null,actor_id uuid not null references auth.users(id),request_id uuid not null,
 kind text not null check(kind in ('branch.create','branch.update')),document jsonb not null,
 foreign key(organization_id,branch_id) references public.branches(organization_id,id));
revoke all on private.branch_actions from public,anon,authenticated,service_role;
alter table private.branch_actions enable row level security;
create trigger immutable_history before update or delete on private.branch_actions for each row execute function private.reject_immutable_mutation();
create trigger immutable_no_truncate before truncate on private.branch_actions for each statement execute function private.reject_immutable_mutation();
create function private.branch_management_member(p_org uuid,p_branch uuid default null)
returns public.organization_memberships language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;
begin
 m:=private.require_active_member(p_org);
 if m.role not in ('owner','admin') then raise exception 'Branch administration required' using errcode='42501';end if;
 if p_branch is null then
  if not m.all_branches then raise exception 'All-branch administration required' using errcode='42501';end if;
 elsif not exists(select 1 from public.branches where organization_id=p_org and id=p_branch)
  or (not m.all_branches and not exists(select 1 from public.membership_branches where organization_id=p_org and membership_id=m.id and branch_id=p_branch)) then
  raise exception 'Branch outside current maintenance scope' using errcode='42501';
 end if;
 return m;
end;$$;
create function private.branch_document(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(b)||jsonb_build_object('created_at',private.offline_time(b.created_at)) from public.branches b where id=p_id;
$$;
create function private.branch_deactivation_check(p_org uuid,p_branch uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if (select count(*) from public.branches where organization_id=p_org and active)<=1 then raise exception 'At least one active branch must remain' using errcode='23514';end if;
 if exists(select 1 from private.stock_balances where organization_id=p_org and branch_id=p_branch and quantity<>0) then raise exception 'Resolve all branch stock and deficits before deactivation' using errcode='23514';end if;
 if exists(select 1 from public.shifts s where organization_id=p_org and branch_id=p_branch and not exists(select 1 from public.shift_closures c where c.shift_id=s.id)) then raise exception 'Close branch shifts before deactivation' using errcode='23514';end if;
 perform private.offline_abandon_expired_unsigned(p_org);
 if exists(select 1 from private.offline_grants g where organization_id=p_org and branch_id=p_branch
  and not exists(select 1 from private.offline_grant_releases r where r.grant_id=g.id)
  and not exists(select 1 from private.offline_grant_abandonments a where a.grant_id=g.id)) then
  raise exception 'Retained offline grants must remain reachable for reconciliation' using errcode='23514';end if;
 if exists(select 1 from public.purchase_orders o join private.purchase_order_states s on s.order_id=o.id
  where o.organization_id=p_org and o.branch_id=p_branch and s.status in ('ordered','partially_received')) then
  raise exception 'Resolve outstanding purchase orders before deactivation' using errcode='23514';end if;
end;$$;
create function public.get_branch_management_context(p_organization_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;
begin
 m:=private.require_active_member(p_organization_id);
 if m.role not in ('owner','admin') then raise exception 'Branch administration required' using errcode='42501';end if;
 return jsonb_build_object('organization_id',p_organization_id,'actor_id',auth.uid(),'can_create',m.all_branches,'can_set_active',m.all_branches,'maximum_active_branches',100);
end;$$;
create function public.list_managed_branches(p_organization_id uuid,p_offset integer default 0,p_limit integer default 51) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;r jsonb;
begin
 m:=private.require_active_member(p_organization_id);
 if m.role not in ('owner','admin') then raise exception 'Branch administration required' using errcode='42501';end if;
 perform private.purchase_page(p_offset,p_limit);
 select coalesce(jsonb_agg(private.branch_document(b.id) order by b.name,b.id),'[]'::jsonb) into r from
 (select b.* from public.branches b where organization_id=p_organization_id and (m.all_branches or exists(select 1 from public.membership_branches a where a.membership_id=m.id and a.branch_id=b.id and a.organization_id=p_organization_id)) order by name,id offset p_offset limit p_limit)b;
 return r;
end;$$;
create function public.save_branch(p_organization_id uuid,p_request_id uuid,p_branch_id uuid,p_expected_revision bigint,p_name text,p_code text,p_address text,p_active boolean,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;b public.branches;payload jsonb;result_id uuid;action jsonb;kind text;v_reason text:=btrim(p_reason);v_name text:=btrim(p_name);v_code text:=btrim(p_code);v_address text:=nullif(btrim(p_address),'');
begin
 m:=private.branch_management_member(p_organization_id,p_branch_id);
 kind:=case when p_branch_id is null then 'branch.create' else 'branch.update' end;
 -- Existing branch SHARE locks precede the feed counter in ordinary writers.
 -- NO KEY UPDATE permits counter-held FK KEY SHARE, unlike FOR UPDATE.
 if p_branch_id is not null then select * into b from public.branches where organization_id=p_organization_id and id=p_branch_id for no key update;end if;
 perform private.offline_counter_lock(p_organization_id);
 payload:=jsonb_build_object('branch_id',p_branch_id,'expected_revision',p_expected_revision,'name',v_name,'code',v_code,'address',v_address,'active',p_active,'reason',v_reason);
 result_id:=private.phase3_request(p_organization_id,p_request_id,kind,payload);
 if result_id is not null then return(select document from private.branch_actions where id=result_id);end if;
 if v_name is null or char_length(v_name) not between 1 and 120 or v_reason is null or char_length(v_reason) not between 3 and 1000 or char_length(v_address)>500 or p_active is null then raise exception 'Invalid branch details or reason' using errcode='22023';end if;
 if p_branch_id is null then
  if p_expected_revision is not null or not p_active or v_code is null or char_length(v_code) not between 1 and 32 then raise exception 'A new active branch needs a code and no previous revision' using errcode='22023';end if;
  if (select count(*) from public.branches where organization_id=p_organization_id and active)>=100 then raise exception 'Active branch limit reached' using errcode='23514';end if;
  insert into public.branches(organization_id,name,code,address) values(p_organization_id,v_name,v_code,v_address) returning * into b;
 else
  if p_expected_revision is null or p_expected_revision<>b.revision then raise exception 'Branch changed; reload before saving' using errcode='40001';end if;
  if v_code is distinct from b.code then raise exception 'Branch codes are immutable' using errcode='22023';end if;
  if p_active<>b.active then
   if not m.all_branches then raise exception 'All-branch administration required for status changes' using errcode='42501';end if;
   if not p_active then perform private.branch_deactivation_check(p_organization_id,b.id);
   elsif (select count(*) from public.branches where organization_id=p_organization_id and active)>=100 then raise exception 'Active branch limit reached' using errcode='23514';end if;
  end if;
  if b.revision>=9007199254740991 then raise exception 'Branch revision limit reached' using errcode='22023';end if;
  update public.branches set name=v_name,address=v_address,active=p_active,revision=revision+1 where id=b.id returning * into b;
 end if;
 result_id:=gen_random_uuid();
 action:=jsonb_build_object('request_id',p_request_id,'kind',kind,'actor_id',auth.uid(),'organization_id',p_organization_id,'branch',private.branch_document(b.id));
 insert into private.branch_actions values(result_id,p_organization_id,b.id,auth.uid(),p_request_id,kind,action);
 perform private.phase3_save_request(p_organization_id,p_request_id,kind,payload,result_id);
 perform private.append_action_audit(p_organization_id,kind,'branches',b.id,b.id,v_reason,jsonb_build_object('revision',b.revision,'active',b.active,'code',b.code));
 return action;
end;$$;
create function private.freeze_referenced_product_unit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.unit is distinct from old.unit and (exists(select 1 from public.stock_movements where product_id=old.id)
  or exists(select 1 from public.purchase_order_items where product_id=old.id)
  or exists(select 1 from private.offline_grants g where organization_id=old.organization_id
   and not exists(select 1 from private.offline_grant_releases r where r.grant_id=g.id)
   and not exists(select 1 from private.offline_grant_abandonments a where a.grant_id=g.id)
   and exists(select 1 from jsonb_array_elements(g.snapshot->'products') p where p->>'id'=old.id::text))) then
  raise exception 'Stock unit is referenced by existing goods or orders; use a new product for a different unit' using errcode='23514';end if;
 return new;
end;$$;
create trigger referenced_stock_unit before update of unit on public.products for each row execute function private.freeze_referenced_product_unit();
revoke all on function private.branch_management_member(uuid,uuid),private.branch_document(uuid),private.branch_deactivation_check(uuid,uuid),private.freeze_referenced_product_unit() from public,anon,authenticated,service_role;
revoke all on function public.get_branch_management_context(uuid),public.list_managed_branches(uuid,integer,integer),public.save_branch(uuid,uuid,uuid,bigint,text,text,text,boolean,text) from public,anon,authenticated,service_role;
grant execute on function public.get_branch_management_context(uuid),public.list_managed_branches(uuid,integer,integer),public.save_branch(uuid,uuid,uuid,bigint,text,text,text,boolean,text) to authenticated;
commit;
