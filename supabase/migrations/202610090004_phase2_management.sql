-- Phase 2: online management only. No checkout or financial ingestion.
begin;
alter table public.organizations add column revision bigint not null default 1 check (revision > 0),
  add column updated_at timestamptz not null default now(),
  add column tax_bps integer not null default 0 check (tax_bps between 0 and 10000),
  add column receipt_footer text check (char_length(receipt_footer) <= 1000);
alter table public.organization_memberships add column revision bigint not null default 1 check (revision > 0),
  add column updated_at timestamptz not null default now();
alter table public.organizations add constraint organizations_address_length check (char_length(address) <= 1000),
  add constraint organizations_contact_length check (char_length(contact) <= 1000),
  add constraint organizations_logo_length check (char_length(logo_path) <= 1024);
alter table public.products add constraint product_image_length check (char_length(image_path) <= 1024);
alter table public.products add constraint product_cost_transport_range check (cost_minor <= 9007199254740991),
  add constraint product_price_transport_range check (price_minor <= 9007199254740991);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),branch_id uuid,
  name text not null check (char_length(btrim(name)) between 1 and 160),
  contact_name text check (char_length(contact_name) <= 120),
  email text check (char_length(email) <= 254),phone text check (char_length(phone) <= 40),
  address text check (char_length(address) <= 1000),notes text check (char_length(notes) <= 2000),
  active boolean not null default true,revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
  unique (organization_id,id),foreign key (organization_id,branch_id) references public.branches(organization_id,id)
);
create table public.customers (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),branch_id uuid,
  name text not null check (char_length(btrim(name)) between 1 and 160),
  email text check (char_length(email) <= 254),phone text check (char_length(phone) <= 40),
  address text check (char_length(address) <= 1000),notes text check (char_length(notes) <= 2000),
  active boolean not null default true,revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
  unique (organization_id,id),foreign key (organization_id,branch_id) references public.branches(organization_id,id)
);
create index supplier_scope_name on public.suppliers(organization_id,branch_id,name);
create index customer_scope_name on public.customers(organization_id,branch_id,name);
alter table public.products add column supplier_id uuid,
  add constraint products_supplier_scope foreign key (organization_id,supplier_id) references public.suppliers(organization_id,id);

-- Internal helpers accept another identity ONLY for persisted invitations and
-- administrative target checks. They are never granted to application roles.
create function private.user_can_access_branch(p_organization_id uuid,p_branch_id uuid,p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.organization_memberships m
    join public.branches b on b.organization_id = m.organization_id and b.id = p_branch_id
    where m.organization_id = p_organization_id and m.user_id = p_user_id and m.status = 'active' and b.active
      and ((m.role in ('owner','admin') and m.all_branches) or exists (
        select 1 from public.membership_branches mb where mb.organization_id = m.organization_id
          and mb.membership_id = m.id and mb.branch_id = b.id
      ))
  );
$$;
revoke all on function private.user_can_access_branch(uuid,uuid,uuid) from public,anon,authenticated,service_role;

create function private.require_active_member(p_organization_id uuid)
returns public.organization_memberships language plpgsql security definer set search_path = '' as $$
declare v_member public.organization_memberships;
begin
  if auth.uid() is null or not exists (select 1 from auth.users u where u.id = auth.uid() and u.email_confirmed_at is not null) then
    raise exception 'A verified authenticated account is required' using errcode = '42501';
  end if;
  select m.* into v_member from public.organization_memberships m
    where m.organization_id = p_organization_id and m.user_id = auth.uid() and m.status = 'active' for share;
  if not found or not private.has_organization_access(p_organization_id) then
    raise exception 'Organization access is unavailable' using errcode = '42501';
  end if;
  return v_member;
end;
$$;
revoke all on function private.require_active_member(uuid) from public,anon,authenticated,service_role;

create function private.append_action_audit(p_organization_id uuid,p_action text,p_entity text,p_entity_id uuid,
  p_branch_id uuid,p_reason text,p_metadata jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_member public.organization_memberships;
begin
  v_member := private.require_active_member(p_organization_id);
  insert into public.audit_logs(organization_id,user_id,role,action,entity,entity_id,branch_id,reason,metadata)
    values (p_organization_id,auth.uid(),v_member.role,p_action,p_entity,p_entity_id,p_branch_id,p_reason,coalesce(p_metadata,'{}'::jsonb));
end;
$$;
revoke all on function private.append_action_audit(uuid,text,text,uuid,uuid,text,jsonb) from public,anon,authenticated,service_role;

create function private.can_read_directory(p_organization_id uuid,p_branch_id uuid,p_kind text)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.has_organization_access(p_organization_id) and exists (
    select 1 from public.organization_memberships m where m.organization_id = p_organization_id
      and m.user_id = auth.uid() and m.status = 'active'
      and ((p_kind = 'supplier' and m.role in ('owner','admin','manager','inventory_staff'))
        or (p_kind = 'customer' and m.role in ('owner','admin','manager','cashier')))
  ) and (p_branch_id is null or private.can_access_branch(p_organization_id,p_branch_id));
$$;
create function private.can_write_directory(p_organization_id uuid,p_branch_id uuid,p_kind text)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.has_organization_access(p_organization_id) and exists (
    select 1 from public.organization_memberships m where m.organization_id = p_organization_id
      and m.user_id = auth.uid() and m.status = 'active'
      and ((p_kind = 'supplier' and m.role in ('owner','admin','manager','inventory_staff'))
        or (p_kind = 'customer' and m.role in ('owner','admin','manager')))
      and ((p_branch_id is null and m.role in ('owner','admin') and m.all_branches)
        or (p_branch_id is not null and private.can_access_branch(p_organization_id,p_branch_id)))
  );
$$;
revoke all on function private.can_read_directory(uuid,uuid,text),private.can_write_directory(uuid,uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function private.can_read_directory(uuid,uuid,text) to authenticated;

alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
create policy suppliers_read on public.suppliers for select to authenticated
  using (private.can_read_directory(organization_id,branch_id,'supplier'));
create policy customers_read on public.customers for select to authenticated
  using (private.can_read_directory(organization_id,branch_id,'customer'));
revoke all on public.suppliers,public.customers from public,anon,authenticated,service_role;
grant select on public.suppliers,public.customers to authenticated;
grant select,insert,update on public.suppliers,public.customers to service_role;

create trigger suppliers_revision before update on public.suppliers for each row execute function private.advance_catalog_revision();
create trigger customers_revision before update on public.customers for each row execute function private.advance_catalog_revision();
create trigger organizations_revision before update on public.organizations for each row execute function private.advance_catalog_revision();
create trigger memberships_revision before update on public.organization_memberships for each row execute function private.advance_catalog_revision();

create function private.record_directory_audit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_role text;
begin
  select m.role into v_role from public.organization_memberships m
    where m.organization_id = new.organization_id and m.user_id = auth.uid() and m.status = 'active';
  insert into public.audit_logs(organization_id,user_id,role,action,entity,entity_id,branch_id,reason,metadata)
    values (new.organization_id,auth.uid(),coalesce(v_role,'system'),tg_table_name || '.' || lower(tg_op),tg_table_name,new.id,new.branch_id,
      nullif(current_setting('nexapos.audit_reason',true),''),jsonb_build_object('revision',new.revision));
  return null;
end;
$$;
revoke all on function private.record_directory_audit() from public,anon,authenticated,service_role;
create trigger suppliers_audit after insert or update on public.suppliers for each row execute function private.record_directory_audit();
create trigger customers_audit after insert or update on public.customers for each row execute function private.record_directory_audit();

-- Direct catalog writes are superseded by authenticated revision-checked RPCs.
-- Cost is absent from direct SELECT; list_products masks it for Cashiers.
revoke insert,update on public.categories,public.products from authenticated;
revoke insert (id,organization_id,name,active),update (name,active) on public.categories from authenticated;
revoke insert (id,organization_id,category_id,sku,barcode,name,image_path,cost_minor,price_minor,currency,reorder_level,unit,active),
  update (category_id,sku,barcode,name,image_path,cost_minor,price_minor,currency,reorder_level,unit,active) on public.products from authenticated;
revoke select on public.products from authenticated;
grant select (id,organization_id,category_id,sku,barcode,name,image_path,price_minor,currency,reorder_level,unit,active,revision,created_at,updated_at,supplier_id)
  on public.products to authenticated;

create function private.write_management_record(p_table text,p_organization_id uuid,p_id uuid,p_expected_revision bigint,p_values jsonb,p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_member public.organization_memberships;
  v_allowed text[]; v_defaults jsonb; v_old jsonb; v_payload jsonb; v_result jsonb;
  v_set text; v_branch uuid; v_key text;
begin
  v_member := private.require_active_member(p_organization_id);
  if p_reason is null or char_length(btrim(p_reason)) not between 3 and 1000 then
    raise exception 'An action reason of 3 to 1000 characters is required' using errcode = '22023';
  end if;
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    raise exception 'Values must be an object' using errcode = '22023';
  end if;
  if p_table = 'categories' then
    v_allowed := array['name','active']; v_defaults := '{"active":true}'::jsonb;
  elsif p_table = 'products' then
    v_allowed := array['category_id','supplier_id','sku','barcode','name','image_path','cost_minor','price_minor','currency','reorder_level','unit','active'];
    v_defaults := '{"active":true,"cost_minor":0,"price_minor":0,"currency":"PHP","reorder_level":0,"unit":"each"}'::jsonb;
  elsif p_table = 'suppliers' then
    v_allowed := array['name','branch_id','contact_name','email','phone','address','notes','active']; v_defaults := '{"active":true}'::jsonb;
  elsif p_table = 'customers' then
    v_allowed := array['name','branch_id','email','phone','address','notes','active']; v_defaults := '{"active":true}'::jsonb;
  else raise exception 'Unsupported management record' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p_values) loop
    if not v_key = any(v_allowed) then raise exception 'Unsupported record field: %',v_key using errcode = '22023'; end if;
  end loop;
  if p_table in ('categories','products') and v_member.role not in ('owner','admin','inventory_staff') then
    raise exception 'Catalog management is not permitted' using errcode = '42501';
  end if;
  if (p_table = 'suppliers' and v_member.role not in ('owner','admin','manager','inventory_staff'))
    or (p_table = 'customers' and v_member.role not in ('owner','admin','manager')) then
    raise exception 'Directory management is not permitted' using errcode = '42501';
  end if;
  perform set_config('nexapos.audit_reason',btrim(p_reason),true);
  if p_id is null then
    if p_expected_revision is not null then raise exception 'A new record has no expected revision' using errcode = '22023'; end if;
    v_payload := v_defaults || p_values || jsonb_build_object('id',gen_random_uuid(),'organization_id',p_organization_id,
      'revision',1,'created_at',now(),'updated_at',now());
  else
    if p_expected_revision is null or p_expected_revision < 1 then raise exception 'Expected revision is required' using errcode = '22023'; end if;
    execute format('select to_jsonb(t) from public.%I t where t.id=$1 and t.organization_id=$2 for update',p_table)
      into v_old using p_id,p_organization_id;
    if v_old is null then raise exception 'Record is unavailable in this organization' using errcode = 'P0002'; end if;
    if p_table in ('suppliers','customers') and not private.can_write_directory(p_organization_id,(v_old->>'branch_id')::uuid,
      case when p_table = 'suppliers' then 'supplier' else 'customer' end) then
      raise exception 'Record is outside the authorized branch' using errcode = '42501';
    end if;
    if (v_old->>'revision')::bigint <> p_expected_revision then raise exception 'The record changed; reload before saving' using errcode = '40001'; end if;
    v_payload := v_old || p_values;
  end if;
  if p_table in ('suppliers','customers') then
    v_branch := (v_payload->>'branch_id')::uuid;
    if not private.can_write_directory(p_organization_id,v_branch,case when p_table = 'suppliers' then 'supplier' else 'customer' end)
      or (v_old is not null and not private.can_write_directory(p_organization_id,(v_old->>'branch_id')::uuid,case when p_table = 'suppliers' then 'supplier' else 'customer' end)) then
      raise exception 'Directory management is outside the authorized branch or role' using errcode = '42501';
    end if;
  end if;
  if p_id is null then
    execute format('insert into public.%1$I select (jsonb_populate_record(null::public.%1$I,$1)).* returning to_jsonb(%1$I.*)',p_table)
      into v_result using v_payload;
  else
    select string_agg(format('%1$I=x.%1$I',k),',') into v_set from unnest(v_allowed) k;
    execute format('update public.%1$I t set %2$s from jsonb_populate_record(null::public.%1$I,$1) x where t.id=$2 and t.organization_id=$3 returning to_jsonb(t)',p_table,v_set)
      into v_result using v_payload,p_id,p_organization_id;
  end if;
  if p_table = 'products' then
    v_result := v_result || jsonb_build_object('reorder_level',(v_result->>'reorder_level')::numeric(18,4)::text);
  end if;
  return v_result;
exception when invalid_text_representation or numeric_value_out_of_range or check_violation or not_null_violation then
  raise exception 'One or more record values are invalid' using errcode = '22023';
end;
$$;
revoke all on function private.write_management_record(text,uuid,uuid,bigint,jsonb,text) from public,anon,authenticated,service_role;

create function public.save_category(p_organization_id uuid,p_id uuid,p_expected_revision bigint,p_values jsonb,p_reason text)
returns jsonb language sql security definer set search_path = '' as $$
  select private.write_management_record('categories',p_organization_id,p_id,p_expected_revision,p_values,p_reason);
$$;
revoke all on function public.save_category(uuid,uuid,bigint,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.save_category(uuid,uuid,bigint,jsonb,text) to authenticated;

create function public.save_product(p_organization_id uuid,p_id uuid,p_expected_revision bigint,p_values jsonb,p_reason text)
returns jsonb language sql security definer set search_path = '' as $$
  select private.write_management_record('products',p_organization_id,p_id,p_expected_revision,p_values,p_reason);
$$;
revoke all on function public.save_product(uuid,uuid,bigint,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.save_product(uuid,uuid,bigint,jsonb,text) to authenticated;

create function public.save_supplier(p_organization_id uuid,p_id uuid,p_expected_revision bigint,p_values jsonb,p_reason text)
returns jsonb language sql security definer set search_path = '' as $$
  select private.write_management_record('suppliers',p_organization_id,p_id,p_expected_revision,p_values,p_reason);
$$;
revoke all on function public.save_supplier(uuid,uuid,bigint,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.save_supplier(uuid,uuid,bigint,jsonb,text) to authenticated;

create function public.save_customer(p_organization_id uuid,p_id uuid,p_expected_revision bigint,p_values jsonb,p_reason text)
returns jsonb language sql security definer set search_path = '' as $$
  select private.write_management_record('customers',p_organization_id,p_id,p_expected_revision,p_values,p_reason);
$$;
revoke all on function public.save_customer(uuid,uuid,bigint,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.save_customer(uuid,uuid,bigint,jsonb,text) to authenticated;

alter table public.products add constraint product_storage_reference check (
  image_path is null or (image_path ~ '^[A-Za-z0-9._/-]+$' and split_part(image_path,'/',1) = organization_id::text
    and not (string_to_array(image_path,'/') && array['','.','..']))
);
alter table public.organizations add constraint organization_storage_reference check (
  logo_path is null or (logo_path ~ '^[A-Za-z0-9._/-]+$' and split_part(logo_path,'/',1) = id::text
    and not (string_to_array(logo_path,'/') && array['','.','..']))
);

create function public.list_products(p_organization_id uuid,p_query text default '',p_category_id uuid default null,
  p_active boolean default null,p_offset integer default 0,p_limit integer default 51)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_member public.organization_memberships; v_result jsonb;
begin
  v_member := private.require_active_member(p_organization_id);
  if p_limit is null or p_limit not between 1 and 101 or p_offset is null or p_offset not between 0 and 1000000
    or char_length(coalesce(p_query,'')) > 120 then raise exception 'Invalid catalog page' using errcode = '22023'; end if;
  select coalesce(jsonb_agg(row_json order by name,id),'[]'::jsonb) into v_result from (
    select p.name,p.id,to_jsonb(p) || jsonb_build_object('reorder_level',p.reorder_level::text,'cost_minor',case when v_member.role = 'cashier' then null else p.cost_minor end) row_json
    from public.products p where p.organization_id = p_organization_id
      and (p_category_id is null or p.category_id = p_category_id) and (p_active is null or p.active = p_active)
      and (coalesce(p_query,'') = '' or p.name ilike '%' || p_query || '%' or p.sku ilike '%' || p_query || '%' or p.barcode ilike '%' || p_query || '%')
    order by p.name,p.id offset p_offset limit p_limit
  ) page;
  return v_result;
end;
$$;
revoke all on function public.list_products(uuid,text,uuid,boolean,integer,integer) from public,anon,authenticated,service_role;
grant execute on function public.list_products(uuid,text,uuid,boolean,integer,integer) to authenticated;

create or replace function private.record_catalog_audit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();v_role text;
  v_org uuid := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
  v_id uuid := case when tg_op = 'DELETE' then old.id else new.id end;
begin
  select m.role into v_role from public.organization_memberships m
    where m.organization_id = v_org and m.user_id = v_actor and m.status = 'active';
  insert into public.audit_logs(organization_id,user_id,role,action,entity,entity_id,reason,metadata)
    values (v_org,v_actor,coalesce(v_role,'system'),tg_table_name || '.' || lower(tg_op),tg_table_name,v_id,
      nullif(current_setting('nexapos.audit_reason',true),''),
      case when tg_op = 'DELETE' then '{}'::jsonb else jsonb_build_object('revision',new.revision) end);
  return null;
end;
$$;
revoke all on function private.record_catalog_audit() from public,anon,authenticated,service_role;

create function private.employee_roster_access(p_organization_id uuid,p_membership_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.has_organization_access(p_organization_id) and exists (
    select 1 from public.organization_memberships actor
    join public.organization_memberships target on target.organization_id = actor.organization_id and target.id = p_membership_id
    where actor.organization_id = p_organization_id and actor.user_id = auth.uid() and actor.status = 'active'
      and actor.role in ('owner','admin') and (
        actor.role = 'owner' or target.user_id = actor.user_id or (
          target.role in ('manager','cashier','inventory_staff') and not target.all_branches
          and exists (select 1 from public.membership_branches mb where mb.membership_id = target.id)
          and not exists (select 1 from public.membership_branches mb where mb.membership_id = target.id
            and not private.can_access_branch(p_organization_id,mb.branch_id))
        )
      )
  );
$$;
revoke all on function private.employee_roster_access(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function private.employee_roster_access(uuid,uuid) to authenticated;
drop policy memberships_read on public.organization_memberships;
create policy memberships_read on public.organization_memberships for select to authenticated
  using (user_id = auth.uid() or private.employee_roster_access(organization_id,id));
create or replace function private.can_read_profile(p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_user_id = auth.uid() or exists (
    select 1 from public.organization_memberships m where m.user_id = p_user_id
      and private.employee_roster_access(m.organization_id,m.id)
  );
$$;
revoke all on function private.can_read_profile(uuid) from public,anon,authenticated,service_role;
grant execute on function private.can_read_profile(uuid) to authenticated;
create or replace function private.can_read_membership_assignment(p_membership_id uuid,p_organization_id uuid,p_branch_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select (private.employee_roster_access(p_organization_id,p_membership_id) and private.can_access_branch(p_organization_id,p_branch_id)) or exists (
    select 1 from public.organization_memberships m where m.id = p_membership_id and m.organization_id = p_organization_id
      and m.user_id = auth.uid() and m.status = 'active' and private.can_access_branch(p_organization_id,p_branch_id)
  );
$$;
revoke all on function private.can_read_membership_assignment(uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function private.can_read_membership_assignment(uuid,uuid,uuid) to authenticated;

create function public.employee_roster(p_organization_id uuid,p_status text default null,p_offset integer default 0,p_limit integer default 51)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_member public.organization_memberships; v_result jsonb;
begin
  v_member := private.require_active_member(p_organization_id);
  if v_member.role not in ('owner','admin') then raise exception 'Employee administration is not permitted' using errcode = '42501'; end if;
  if p_limit is null or p_limit not between 1 and 101 or p_offset is null or p_offset not between 0 and 1000000
    or (p_status is not null and p_status not in ('active','disabled','pending')) then raise exception 'Invalid employee page' using errcode = '22023'; end if;
  select coalesce(jsonb_agg(row_json order by full_name,id),'[]'::jsonb) into v_result from (
    select coalesce(p.full_name,'') full_name,m.id,to_jsonb(m) || jsonb_build_object('full_name',coalesce(p.full_name,''),'phone',p.phone,'email',u.email,
      'branch_ids',coalesce((select jsonb_agg(mb.branch_id order by mb.branch_id) from public.membership_branches mb where mb.membership_id = m.id),'[]'::jsonb)) row_json
    from public.organization_memberships m left join public.profiles p on p.user_id = m.user_id join auth.users u on u.id = m.user_id
    where m.organization_id = p_organization_id and private.employee_roster_access(p_organization_id,m.id)
      and (p_status is null or m.status = p_status)
    order by coalesce(p.full_name,''),m.id offset p_offset limit p_limit
  ) page;
  return v_result;
end;
$$;
revoke all on function public.employee_roster(uuid,text,integer,integer) from public,anon,authenticated,service_role;
grant execute on function public.employee_roster(uuid,text,integer,integer) to authenticated;

create function public.change_employee_access(p_organization_id uuid,p_membership_id uuid,p_role text,p_status text,
  p_all_branches boolean,p_branch_ids uuid[],p_expected_revision bigint,p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor public.organization_memberships;v_target public.organization_memberships;v_old public.organization_memberships;
  v_branch uuid;v_branches uuid[];v_old_branches uuid[];
begin
  v_actor := private.require_active_member(p_organization_id);
  if v_actor.role not in ('owner','admin') then raise exception 'Employee administration is not permitted' using errcode = '42501'; end if;
  if p_role is null or p_role not in ('admin','manager','cashier','inventory_staff') or p_status is null or p_status not in ('active','disabled')
    or p_all_branches is null or p_expected_revision is null or p_expected_revision < 1
    or p_reason is null or char_length(btrim(p_reason)) not between 3 and 1000 then
    raise exception 'Invalid employee access request' using errcode = '22023';
  end if;
  select m.* into v_target from public.organization_memberships m
    where m.organization_id = p_organization_id and m.id = p_membership_id for update;
  if not found then raise exception 'Employee is unavailable in this organization' using errcode = 'P0002'; end if;
  if v_target.role = 'owner' or v_target.user_id = auth.uid() then raise exception 'Owner and self access cannot be changed here' using errcode = '42501'; end if;
  if v_actor.role = 'admin' and (v_target.role = 'admin' or p_role = 'admin' or p_all_branches or not private.employee_roster_access(p_organization_id,v_target.id)) then
    raise exception 'Admin cannot change this employee or grant administrator access' using errcode = '42501';
  end if;
  if v_target.revision <> p_expected_revision then raise exception 'Employee access changed; reload before saving' using errcode = '40001'; end if;
  if p_all_branches and p_role <> 'admin' then raise exception 'Only an Admin can receive delegated all-branch access' using errcode = '22023'; end if;
  select coalesce(array_agg(distinct b order by b),'{}'::uuid[]) into v_branches from unnest(coalesce(p_branch_ids,'{}'::uuid[])) b;
  if array_position(v_branches,null) is not null or (not p_all_branches and cardinality(v_branches) = 0)
    or (p_all_branches and cardinality(v_branches) <> 0) then raise exception 'Branch assignments are invalid' using errcode = '22023'; end if;
  foreach v_branch in array v_branches loop
    if not private.can_access_branch(p_organization_id,v_branch) then raise exception 'A branch is outside the authorized scope' using errcode = '42501'; end if;
  end loop;
  select coalesce(array_agg(branch_id order by branch_id),'{}'::uuid[]) into v_old_branches from public.membership_branches where membership_id = v_target.id;
  v_old := v_target;
  perform set_config('nexapos.target_branch_ids',to_jsonb(v_branches)::text,true);
  update public.organization_memberships set role = p_role,status = p_status,all_branches = p_all_branches
    where id = v_target.id returning * into v_target;
  perform set_config('nexapos.target_branch_ids','',true);
  delete from public.membership_branches where membership_id = v_target.id;
  insert into public.membership_branches(membership_id,organization_id,branch_id)
    select v_target.id,p_organization_id,b from unnest(v_branches) b;
  perform private.append_action_audit(p_organization_id,'employee.access_changed','organization_memberships',v_target.id,null,btrim(p_reason),
    jsonb_build_object('previous_role',v_old.role,'role',v_target.role,'previous_status',v_old.status,'status',v_target.status,
      'previous_branch_ids',v_old_branches,'branch_ids',v_branches,'previous_all_branches',v_old.all_branches,'all_branches',v_target.all_branches,'revision',v_target.revision));
  return to_jsonb(v_target) || jsonb_build_object('branch_ids',v_branches,
    'full_name',coalesce((select p.full_name from public.profiles p where p.user_id=v_target.user_id),''),
    'phone',(select p.phone from public.profiles p where p.user_id=v_target.user_id),
    'email',(select u.email from auth.users u where u.id=v_target.user_id));
end;
$$;
revoke all on function public.change_employee_access(uuid,uuid,text,text,boolean,uuid[],bigint,text) from public,anon,authenticated,service_role;
grant execute on function public.change_employee_access(uuid,uuid,text,text,boolean,uuid[],bigint,text) to authenticated;

create function public.get_business_settings(p_organization_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_member public.organization_memberships;v_result jsonb;
begin
  v_member := private.require_active_member(p_organization_id);
  if v_member.role not in ('owner','admin') then raise exception 'Business settings access is not permitted' using errcode = '42501'; end if;
  select to_jsonb(o) into v_result from public.organizations o where o.id = p_organization_id;
  return v_result;
end;
$$;
create function private.record_business_audit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_role text;
begin
  select m.role into v_role from public.organization_memberships m where m.organization_id = new.id and m.user_id = auth.uid() and m.status = 'active';
  insert into public.audit_logs(organization_id,user_id,role,action,entity,entity_id,reason,metadata)
    values (new.id,auth.uid(),coalesce(v_role,'system'),'settings.business_updated','organizations',new.id,
      nullif(current_setting('nexapos.audit_reason',true),''),jsonb_build_object('revision',new.revision));
  return null;
end;
$$;
revoke all on function private.record_business_audit() from public,anon,authenticated,service_role;
create trigger business_settings_audit after update on public.organizations for each row execute function private.record_business_audit();
create function public.save_business_settings(p_organization_id uuid,p_expected_revision bigint,p_values jsonb,p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_member public.organization_memberships;v_old public.organizations;v_result jsonb;v_key text;v_payload jsonb;
begin
  v_member := private.require_active_member(p_organization_id);
  if v_member.role not in ('owner','admin') then raise exception 'Business settings management is not permitted' using errcode = '42501'; end if;
  if p_expected_revision is null or p_expected_revision < 1 or p_reason is null or char_length(btrim(p_reason)) not between 3 and 1000
    or p_values is null or jsonb_typeof(p_values) <> 'object' then raise exception 'Invalid business settings request' using errcode = '22023'; end if;
  for v_key in select jsonb_object_keys(p_values) loop
    if v_key not in ('business_name','address','contact','currency','logo_path','tax_bps','receipt_footer') then
      raise exception 'Unsupported business settings field: %',v_key using errcode = '22023'; end if;
  end loop;
  select o.* into v_old from public.organizations o where o.id = p_organization_id for update;
  if v_old.revision <> p_expected_revision then raise exception 'Settings changed; reload before saving' using errcode = '40001'; end if;
  v_payload := to_jsonb(v_old) || p_values;
  perform set_config('nexapos.audit_reason',btrim(p_reason),true);
  update public.organizations o set business_name=x.business_name,address=x.address,contact=x.contact,currency=x.currency,
    logo_path=x.logo_path,tax_bps=x.tax_bps,receipt_footer=x.receipt_footer
    from jsonb_populate_record(null::public.organizations,v_payload) x where o.id = p_organization_id returning to_jsonb(o) into v_result;
  return v_result;
exception when invalid_text_representation or numeric_value_out_of_range or check_violation or not_null_violation then
  raise exception 'One or more settings values are invalid' using errcode = '22023';
end;
$$;
revoke all on function public.get_business_settings(uuid),public.save_business_settings(uuid,bigint,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.get_business_settings(uuid),public.save_business_settings(uuid,bigint,jsonb,text) to authenticated;

-- Evaluate immutable event scope, never the target's current assignments.
create function private.can_read_audit(p_organization_id uuid,p_branch_id uuid,p_entity text,p_entity_id uuid,p_action text,p_metadata jsonb)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare v_actor public.organization_memberships;v_branches uuid[];v_branch uuid;
begin
  if not private.has_organization_access(p_organization_id) then return false; end if;
  select m.* into v_actor from public.organization_memberships m
    where m.organization_id=p_organization_id and m.user_id=auth.uid() and m.status='active';
  if not found then return false; end if;
  if v_actor.role='owner' or (v_actor.role='admin' and v_actor.all_branches) then return true; end if;
  if v_actor.role='admin' then
    if p_branch_id is not null and not private.can_access_branch(p_organization_id,p_branch_id) then return false; end if;
    if p_entity='organization_memberships' then
      if jsonb_typeof(p_metadata->'branch_ids') is distinct from 'array'
        or jsonb_typeof(p_metadata->'previous_branch_ids') is distinct from 'array'
        or p_metadata->'all_branches' is distinct from 'false'::jsonb
        or p_metadata->'previous_all_branches' is distinct from 'false'::jsonb
        or coalesce(p_metadata->>'role','owner') in ('owner','admin')
        or coalesce(p_metadata->>'previous_role','owner') in ('owner','admin') then return false; end if;
      select array_agg(distinct b) into v_branches from (
        select value::uuid b from jsonb_array_elements_text(p_metadata->'branch_ids')
        union select value::uuid b from jsonb_array_elements_text(p_metadata->'previous_branch_ids')
      ) scope;
    elsif p_entity='employee_invitations' then
      if jsonb_typeof(p_metadata->'branch_ids') is distinct from 'array'
        or p_metadata->'all_branches' is distinct from 'false'::jsonb then return false; end if;
      select array_agg(value::uuid) into v_branches from jsonb_array_elements_text(p_metadata->'branch_ids');
    else return true;
    end if;
    if coalesce(cardinality(v_branches),0)=0 then return false; end if;
    foreach v_branch in array v_branches loop
      if not private.can_access_branch(p_organization_id,v_branch) then return false; end if;
    end loop;
    return true;
  end if;
  return p_branch_id is not null and private.can_access_branch(p_organization_id,p_branch_id) and
    ((v_actor.role='manager' and p_entity in ('suppliers','customers')) or
      (v_actor.role='inventory_staff' and p_entity='suppliers'));
exception when invalid_text_representation then return false;
end;
$$;
revoke all on function private.can_read_audit(uuid,uuid,text,uuid,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.can_read_audit(uuid,uuid,text,uuid,text,jsonb) to authenticated;
drop policy audit_read_admin on public.audit_logs;
create policy audit_read_authorized on public.audit_logs for select to authenticated
  using (private.can_read_audit(organization_id,branch_id,entity,entity_id,action,metadata));
create function public.list_audit_logs(p_organization_id uuid,p_entity text default null,p_action text default null,p_branch_id uuid default null,
  p_offset integer default 0,p_limit integer default 51)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_member public.organization_memberships;v_result jsonb;
begin
  v_member := private.require_active_member(p_organization_id);
  if v_member.role = 'cashier' then raise exception 'Audit access is not permitted' using errcode = '42501'; end if;
  if p_limit is null or p_limit not between 1 and 101 or p_offset is null or p_offset not between 0 and 1000000
    or char_length(p_entity) > 80 or char_length(p_action) > 80 then raise exception 'Invalid audit page' using errcode = '22023'; end if;
  if p_branch_id is not null and (not exists(select 1 from public.branches b where b.id=p_branch_id and b.organization_id=p_organization_id)
    or (v_member.role<>'owner' and not (v_member.role='admin' and v_member.all_branches) and not private.can_access_branch(p_organization_id,p_branch_id))) then
    raise exception 'Requested audit branch is outside the authorized scope' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(row_json order by occurred_at desc,id desc),'[]'::jsonb) into v_result from (
    select a.occurred_at,a.id,to_jsonb(a) row_json from public.audit_logs a where a.organization_id = p_organization_id
      and private.can_read_audit(a.organization_id,a.branch_id,a.entity,a.entity_id,a.action,a.metadata) and (p_entity is null or a.entity = p_entity)
      and (p_action is null or a.action = p_action) and (p_branch_id is null or a.branch_id = p_branch_id)
    order by a.occurred_at desc,a.id desc offset p_offset limit p_limit
  ) page;
  return v_result;
end;
$$;
revoke all on function public.list_audit_logs(uuid,text,text,uuid,integer,integer) from public,anon,authenticated,service_role;
grant execute on function public.list_audit_logs(uuid,text,text,uuid,integer,integer) to authenticated;
-- Membership security snapshots must include BOTH the prior and requested branch
-- sets. The RPC supplies the latter; ordinary privileged updates retain current
-- assignments. Clients have neither direct writes nor trigger execution grants.
create or replace function private.record_membership_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_role text;v_previous uuid[];v_next jsonb;
begin
  if (old.role,old.status,old.all_branches) is distinct from (new.role,new.status,new.all_branches) then
    select m.role into v_role from public.organization_memberships m
      where m.organization_id=new.organization_id and m.user_id=auth.uid() and m.status='active';
    select coalesce(array_agg(branch_id order by branch_id),'{}'::uuid[]) into v_previous
      from public.membership_branches where membership_id=new.id;
    v_next := coalesce(nullif(current_setting('nexapos.target_branch_ids',true),'')::jsonb,to_jsonb(v_previous));
    insert into public.audit_logs(organization_id,user_id,role,action,entity,entity_id,metadata)
      values (new.organization_id,auth.uid(),coalesce(v_role,'system'),'membership.security_changed','organization_memberships',new.id,
        jsonb_build_object('previous_role',old.role,'role',new.role,'previous_status',old.status,'status',new.status,
          'previous_all_branches',old.all_branches,'all_branches',new.all_branches,'previous_branch_ids',v_previous,'branch_ids',v_next));
  end if;
  return null;
end;
$$;
revoke all on function private.record_membership_change() from public,anon,authenticated,service_role;
create or replace function private.enforce_owner_membership()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op='UPDATE' and old.role='owner' and new.role<>'owner' then
    raise exception 'Owner transfer requires a dedicated backend operation' using errcode='23514';
  end if;
  if new.role='owner' and (new.status<>'active' or not exists (
    select 1 from public.organizations o where o.id=new.organization_id and o.owner_user_id=new.user_id
  )) then raise exception 'Owner membership must remain active and match organization ownership' using errcode='23514'; end if;
  return new;
end;
$$;
revoke all on function private.enforce_owner_membership() from public,anon,authenticated,service_role;

commit;
