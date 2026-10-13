-- Phase 6A: immutable manually confirmed expenses and full compensation.
-- Recording evidence never invokes a provider payout or rewrites a shift count.
begin;
create table public.expenses (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),branch_id uuid not null,
 actor_user_id uuid not null references auth.users(id),
 created_at timestamptz not null,occurred_at timestamptz not null,
 currency text not null check(currency in ('PHP','USD','EUR','GBP','AUD','CAD','SGD')),
 settings_revision bigint not null check(settings_revision between 1 and 9007199254740991),
 amount_minor bigint not null check(amount_minor between 1 and 9007199254740991),
 category text not null check(category in ('rent','utilities','wages','transport','maintenance','fees','other')),
 payee text check(payee is null or (payee=btrim(payee) and char_length(payee) between 1 and 160)),
 payment_method text not null check(payment_method in ('cash','card','gcash','maya','other')),
 manual_confirmed boolean not null check(manual_confirmed),
 reference text check(reference is null or (reference=btrim(reference) and char_length(reference) between 1 and 120)),
 source text not null check(source in ('external','cash_drawer')),shift_id uuid,
 reason text not null check(reason=btrim(reason) and char_length(reason) between 3 and 1000),
 unique(organization_id,id),unique(organization_id,branch_id,id),
 unique(organization_id,branch_id,id,currency,amount_minor,source),
 foreign key(organization_id,branch_id) references public.branches(organization_id,id),
 foreign key(organization_id,branch_id,shift_id) references public.shifts(organization_id,branch_id,id),
 check(created_at=occurred_at),
 check(payment_method='cash' or (reference is not null and char_length(reference)>=3)),
 check((source='external' and shift_id is null) or (source='cash_drawer' and shift_id is not null and payment_method='cash'))
);
create table public.expense_reversals (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,branch_id uuid not null,
 expense_id uuid not null unique,actor_user_id uuid not null references auth.users(id),
 created_at timestamptz not null,occurred_at timestamptz not null,
 currency text not null check(currency in ('PHP','USD','EUR','GBP','AUD','CAD','SGD')),
 amount_minor bigint not null check(amount_minor between 1 and 9007199254740991),
 manual_confirmed boolean not null check(manual_confirmed),
 reference text check(reference is null or (reference=btrim(reference) and char_length(reference) between 1 and 120)),
 source text not null check(source in ('external','cash_drawer')),shift_id uuid,
 reason text not null check(reason=btrim(reason) and char_length(reason) between 3 and 1000),
 unique(organization_id,id),unique(organization_id,branch_id,id),
 foreign key(organization_id,branch_id,expense_id,currency,amount_minor,source)
  references public.expenses(organization_id,branch_id,id,currency,amount_minor,source),
 foreign key(organization_id,branch_id,shift_id) references public.shifts(organization_id,branch_id,id),
 check(created_at=occurred_at),
 check((source='external' and shift_id is null) or (source='cash_drawer' and shift_id is not null))
);
create index expenses_scope_time on public.expenses(organization_id,branch_id,occurred_at desc,id);
create index expense_reversals_scope_time on public.expense_reversals(organization_id,branch_id,occurred_at desc,id);
create index expenses_drawer on public.expenses(shift_id) where source='cash_drawer';
create index expense_reversals_drawer on public.expense_reversals(shift_id) where source='cash_drawer';

create function private.phase6_check_expense_reversal()
returns trigger language plpgsql security definer set search_path='' as $$
declare e public.expenses;
begin
 select * into e from public.expenses where id=new.expense_id and organization_id=new.organization_id and branch_id=new.branch_id;
 if not found or new.currency<>e.currency or new.amount_minor<>e.amount_minor or new.source<>e.source or new.shift_id is distinct from e.shift_id then
  raise exception 'Compensation must preserve the original expense' using errcode='23514';
 end if;
 return new;
end; $$;
create trigger expense_reversal_original before insert on public.expense_reversals for each row execute function private.phase6_check_expense_reversal();

create or replace function private.phase3_expected_cash(p_shift uuid)
returns bigint language plpgsql stable security definer set search_path='' as $$
declare amount numeric;
begin
 select s.opening_cash_minor::numeric
  +coalesce((select sum(p.amount_minor::numeric) from public.sale_payments p join public.sales x on x.id=p.sale_id where x.shift_id=s.id and p.method='cash'),0)
  -coalesce((select sum(p.amount_minor::numeric) from public.sale_reversal_payments p join public.sale_reversals r on r.id=p.reversal_id
    join public.sale_payments original on original.id=p.original_payment_id where r.shift_id=s.id and original.method='cash'),0)
  -coalesce((select sum(e.amount_minor::numeric) from public.expenses e where e.shift_id=s.id and e.source='cash_drawer'),0)
  +coalesce((select sum(r.amount_minor::numeric) from public.expense_reversals r where r.shift_id=s.id and r.source='cash_drawer'),0)
 into amount from public.shifts s where s.id=p_shift;
 if amount is null then return null; end if;
 if amount not between -9007199254740991 and 9007199254740991 then raise exception 'Shift cash exceeds the exact monetary limit' using errcode='22023'; end if;
 return amount::bigint;
end; $$;

create function private.phase6_expense_reversal_json(p_reversal uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(r)||jsonb_build_object('created_at',private.offline_time(r.created_at),'occurred_at',private.offline_time(r.occurred_at),
  'request_id',(select request_id from private.operation_requests where result_id=r.id and kind='expense.reverse'))
 from public.expense_reversals r where r.id=p_reversal;
$$;
create function private.phase6_expense_json(p_expense uuid,p_current boolean default true)
returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(e)||jsonb_build_object('created_at',private.offline_time(e.created_at),'occurred_at',private.offline_time(e.occurred_at),
  'request_id',(select request_id from private.operation_requests where result_id=e.id and kind='expense.record'),
  'reversal',case when p_current then (select private.phase6_expense_reversal_json(r.id) from public.expense_reversals r where r.expense_id=e.id) else null end)
 from public.expenses e where e.id=p_expense;
$$;

create function private.phase6_can_read_expense(p_org uuid,p_branch uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select private.security_business_assurance(p_org) and private.phase3_can_read(p_org,p_branch,auth.uid(),'sale')
  and exists(select 1 from public.organization_memberships m where m.organization_id=p_org and m.user_id=auth.uid() and m.status='active' and m.role in ('owner','admin','manager'));
$$;
do $$ declare t text;begin
 foreach t in array array['expenses','expense_reversals'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated,service_role',t);
  execute format('create trigger immutable_history before update or delete on public.%I for each row execute function private.reject_immutable_mutation()',t);
  execute format('create trigger immutable_no_truncate before truncate on public.%I for each statement execute function private.reject_immutable_mutation()',t);
  execute format('create policy expenses_read on public.%I for select to authenticated using(private.phase6_can_read_expense(organization_id,branch_id))',t);
  execute format('create policy security_mfa_assurance on public.%I as restrictive for all to authenticated using(private.security_business_assurance(organization_id)) with check(private.security_business_assurance(organization_id))',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
end; $$;

create function public.get_expense_context(p_organization_id uuid,p_branch_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.organizations;b public.branches;s public.shifts;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'manage');
 select * into o from public.organizations where id=p_organization_id;
 select * into b from public.branches where organization_id=p_organization_id and id=p_branch_id;
 if o.currency not in ('PHP','USD','EUR','GBP','AUD','CAD','SGD') then raise exception 'Unsupported expense currency' using errcode='22023'; end if;
 select * into s from public.shifts where organization_id=p_organization_id and branch_id=p_branch_id and actor_user_id=auth.uid()
  and not exists(select 1 from public.shift_closures c where c.shift_id=shifts.id) order by opened_at desc,id limit 1;
 return jsonb_build_object('organization_id',o.id,'branch_id',b.id,'branch_name',b.name,'currency',o.currency,'settings_revision',o.revision,
  'own_open_shift',case when s.id is null then null else jsonb_build_object('id',s.id,'actor_user_id',s.actor_user_id,'currency',s.currency,'opened_at',private.offline_time(s.opened_at),'expected_cash_minor',private.phase3_expected_cash(s.id)) end);
end; $$;
create function public.get_expense(p_organization_id uuid,p_branch_id uuid,p_expense_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'manage');
 if not exists(select 1 from public.expenses where organization_id=p_organization_id and branch_id=p_branch_id and id=p_expense_id) then raise exception 'Expense unavailable' using errcode='P0002'; end if;
 return private.phase6_expense_json(p_expense_id,true);
end; $$;
create function public.list_expenses(p_organization_id uuid,p_branch_id uuid,p_from timestamptz default null,p_to timestamptz default null,p_category text default null,p_offset integer default 0,p_limit integer default 51)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'manage');
 if p_limit is null or p_limit not between 1 and 101 or p_offset is null or p_offset not between 0 and 1000000
  or ((p_from is null)<>(p_to is null)) or (p_from is not null and not isfinite(p_from)) or (p_to is not null and not isfinite(p_to))
  or (p_from is not null and (p_from>=p_to or p_to-p_from>interval '366 days'))
  or (p_category is not null and p_category not in ('rent','utilities','wages','transport','maintenance','fees','other')) then raise exception 'Invalid expense page or time window' using errcode='22023'; end if;
 select coalesce(jsonb_agg(row_json order by occurred_at desc,id),'[]'::jsonb) into result from (
  select id,occurred_at,private.phase6_expense_json(id,true) row_json from public.expenses
   where organization_id=p_organization_id and branch_id=p_branch_id and (p_from is null or occurred_at>=p_from) and (p_to is null or occurred_at<p_to) and (p_category is null or category=p_category)
   order by occurred_at desc,id offset p_offset limit p_limit) page;
 return result;
end; $$;

create function public.record_expense(p_organization_id uuid,p_branch_id uuid,p_request_id uuid,p_expected_settings_revision bigint,p_currency text,p_amount_minor bigint,
 p_category text,p_source text,p_shift_id uuid,p_payment_method text,p_manual_confirmed boolean,p_payee text,p_reference text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;result_id uuid;o public.organizations;s public.shifts;v_time timestamptz;reason text:=btrim(p_reason);payee text:=nullif(btrim(p_payee),'');ref text:=nullif(btrim(p_reference),'');cash numeric;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'manage');
 payload:=jsonb_build_object('branch_id',p_branch_id,'expected_settings_revision',p_expected_settings_revision,'currency',p_currency,'amount_minor',p_amount_minor,'category',p_category,
  'source',p_source,'shift_id',p_shift_id,'payment_method',p_payment_method,'manual_confirmed',p_manual_confirmed,'payee',payee,'reference',ref,'reason',reason);
 result_id:=private.phase3_request(p_organization_id,p_request_id,'expense.record',payload);
 if result_id is not null then return jsonb_build_object('request_id',p_request_id,'kind','expense.record','expense',private.phase6_expense_json(result_id,false)); end if;
 if p_manual_confirmed is distinct from true or p_amount_minor is null or p_amount_minor not between 1 and 9007199254740991
  or p_expected_settings_revision is null or p_expected_settings_revision not between 1 and 9007199254740991
  or p_currency is null or p_currency not in ('PHP','USD','EUR','GBP','AUD','CAD','SGD')
  or p_category is null or p_category not in ('rent','utilities','wages','transport','maintenance','fees','other')
  or p_source is null or p_source not in ('external','cash_drawer') or p_payment_method is null or p_payment_method not in ('cash','card','gcash','maya','other')
  or reason is null or char_length(reason) not between 3 and 1000 or (payee is not null and char_length(payee)>160)
  or (ref is not null and char_length(ref) not between 1 and 120) or (p_payment_method<>'cash' and (ref is null or char_length(ref)<3))
  or (p_source='external' and p_shift_id is not null) or (p_source='cash_drawer' and (p_shift_id is null or p_payment_method<>'cash')) then
  raise exception 'Invalid expense or explicit manual payment evidence' using errcode='22023';
 end if;
 -- No change-feed counter is needed: expense history does not mutate stock.
 -- Read settings before taking the shared shift row, never counter-after-shift.
 select * into o from public.organizations where id=p_organization_id for share;
 if o.currency<>p_currency or o.revision<>p_expected_settings_revision then raise exception 'Business settings changed; reload before recording expense' using errcode='40001'; end if;
 if p_source='cash_drawer' then
  select * into s from public.shifts where id=p_shift_id and organization_id=p_organization_id and branch_id=p_branch_id for update;
  if not found then raise exception 'Own branch shift unavailable' using errcode='P0002'; end if;
  if s.actor_user_id<>auth.uid() then raise exception 'Cash payouts require your own shift' using errcode='42501'; end if;
  if exists(select 1 from public.shift_closures where shift_id=s.id) or s.currency<>p_currency then raise exception 'Own drawer is closed or its currency changed' using errcode='40001'; end if;
  cash:=private.phase3_expected_cash(s.id)::numeric-p_amount_minor::numeric;
  if cash not between -9007199254740991 and 9007199254740991 then raise exception 'Expense exceeds the exact shift cash limit' using errcode='22023'; end if;
 end if;
 v_time:=clock_timestamp();
 insert into public.expenses(organization_id,branch_id,actor_user_id,created_at,occurred_at,currency,settings_revision,amount_minor,category,payee,payment_method,manual_confirmed,reference,source,shift_id,reason)
 values(p_organization_id,p_branch_id,auth.uid(),v_time,v_time,p_currency,p_expected_settings_revision,p_amount_minor,p_category,payee,p_payment_method,true,ref,p_source,p_shift_id,reason) returning id into result_id;
 perform private.phase3_save_request(p_organization_id,p_request_id,'expense.record',payload,result_id);
 perform private.append_action_audit(p_organization_id,'expense.recorded','expenses',result_id,p_branch_id,reason,
  jsonb_build_object('amount_minor',p_amount_minor,'currency',p_currency,'category',p_category,'source',p_source,'shift_id',p_shift_id));
 return jsonb_build_object('request_id',p_request_id,'kind','expense.record','expense',private.phase6_expense_json(result_id,false));
end; $$;

create function public.reverse_expense(p_organization_id uuid,p_branch_id uuid,p_request_id uuid,p_expense_id uuid,p_manual_confirmed boolean,p_reference text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;result_id uuid;e public.expenses;s public.shifts;v_time timestamptz;reason text:=btrim(p_reason);ref text:=nullif(btrim(p_reference),'');cash numeric;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'manage');
 payload:=jsonb_build_object('branch_id',p_branch_id,'expense_id',p_expense_id,'manual_confirmed',p_manual_confirmed,'reference',ref,'reason',reason);
 result_id:=private.phase3_request(p_organization_id,p_request_id,'expense.reverse',payload);
 if result_id is not null then return jsonb_build_object('request_id',p_request_id,'kind','expense.reverse','expense_id',p_expense_id,'reversal',private.phase6_expense_reversal_json(result_id)); end if;
 if p_manual_confirmed is distinct from true or reason is null or char_length(reason) not between 3 and 1000 or (ref is not null and char_length(ref) not between 1 and 120) then
  raise exception 'Explicitly confirm the full correction or physical cash return and reason' using errcode='22023';
 end if;
 select * into e from public.expenses where id=p_expense_id and organization_id=p_organization_id and branch_id=p_branch_id;
 if not found then raise exception 'Expense unavailable' using errcode='P0002'; end if;
 if e.source='cash_drawer' then
  -- Match close/checkout/offline-ingest shift serialization before expense row.
  select * into s from public.shifts where id=e.shift_id and organization_id=p_organization_id and branch_id=p_branch_id for update;
  if s.actor_user_id<>auth.uid() then raise exception 'Physical cash must return to your original own drawer' using errcode='42501'; end if;
  if exists(select 1 from public.shift_closures where shift_id=s.id) or s.currency<>e.currency then raise exception 'Original drawer is closed; administrator review required' using errcode='40001'; end if;
 end if;
 perform 1 from public.expenses where id=e.id for update;
 if exists(select 1 from public.expense_reversals where expense_id=e.id) then raise exception 'Expense already has a full compensation' using errcode='23505'; end if;
 if e.source='cash_drawer' then
  cash:=private.phase3_expected_cash(s.id)::numeric+e.amount_minor::numeric;
  if cash not between -9007199254740991 and 9007199254740991 then raise exception 'Cash return exceeds the exact shift cash limit' using errcode='22023'; end if;
 end if;
 v_time:=clock_timestamp();
 insert into public.expense_reversals(organization_id,branch_id,expense_id,actor_user_id,created_at,occurred_at,currency,amount_minor,manual_confirmed,reference,source,shift_id,reason)
 values(p_organization_id,p_branch_id,e.id,auth.uid(),v_time,v_time,e.currency,e.amount_minor,true,ref,e.source,e.shift_id,reason) returning id into result_id;
 perform private.phase3_save_request(p_organization_id,p_request_id,'expense.reverse',payload,result_id);
 perform private.append_action_audit(p_organization_id,'expense.reversed','expense_reversals',result_id,p_branch_id,reason,
  jsonb_build_object('expense_id',e.id,'amount_minor',e.amount_minor,'currency',e.currency,'source',e.source,'shift_id',e.shift_id));
 return jsonb_build_object('request_id',p_request_id,'kind','expense.reverse','expense_id',e.id,'reversal',private.phase6_expense_reversal_json(result_id));
end; $$;

-- Delegate every prior employee/security/purchase snapshot rule unchanged.
alter function private.can_read_audit(uuid,uuid,text,uuid,text,jsonb) rename to phase6_expense_prior_can_read_audit;
create function private.can_read_audit(p_organization_id uuid,p_branch_id uuid,p_entity text,p_entity_id uuid,p_action text,p_metadata jsonb)
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 if (p_entity='expenses' and p_action='expense.recorded') or (p_entity='expense_reversals' and p_action='expense.reversed') then
  return p_branch_id is not null and private.phase6_can_read_expense(p_organization_id,p_branch_id);
 end if;
 return private.phase6_expense_prior_can_read_audit(p_organization_id,p_branch_id,p_entity,p_entity_id,p_action,p_metadata);
end; $$;
revoke all on function private.phase6_expense_prior_can_read_audit(uuid,uuid,text,uuid,text,jsonb),private.can_read_audit(uuid,uuid,text,uuid,text,jsonb),
 private.phase6_check_expense_reversal(),private.phase6_expense_reversal_json(uuid),private.phase6_expense_json(uuid,boolean),private.phase6_can_read_expense(uuid,uuid),private.phase3_expected_cash(uuid) from public,anon,authenticated,service_role;
grant execute on function private.can_read_audit(uuid,uuid,text,uuid,text,jsonb),private.phase6_can_read_expense(uuid,uuid) to authenticated;
-- Renaming a function retains its OID. Rebind the existing policy so direct
-- audit-table reads use the new expense wrapper rather than the old helper.
drop policy audit_read_authorized on public.audit_logs;
create policy audit_read_authorized on public.audit_logs for select to authenticated
 using(private.can_read_audit(organization_id,branch_id,entity,entity_id,action,metadata));
revoke all on function public.get_expense_context(uuid,uuid),public.get_expense(uuid,uuid,uuid),public.list_expenses(uuid,uuid,timestamptz,timestamptz,text,integer,integer),
 public.record_expense(uuid,uuid,uuid,bigint,text,bigint,text,text,uuid,text,boolean,text,text,text),public.reverse_expense(uuid,uuid,uuid,uuid,boolean,text,text) from public,anon,authenticated,service_role;
grant execute on function public.get_expense_context(uuid,uuid),public.get_expense(uuid,uuid,uuid),public.list_expenses(uuid,uuid,timestamptz,timestamptz,text,integer,integer),
 public.record_expense(uuid,uuid,uuid,bigint,text,bigint,text,text,uuid,text,boolean,text,text,text),public.reverse_expense(uuid,uuid,uuid,uuid,boolean,text,text) to authenticated;
commit;
