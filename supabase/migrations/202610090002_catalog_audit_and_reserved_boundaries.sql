begin;
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  name text not null check (char_length(btrim(name)) between 1 and 120),
  active boolean not null default true,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_id,id)
);
create unique index categories_org_name on public.categories(organization_id,lower(btrim(name)));
create table public.products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  category_id uuid,
  sku text not null check (char_length(btrim(sku)) between 1 and 64),
  barcode text check (barcode is null or char_length(btrim(barcode)) between 1 and 128),
  name text not null check (char_length(btrim(name)) between 1 and 160),
  image_path text,
  cost_minor bigint not null default 0 check (cost_minor >= 0),
  price_minor bigint not null default 0 check (price_minor >= 0),
  currency text not null default 'PHP' check (currency ~ '^[A-Z]{3}$'),
  reorder_level numeric(18,4) not null default 0 check (reorder_level >= 0),
  unit text not null default 'each' check (char_length(btrim(unit)) between 1 and 32),
  active boolean not null default true,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_id,id), unique (organization_id,sku), unique (organization_id,barcode),
  foreign key (organization_id,category_id) references public.categories(organization_id,id)
);
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  user_id uuid references auth.users(id),
  role text not null check (role in ('owner','admin','manager','cashier','inventory_staff','system')),
  action text not null check (char_length(action) between 1 and 80),
  entity text not null check (char_length(entity) between 1 and 80), entity_id uuid,
  branch_id uuid, device_id uuid,
  occurred_at timestamptz not null default now(),
  reason text check (reason is null or char_length(reason) <= 1000),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  foreign key (organization_id,branch_id) references public.branches(organization_id,id)
);
create index audit_scope_time on public.audit_logs(organization_id,occurred_at desc);

-- Reserved privileged envelope ONLY. No financial-ingestion RPC, checkout,
-- acceptance, idempotency algorithm, payments or stock projection is implemented.
create table public.financial_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id), branch_id uuid not null,
  actor_user_id uuid not null references auth.users(id),
  event_kind text not null check (char_length(event_kind) between 1 and 80),
  payload_digest bytea not null check (octet_length(payload_digest) = 32),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  recorded_at timestamptz not null default now(),
  foreign key (organization_id,branch_id) references public.branches(organization_id,id)
);
create table public.employee_invitations (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
  normalized_email text not null check (normalized_email = lower(btrim(normalized_email)) and char_length(normalized_email) between 3 and 254),
  full_name text not null check (char_length(btrim(full_name)) between 2 and 120),
  requested_role text not null check (requested_role in ('admin','manager','cashier','inventory_staff')),
  invited_by uuid not null references auth.users(id), branch_id uuid,
  all_branches boolean not null default false,
  token_digest bytea not null check (octet_length(token_digest) = 32),
  created_at timestamptz not null default now(), expires_at timestamptz not null,
  accepted_at timestamptz, revoked_at timestamptz,
  check (expires_at > created_at),
  check (not all_branches or requested_role = 'admin'),
  check (branch_id is not null or (requested_role = 'admin' and all_branches)),
  foreign key (organization_id,branch_id) references public.branches(organization_id,id)
);
create unique index invitation_digest_unique on public.employee_invitations(token_digest);

create function private.can_read_invitation(p_organization_id uuid,p_branch_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_organization_admin(p_organization_id) and (
    (p_branch_id is not null and private.can_access_branch(p_organization_id,p_branch_id))
    or (p_branch_id is null and exists (
      select 1 from public.organization_memberships m
      where m.organization_id = p_organization_id and m.user_id = auth.uid()
        and m.status = 'active' and m.role in ('owner','admin') and m.all_branches
    ))
  );
$$;
revoke all on function private.can_read_invitation(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function private.can_read_invitation(uuid,uuid) to authenticated;

create function private.reject_immutable_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'Immutable history cannot be updated, deleted, or truncated' using errcode = '42501';
end;
$$;
revoke all on function private.reject_immutable_mutation() from public,anon,authenticated,service_role;
create trigger audit_immutable before update or delete on public.audit_logs
  for each row execute function private.reject_immutable_mutation();
create trigger audit_no_truncate before truncate on public.audit_logs
  for each statement execute function private.reject_immutable_mutation();
create trigger financial_immutable before update or delete on public.financial_events
  for each row execute function private.reject_immutable_mutation();
create trigger financial_no_truncate before truncate on public.financial_events
  for each statement execute function private.reject_immutable_mutation();

create function private.advance_catalog_revision()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.revision := old.revision + 1;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;
revoke all on function private.advance_catalog_revision() from public,anon,authenticated,service_role;
create trigger categories_revision before update on public.categories
  for each row execute function private.advance_catalog_revision();
create trigger products_revision before update on public.products
  for each row execute function private.advance_catalog_revision();

create function private.record_catalog_audit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_role text;
  v_org uuid := case when tg_op = 'DELETE' then old.organization_id else new.organization_id end;
  v_id uuid := case when tg_op = 'DELETE' then old.id else new.id end;
begin
  select m.role into v_role from public.organization_memberships m
    where m.organization_id = v_org and m.user_id = v_actor and m.status = 'active';
  insert into public.audit_logs(organization_id,user_id,role,action,entity,entity_id,metadata)
  values (v_org,v_actor,coalesce(v_role,'system'),tg_table_name || '.' || lower(tg_op),tg_table_name,v_id,
    case when tg_op = 'DELETE' then '{}'::jsonb else jsonb_build_object('revision',new.revision) end);
  return null;
end;
$$;
revoke all on function private.record_catalog_audit() from public,anon,authenticated,service_role;
create trigger categories_audit after insert or update or delete on public.categories
  for each row execute function private.record_catalog_audit();
create trigger products_audit after insert or update or delete on public.products
  for each row execute function private.record_catalog_audit();

create function private.record_membership_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_role text;
begin
  if (old.role,old.status,old.all_branches) is distinct from (new.role,new.status,new.all_branches) then
    select m.role into v_role from public.organization_memberships m
      where m.organization_id = new.organization_id and m.user_id = auth.uid() and m.status = 'active';
    insert into public.audit_logs(organization_id,user_id,role,action,entity,entity_id,metadata)
    values (new.organization_id,auth.uid(),coalesce(v_role,'system'),'membership.security_changed',
      'organization_memberships',new.id,jsonb_build_object('previous_role',old.role,'role',new.role,
        'previous_status',old.status,'status',new.status,'all_branches',new.all_branches));
  end if;
  return null;
end;
$$;
revoke all on function private.record_membership_change() from public,anon,authenticated,service_role;
create trigger memberships_security_audit after update on public.organization_memberships
  for each row execute function private.record_membership_change();

alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.audit_logs enable row level security;
alter table public.financial_events enable row level security;
alter table public.employee_invitations enable row level security;
create policy categories_read on public.categories for select to authenticated using (private.has_organization_access(organization_id));
create policy categories_insert on public.categories for insert to authenticated with check (private.is_organization_admin(organization_id));
create policy categories_update on public.categories for update to authenticated
  using (private.is_organization_admin(organization_id)) with check (private.is_organization_admin(organization_id));
create policy products_read on public.products for select to authenticated using (private.has_organization_access(organization_id));
create policy products_insert on public.products for insert to authenticated with check (private.is_organization_admin(organization_id));
create policy products_update on public.products for update to authenticated
  using (private.is_organization_admin(organization_id)) with check (private.is_organization_admin(organization_id));
create policy audit_read_admin on public.audit_logs for select to authenticated
  using (private.is_organization_admin(organization_id) and
    (branch_id is null or private.can_access_branch(organization_id,branch_id)));
create policy invitations_read_admin on public.employee_invitations for select to authenticated
  using (private.can_read_invitation(organization_id,branch_id));
-- There is deliberately no financial_events client policy.
revoke all on public.categories,public.products,public.audit_logs,public.financial_events,
  public.employee_invitations from public,anon,authenticated,service_role;
grant select on public.categories,public.products,public.audit_logs to authenticated;
grant insert (id,organization_id,name,active) on public.categories to authenticated;
grant update (name,active) on public.categories to authenticated;
grant insert (id,organization_id,category_id,sku,barcode,name,image_path,cost_minor,price_minor,currency,reorder_level,unit,active)
  on public.products to authenticated;
grant update (category_id,sku,barcode,name,image_path,cost_minor,price_minor,currency,reorder_level,unit,active)
  on public.products to authenticated;
grant select (id,organization_id,normalized_email,full_name,requested_role,invited_by,branch_id,
  all_branches,created_at,expires_at,accepted_at,revoked_at) on public.employee_invitations to authenticated;
grant select,insert,update on public.categories,public.products,public.employee_invitations to service_role;
grant select,insert on public.audit_logs,public.financial_events to service_role;
commit;
