-- Phase 4. The service boundary requires Auth /user and Ed25519 proofs in
-- offline-sync. SQL independently rechecks current authority and every frozen
-- financial invariant. Service credentials are a trusted administrative boundary.
begin;

create function private.offline_canonical(p_value jsonb)
returns text language plpgsql immutable set search_path='' as $$
declare k text; v jsonb; r text; first boolean:=true;
begin
 case jsonb_typeof(p_value)
 when 'object' then
  r:='{';
  for k,v in select key,value from jsonb_each(p_value) order by key collate "C" loop
   if not first then r:=r||','; end if; first:=false;
   r:=r||to_json(k)::text||':'||private.offline_canonical(v);
  end loop; return r||'}';
 when 'array' then
  r:='[';
  for v in select value from jsonb_array_elements(p_value) loop
   if not first then r:=r||','; end if; first:=false;
   r:=r||private.offline_canonical(v);
  end loop; return r||']';
 when 'number' then
  perform private.phase3_integer(p_value,-9007199254740991,9007199254740991);
  return p_value::text;
 when 'string','boolean','null' then return p_value::text;
 else raise exception 'Unsupported canonical JSON' using errcode='22023';
 end case;
end; $$;
create function private.offline_digest(p_value jsonb)
returns text language sql immutable set search_path='' as $$
 select encode(sha256(convert_to(private.offline_canonical(p_value),'UTF8')),'hex');
$$;
create function private.offline_check_keys(p_value jsonb,p_keys text[])
returns void language plpgsql immutable set search_path='' as $$
begin
 perform private.phase3_check_keys(p_value,p_keys);
 if (select count(*) from jsonb_object_keys(p_value))<>cardinality(p_keys) then
  raise exception 'Every immutable offline field is required' using errcode='22023';
 end if;
end; $$;
create function private.offline_uuid(p_value jsonb)
returns uuid language plpgsql immutable set search_path='' as $$
begin
 if jsonb_typeof(p_value) is distinct from 'string' or p_value#>>'{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  raise exception 'Canonical immutable UUID required' using errcode='22023';
 end if;
 return (p_value#>>'{}')::uuid;
end; $$;
create function private.offline_time(p_time timestamptz)
returns text language sql immutable set search_path='' as $$
 select to_char(p_time at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
$$;
create function private.offline_require(p_actor uuid,p_org uuid,p_branch uuid)
returns public.organization_memberships language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;
begin
 perform 1 from auth.users where id=p_actor and email_confirmed_at is not null for share;
 if not found then raise exception 'Verified account required' using errcode='42501'; end if;
 select * into m from public.organization_memberships where organization_id=p_org and user_id=p_actor and status='active' for share;
 if not found or m.role not in ('owner','admin','manager','cashier') then raise exception 'Active POS membership required' using errcode='42501'; end if;
 perform 1 from public.branches where organization_id=p_org and id=p_branch and active for share;
 if not found then raise exception 'Active branch required' using errcode='42501'; end if;
 if not (m.role in ('owner','admin') and m.all_branches) then
  perform 1 from public.membership_branches where organization_id=p_org and membership_id=m.id and branch_id=p_branch for share;
  if not found then raise exception 'Current branch assignment required' using errcode='42501'; end if;
 end if;
 return m;
end; $$;

create table private.offline_device_challenges (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,branch_id uuid not null,
 actor_id uuid not null references auth.users(id),device_id uuid not null,public_key text not null check(public_key ~ '^[A-Za-z0-9_-]{43}$'),
 device_name text not null check(char_length(btrim(device_name)) between 1 and 120),platform text not null check(platform in ('android','windows','linux','macos','ios')),
 nonce text not null,created_at timestamptz not null default clock_timestamp(),expires_at timestamptz not null,
 foreign key(organization_id,branch_id) references public.branches(organization_id,id)
);
create table private.offline_devices (
 id uuid primary key,organization_id uuid not null,branch_id uuid not null,actor_id uuid not null references auth.users(id),
 public_key text not null check(public_key ~ '^[A-Za-z0-9_-]{43}$'),device_name text not null,platform text not null,
 challenge_id uuid not null unique references private.offline_device_challenges(id),enrollment_signature text not null check(enrollment_signature ~ '^[A-Za-z0-9_-]{86}$'),
 enrolled_at timestamptz not null default clock_timestamp(),unique(organization_id,branch_id,actor_id,id),unique(organization_id,actor_id,id),
 foreign key(organization_id,branch_id) references public.branches(organization_id,id)
);
create table private.offline_device_revocations (
 device_id uuid primary key references private.offline_devices(id),revoked_by uuid not null references auth.users(id),
 reason text not null check(char_length(btrim(reason)) between 3 and 1000),revoked_at timestamptz not null default clock_timestamp()
);
-- One OS key is retained per actor/organization. Additional authorized
-- branches require their own fresh challenge and proof, without replacing it.
create table private.offline_device_branches (
 device_id uuid not null,organization_id uuid not null,branch_id uuid not null,actor_id uuid not null,
 challenge_id uuid not null unique references private.offline_device_challenges(id),
 enrollment_signature text not null check(enrollment_signature ~ '^[A-Za-z0-9_-]{86}$'),
 enrolled_at timestamptz not null default clock_timestamp(),primary key(device_id,branch_id),unique(organization_id,branch_id,actor_id,device_id),
 foreign key(organization_id,actor_id,device_id) references private.offline_devices(organization_id,actor_id,id),
 foreign key(organization_id,branch_id) references public.branches(organization_id,id)
);
create table private.offline_device_proofs (
 challenge_id uuid primary key references private.offline_device_challenges(id),device_id uuid not null,branch_id uuid not null,
 signature text not null check(signature ~ '^[A-Za-z0-9_-]{86}$'),verified_at timestamptz not null default clock_timestamp(),
 foreign key(device_id,branch_id) references private.offline_device_branches(device_id,branch_id)
);
create table private.offline_grants (
 id uuid primary key,organization_id uuid not null,branch_id uuid not null,actor_id uuid not null,device_id uuid not null,membership_id uuid not null,
 request_id uuid not null,shift_id uuid not null,claims jsonb not null,snapshot jsonb not null,snapshot_digest text not null,
 issued_at timestamptz not null,expires_at timestamptz not null,max_events integer not null check(max_events between 1 and 1000),
 max_total_minor bigint not null check(max_total_minor between 1 and 100000000),
 unique(organization_id,actor_id,device_id,request_id),unique(organization_id,branch_id,actor_id,device_id,id),
 foreign key(organization_id,branch_id,actor_id,device_id) references private.offline_device_branches(organization_id,branch_id,actor_id,device_id),
 foreign key(organization_id,membership_id) references public.organization_memberships(organization_id,id),
 foreign key(organization_id,branch_id,shift_id) references public.shifts(organization_id,branch_id,id),
 check(expires_at>issued_at and expires_at<=issued_at+interval '8 hours')
);
create table private.offline_grant_signatures (
 grant_id uuid primary key references private.offline_grants(id),signature text not null check(signature ~ '^[A-Za-z0-9_-]{86}$'),
 signed_at timestamptz not null default clock_timestamp()
);
create table private.offline_grant_states (
 grant_id uuid primary key references private.offline_grants(id),last_sequence bigint not null default 0,total_minor bigint not null default 0,
 check(last_sequence between 0 and 1000),check(total_minor between 0 and 100000000)
);
create table private.offline_grant_releases (
 grant_id uuid primary key references private.offline_grants(id),final_sequence bigint not null check(final_sequence between 0 and 1000),
 signature text not null check(signature ~ '^[A-Za-z0-9_-]{86}$'),released_at timestamptz not null default clock_timestamp()
);
create table private.offline_grant_abandonments (
 grant_id uuid primary key references private.offline_grants(id),reason text not null check(reason='EXPIRED_UNSIGNED'),
 recorded_at timestamptz not null default clock_timestamp()
);
create table private.offline_event_outcomes (
 event_id uuid primary key,organization_id uuid not null,branch_id uuid not null,actor_id uuid not null,device_id uuid not null,grant_id uuid not null,
 sequence bigint not null,document_id uuid not null unique,event jsonb not null,digest text not null check(digest ~ '^[0-9a-f]{64}$'),
 authorization_payload jsonb not null,signature text not null check(signature ~ '^[A-Za-z0-9_-]{86}$'),result jsonb not null,
 recorded_at timestamptz not null default clock_timestamp(),unique(grant_id,sequence),
 foreign key(organization_id,branch_id,actor_id,device_id,grant_id) references private.offline_grants(organization_id,branch_id,actor_id,device_id,id)
);
create table private.offline_sale_sources (
 sale_id uuid primary key references public.sales(id),event_id uuid not null unique,grant_id uuid not null references private.offline_grants(id),
 organization_id uuid not null,branch_id uuid not null,actor_id uuid not null,provisional_receipt text not null,
 foreign key(organization_id,branch_id,sale_id) references public.sales(organization_id,branch_id,id)
);
-- Online receipt readers share the same immutable offline document identity.
-- Existing request-registry semantics remain unchanged for online sales.
alter function private.phase3_sale_json(uuid) rename to phase3_sale_json_online;
create function private.phase3_sale_json(p_sale uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select private.phase3_sale_json_online(p_sale)||jsonb_build_object('request_id',coalesce(
  (select request_id from private.operation_requests where result_id=p_sale and kind='sale.checkout'),
  (select event_id from private.offline_sale_sources where sale_id=p_sale)));
$$;
revoke all on function private.phase3_sale_json(uuid) from public,anon,authenticated,service_role;
create table private.offline_reconciliation_cases (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,branch_id uuid not null,actor_id uuid not null,device_id uuid not null,
 event_id uuid not null,grant_id uuid not null references private.offline_grants(id),code text not null,details jsonb not null,
 created_at timestamptz not null default clock_timestamp(),unique(event_id,code),
 foreign key(organization_id,branch_id) references public.branches(organization_id,id)
);
create table private.offline_change_counters (organization_id uuid primary key references public.organizations(id),revision bigint not null default 0 check(revision between 0 and 9007199254740991));
create table private.offline_changes (
 organization_id uuid not null,revision bigint not null,branch_id uuid,kind text not null,id uuid not null,deleted boolean not null,value jsonb not null,
 primary key(organization_id,revision),foreign key(organization_id,branch_id) references public.branches(organization_id,id)
);
create index offline_grants_shift on private.offline_grants(shift_id);
create index offline_changes_scope on private.offline_changes(organization_id,branch_id,revision);

create function private.offline_device_require(p_actor uuid,p_org uuid,p_branch uuid,p_device uuid)
returns private.offline_devices language plpgsql security definer set search_path='' as $$
declare d private.offline_devices;
begin
 perform private.offline_require(p_actor,p_org,p_branch);
 select devices.* into d from private.offline_devices devices join private.offline_device_branches binding on binding.device_id=devices.id
  where binding.organization_id=p_org and binding.branch_id=p_branch and binding.actor_id=p_actor and devices.id=p_device for share of devices,binding;
 if not found or exists(select 1 from private.offline_device_revocations where device_id=d.id) then raise exception 'Enrolled active device required' using errcode='42501'; end if;
 return d;
end; $$;
create function private.offline_counter_lock(p_org uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare r bigint;
begin
 insert into private.offline_change_counters(organization_id) values(p_org) on conflict do nothing;
 select revision into r from private.offline_change_counters where organization_id=p_org for update;
 return r;
end; $$;
create function private.offline_change(p_org uuid,p_branch uuid,p_kind text,p_id uuid,p_deleted boolean,p_value jsonb)
returns bigint language plpgsql security definer set search_path='' as $$
declare r bigint;
begin
 r:=private.offline_counter_lock(p_org)+1;
 update private.offline_change_counters set revision=r where organization_id=p_org;
 insert into private.offline_changes(organization_id,revision,branch_id,kind,id,deleted,value) values(p_org,r,p_branch,p_kind,p_id,p_deleted,p_value);
 return r;
end; $$;
create function private.offline_product_json(p public.products)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('id',p.id,'organization_id',p.organization_id,'category_id',p.category_id,'sku',p.sku,'barcode',p.barcode,'name',p.name,
 'price_minor',p.price_minor,'currency',p.currency,'unit',p.unit,'active',p.active,'revision',p.revision);
$$;
create function private.offline_context_json(p_org uuid,p_branch uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('organization_id',o.id,'branch_id',b.id,'branch_name',b.name,'branch_code',b.code,'currency',o.currency,
 'tax_bps',o.tax_bps,'settings_revision',o.revision,'business_name',o.business_name,'address',o.address,'contact',o.contact,'receipt_footer',o.receipt_footer)
 from public.organizations o join public.branches b on b.organization_id=o.id and b.id=p_branch where o.id=p_org;
$$;
create function private.offline_catalog_change()
returns trigger language plpgsql security definer set search_path='' as $$
declare v jsonb;
begin
 if tg_table_name='products' then v:=private.offline_product_json(new);
 else v:=jsonb_build_object('id',new.id,'organization_id',new.organization_id,'name',new.name,'active',new.active,'revision',new.revision); end if;
 perform private.offline_change(new.organization_id,null,case when tg_table_name='products' then 'product' else 'category' end,new.id,not new.active,v);
 return new;
end; $$;
create trigger offline_catalog_feed after insert or update on public.products for each row execute function private.offline_catalog_change();
create trigger offline_category_feed after insert or update on public.categories for each row execute function private.offline_catalog_change();
create function private.offline_settings_change()
returns trigger language plpgsql security definer set search_path='' as $$
declare b public.branches;
begin
 for b in select * from public.branches where organization_id=new.id and active order by id loop
  perform private.offline_change(new.id,b.id,'context',b.id,false,private.offline_context_json(new.id,b.id));
 end loop;
 return new;
end; $$;
create trigger offline_settings_feed after update on public.organizations for each row execute function private.offline_settings_change();
create function private.offline_branch_change()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform private.offline_change(new.organization_id,new.id,'context',new.id,not new.active,private.offline_context_json(new.organization_id,new.id));
 return new;
end; $$;
create trigger offline_branch_feed after insert or update on public.branches for each row execute function private.offline_branch_change();

-- Signed deficits are possible ONLY when a sealed sale has a retained trusted
-- offline source. Session variables and ordinary client flags cannot enable it.
alter table private.stock_balances drop constraint stock_balances_quantity_check;
alter table private.stock_balances add constraint stock_balances_quantity_check check(quantity between -9007199254740991 and 9007199254740991);
alter table private.stock_balances add column revision bigint not null default 0 check(revision between 0 and 9007199254740991);
update private.stock_balances b set revision=(select count(*) from public.stock_movements m where m.organization_id=b.organization_id and m.branch_id=b.branch_id and m.product_id=b.product_id);
alter table public.stock_movements drop constraint stock_movements_balance_after_check;
alter table public.stock_movements add constraint stock_movements_balance_after_check check(balance_after between -9007199254740991 and 9007199254740991);
alter table public.stock_movements add column stock_revision bigint not null default 0 check(stock_revision between 0 and 9007199254740991);
create or replace function private.phase3_apply_movement()
returns trigger language plpgsql security definer set search_path='' as $$
declare n numeric; r bigint; trusted boolean;
begin
 insert into private.stock_balances(organization_id,branch_id,product_id,quantity) values(new.organization_id,new.branch_id,new.product_id,0) on conflict do nothing;
 select quantity::numeric+new.quantity_delta,revision+1 into n,r from private.stock_balances where organization_id=new.organization_id and branch_id=new.branch_id and product_id=new.product_id for update;
 trusted:=exists(select 1 from private.offline_sale_sources s join private.offline_grants g on g.id=s.grant_id
  join private.offline_grant_signatures proof on proof.grant_id=g.id
  where s.sale_id=new.sale_id and s.organization_id=new.organization_id and s.branch_id=new.branch_id and s.actor_id=new.actor_user_id);
 if n<0 and new.quantity_delta<0 and not trusted then raise exception 'Insufficient stock; reload availability' using errcode='23514'; end if;
 if n not between -9007199254740991 and 9007199254740991 or r>9007199254740991 then raise exception 'Stock exceeds exact quantity limit' using errcode='22023'; end if;
 new.balance_after:=n::bigint;new.stock_revision:=r;
 update private.stock_balances set quantity=new.balance_after,revision=r where organization_id=new.organization_id and branch_id=new.branch_id and product_id=new.product_id;
 return new;
end; $$;
create function private.offline_stock_change()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform private.offline_change(new.organization_id,new.branch_id,'stock',new.product_id,false,
  jsonb_build_object('product_id',new.product_id,'quantity',new.balance_after,'revision',new.stock_revision));
 return new;
end; $$;
create trigger offline_stock_feed after insert on public.stock_movements for each row execute function private.offline_stock_change();
-- A reservation whose signature was never finalized could not have been
-- returned as authorization by Edge. Only expired, unsigned, zero-event rows
-- may be abandoned. Keep the original reservation and append the server fact.
create function private.offline_abandon_expired_unsigned(p_org uuid)
returns void language plpgsql security definer set search_path='' as $$
declare g private.offline_grants;
begin
 perform private.offline_counter_lock(p_org);
 for g in select * from private.offline_grants where organization_id=p_org and expires_at<=clock_timestamp()
  and not exists(select 1 from private.offline_grant_abandonments a where a.grant_id=offline_grants.id) order by id for update loop
  if not exists(select 1 from private.offline_grant_signatures where grant_id=g.id)
   and not exists(select 1 from private.offline_event_outcomes where grant_id=g.id)
   and exists(select 1 from private.offline_grant_states where grant_id=g.id and last_sequence=0 and total_minor=0) then
   insert into private.offline_grant_abandonments(grant_id,reason) values(g.id,'EXPIRED_UNSIGNED') on conflict do nothing;
  end if;
 end loop;
end; $$;
create function private.offline_guard_shift_close()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform private.offline_abandon_expired_unsigned(new.organization_id);
 if exists(select 1 from private.offline_grants g where g.shift_id=new.shift_id
  and not exists(select 1 from private.offline_grant_releases r where r.grant_id=g.id)
  and not exists(select 1 from private.offline_grant_abandonments a where a.grant_id=g.id)) then
  raise exception 'Synchronize and release every offline grant before closing the shift, including expired grants' using errcode='23514';
 end if;
 return new;
end; $$;
create trigger offline_shift_close_guard before insert on public.shift_closures for each row execute function private.offline_guard_shift_close();

create function public.prepare_offline_device_challenge(p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_public_key text,p_device_name text,p_platform text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c private.offline_device_challenges;
begin
 perform private.offline_require(auth.uid(),p_organization_id,p_branch_id);
 if p_device_id is null or p_public_key is null or p_public_key !~ '^[A-Za-z0-9_-]{43}$' or p_device_name is null or char_length(btrim(p_device_name)) not between 1 and 120
  or p_platform is null or p_platform not in ('android','windows','linux','macos','ios') then raise exception 'Invalid device enrollment' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('offline-enroll:'||auth.uid()::text,0));
 if (select count(*) from private.offline_device_challenges where actor_id=auth.uid() and created_at>clock_timestamp()-interval '10 minutes')>=10 then raise exception 'Too many enrollment challenges' using errcode='NX001'; end if;
 if exists(select 1 from private.offline_devices where id=p_device_id and (organization_id<>p_organization_id or actor_id<>auth.uid() or public_key<>p_public_key)) then
  raise exception 'Device identity or branch already enrolled; key replacement is unavailable' using errcode='23505'; end if;
 if exists(select 1 from private.offline_device_revocations where device_id=p_device_id) then raise exception 'Device has been revoked' using errcode='42501'; end if;
 insert into private.offline_device_challenges(organization_id,branch_id,actor_id,device_id,public_key,device_name,platform,nonce,expires_at)
 values(p_organization_id,p_branch_id,auth.uid(),p_device_id,p_public_key,btrim(p_device_name),p_platform,
  rtrim(translate(encode(uuid_send(gen_random_uuid())||uuid_send(gen_random_uuid()),'base64'),'+/','-_'),'='),clock_timestamp()+interval '5 minutes') returning * into c;
 return jsonb_build_object('challenge_id',c.id,'nonce',c.nonce,'organization_id',c.organization_id,'branch_id',c.branch_id,'device_id',c.device_id,'actor_id',c.actor_id,
  'public_key',c.public_key,'expires_at',private.offline_time(c.expires_at));
end; $$;
create function public.get_offline_verification_context(p_actor_id uuid,p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_grant_id uuid default null,p_challenge_id uuid default null)
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
 d:=private.offline_device_require(p_actor_id,p_organization_id,p_branch_id,p_device_id);
 r:=jsonb_build_object('public_key',d.public_key);
 if p_grant_id is not null then
  select * into g from private.offline_grants where id=p_grant_id and organization_id=p_organization_id and branch_id=p_branch_id and actor_id=p_actor_id and device_id=p_device_id;
  if not found or not exists(select 1 from private.offline_grant_signatures where grant_id=g.id) then raise exception 'Signed grant unavailable' using errcode='42501'; end if;
  r:=r||jsonb_build_object('grant',jsonb_build_object('claims',g.claims,'signature',(select signature from private.offline_grant_signatures where grant_id=g.id)));
 end if;
 return r;
end; $$;
create function public.complete_offline_device_enrollment(p_actor_id uuid,p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_challenge_id uuid,p_signature text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c private.offline_device_challenges;d private.offline_devices;b private.offline_device_branches;proof private.offline_device_proofs;
begin
 perform private.offline_require(p_actor_id,p_organization_id,p_branch_id);
 if p_signature is null or p_signature !~ '^[A-Za-z0-9_-]{86}$' then raise exception 'Invalid enrollment proof' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('offline-device:'||p_device_id::text,0));
 select * into c from private.offline_device_challenges where id=p_challenge_id and organization_id=p_organization_id and branch_id=p_branch_id and actor_id=p_actor_id and device_id=p_device_id for update;
 if not found then raise exception 'Enrollment challenge unavailable' using errcode='42501'; end if;
 select * into d from private.offline_devices where id=p_device_id;
 if found and (d.organization_id<>c.organization_id or d.actor_id<>c.actor_id or d.public_key<>c.public_key) then
  raise exception 'Device enrollment cannot change actor, organization or key' using errcode='23505';
 end if;
 select * into proof from private.offline_device_proofs where challenge_id=c.id;
 if found then
  if proof.signature<>p_signature or proof.device_id<>p_device_id or proof.branch_id<>p_branch_id then raise exception 'Device enrollment replay conflict' using errcode='23505'; end if;
  perform private.offline_device_require(p_actor_id,p_organization_id,p_branch_id,p_device_id);
  select * into b from private.offline_device_branches where device_id=p_device_id and branch_id=p_branch_id;
 else
  if c.expires_at<=clock_timestamp() then raise exception 'Enrollment challenge expired' using errcode='42501'; end if;
  if exists(select 1 from private.offline_device_revocations where device_id=p_device_id) then raise exception 'Device has been revoked' using errcode='42501'; end if;
  if d.id is null then
   insert into private.offline_devices(id,organization_id,branch_id,actor_id,public_key,device_name,platform,challenge_id,enrollment_signature)
   values(c.device_id,c.organization_id,c.branch_id,c.actor_id,c.public_key,c.device_name,c.platform,c.id,p_signature) returning * into d;
  end if;
  select * into b from private.offline_device_branches where device_id=p_device_id and branch_id=p_branch_id;
  if not found then
   insert into private.offline_device_branches(device_id,organization_id,branch_id,actor_id,challenge_id,enrollment_signature)
    values(c.device_id,c.organization_id,c.branch_id,c.actor_id,c.id,p_signature) returning * into b;
  end if;
  insert into private.offline_device_proofs(challenge_id,device_id,branch_id,signature) values(c.id,c.device_id,c.branch_id,p_signature);
 end if;
 return jsonb_build_object('device_id',d.id,'organization_id',b.organization_id,'branch_id',b.branch_id,'actor_id',b.actor_id,'public_key',d.public_key,'enrolled_at',private.offline_time(b.enrolled_at));
end; $$;

create function public.prepare_offline_grant(p_actor_id uuid,p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_request_id uuid,p_issuer text,p_key_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;d private.offline_devices;g private.offline_grants;s public.shifts;o public.organizations;
 snapshot jsonb;claims jsonb;cursor bigint;issued timestamptz;expiry timestamptz;grant_id uuid;count_products integer;
begin
 m:=private.offline_require(p_actor_id,p_organization_id,p_branch_id);
 d:=private.offline_device_require(p_actor_id,p_organization_id,p_branch_id,p_device_id);
 perform private.offline_counter_lock(p_organization_id);
 if p_request_id is null or p_issuer is null or p_issuer !~ '^(https://[^/@?#[:space:]]+|http://(localhost|127[.]0[.]0[.]1|\[::1\])(:[0-9]{1,5})?)$' or p_key_id is null or char_length(p_key_id) not between 1 and 80 then raise exception 'Invalid grant configuration' using errcode='22023'; end if;
 perform private.offline_abandon_expired_unsigned(p_organization_id);
 perform pg_advisory_xact_lock(hashtextextended('offline-prepare:'||p_actor_id::text||':'||p_device_id::text,0));
 select * into g from private.offline_grants where organization_id=p_organization_id and actor_id=p_actor_id and device_id=p_device_id and request_id=p_request_id;
 if found then
  if exists(select 1 from private.offline_grant_abandonments a where a.grant_id=g.id) then raise exception 'Unsigned preparation expired before authorization' using errcode='NX002'; end if;
  if g.branch_id<>p_branch_id or g.claims->>'issuer'<>p_issuer then raise exception 'Grant request replay conflict' using errcode='23505'; end if;
  return jsonb_build_object('claims',g.claims,'snapshot',g.snapshot,'server_time',private.offline_time(clock_timestamp()))
   ||coalesce((select jsonb_build_object('signature',proof.signature) from private.offline_grant_signatures proof where proof.grant_id=g.id),'{}'::jsonb);
 end if;
 if (select count(*) from private.offline_grants where actor_id=p_actor_id and device_id=p_device_id and issued_at>clock_timestamp()-interval '10 minutes')>=10 then raise exception 'Too many grant preparations' using errcode='NX001'; end if;
 if exists(select 1 from private.offline_grants q where q.device_id=p_device_id and not exists(select 1 from private.offline_grant_releases r where r.grant_id=q.id)
  and not exists(select 1 from private.offline_grant_abandonments a where a.grant_id=q.id)) then raise exception 'Release the existing device grant before preparing another' using errcode='23514'; end if;
 select * into s from public.shifts where organization_id=p_organization_id and branch_id=p_branch_id and actor_user_id=p_actor_id
  and not exists(select 1 from public.shift_closures c where c.shift_id=shifts.id) for update;
 if not found then raise exception 'Previously opened own online shift required' using errcode='42501'; end if;
 select * into o from public.organizations where id=p_organization_id for share;
 if o.currency<>s.currency or s.currency not in ('PHP','USD','EUR','GBP','AUD','CAD','SGD') then raise exception 'Shift currency must match supported business currency' using errcode='40001'; end if;
 -- This lock is also held by every change allocation until COMMIT. Snapshot
 -- reads take no product locks, so a blocked writer cannot create a lock cycle.
 cursor:=private.offline_counter_lock(p_organization_id);
 select count(*) into count_products from public.products p where p.organization_id=p_organization_id and p.active and p.currency=s.currency
  and (p.category_id is null or exists(select 1 from public.categories c where c.id=p.category_id and c.active));
 if count_products>1000 then raise exception 'Offline snapshot exceeds 1000 products; preparation refused' using errcode='22023'; end if;
 snapshot:=jsonb_build_object('context',private.offline_context_json(p_organization_id,p_branch_id),'shift',private.phase3_shift_json(s.id),'cursor',cursor,
  'products',coalesce((select jsonb_agg(private.offline_product_json(p)||jsonb_build_object('available_quantity',coalesce(b.quantity,0)) order by p.id)
   from public.products p left join private.stock_balances b on b.organization_id=p.organization_id and b.branch_id=p_branch_id and b.product_id=p.id
   where p.organization_id=p_organization_id and p.active and p.currency=s.currency and (p.category_id is null or exists(select 1 from public.categories c where c.id=p.category_id and c.active))),'[]'::jsonb),
  'categories',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'organization_id',c.organization_id,'name',c.name,'active',c.active,'revision',c.revision) order by c.id)
   from public.categories c where c.organization_id=p_organization_id and c.active),'[]'::jsonb),
  'stock',coalesce((select jsonb_agg(jsonb_build_object('product_id',p.id,'quantity',coalesce(b.quantity,0),'revision',coalesce(b.revision,0)) order by p.id)
   from public.products p left join private.stock_balances b on b.organization_id=p.organization_id and b.branch_id=p_branch_id and b.product_id=p.id
   where p.organization_id=p_organization_id and p.active and p.currency=s.currency and (p.category_id is null or exists(select 1 from public.categories c where c.id=p.category_id and c.active))),'[]'::jsonb));
 grant_id:=gen_random_uuid();issued:=date_trunc('milliseconds',clock_timestamp());expiry:=issued+interval '8 hours';
 claims:=jsonb_build_object('schema_version',1,'issuer',p_issuer,'audience','nexapos.offline.v1','key_id',p_key_id,'grant_id',grant_id,
  'organization_id',p_organization_id,'branch_id',p_branch_id,'device_id',p_device_id,'actor_id',p_actor_id,'membership_id',m.id,'role',m.role,
  'business_name',o.business_name,'allowed_actions',jsonb_build_array('sale.created'),'issued_at',private.offline_time(issued),'expires_at',private.offline_time(expiry),
  'shift_id',s.id,'currency',s.currency,'tax_bps',o.tax_bps,'settings_revision',o.revision,'snapshot_digest',private.offline_digest(snapshot),'max_events',1000,'max_total_minor',100000000);
 insert into private.offline_grants(id,organization_id,branch_id,actor_id,device_id,membership_id,request_id,shift_id,claims,snapshot,snapshot_digest,issued_at,expires_at,max_events,max_total_minor)
 values(grant_id,p_organization_id,p_branch_id,p_actor_id,p_device_id,m.id,p_request_id,s.id,claims,snapshot,claims->>'snapshot_digest',issued,expiry,1000,100000000);
 insert into private.offline_grant_states(grant_id) values(grant_id);
 return jsonb_build_object('claims',claims,'snapshot',snapshot,'server_time',private.offline_time(clock_timestamp()));
end; $$;
create function public.finalize_offline_grant(p_actor_id uuid,p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_grant_id uuid,p_claims jsonb,p_signature text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare g private.offline_grants;existing text;
begin
 perform private.offline_device_require(p_actor_id,p_organization_id,p_branch_id,p_device_id);
 select * into g from private.offline_grants where id=p_grant_id and organization_id=p_organization_id and branch_id=p_branch_id and actor_id=p_actor_id and device_id=p_device_id for update;
 if not found then raise exception 'Prepared grant unavailable' using errcode='42501'; end if;
 if exists(select 1 from private.offline_grant_abandonments a where a.grant_id=g.id) then raise exception 'Unsigned preparation expired before authorization' using errcode='NX002'; end if;
 if p_claims is distinct from g.claims or p_signature is null or p_signature !~ '^[A-Za-z0-9_-]{86}$' then raise exception 'Grant signing does not match retained preparation' using errcode='23505'; end if;
 select signature into existing from private.offline_grant_signatures where grant_id=g.id;
 if found and existing<>p_signature then raise exception 'Grant signature replay conflict' using errcode='23505'; end if;
 if not found then
  if g.expires_at<=clock_timestamp() then raise exception 'Prepared grant expired' using errcode='42501'; end if;
  insert into private.offline_grant_signatures(grant_id,signature) values(g.id,p_signature);
 end if;
 return jsonb_build_object('grant',jsonb_build_object('claims',g.claims,'signature',p_signature),'snapshot',g.snapshot,'server_time',private.offline_time(clock_timestamp()));
end; $$;

create function public.ingest_offline_event(p_actor_id uuid,p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_event jsonb,p_digest text,p_authorization jsonb,p_signature text)
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
 perform private.offline_device_require(p_actor_id,p_organization_id,p_branch_id,p_device_id);
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
 if sequence<>state.last_sequence+1 then raise exception 'Grant events must arrive in uninterrupted sequence' using errcode='23505'; end if;
 if jsonb_typeof(p_event->'occurred_at') is distinct from 'string' then raise exception 'UTC event observation is required' using errcode='22023'; end if;
 occurred:=(p_event->>'occurred_at')::timestamptz;
 if p_event->>'occurred_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|\+00:00)$' or occurred<g.issued_at or occurred>=g.expires_at
  or clock_timestamp()>g.expires_at+interval '72 hours' or occurred>clock_timestamp()+interval '5 minutes' then raise exception 'Event observation or ingestion is outside bounded grant lifetime' using errcode='42501'; end if;
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
 if exists(select 1 from public.shift_closures where shift_id=g.shift_id) then code:='SHIFT_CLOSED'; end if;
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
 update private.offline_grant_states set last_sequence=sequence,total_minor=total_minor+total where grant_id=g.id;
 return result;
exception when invalid_text_representation or numeric_value_out_of_range or datetime_field_overflow or invalid_datetime_format then raise exception 'Invalid offline identifier, time or exact amount' using errcode='22023';
end; $$;

create function public.pull_offline_changes(p_actor_id uuid,p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_cursor bigint,p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path='' as $$
declare current_cursor bigint;next_cursor bigint;changes jsonb;more boolean;
begin
 perform private.offline_device_require(p_actor_id,p_organization_id,p_branch_id,p_device_id);
 if p_cursor is null or p_cursor not between 0 and 9007199254740991 or p_limit is null or p_limit not between 1 and 100 then raise exception 'Invalid bounded synchronization page' using errcode='22023'; end if;
 current_cursor:=private.offline_counter_lock(p_organization_id);
 if p_cursor>current_cursor then raise exception 'Cursor is ahead of committed organization history' using errcode='22023'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'id',id,'revision',revision,'deleted',deleted,'value',value) order by revision),'[]'::jsonb),max(revision)
 into changes,next_cursor from (select * from private.offline_changes where organization_id=p_organization_id and revision>p_cursor
  and (branch_id is null or branch_id=p_branch_id) order by revision limit p_limit) page;
 more:=exists(select 1 from private.offline_changes where organization_id=p_organization_id and revision>coalesce(next_cursor,p_cursor) and (branch_id is null or branch_id=p_branch_id));
 -- When the scoped page is exhausted, advance over invisible other-branch
 -- changes only while holding the same organization lock used by allocation.
 if not more then next_cursor:=current_cursor; end if;
 return jsonb_build_object('cursor',coalesce(next_cursor,p_cursor),'has_more',more,'server_time',private.offline_time(clock_timestamp()),'changes',changes);
end; $$;
create function public.release_offline_grant(p_actor_id uuid,p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_grant_id uuid,p_final_sequence bigint,p_signature text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare g private.offline_grants;state private.offline_grant_states;r private.offline_grant_releases;
begin
 perform private.offline_device_require(p_actor_id,p_organization_id,p_branch_id,p_device_id);
 select * into g from private.offline_grants where id=p_grant_id and organization_id=p_organization_id and branch_id=p_branch_id and actor_id=p_actor_id and device_id=p_device_id for update;
 if not found or not exists(select 1 from private.offline_grant_signatures where grant_id=g.id) then raise exception 'Signed grant unavailable' using errcode='42501'; end if;
 if p_final_sequence is null or p_final_sequence not between 0 and g.max_events or p_signature is null or p_signature !~ '^[A-Za-z0-9_-]{86}$' then raise exception 'Invalid signed release' using errcode='22023'; end if;
 select * into r from private.offline_grant_releases where grant_id=g.id;
 if found then
  if r.final_sequence<>p_final_sequence or r.signature<>p_signature then raise exception 'Release replay changed final boundary' using errcode='23505'; end if;
 else
  select * into state from private.offline_grant_states where grant_id=g.id for update;
  if state.last_sequence<>p_final_sequence or (select count(*) from private.offline_event_outcomes where grant_id=g.id)<>p_final_sequence then raise exception 'All final sequences must have accepted or review outcomes before release' using errcode='23514'; end if;
  insert into private.offline_grant_releases(grant_id,final_sequence,signature) values(g.id,p_final_sequence,p_signature) returning * into r;
 end if;
 return jsonb_build_object('status','released','organization_id',p_organization_id,'branch_id',p_branch_id,'actor_id',p_actor_id,'device_id',p_device_id,'grant_id',g.id,
  'final_sequence',r.final_sequence,'released_at',private.offline_time(r.released_at));
end; $$;

-- Device revocation is a real authenticated management action. It preserves all
-- grants/events and does not bypass required queue reconciliation or closure.
create function public.revoke_offline_device(p_organization_id uuid,p_branch_id uuid,p_device_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;d private.offline_devices;r private.offline_device_revocations;
begin
 m:=private.offline_require(auth.uid(),p_organization_id,p_branch_id);
 select devices.* into d from private.offline_devices devices join private.offline_device_branches binding on binding.device_id=devices.id
  where binding.organization_id=p_organization_id and binding.branch_id=p_branch_id and devices.id=p_device_id for update of devices;
 if not found or (d.actor_id<>auth.uid() and m.role not in ('owner','admin','manager')) then raise exception 'Device management unavailable' using errcode='42501'; end if;
 if p_reason is null or char_length(btrim(p_reason)) not between 3 and 1000 then raise exception 'Revocation requires a meaningful reason' using errcode='22023'; end if;
 select * into r from private.offline_device_revocations where device_id=d.id;
 if not found then insert into private.offline_device_revocations(device_id,revoked_by,reason) values(d.id,auth.uid(),btrim(p_reason)) returning * into r; end if;
 return jsonb_build_object('device_id',d.id,'revoked_at',private.offline_time(r.revoked_at));
end; $$;

-- Normal RPC writers take the commit-order feed lock before any catalog,
-- shift, sale or stock row locks. This prevents a writer holding product B
-- while waiting on the feed counter from deadlocking a multi-product writer
-- that already holds the counter and then needs B. Auth/branch checks still
-- precede the lock. Preserve the prior implementations and their exact ACLs.
do $$
declare r record;definition text;needle text;
begin
 for r in select * from (values
  ('private.write_management_record(text,uuid,uuid,bigint,jsonb,text)','  v_member := private.require_active_member(p_organization_id);'),
  ('public.save_business_settings(uuid,bigint,jsonb,text)','  v_member := private.require_active_member(p_organization_id);'),
  ('public.checkout_sale(uuid,uuid,uuid,jsonb)',' m:=private.phase3_require(p_organization_id,p_branch_id,''pos'');'),
  ('public.receive_stock(uuid,uuid,uuid,jsonb,uuid,text,text)',' perform private.phase3_require(p_organization_id,p_branch_id,''stock'');'),
  ('public.adjust_stock(uuid,uuid,uuid,uuid,bigint,text)',' perform private.phase3_require(p_organization_id,p_branch_id,''manage'');'),
  ('public.close_shift(uuid,uuid,uuid,bigint,text)',' m:=private.phase3_require(p_organization_id,s.branch_id,''pos'');'),
  ('public.reverse_sale(uuid,uuid,uuid,jsonb)',' m:=private.phase3_require(p_organization_id,s.branch_id,''manage'');')
 ) hooks(signature,authority_check) loop
  definition:=pg_get_functiondef(to_regprocedure(r.signature));needle:=r.authority_check;
  if definition is null or strpos(definition,needle)=0 then raise exception 'Missing audited feed-lock hook: %',r.signature; end if;
  execute replace(definition,needle,needle||E'\n perform private.offline_counter_lock(p_organization_id);');
 end loop;
end $$;

-- No generic service DML, anonymous access, or client-controlled ingestion.
-- Even security-definer trigger functions are not directly callable by clients.
do $$ declare t text;r record; begin
 foreach t in array array['offline_device_challenges','offline_devices','offline_device_branches','offline_device_proofs','offline_device_revocations','offline_grants','offline_grant_signatures','offline_grant_states',
  'offline_grant_releases','offline_grant_abandonments','offline_event_outcomes','offline_sale_sources','offline_reconciliation_cases','offline_change_counters','offline_changes'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on table private.%I from public,anon,authenticated,service_role',t);
  if t not in ('offline_grant_states','offline_change_counters') then
   execute format('create trigger immutable_history before update or delete on private.%I for each row execute function private.reject_immutable_mutation()',t);
   execute format('create trigger immutable_no_truncate before truncate on private.%I for each statement execute function private.reject_immutable_mutation()',t);
  end if;
 end loop;
 for r in select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where (n.nspname='private' and p.proname like 'offline_%') or (n.nspname='public' and p.proname in ('prepare_offline_device_challenge','complete_offline_device_enrollment',
   'prepare_offline_grant','finalize_offline_grant','get_offline_verification_context','ingest_offline_event','pull_offline_changes','release_offline_grant','revoke_offline_device')) loop
  execute format('revoke all on function %I.%I(%s) from public,anon,authenticated,service_role',r.nspname,r.proname,r.args);
 end loop;
end $$;
grant execute on function public.prepare_offline_device_challenge(uuid,uuid,uuid,text,text,text),public.revoke_offline_device(uuid,uuid,uuid,text) to authenticated;
grant execute on function public.complete_offline_device_enrollment(uuid,uuid,uuid,uuid,uuid,text),
 public.prepare_offline_grant(uuid,uuid,uuid,uuid,uuid,text,text),public.finalize_offline_grant(uuid,uuid,uuid,uuid,uuid,jsonb,text),
 public.get_offline_verification_context(uuid,uuid,uuid,uuid,uuid,uuid),public.ingest_offline_event(uuid,uuid,uuid,uuid,jsonb,text,jsonb,text),
 public.pull_offline_changes(uuid,uuid,uuid,uuid,bigint,integer),public.release_offline_grant(uuid,uuid,uuid,uuid,uuid,bigint,text) to service_role;
commit;
