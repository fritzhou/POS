begin;
create function public.bootstrap_organization(p_business_name text,p_full_name text)
returns table(organization_id uuid,branch_id uuid,membership_id uuid,role text)
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_confirmed timestamptz;
  v_org uuid;
  v_branch uuid;
  v_membership uuid;
begin
  if v_user is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;
  if p_business_name is null or char_length(btrim(p_business_name)) not between 2 and 120
    or p_full_name is null or char_length(btrim(p_full_name)) not between 2 and 120 then
    raise exception 'Business name and full name must contain 2 to 120 characters' using errcode = '22023';
  end if;
  -- Locking the identity serializes concurrent bootstrap attempts. The unique
  -- owner_user_id and organization/user constraints independently prevent copies.
  select u.email_confirmed_at into v_confirmed from auth.users u where u.id = v_user for update;
  if not found or v_confirmed is null then
    raise exception 'A verified email account is required' using errcode = '42501';
  end if;
  select o.id into v_org from public.organizations o where o.owner_user_id = v_user;
  if v_org is not null then
    select m.id into v_membership from public.organization_memberships m
      where m.organization_id = v_org and m.user_id = v_user and m.role = 'owner' and m.status = 'active';
    if v_membership is null then
      raise exception 'Organization access is disabled or requires administrator review' using errcode = '42501';
    end if;
    select b.id into v_branch from public.branches b
      where b.organization_id = v_org and b.code = 'MAIN' and b.active;
    if v_branch is null then
      raise exception 'Main Branch requires administrator review' using errcode = '42501';
    end if;
    return query select v_org,v_branch,v_membership,'owner'::text;
    return;
  end if;
  insert into public.profiles(user_id,full_name) values (v_user,btrim(p_full_name))
    on conflict (user_id) do nothing;
  insert into public.organizations(business_name,owner_user_id)
    values (btrim(p_business_name),v_user) returning id into v_org;
  insert into public.branches(organization_id,name,code)
    values (v_org,'Main Branch','MAIN') returning id into v_branch;
  insert into public.organization_memberships(organization_id,user_id,role,status,all_branches)
    values (v_org,v_user,'owner','active',true) returning id into v_membership;
  insert into public.membership_branches(membership_id,organization_id,branch_id)
    values (v_membership,v_org,v_branch);
  insert into public.audit_logs(organization_id,user_id,role,action,entity,entity_id,branch_id,metadata)
    values (v_org,v_user,'owner','organization.bootstrap','organizations',v_org,v_branch,
      jsonb_build_object('membership_id',v_membership));
  return query select v_org,v_branch,v_membership,'owner'::text;
end;
$$;
revoke all on function public.bootstrap_organization(text,text) from public,anon,authenticated,service_role;
grant execute on function public.bootstrap_organization(text,text) to authenticated;
comment on function public.bootstrap_organization(text,text) is
  'Verified JWT-bound first owner setup. Transactional and serialized per identity; repeated calls return the same organization.';
commit;
