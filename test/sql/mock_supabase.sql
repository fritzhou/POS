-- Test database ONLY. Never deploy these roles or auth mocks to Supabase.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;
create schema auth;
create table auth.users (id uuid primary key,email text unique,email_confirmed_at timestamptz,
  encrypted_password text default 'test-only-nonsecret-password-present');
create function auth.uid() returns uuid language sql stable set search_path = '' as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
grant usage on schema auth to anon,authenticated,service_role;
grant execute on function auth.uid() to anon,authenticated,service_role;
-- Mimic Supabase's broad default grants: application migrations must explicitly
-- revoke them, including direct function grants, before applying least privilege.
alter default privileges grant all on tables to anon,authenticated,service_role;
alter default privileges grant execute on functions to anon,authenticated,service_role;
