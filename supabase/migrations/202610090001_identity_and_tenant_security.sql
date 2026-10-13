-- Run with the Supabase migration owner, never a client identity.
begin;
create schema if not exists private;
revoke all on schema private from public;
revoke create on schema public from public;
grant usage on schema public, private to authenticated;
grant usage on schema public to anon, service_role;
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema private revoke execute on functions from public;

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  business_name text not null check (char_length(btrim(business_name)) between 2 and 120),
  owner_user_id uuid not null unique references auth.users(id),
  currency text not null default 'PHP' check (currency ~ '^[A-Z]{3}$'),
  address text, contact text, logo_path text,
  created_at timestamptz not null default now()
);
create table public.branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  name text not null check (char_length(btrim(name)) between 1 and 120),
  code text not null check (char_length(btrim(code)) between 1 and 32),
  address text, active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, code), unique (organization_id, id)
);
create table public.profiles (
  user_id uuid primary key references auth.users(id),
  full_name text not null check (char_length(btrim(full_name)) between 2 and 120),
  phone text check (phone is null or char_length(phone) <= 40),
  created_at timestamptz not null default now()
);
create table public.organization_memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  user_id uuid not null references auth.users(id),
  role text not null check (role in ('owner','admin','manager','cashier','inventory_staff')),
  status text not null default 'pending' check (status in ('active','disabled','pending')),
  all_branches boolean not null default false,
  employee_id text check (employee_id is null or char_length(employee_id) between 1 and 64),
  created_at timestamptz not null default now(),
  unique (organization_id,user_id), unique (organization_id,employee_id), unique (organization_id,id),
  check (not all_branches or role in ('owner','admin')),
  check (role <> 'owner' or all_branches)
);
create table public.membership_branches (
  membership_id uuid not null, organization_id uuid not null, branch_id uuid not null,
  primary key (membership_id,branch_id),
  foreign key (organization_id,membership_id) references public.organization_memberships(organization_id,id),
  foreign key (organization_id,branch_id) references public.branches(organization_id,id)
);
create index memberships_user_active on public.organization_memberships(user_id,status,organization_id);
create index membership_branches_branch on public.membership_branches(organization_id,branch_id);

-- Definer helpers avoid recursive RLS. Every authorization consults current
-- database membership and JWT identity; user metadata never supplies roles.
create function private.has_organization_access(p_organization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.organization_memberships m
    where m.organization_id = p_organization_id and m.user_id = auth.uid() and m.status = 'active'
      and ((m.role in ('owner','admin') and m.all_branches) or exists (
        select 1 from public.membership_branches mb
        join public.branches b on b.organization_id = mb.organization_id and b.id = mb.branch_id
        where mb.membership_id = m.id and mb.organization_id = m.organization_id and b.active
      ))
  );
$$;
create function private.can_access_branch(p_organization_id uuid,p_branch_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.organization_memberships m
    join public.branches b on b.organization_id = m.organization_id and b.id = p_branch_id
    where m.organization_id = p_organization_id and m.user_id = auth.uid() and m.status = 'active' and b.active
      and ((m.role in ('owner','admin') and m.all_branches) or exists (
        select 1 from public.membership_branches mb
        where mb.organization_id = m.organization_id and mb.membership_id = m.id and mb.branch_id = b.id
      ))
  );
$$;
create function private.is_organization_admin(p_organization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.has_organization_access(p_organization_id) and exists (
    select 1 from public.organization_memberships m
    where m.organization_id = p_organization_id and m.user_id = auth.uid()
      and m.status = 'active' and m.role in ('owner','admin')
  );
$$;
create function private.can_read_membership_assignment(p_membership_id uuid,p_organization_id uuid,p_branch_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select (private.is_organization_admin(p_organization_id) and private.can_access_branch(p_organization_id,p_branch_id)) or exists (
    select 1 from public.organization_memberships m
    where m.id = p_membership_id and m.organization_id = p_organization_id
      and m.user_id = auth.uid() and m.status = 'active'
      and private.can_access_branch(p_organization_id,p_branch_id)
  );
$$;
create function private.can_read_profile(p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_user_id = auth.uid() or exists (
    select 1 from public.organization_memberships m
    where m.user_id = p_user_id and private.is_organization_admin(m.organization_id)
  );
$$;
revoke all on function private.has_organization_access(uuid),private.can_access_branch(uuid,uuid),
  private.is_organization_admin(uuid),private.can_read_membership_assignment(uuid,uuid,uuid),
  private.can_read_profile(uuid) from public,anon,authenticated,service_role;
grant execute on function private.has_organization_access(uuid),private.can_access_branch(uuid,uuid),
  private.is_organization_admin(uuid),private.can_read_membership_assignment(uuid,uuid,uuid),
  private.can_read_profile(uuid) to authenticated;

create function private.enforce_owner_membership()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.role = 'owner' and new.role <> 'owner' then
    raise exception 'Owner transfer requires a dedicated backend operation' using errcode = '23514';
  end if;
  if new.role = 'owner' and not exists (
    select 1 from public.organizations o where o.id = new.organization_id and o.owner_user_id = new.user_id
  ) then
    raise exception 'Owner membership must match organization owner' using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function private.enforce_owner_membership() from public,anon,authenticated,service_role;
create trigger enforce_owner_membership before insert or update on public.organization_memberships
  for each row execute function private.enforce_owner_membership();

alter table public.organizations enable row level security;
alter table public.branches enable row level security;
alter table public.profiles enable row level security;
alter table public.organization_memberships enable row level security;
alter table public.membership_branches enable row level security;
create policy organizations_read on public.organizations for select to authenticated
  using (private.has_organization_access(id));
create policy branches_read on public.branches for select to authenticated
  using (private.can_access_branch(organization_id,id));
create policy profiles_read on public.profiles for select to authenticated
  using (private.can_read_profile(user_id));
create policy profiles_update_self on public.profiles for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy memberships_read on public.organization_memberships for select to authenticated
  using (user_id = auth.uid() or private.is_organization_admin(organization_id));
create policy assignments_read on public.membership_branches for select to authenticated
  using (private.can_read_membership_assignment(membership_id,organization_id,branch_id));

revoke all on public.organizations,public.branches,public.profiles,
  public.organization_memberships,public.membership_branches from public,anon,authenticated,service_role;
grant select on public.organizations,public.branches,public.profiles,
  public.organization_memberships,public.membership_branches to authenticated;
grant update (full_name,phone) on public.profiles to authenticated;
grant select,insert on public.organizations,public.branches,public.profiles,
  public.organization_memberships,public.membership_branches to service_role;
grant update (business_name,currency,address,contact,logo_path) on public.organizations to service_role;
grant update (name,code,address,active) on public.branches to service_role;
grant update (full_name,phone) on public.profiles to service_role;
grant update (role,status,all_branches,employee_id) on public.organization_memberships to service_role;
commit;
