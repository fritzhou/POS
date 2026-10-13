-- Phase 3: authoritative ONLINE transactions. Offline ingestion remains closed.
begin;
create table public.shifts (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),branch_id uuid not null,
 actor_user_id uuid not null references auth.users(id),currency text not null check(currency in ('PHP','USD','EUR','GBP','AUD','CAD','SGD')),
 opening_cash_minor bigint not null check(opening_cash_minor between 0 and 9007199254740991),opened_at timestamptz not null default now(),
 unique(organization_id,id),unique(organization_id,branch_id,id),foreign key(organization_id,branch_id) references public.branches(organization_id,id)
);
create table public.shift_closures (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,branch_id uuid not null,shift_id uuid not null unique,
 closed_by uuid not null references auth.users(id),closed_at timestamptz not null default now(),
 counted_cash_minor bigint not null check(counted_cash_minor between 0 and 9007199254740991),
 expected_cash_minor bigint not null check(expected_cash_minor between -9007199254740991 and 9007199254740991),
 difference_minor bigint not null check(difference_minor between -9007199254740991 and 9007199254740991),reason text not null check(char_length(btrim(reason)) between 3 and 1000),
 unique(organization_id,id),foreign key(organization_id,branch_id,shift_id) references public.shifts(organization_id,branch_id,id),
 check(difference_minor=counted_cash_minor-expected_cash_minor)
);
create table public.sales (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,branch_id uuid not null,shift_id uuid not null,
 actor_user_id uuid not null references auth.users(id),customer_id uuid,receipt_sequence bigint not null check(receipt_sequence between 1 and 9007199254740991),
 receipt_number text not null,currency text not null check(currency in ('PHP','USD','EUR','GBP','AUD','CAD','SGD')),
 business_snapshot jsonb not null check(jsonb_typeof(business_snapshot)='object'),settings_revision bigint not null,
 subtotal_minor bigint not null check(subtotal_minor between 0 and 9007199254740991),discount_minor bigint not null check(discount_minor between 0 and subtotal_minor),
 tax_bps integer not null check(tax_bps between 0 and 10000),tax_minor bigint not null check(tax_minor between 0 and 9007199254740991),
 total_minor bigint not null check(total_minor between 1 and 9007199254740991),discount_reason text,created_at timestamptz not null default now(),
 unique(organization_id,id),unique(organization_id,branch_id,id),unique(organization_id,branch_id,receipt_sequence),
 foreign key(organization_id,branch_id,shift_id) references public.shifts(organization_id,branch_id,id),
 foreign key(organization_id,customer_id) references public.customers(organization_id,id),check(total_minor=subtotal_minor-discount_minor+tax_minor)
);
create table public.sale_items (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,sale_id uuid not null,product_id uuid not null,
 product_name text not null,sku text not null,unit text not null,product_revision bigint not null,quantity bigint not null check(quantity between 1 and 1000000),
 unit_price_minor bigint not null check(unit_price_minor between 0 and 9007199254740991),line_subtotal_minor bigint not null check(line_subtotal_minor between 0 and 9007199254740991),
 discount_minor bigint not null check(discount_minor between 0 and line_subtotal_minor),tax_minor bigint not null check(tax_minor between 0 and 9007199254740991),
 line_total_minor bigint not null check(line_total_minor between 0 and 9007199254740991),
 unique(organization_id,id),unique(organization_id,sale_id,id),unique(sale_id,product_id),
 foreign key(organization_id,sale_id) references public.sales(organization_id,id),foreign key(organization_id,product_id) references public.products(organization_id,id),
 check(line_subtotal_minor=unit_price_minor*quantity),check(line_total_minor=line_subtotal_minor-discount_minor+tax_minor)
);
create table private.sale_cost_snapshots (
 sale_item_id uuid primary key references public.sale_items(id),cost_minor bigint not null check(cost_minor between 0 and 9007199254740991)
);
create table public.sale_payments (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,sale_id uuid not null,
 method text not null check(method in ('cash','card','gcash','maya','other')),amount_minor bigint not null check(amount_minor between 1 and 9007199254740991),
 tendered_minor bigint,change_minor bigint,reference text,manual_confirmed boolean not null default false,
 unique(organization_id,id),unique(organization_id,sale_id,id),foreign key(organization_id,sale_id) references public.sales(organization_id,id),
 check((method='cash' and tendered_minor between amount_minor and 9007199254740991 and change_minor=tendered_minor-amount_minor and reference is null and not manual_confirmed)
  or (method<>'cash' and tendered_minor is null and change_minor is null and manual_confirmed and char_length(btrim(reference)) between 3 and 120))
);
create table public.inventory_operations (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),branch_id uuid not null,
 actor_user_id uuid not null references auth.users(id),kind text not null check(kind in ('receive','adjust')),
 supplier_id uuid,reference text check(char_length(reference)<=120),reason text not null check(char_length(btrim(reason)) between 3 and 1000),created_at timestamptz not null default now(),
 unique(organization_id,id),foreign key(organization_id,branch_id) references public.branches(organization_id,id),foreign key(organization_id,supplier_id) references public.suppliers(organization_id,id)
);
create table public.sale_reversals (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,branch_id uuid not null,sale_id uuid not null,shift_id uuid not null,
 actor_user_id uuid not null references auth.users(id),kind text not null check(kind in ('refund','void')),
 currency text not null,total_minor bigint not null check(total_minor between 0 and 9007199254740991),reason text not null check(char_length(btrim(reason)) between 3 and 1000),created_at timestamptz not null default now(),
 unique(organization_id,id),foreign key(organization_id,branch_id,sale_id) references public.sales(organization_id,branch_id,id),
 foreign key(organization_id,branch_id,shift_id) references public.shifts(organization_id,branch_id,id)
);
create table public.sale_reversal_items (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,reversal_id uuid not null,sale_item_id uuid not null,
 quantity bigint not null check(quantity between 1 and 1000000),amount_minor bigint not null check(amount_minor between 0 and 9007199254740991),
 unique(reversal_id,sale_item_id),foreign key(organization_id,reversal_id) references public.sale_reversals(organization_id,id),foreign key(organization_id,sale_item_id) references public.sale_items(organization_id,id)
);
create table public.sale_reversal_payments (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,reversal_id uuid not null,original_payment_id uuid not null,
 amount_minor bigint not null check(amount_minor between 1 and 9007199254740991),manual_confirmed boolean not null check(manual_confirmed),reference text check(char_length(reference)<=120),
 unique(reversal_id,original_payment_id),foreign key(organization_id,reversal_id) references public.sale_reversals(organization_id,id),
 foreign key(organization_id,original_payment_id) references public.sale_payments(organization_id,id)
);
create table private.stock_balances (
 organization_id uuid not null,branch_id uuid not null,product_id uuid not null,quantity bigint not null default 0 check(quantity between 0 and 9007199254740991),
 primary key(organization_id,branch_id,product_id),foreign key(organization_id,branch_id) references public.branches(organization_id,id),foreign key(organization_id,product_id) references public.products(organization_id,id)
);
create table public.stock_movements (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,branch_id uuid not null,product_id uuid not null,
 actor_user_id uuid not null references auth.users(id),quantity_delta bigint not null check(quantity_delta<>0 and quantity_delta between -1000000 and 1000000),
 balance_after bigint not null check(balance_after between 0 and 9007199254740991),operation_id uuid,sale_id uuid,reversal_id uuid,created_at timestamptz not null default now(),
 foreign key(organization_id,branch_id) references public.branches(organization_id,id),foreign key(organization_id,product_id) references public.products(organization_id,id),
 foreign key(organization_id,operation_id) references public.inventory_operations(organization_id,id),foreign key(organization_id,sale_id) references public.sales(organization_id,id),
 foreign key(organization_id,reversal_id) references public.sale_reversals(organization_id,id),check(num_nonnulls(operation_id,sale_id,reversal_id)=1)
);
create table private.inventory_cost_evidence (movement_id uuid primary key references public.stock_movements(id),unit_cost_minor bigint not null check(unit_cost_minor between 0 and 9007199254740991));
create table private.receipt_sequences (organization_id uuid not null,branch_id uuid not null,next_number bigint not null check(next_number between 1 and 9007199254740991),primary key(organization_id,branch_id));
create table private.operation_requests (
 organization_id uuid not null,actor_user_id uuid not null,request_id uuid not null,kind text not null,payload jsonb not null,result_id uuid not null,created_at timestamptz not null default now(),
 primary key(organization_id,actor_user_id,request_id)
);
create index sales_scope_time on public.sales(organization_id,branch_id,created_at desc,id);
create index stock_scope_time on public.stock_movements(organization_id,branch_id,created_at desc,id);
create index shift_scope_actor on public.shifts(organization_id,actor_user_id,opened_at desc);
create index reversal_sale_scope on public.sale_reversals(organization_id,sale_id);
revoke all on public.shifts,public.shift_closures,public.sales,public.sale_items,public.sale_payments,public.inventory_operations,
 public.sale_reversals,public.sale_reversal_items,public.sale_reversal_payments,public.stock_movements,
 private.stock_balances,private.receipt_sequences,private.operation_requests,private.sale_cost_snapshots,private.inventory_cost_evidence from public,anon,authenticated,service_role;

create function private.phase3_require(p_org uuid,p_branch uuid,p_kind text)
returns public.organization_memberships language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;
begin
 m:=private.require_active_member(p_org);
 perform 1 from auth.users where id=auth.uid() and email_confirmed_at is not null for share;
 if not found then raise exception 'Verified account required' using errcode='42501'; end if;
 perform 1 from public.branches where organization_id=p_org and id=p_branch and active for share;
 if not found or not private.can_access_branch(p_org,p_branch) then raise exception 'Branch access unavailable' using errcode='42501'; end if;
 if not (m.role in ('owner','admin') and m.all_branches) then
  perform 1 from public.membership_branches where organization_id=p_org and membership_id=m.id and branch_id=p_branch for share;
  if not found then raise exception 'Branch assignment unavailable' using errcode='42501'; end if;
 end if;
 if (p_kind='pos' and m.role not in ('owner','admin','manager','cashier')) or
  (p_kind='stock' and m.role not in ('owner','admin','manager','inventory_staff')) or
  (p_kind='manage' and m.role not in ('owner','admin','manager')) then raise exception 'Operation is not permitted' using errcode='42501'; end if;
 if p_kind not in ('pos','stock','manage','read') then raise exception 'Invalid operation' using errcode='22023'; end if;
 return m;
end; $$;
create function private.phase3_can_read(p_org uuid,p_branch uuid,p_actor uuid,p_kind text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) and private.can_access_branch(p_org,p_branch)
 and exists(select 1 from public.organization_memberships m where m.organization_id=p_org and m.user_id=auth.uid() and m.status='active'
  and ((p_kind='sale' and (m.role in ('owner','admin','manager') or (m.role='cashier' and p_actor=auth.uid())))
   or (p_kind='stock' and m.role in ('owner','admin','manager','inventory_staff'))));
$$;
create function private.phase3_request(p_org uuid,p_request uuid,p_kind text,p_payload jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare r private.operation_requests;
begin
 if p_request is null or p_payload is null then raise exception 'Request identifier and payload required' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||':'||auth.uid()::text||':'||p_request::text,0));
 select * into r from private.operation_requests where organization_id=p_org and actor_user_id=auth.uid() and request_id=p_request;
 if found then
  if r.kind<>p_kind or r.payload<>p_payload then raise exception 'Request identifier was reused with different details' using errcode='23505'; end if;
  return r.result_id;
 end if;
 return null;
end; $$;
create function private.phase3_save_request(p_org uuid,p_request uuid,p_kind text,p_payload jsonb,p_result uuid)
returns void language sql security definer set search_path='' as $$
 insert into private.operation_requests(organization_id,actor_user_id,request_id,kind,payload,result_id) values(p_org,auth.uid(),p_request,p_kind,p_payload,p_result);
$$;
create function private.phase3_check_keys(p_value jsonb,p_allowed text[])
returns void language plpgsql set search_path='' as $$
declare k text;
begin
 if jsonb_typeof(p_value) is distinct from 'object' then raise exception 'Expected an object' using errcode='22023'; end if;
 for k in select jsonb_object_keys(p_value) loop
  if not k=any(p_allowed) then raise exception 'Unexpected transaction field: %',k using errcode='22023'; end if;
 end loop;
end; $$;
create function private.phase3_integer(p_value jsonb,p_min bigint,p_max bigint)
returns bigint language plpgsql set search_path='' as $$
declare n numeric;
begin
 if jsonb_typeof(p_value) is distinct from 'number' or (p_value::text) !~ '^-?[0-9]+$' then raise exception 'An exact whole integer is required' using errcode='22023'; end if;
 n:=(p_value::text)::numeric;
 if n<p_min or n>p_max then raise exception 'Integer is outside the permitted range' using errcode='22023'; end if;
 return n::bigint;
end; $$;
create function private.phase3_apply_movement()
returns trigger language plpgsql security definer set search_path='' as $$
declare n numeric;
begin
 insert into private.stock_balances(organization_id,branch_id,product_id,quantity) values(new.organization_id,new.branch_id,new.product_id,0) on conflict do nothing;
 select quantity::numeric+new.quantity_delta into n from private.stock_balances where organization_id=new.organization_id and branch_id=new.branch_id and product_id=new.product_id for update;
 if n<0 then raise exception 'Insufficient stock; reload availability' using errcode='23514'; end if;
 if n>9007199254740991 then raise exception 'Stock exceeds exact quantity limit' using errcode='22023'; end if;
 new.balance_after:=n::bigint;
 update private.stock_balances set quantity=new.balance_after where organization_id=new.organization_id and branch_id=new.branch_id and product_id=new.product_id;
 return new;
end; $$;
create trigger stock_projection before insert on public.stock_movements for each row execute function private.phase3_apply_movement();
-- Frozen history has no application/service mutation grant; owner maintenance is
-- also guarded against accidental UPDATE/DELETE/TRUNCATE.
do $$ declare t text; begin
 foreach t in array array['shifts','shift_closures','sales','sale_items','sale_payments','inventory_operations','sale_reversals','sale_reversal_items','sale_reversal_payments','stock_movements'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('create trigger immutable_history before update or delete on public.%I for each row execute function private.reject_immutable_mutation()',t);
  execute format('create trigger immutable_no_truncate before truncate on public.%I for each statement execute function private.reject_immutable_mutation()',t);
 end loop;
 foreach t in array array['operation_requests','sale_cost_snapshots','inventory_cost_evidence'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('create trigger immutable_history before update or delete on private.%I for each row execute function private.reject_immutable_mutation()',t);
  execute format('create trigger immutable_no_truncate before truncate on private.%I for each statement execute function private.reject_immutable_mutation()',t);
 end loop;
end; $$;
create policy shifts_read on public.shifts for select to authenticated using(private.phase3_can_read(organization_id,branch_id,actor_user_id,'sale'));
create policy closures_read on public.shift_closures for select to authenticated using(exists(select 1 from public.shifts s where s.id=shift_id));
create policy sales_read on public.sales for select to authenticated using(private.phase3_can_read(organization_id,branch_id,actor_user_id,'sale'));
create policy items_read on public.sale_items for select to authenticated using(exists(select 1 from public.sales s where s.id=sale_id));
create policy payments_read on public.sale_payments for select to authenticated using(exists(select 1 from public.sales s where s.id=sale_id));
create policy operations_read on public.inventory_operations for select to authenticated using(private.phase3_can_read(organization_id,branch_id,actor_user_id,'stock'));
create policy movements_read on public.stock_movements for select to authenticated using(private.phase3_can_read(organization_id,branch_id,actor_user_id,'stock'));
create policy reversals_read on public.sale_reversals for select to authenticated using(exists(select 1 from public.sales s where s.id=sale_id));
create policy reversal_items_read on public.sale_reversal_items for select to authenticated using(exists(select 1 from public.sale_reversals r where r.id=reversal_id));
create policy reversal_payments_read on public.sale_reversal_payments for select to authenticated using(exists(select 1 from public.sale_reversals r where r.id=reversal_id));
grant select on public.shifts,public.shift_closures,public.sales,public.sale_items,public.sale_payments,public.inventory_operations,
 public.sale_reversals,public.sale_reversal_items,public.sale_reversal_payments,public.stock_movements to authenticated;
alter table public.sale_reversals add column return_stock boolean not null default false;
create function private.phase3_expected_cash(p_shift uuid)
returns bigint language sql stable security definer set search_path='' as $$
 select (s.opening_cash_minor::numeric
  +coalesce((select sum(p.amount_minor::numeric) from public.sale_payments p join public.sales x on x.id=p.sale_id where x.shift_id=s.id and p.method='cash'),0)
  -coalesce((select sum(p.amount_minor::numeric) from public.sale_reversal_payments p join public.sale_reversals r on r.id=p.reversal_id
    join public.sale_payments original on original.id=p.original_payment_id where r.shift_id=s.id and original.method='cash'),0))::bigint
 from public.shifts s where s.id=p_shift;
$$;
create function private.phase3_shift_json(p_shift uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(s)||jsonb_build_object('request_id',(select request_id from private.operation_requests where result_id=s.id and kind='shift.open'),'expected_cash_minor',private.phase3_expected_cash(s.id),
  'closure',(select to_jsonb(c) from public.shift_closures c where c.shift_id=s.id)) from public.shifts s where s.id=p_shift;
$$;
create function private.phase3_sale_json(p_sale uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(s)||s.business_snapshot||jsonb_build_object(
  'request_id',(select request_id from private.operation_requests where result_id=s.id and kind='sale.checkout'),'items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object(
   'reversed_quantity',coalesce((select sum(r.quantity) from public.sale_reversal_items r where r.sale_item_id=i.id),0)::bigint,
   'remaining_quantity',i.quantity-coalesce((select sum(r.quantity) from public.sale_reversal_items r where r.sale_item_id=i.id),0)::bigint) order by i.product_id)
   from public.sale_items i where i.sale_id=s.id),'[]'::jsonb),
  'payments',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object(
   'reversed_minor',coalesce((select sum(r.amount_minor) from public.sale_reversal_payments r where r.original_payment_id=p.id),0)::bigint,
   'remaining_minor',p.amount_minor-coalesce((select sum(r.amount_minor) from public.sale_reversal_payments r where r.original_payment_id=p.id),0)::bigint) order by p.id)
   from public.sale_payments p where p.sale_id=s.id),'[]'::jsonb),
  'reversed_minor',coalesce((select sum(r.total_minor) from public.sale_reversals r where r.sale_id=s.id),0)::bigint,
  'reversals',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at,r.id) from public.sale_reversals r where r.sale_id=s.id),'[]'::jsonb))
 from public.sales s where s.id=p_sale;
$$;
create function private.phase3_operation_json(p_operation uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(o)||jsonb_build_object('request_id',(select request_id from private.operation_requests where result_id=o.id and kind in ('stock.receive','stock.adjust')),'movements',coalesce((select jsonb_agg(to_jsonb(m) order by m.product_id) from public.stock_movements m where m.operation_id=o.id),'[]'::jsonb))
 from public.inventory_operations o where o.id=p_operation;
$$;
create function private.phase3_reversal_json(p_reversal uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(r)||jsonb_build_object('request_id',(select request_id from private.operation_requests where result_id=r.id and kind='sale.reverse'),'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.sale_item_id) from public.sale_reversal_items i where i.reversal_id=r.id),'[]'::jsonb),
  'payments',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('method',o.method) order by p.original_payment_id)
   from public.sale_reversal_payments p join public.sale_payments o on o.id=p.original_payment_id where p.reversal_id=r.id),'[]'::jsonb),
  'sale',private.phase3_sale_json(r.sale_id)) from public.sale_reversals r where r.id=p_reversal;
$$;
create function public.get_pos_context(p_organization_id uuid,p_branch_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;o public.organizations;b public.branches;
begin
 m:=private.phase3_require(p_organization_id,p_branch_id,'pos');
 select * into o from public.organizations where id=p_organization_id;
 select * into b from public.branches where id=p_branch_id;
 if o.currency not in ('PHP','USD','EUR','GBP','AUD','CAD','SGD') then raise exception 'This currency is not supported for two-decimal transactions' using errcode='22023'; end if;
 return jsonb_build_object('organization_id',o.id,'branch_id',b.id,'branch_name',b.name,'branch_code',b.code,'currency',o.currency,
  'tax_bps',o.tax_bps,'settings_revision',o.revision,'business_name',o.business_name,'address',o.address,'contact',o.contact,'receipt_footer',o.receipt_footer);
end; $$;
create function public.list_pos_products(p_organization_id uuid,p_branch_id uuid,p_query text default '',p_category_id uuid default null,p_offset integer default 0,p_limit integer default 51)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;r jsonb;
begin
 m:=private.phase3_require(p_organization_id,p_branch_id,'read');
 if p_limit is null or p_limit not between 1 and 101 or p_offset is null or p_offset not between 0 and 1000000 or char_length(coalesce(p_query,''))>120 then raise exception 'Invalid product page' using errcode='22023'; end if;
 select coalesce(jsonb_agg(row_json order by name,id),'[]'::jsonb) into r from (
  select p.name,p.id,to_jsonb(p)||jsonb_build_object('cost_minor',case when m.role='cashier' then null else p.cost_minor end,
   'reorder_level',p.reorder_level::text,'available_quantity',coalesce(b.quantity,0)) row_json
  from public.products p left join private.stock_balances b on b.organization_id=p.organization_id and b.product_id=p.id and b.branch_id=p_branch_id
  where p.organization_id=p_organization_id and p.active and (p.category_id is null or exists(select 1 from public.categories c where c.id=p.category_id and c.active)) and (p_category_id is null or p.category_id=p_category_id)
   and (coalesce(p_query,'')='' or p.name ilike '%'||p_query||'%' or p.sku ilike '%'||p_query||'%' or p.barcode ilike '%'||p_query||'%')
  order by p.name,p.id offset p_offset limit p_limit) page;
 return r;
end; $$;
create function public.lookup_pos_product_by_barcode(p_organization_id uuid,p_branch_id uuid,p_barcode text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;r jsonb;
begin
 m:=private.phase3_require(p_organization_id,p_branch_id,'pos');
 if p_barcode is null or char_length(btrim(p_barcode)) not between 1 and 128 then raise exception 'Invalid barcode' using errcode='22023'; end if;
 select to_jsonb(p)||jsonb_build_object('cost_minor',case when m.role='cashier' then null else p.cost_minor end,'reorder_level',p.reorder_level::text,'available_quantity',coalesce(b.quantity,0))
 into r from public.products p left join private.stock_balances b on b.organization_id=p.organization_id and b.product_id=p.id and b.branch_id=p_branch_id
 where p.organization_id=p_organization_id and p.active and (p.category_id is null or exists(select 1 from public.categories c where c.id=p.category_id and c.active)) and p.barcode=p_barcode;
 return r;
end; $$;
create function public.open_shift(p_organization_id uuid,p_branch_id uuid,p_request_id uuid,p_opening_cash_minor bigint,p_expected_currency text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;payload jsonb;v_id uuid;c text;
begin
 m:=private.phase3_require(p_organization_id,p_branch_id,'pos');
 payload:=jsonb_build_object('branch_id',p_branch_id,'opening_cash_minor',p_opening_cash_minor,'expected_currency',p_expected_currency);
 v_id:=private.phase3_request(p_organization_id,p_request_id,'shift.open',payload);
 if v_id is not null then return private.phase3_shift_json(v_id); end if;
 if p_opening_cash_minor is null or p_opening_cash_minor not between 0 and 9007199254740991 then raise exception 'Invalid opening cash amount' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('shift:'||p_organization_id::text||':'||auth.uid()::text,0));
 if exists(select 1 from public.shifts s where s.organization_id=p_organization_id and s.actor_user_id=auth.uid() and not exists(select 1 from public.shift_closures x where x.shift_id=s.id)) then
  raise exception 'An open shift already exists; close it before opening another' using errcode='23505'; end if;
 select currency into c from public.organizations where id=p_organization_id for share;
 if p_expected_currency is null or p_expected_currency<>c then raise exception 'Business currency changed; reload before opening the shift' using errcode='40001'; end if;
 if c not in ('PHP','USD','EUR','GBP','AUD','CAD','SGD') then raise exception 'Unsupported transaction currency' using errcode='22023'; end if;
 insert into public.shifts(organization_id,branch_id,actor_user_id,currency,opening_cash_minor) values(p_organization_id,p_branch_id,auth.uid(),c,p_opening_cash_minor) returning id into v_id;
 perform private.phase3_save_request(p_organization_id,p_request_id,'shift.open',payload,v_id);
 perform private.append_action_audit(p_organization_id,'shift.opened','shifts',v_id,p_branch_id,'Opened shift',jsonb_build_object('opening_cash_minor',p_opening_cash_minor));
 return private.phase3_shift_json(v_id);
end; $$;
create function public.get_current_shift(p_organization_id uuid,p_branch_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'pos');
 select s.id into v_id from public.shifts s where s.organization_id=p_organization_id and s.branch_id=p_branch_id and s.actor_user_id=auth.uid()
  and not exists(select 1 from public.shift_closures c where c.shift_id=s.id) order by s.opened_at desc,s.id limit 1;
 return private.phase3_shift_json(v_id);
end; $$;
create function public.close_shift(p_organization_id uuid,p_shift_id uuid,p_request_id uuid,p_counted_cash_minor bigint,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;s public.shifts;payload jsonb;v_id uuid;expected numeric;
begin
 m:=private.require_active_member(p_organization_id);
 if m.role not in ('owner','admin','manager','cashier') then raise exception 'Operation is not permitted' using errcode='42501'; end if;
 select * into s from public.shifts where id=p_shift_id and organization_id=p_organization_id;
 if not found then raise exception 'Shift unavailable' using errcode='P0002'; end if;
 m:=private.phase3_require(p_organization_id,s.branch_id,'pos');
 if m.role='cashier' and s.actor_user_id<>auth.uid() then raise exception 'Only your own shift may be closed' using errcode='42501'; end if;
 payload:=jsonb_build_object('shift_id',p_shift_id,'counted_cash_minor',p_counted_cash_minor,'reason',p_reason);
 v_id:=private.phase3_request(p_organization_id,p_request_id,'shift.close',payload);
 if v_id is not null then return private.phase3_shift_json(p_shift_id)||jsonb_build_object('request_id',p_request_id,'closing_request_id',p_request_id); end if;
 select * into s from public.shifts where id=p_shift_id for update;
 if exists(select 1 from public.shift_closures where shift_id=p_shift_id) then raise exception 'Shift is already closed' using errcode='40001'; end if;
 if p_counted_cash_minor is null or p_counted_cash_minor not between 0 and 9007199254740991 or p_reason is null or char_length(btrim(p_reason)) not between 3 and 1000 then raise exception 'Invalid shift count or reason' using errcode='22023'; end if;
 expected:=private.phase3_expected_cash(p_shift_id);
 if expected not between -9007199254740991 and 9007199254740991 or p_counted_cash_minor::numeric-expected not between -9007199254740991 and 9007199254740991 then raise exception 'Cash count exceeds exact amount limit' using errcode='22023'; end if;
 insert into public.shift_closures(organization_id,branch_id,shift_id,closed_by,counted_cash_minor,expected_cash_minor,difference_minor,reason)
  values(p_organization_id,s.branch_id,s.id,auth.uid(),p_counted_cash_minor,expected::bigint,(p_counted_cash_minor::numeric-expected)::bigint,btrim(p_reason)) returning id into v_id;
 perform private.phase3_save_request(p_organization_id,p_request_id,'shift.close',payload,v_id);
 perform private.append_action_audit(p_organization_id,'shift.closed','shifts',s.id,s.branch_id,btrim(p_reason),jsonb_build_object('counted_cash_minor',p_counted_cash_minor,'expected_cash_minor',expected,'difference_minor',p_counted_cash_minor::numeric-expected));
 return private.phase3_shift_json(s.id)||jsonb_build_object('request_id',p_request_id,'closing_request_id',p_request_id);
end; $$;
create function public.checkout_sale(p_organization_id uuid,p_branch_id uuid,p_request_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 m public.organization_memberships;s public.shifts;o public.organizations;p public.products;b public.branches;
 payload jsonb;v_id uuid;item jsonb;pay jsonb;lines jsonb:='[]';line jsonb;qty bigint;rev bigint;
 subtotal numeric:=0;discount bigint;tax_total numeric:=0;total numeric;line_subtotal numeric;line_discount numeric;cumulative numeric:=0;previous_discount numeric:=0;line_tax numeric;
 paid numeric:=0;cash_paid numeric:=0;amount bigint;tendered bigint;method text;reference text;reason text;customer uuid;item_id uuid;receipt bigint;
begin
 m:=private.phase3_require(p_organization_id,p_branch_id,'pos');
 perform private.phase3_check_keys(p_payload,array['shift_id','expected_settings_revision','items','discount_minor','payments','reason','customer_id']);
 payload:=jsonb_build_object('branch_id',p_branch_id,'details',p_payload);
 v_id:=private.phase3_request(p_organization_id,p_request_id,'sale.checkout',payload);
 if v_id is not null then return private.phase3_sale_json(v_id); end if;
 select * into s from public.shifts where organization_id=p_organization_id and branch_id=p_branch_id and id=(p_payload->>'shift_id')::uuid for update;
 if not found or s.actor_user_id<>auth.uid() then raise exception 'Your open shift is required' using errcode='42501'; end if;
 if exists(select 1 from public.shift_closures where shift_id=s.id) then raise exception 'Shift is closed' using errcode='40001'; end if;
 select * into o from public.organizations where id=p_organization_id for share;
 if private.phase3_integer(p_payload->'expected_settings_revision',1,9007199254740991)<>o.revision then raise exception 'POS settings changed; reload before checkout' using errcode='40001'; end if;
 if o.currency<>s.currency then raise exception 'Business currency changed; close this shift and reopen' using errcode='40001'; end if;
 if jsonb_typeof(p_payload->'items') is distinct from 'array' or jsonb_array_length(p_payload->'items') not between 1 and 100 then raise exception 'Checkout requires 1 to 100 unique products' using errcode='22023'; end if;
 if (select count(distinct (x->>'product_id')::uuid) from jsonb_array_elements(p_payload->'items') x)<>jsonb_array_length(p_payload->'items') then raise exception 'Duplicate product lines are not permitted' using errcode='22023'; end if;
 discount:=private.phase3_integer(coalesce(p_payload->'discount_minor','0'::jsonb),0,9007199254740991);
 reason:=nullif(btrim(p_payload->>'reason'),'');
 if discount>0 and (m.role not in ('owner','admin','manager') or reason is null or char_length(reason) not between 3 and 1000) then raise exception 'Discount requires authorized manager role and reason' using errcode='42501'; end if;
 if reason is not null and char_length(reason)>1000 then raise exception 'Reason is too long' using errcode='22023'; end if;
 customer:=nullif(p_payload->>'customer_id','')::uuid;
 if customer is not null then
  perform 1 from public.customers where organization_id=p_organization_id and id=customer and active and (branch_id is null or branch_id=p_branch_id) for share;
  if not found then raise exception 'Customer is unavailable in this branch' using errcode='22023'; end if;
 end if;
 -- Stable UUID order serializes every multi-product ledger operation.
 for item in select value from jsonb_array_elements(p_payload->'items') order by (value->>'product_id')::uuid loop
  perform private.phase3_check_keys(item,array['product_id','quantity','expected_revision']);
  qty:=private.phase3_integer(item->'quantity',1,1000000);rev:=private.phase3_integer(item->'expected_revision',1,9007199254740991);
  select * into p from public.products where organization_id=p_organization_id and id=(item->>'product_id')::uuid for update;
  if not found then raise exception 'Product unavailable in this organization' using errcode='P0002'; end if;
  if not p.active then raise exception 'Product is inactive' using errcode='22023'; end if;
  if p.revision<>rev then raise exception 'Product changed; reload prices before checkout' using errcode='40001'; end if;
  if p.currency<>s.currency then raise exception 'Product currency does not match this shift' using errcode='22023'; end if;
  if p.category_id is not null then
   perform 1 from public.categories where organization_id=p_organization_id and id=p.category_id and active for share;
   if not found then raise exception 'Product category is inactive' using errcode='22023'; end if;
  end if;
  line_subtotal:=p.price_minor::numeric*qty;
  subtotal:=subtotal+line_subtotal;
  if subtotal>9007199254740991 then raise exception 'Checkout exceeds exact monetary limit' using errcode='22023'; end if;
  lines:=lines||jsonb_build_array(jsonb_build_object('product_id',p.id,'product_name',p.name,'sku',p.sku,'unit',p.unit,'product_revision',p.revision,'quantity',qty,'unit_price_minor',p.price_minor,'cost_minor',p.cost_minor,'line_subtotal_minor',line_subtotal));
 end loop;
 if subtotal=0 or discount>subtotal then raise exception 'A positive sale subtotal and valid discount are required' using errcode='22023'; end if;
 for line in select value from jsonb_array_elements(lines) loop
  cumulative:=cumulative+(line->>'line_subtotal_minor')::numeric;
  line_discount:=div(discount::numeric*cumulative,subtotal)-previous_discount;previous_discount:=previous_discount+line_discount;
  line_tax:=floor((((line->>'line_subtotal_minor')::numeric-line_discount)*o.tax_bps+5000)/10000);
  tax_total:=tax_total+line_tax;
 end loop;
 total:=subtotal-discount+tax_total;
 if total not between 1 and 9007199254740991 then raise exception 'Sale total must be positive and within the exact monetary limit' using errcode='22023'; end if;
 if jsonb_typeof(p_payload->'payments') is distinct from 'array' or jsonb_array_length(p_payload->'payments') not between 1 and 5 then raise exception 'One to five payment records are required' using errcode='22023'; end if;
 for pay in select value from jsonb_array_elements(p_payload->'payments') loop
  perform private.phase3_check_keys(pay,array['method','amount_minor','tendered_minor','reference','manual_confirmed']);
  method:=pay->>'method';amount:=private.phase3_integer(pay->'amount_minor',1,9007199254740991);paid:=paid+amount;
  if method='cash' then
   tendered:=private.phase3_integer(pay->'tendered_minor',amount,9007199254740991);cash_paid:=cash_paid+amount;
   if nullif(pay->>'reference','') is not null or coalesce(pay->'manual_confirmed','false'::jsonb)<>'false'::jsonb then raise exception 'Cash evidence must describe the counted tender only' using errcode='22023'; end if;
  elsif method in ('card','gcash','maya','other') then
   reference:=nullif(btrim(pay->>'reference'),'');
   if pay->'manual_confirmed' is distinct from 'true'::jsonb or reference is null or char_length(reference) not between 3 and 120 or (pay->'tendered_minor' is not null and pay->'tendered_minor'<>'null'::jsonb) then raise exception 'Digital payment requires explicit manual confirmation and reference; no provider is connected' using errcode='22023'; end if;
  else raise exception 'Unsupported payment method' using errcode='22023'; end if;
 end loop;
 if paid<>total then raise exception 'Payment applied amounts must exactly equal the server total' using errcode='22023'; end if;
 if private.phase3_expected_cash(s.id)::numeric+cash_paid not between -9007199254740991 and 9007199254740991 then raise exception 'Shift cash exceeds exact monetary limit' using errcode='22023'; end if;
 select * into b from public.branches where id=p_branch_id;
 insert into private.receipt_sequences(organization_id,branch_id,next_number) values(p_organization_id,p_branch_id,1)
  on conflict(organization_id,branch_id) do update set next_number=private.receipt_sequences.next_number+1 returning next_number into receipt;
 insert into public.sales(organization_id,branch_id,shift_id,actor_user_id,customer_id,receipt_sequence,receipt_number,currency,business_snapshot,settings_revision,subtotal_minor,discount_minor,tax_bps,tax_minor,total_minor,discount_reason)
  values(p_organization_id,p_branch_id,s.id,auth.uid(),customer,receipt,b.code||'-'||case when receipt<1000000 then lpad(receipt::text,6,'0') else receipt::text end,s.currency,
   jsonb_build_object('business_name',o.business_name,'address',o.address,'contact',o.contact,'receipt_footer',o.receipt_footer,'branch_name',b.name,'branch_code',b.code),o.revision,subtotal::bigint,discount,o.tax_bps,tax_total::bigint,total::bigint,case when discount>0 then reason else null end) returning id into v_id;
 cumulative:=0;previous_discount:=0;
 for line in select value from jsonb_array_elements(lines) loop
  line_subtotal:=(line->>'line_subtotal_minor')::numeric;cumulative:=cumulative+line_subtotal;
  line_discount:=div(discount::numeric*cumulative,subtotal)-previous_discount;previous_discount:=previous_discount+line_discount;
  line_tax:=floor(((line_subtotal-line_discount)*o.tax_bps+5000)/10000);
  insert into public.sale_items(organization_id,sale_id,product_id,product_name,sku,unit,product_revision,quantity,unit_price_minor,line_subtotal_minor,discount_minor,tax_minor,line_total_minor)
   values(p_organization_id,v_id,(line->>'product_id')::uuid,line->>'product_name',line->>'sku',line->>'unit',(line->>'product_revision')::bigint,(line->>'quantity')::bigint,
    (line->>'unit_price_minor')::bigint,line_subtotal::bigint,line_discount::bigint,line_tax::bigint,(line_subtotal-line_discount+line_tax)::bigint) returning id into item_id;
  insert into private.sale_cost_snapshots(sale_item_id,cost_minor) values(item_id,(line->>'cost_minor')::bigint);
  insert into public.stock_movements(organization_id,branch_id,product_id,actor_user_id,quantity_delta,balance_after,sale_id)
   values(p_organization_id,p_branch_id,(line->>'product_id')::uuid,auth.uid(),-(line->>'quantity')::bigint,0,v_id);
 end loop;
 for pay in select value from jsonb_array_elements(p_payload->'payments') loop
  method:=pay->>'method';amount:=(pay->>'amount_minor')::bigint;
  insert into public.sale_payments(organization_id,sale_id,method,amount_minor,tendered_minor,change_minor,reference,manual_confirmed)
   values(p_organization_id,v_id,method,amount,case when method='cash' then (pay->>'tendered_minor')::bigint end,
    case when method='cash' then (pay->>'tendered_minor')::bigint-amount end,case when method<>'cash' then btrim(pay->>'reference') end,method<>'cash');
 end loop;
 perform private.phase3_save_request(p_organization_id,p_request_id,'sale.checkout',payload,v_id);
 perform private.append_action_audit(p_organization_id,'sale.accepted','sales',v_id,p_branch_id,coalesce(reason,'Online checkout'),jsonb_build_object('receipt_number',b.code||'-'||receipt::text,'total_minor',total,'currency',s.currency,'discount_minor',discount));
 return private.phase3_sale_json(v_id);
exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'Invalid transaction identifier or exact amount' using errcode='22023';
end; $$;
alter table private.inventory_cost_evidence add column currency text not null,add column product_revision bigint not null;
create function public.receive_stock(p_organization_id uuid,p_branch_id uuid,p_request_id uuid,p_items jsonb,p_supplier_id uuid default null,p_reference text default null,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;v_id uuid;item jsonb;p public.products;qty bigint;rev bigint;cost bigint;movement uuid;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'stock');
 payload:=jsonb_build_object('branch_id',p_branch_id,'items',p_items,'supplier_id',p_supplier_id,'reference',p_reference,'reason',p_reason);
 v_id:=private.phase3_request(p_organization_id,p_request_id,'stock.receive',payload);
 if v_id is not null then return private.phase3_operation_json(v_id); end if;
 if p_reason is null or char_length(btrim(p_reason)) not between 3 and 1000 or char_length(p_reference)>120 then raise exception 'Stock receipt requires a valid reason/reference' using errcode='22023'; end if;
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Receipt requires 1 to 100 unique products' using errcode='22023'; end if;
 if (select count(distinct (x->>'product_id')::uuid) from jsonb_array_elements(p_items) x)<>jsonb_array_length(p_items) then raise exception 'Duplicate stock receipt products' using errcode='22023'; end if;
 if p_supplier_id is not null then
  perform 1 from public.suppliers where organization_id=p_organization_id and id=p_supplier_id and active and (branch_id is null or branch_id=p_branch_id) for share;
  if not found then raise exception 'Supplier unavailable in this branch' using errcode='22023'; end if;
 end if;
 -- Lock and validate every line BEFORE appending the receipt's first movement.
 for item in select value from jsonb_array_elements(p_items) order by (value->>'product_id')::uuid loop
  perform private.phase3_check_keys(item,array['product_id','quantity','expected_revision','unit_cost_minor']);
  qty:=private.phase3_integer(item->'quantity',1,1000000);rev:=private.phase3_integer(item->'expected_revision',1,9007199254740991);
  select * into p from public.products where organization_id=p_organization_id and id=(item->>'product_id')::uuid for update;
  if not found then raise exception 'Product unavailable' using errcode='P0002'; end if;
  if not p.active then raise exception 'Inactive products cannot be received' using errcode='22023'; end if;
  if rev<>p.revision then raise exception 'Product changed; reload before receiving' using errcode='40001'; end if;
  if item->'unit_cost_minor' is not null and item->'unit_cost_minor'<>'null'::jsonb then cost:=private.phase3_integer(item->'unit_cost_minor',0,9007199254740991); end if;
 end loop;
 insert into public.inventory_operations(organization_id,branch_id,actor_user_id,kind,supplier_id,reference,reason)
  values(p_organization_id,p_branch_id,auth.uid(),'receive',p_supplier_id,nullif(btrim(p_reference),''),btrim(p_reason)) returning id into v_id;
 for item in select value from jsonb_array_elements(p_items) order by (value->>'product_id')::uuid loop
  select * into p from public.products where organization_id=p_organization_id and id=(item->>'product_id')::uuid;
  cost:=case when item->'unit_cost_minor' is null or item->'unit_cost_minor'='null'::jsonb then p.cost_minor else (item->>'unit_cost_minor')::bigint end;
  insert into public.stock_movements(organization_id,branch_id,product_id,actor_user_id,quantity_delta,balance_after,operation_id)
   values(p_organization_id,p_branch_id,p.id,auth.uid(),(item->>'quantity')::bigint,0,v_id) returning id into movement;
  insert into private.inventory_cost_evidence(movement_id,unit_cost_minor,currency,product_revision) values(movement,cost,p.currency,p.revision);
 end loop;
 perform private.phase3_save_request(p_organization_id,p_request_id,'stock.receive',payload,v_id);
 perform private.append_action_audit(p_organization_id,'stock.received','inventory_operations',v_id,p_branch_id,btrim(p_reason),jsonb_build_object('line_count',jsonb_array_length(p_items),'supplier_id',p_supplier_id));
 return private.phase3_operation_json(v_id);
exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'Invalid receipt identifier or quantity' using errcode='22023';
end; $$;
create function public.adjust_stock(p_organization_id uuid,p_branch_id uuid,p_request_id uuid,p_product_id uuid,p_delta_quantity bigint,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;v_id uuid;p public.products;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'manage');
 payload:=jsonb_build_object('branch_id',p_branch_id,'product_id',p_product_id,'delta_quantity',p_delta_quantity,'reason',p_reason);
 v_id:=private.phase3_request(p_organization_id,p_request_id,'stock.adjust',payload);
 if v_id is not null then return private.phase3_operation_json(v_id); end if;
 if p_delta_quantity is null or p_delta_quantity=0 or p_delta_quantity not between -1000000 and 1000000 or p_reason is null or char_length(btrim(p_reason)) not between 3 and 1000 then raise exception 'A nonzero whole-unit adjustment and reason are required' using errcode='22023'; end if;
 select * into p from public.products where organization_id=p_organization_id and id=p_product_id for update;
 if not found then raise exception 'Product unavailable' using errcode='P0002'; end if;
 insert into public.inventory_operations(organization_id,branch_id,actor_user_id,kind,reason) values(p_organization_id,p_branch_id,auth.uid(),'adjust',btrim(p_reason)) returning id into v_id;
 insert into public.stock_movements(organization_id,branch_id,product_id,actor_user_id,quantity_delta,balance_after,operation_id)
  values(p_organization_id,p_branch_id,p_product_id,auth.uid(),p_delta_quantity,0,v_id);
 perform private.phase3_save_request(p_organization_id,p_request_id,'stock.adjust',payload,v_id);
 perform private.append_action_audit(p_organization_id,'stock.adjusted','inventory_operations',v_id,p_branch_id,btrim(p_reason),jsonb_build_object('product_id',p_product_id,'quantity_delta',p_delta_quantity));
 return private.phase3_operation_json(v_id);
end; $$;
create function public.list_inventory(p_organization_id uuid,p_branch_id uuid,p_query text default '',p_offset integer default 0,p_limit integer default 51)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'stock');
 if p_limit is null or p_limit not between 1 and 101 or p_offset is null or p_offset not between 0 and 1000000 or char_length(coalesce(p_query,''))>120 then raise exception 'Invalid inventory page' using errcode='22023'; end if;
 select coalesce(jsonb_agg(row_json order by name,id),'[]'::jsonb) into r from (
  select p.name,p.id,to_jsonb(p)||jsonb_build_object('reorder_level',p.reorder_level::text,'available_quantity',coalesce(b.quantity,0)) row_json
  from public.products p left join private.stock_balances b on b.organization_id=p.organization_id and b.product_id=p.id and b.branch_id=p_branch_id
  where p.organization_id=p_organization_id and (coalesce(p_query,'')='' or p.name ilike '%'||p_query||'%' or p.sku ilike '%'||p_query||'%' or p.barcode ilike '%'||p_query||'%')
  order by p.name,p.id offset p_offset limit p_limit) page;
 return r;
end; $$;
create function public.list_stock_movements(p_organization_id uuid,p_branch_id uuid,p_product_id uuid default null,p_offset integer default 0,p_limit integer default 51)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'stock');
 if p_offset is null or p_offset not between 0 and 1000000 or p_limit is null or p_limit not between 1 and 101 then raise exception 'Invalid ledger page' using errcode='22023'; end if;
 select coalesce(jsonb_agg(row_json order by created_at desc,id desc),'[]'::jsonb) into r from (
  select m.created_at,m.id,to_jsonb(m)||jsonb_build_object('product_name',p.name,'sku',p.sku,
   'kind',case when m.operation_id is not null then o.kind when m.sale_id is not null then 'sale' else v.kind end,
   'source_id',coalesce(m.operation_id,m.sale_id,m.reversal_id),'reason',coalesce(o.reason,v.reason,'Online checkout'),'reference',o.reference) row_json
  from public.stock_movements m join public.products p on p.id=m.product_id left join public.inventory_operations o on o.id=m.operation_id left join public.sale_reversals v on v.id=m.reversal_id
  where m.organization_id=p_organization_id and m.branch_id=p_branch_id and (p_product_id is null or m.product_id=p_product_id)
  order by m.created_at desc,m.id desc offset p_offset limit p_limit) page;
 return r;
end; $$;
create function public.list_shifts(p_organization_id uuid,p_branch_id uuid default null,p_offset integer default 0,p_limit integer default 51)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;r jsonb;
begin
 m:=private.require_active_member(p_organization_id);
 if m.role not in ('owner','admin','manager','cashier') then raise exception 'Shift history unavailable' using errcode='42501'; end if;
 if p_branch_id is not null then perform private.phase3_require(p_organization_id,p_branch_id,'pos'); end if;
 if p_offset is null or p_offset not between 0 and 1000000 or p_limit is null or p_limit not between 1 and 101 then raise exception 'Invalid shift page' using errcode='22023'; end if;
 select coalesce(jsonb_agg(row_json order by opened_at desc,id desc),'[]'::jsonb) into r from (
  select s.opened_at,s.id,private.phase3_shift_json(s.id) row_json from public.shifts s where s.organization_id=p_organization_id
   and (p_branch_id is null or s.branch_id=p_branch_id) and private.phase3_can_read(s.organization_id,s.branch_id,s.actor_user_id,'sale')
  order by s.opened_at desc,s.id desc offset p_offset limit p_limit) page;
 return r;
end; $$;
create function public.list_sales(p_organization_id uuid,p_branch_id uuid default null,p_query text default '',p_offset integer default 0,p_limit integer default 51)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;r jsonb;
begin
 m:=private.require_active_member(p_organization_id);
 if m.role not in ('owner','admin','manager','cashier') then raise exception 'Sales history unavailable' using errcode='42501'; end if;
 if p_branch_id is not null then perform private.phase3_require(p_organization_id,p_branch_id,'pos'); end if;
 if p_offset is null or p_offset not between 0 and 1000000 or p_limit is null or p_limit not between 1 and 101 or char_length(coalesce(p_query,''))>120 then raise exception 'Invalid sales page' using errcode='22023'; end if;
 select coalesce(jsonb_agg(row_json order by created_at desc,id desc),'[]'::jsonb) into r from (
  select s.created_at,s.id,private.phase3_sale_json(s.id) row_json from public.sales s where s.organization_id=p_organization_id
   and (p_branch_id is null or s.branch_id=p_branch_id) and (coalesce(p_query,'')='' or s.receipt_number ilike '%'||p_query||'%')
   and private.phase3_can_read(s.organization_id,s.branch_id,s.actor_user_id,'sale')
  order by s.created_at desc,s.id desc offset p_offset limit p_limit) page;
 return r;
end; $$;
create function public.get_sale(p_organization_id uuid,p_sale_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.sales;m public.organization_memberships;
begin
 m:=private.require_active_member(p_organization_id);
 if m.role not in ('owner','admin','manager','cashier') then raise exception 'Operation is not permitted' using errcode='42501'; end if;
 select * into s from public.sales where id=p_sale_id and organization_id=p_organization_id;
 if not found then raise exception 'Sale unavailable' using errcode='P0002'; end if;
 perform private.phase3_require(p_organization_id,s.branch_id,'pos');
 if not private.phase3_can_read(p_organization_id,s.branch_id,s.actor_user_id,'sale') then raise exception 'Sale access unavailable' using errcode='42501'; end if;
 return private.phase3_sale_json(s.id);
end; $$;
create function public.get_sale_by_request(p_organization_id uuid,p_branch_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'pos');
 select r.result_id into v_id from private.operation_requests r join public.sales s on s.id=r.result_id and s.branch_id=p_branch_id
  where r.organization_id=p_organization_id and r.actor_user_id=auth.uid() and r.request_id=p_request_id and r.kind='sale.checkout';
 return private.phase3_sale_json(v_id);
end; $$;
create function public.reverse_sale(p_organization_id uuid,p_sale_id uuid,p_request_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 m public.organization_memberships;s public.sales;sh public.shifts;payload jsonb;v_id uuid;kind text;reason text;return_stock boolean;
 line jsonb;pay jsonb;original public.sale_items;original_pay public.sale_payments;qty bigint;used bigint;amount numeric;total numeric:=0;paid numeric:=0;cash_paid numeric:=0;used_amount numeric;
 computed jsonb:='[]';item_id uuid;reference text;
begin
 m:=private.require_active_member(p_organization_id);
 if m.role not in ('owner','admin','manager') then raise exception 'Operation is not permitted' using errcode='42501'; end if;
 select * into s from public.sales where id=p_sale_id and organization_id=p_organization_id;
 if not found then raise exception 'Sale unavailable' using errcode='P0002'; end if;
 m:=private.phase3_require(p_organization_id,s.branch_id,'manage');
 perform private.phase3_check_keys(p_payload,array['kind','shift_id','items','payments','reason','return_stock']);
 payload:=jsonb_build_object('sale_id',p_sale_id,'details',p_payload);
 v_id:=private.phase3_request(p_organization_id,p_request_id,'sale.reverse',payload);
 if v_id is not null then return private.phase3_reversal_json(v_id); end if;
 select * into s from public.sales where id=p_sale_id for update;
 kind:=p_payload->>'kind';reason:=btrim(p_payload->>'reason');
 if kind is null or kind not in ('refund','void') or reason is null or char_length(reason) not between 3 and 1000 or p_payload->'return_stock' not in ('true'::jsonb,'false'::jsonb) or p_payload->'return_stock' is null then raise exception 'Explicit reversal kind, stock-return choice and reason are required' using errcode='22023'; end if;
 return_stock:=(p_payload->>'return_stock')::boolean;
 select * into sh from public.shifts where organization_id=p_organization_id and branch_id=s.branch_id and id=(p_payload->>'shift_id')::uuid for update;
 if not found or sh.actor_user_id<>auth.uid() then raise exception 'Your current open shift is required to record the payout' using errcode='42501'; end if;
 if exists(select 1 from public.shift_closures where shift_id=sh.id) then raise exception 'Refund shift is closed' using errcode='40001'; end if;
 if sh.currency<>s.currency then raise exception 'Refund shift currency must match the original sale' using errcode='22023'; end if;
 if jsonb_typeof(p_payload->'items') is distinct from 'array' or jsonb_array_length(p_payload->'items') not between 1 and 100 then raise exception 'Reversal requires selected original sale units' using errcode='22023'; end if;
 if (select count(distinct (x->>'sale_item_id')::uuid) from jsonb_array_elements(p_payload->'items') x)<>jsonb_array_length(p_payload->'items') then raise exception 'Duplicate reversal items' using errcode='22023'; end if;
 if kind='void' and (exists(select 1 from public.sale_reversals where sale_id=s.id) or jsonb_array_length(p_payload->'items')<>(select count(*) from public.sale_items where sale_id=s.id)) then raise exception 'Void requires a full untouched sale' using errcode='23514'; end if;
 for line in select value from jsonb_array_elements(p_payload->'items') order by (value->>'sale_item_id')::uuid loop
  perform private.phase3_check_keys(line,array['sale_item_id','quantity']);qty:=private.phase3_integer(line->'quantity',1,1000000);
  select * into original from public.sale_items where organization_id=p_organization_id and sale_id=s.id and id=(line->>'sale_item_id')::uuid;
  if not found then raise exception 'Reversal item does not belong to this sale' using errcode='22023'; end if;
  select coalesce(sum(quantity),0)::bigint into used from public.sale_reversal_items where sale_item_id=original.id;
  if qty>original.quantity-used then raise exception 'Requested units exceed the remaining original quantity' using errcode='23514'; end if;
  if kind='void' and qty<>original.quantity then raise exception 'Void must reverse every original unit' using errcode='23514'; end if;
  -- Cumulative integer division releases the exact last cent on final return.
  amount:=div(original.line_total_minor::numeric*(used+qty),original.quantity::numeric)-div(original.line_total_minor::numeric*used,original.quantity::numeric);
  total:=total+amount;
  computed:=computed||jsonb_build_array(jsonb_build_object('sale_item_id',original.id,'product_id',original.product_id,'quantity',qty,'amount_minor',amount));
 end loop;
 if jsonb_typeof(p_payload->'payments') is distinct from 'array' or jsonb_array_length(p_payload->'payments')>5 or (total>0 and jsonb_array_length(p_payload->'payments')=0) then raise exception 'Manual payout evidence must match the computed reversal amount' using errcode='22023'; end if;
 if (select count(distinct (x->>'original_payment_id')::uuid) from jsonb_array_elements(p_payload->'payments') x)<>jsonb_array_length(p_payload->'payments') then raise exception 'Duplicate reversal payment sources' using errcode='22023'; end if;
 for pay in select value from jsonb_array_elements(p_payload->'payments') loop
  perform private.phase3_check_keys(pay,array['original_payment_id','amount_minor','manual_confirmed','reference']);
  amount:=private.phase3_integer(pay->'amount_minor',1,9007199254740991);
  select * into original_pay from public.sale_payments where organization_id=p_organization_id and sale_id=s.id and id=(pay->>'original_payment_id')::uuid;
  if not found then raise exception 'Payout source does not belong to this sale' using errcode='22023'; end if;
  select coalesce(sum(amount_minor::numeric),0) into used_amount from public.sale_reversal_payments where original_payment_id=original_pay.id;
  if amount>original_pay.amount_minor::numeric-used_amount then raise exception 'Payout exceeds the remaining original payment' using errcode='23514'; end if;
  if pay->'manual_confirmed' is distinct from 'true'::jsonb then raise exception 'Every payout needs explicit manual confirmation; provider reversal is not connected' using errcode='22023'; end if;
  reference:=nullif(btrim(pay->>'reference'),'');
  if char_length(reference)>120 or (original_pay.method<>'cash' and (reference is null or char_length(reference)<3)) then raise exception 'Digital payout needs a valid manual reference' using errcode='22023'; end if;
  paid:=paid+amount;
  if original_pay.method='cash' then cash_paid:=cash_paid+amount; end if;
 end loop;
 if paid<>total then raise exception 'Payout applied amounts must exactly equal the computed original-price reversal' using errcode='22023'; end if;
 if private.phase3_expected_cash(sh.id)::numeric-cash_paid not between -9007199254740991 and 9007199254740991 then raise exception 'Shift cash exceeds exact monetary limit' using errcode='22023'; end if;
 if return_stock then
  -- Match checkout/receipt lock order even when original items have random IDs.
  perform 1 from public.products p where p.organization_id=p_organization_id and p.id in(select (x->>'product_id')::uuid from jsonb_array_elements(computed) x) order by p.id for update;
 end if;
 insert into public.sale_reversals(organization_id,branch_id,sale_id,shift_id,actor_user_id,kind,currency,total_minor,reason,return_stock)
  values(p_organization_id,s.branch_id,s.id,sh.id,auth.uid(),kind,s.currency,total::bigint,reason,return_stock) returning id into v_id;
 for line in select value from jsonb_array_elements(computed) order by (value->>'product_id')::uuid loop
  insert into public.sale_reversal_items(organization_id,reversal_id,sale_item_id,quantity,amount_minor)
   values(p_organization_id,v_id,(line->>'sale_item_id')::uuid,(line->>'quantity')::bigint,(line->>'amount_minor')::bigint);
  if return_stock then
   insert into public.stock_movements(organization_id,branch_id,product_id,actor_user_id,quantity_delta,balance_after,reversal_id)
    values(p_organization_id,s.branch_id,(line->>'product_id')::uuid,auth.uid(),(line->>'quantity')::bigint,0,v_id);
  end if;
 end loop;
 for pay in select value from jsonb_array_elements(p_payload->'payments') loop
  insert into public.sale_reversal_payments(organization_id,reversal_id,original_payment_id,amount_minor,manual_confirmed,reference)
   values(p_organization_id,v_id,(pay->>'original_payment_id')::uuid,(pay->>'amount_minor')::bigint,true,nullif(btrim(pay->>'reference'),''));
 end loop;
 perform private.phase3_save_request(p_organization_id,p_request_id,'sale.reverse',payload,v_id);
 perform private.append_action_audit(p_organization_id,'sale.'||kind,'sale_reversals',v_id,s.branch_id,reason,jsonb_build_object('sale_id',s.id,'total_minor',total,'currency',s.currency,'return_stock',return_stock));
 return private.phase3_reversal_json(v_id);
exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'Invalid reversal identifier or exact amount' using errcode='22023';
end; $$;
-- Structural source scope is enforced in addition to actor-bound RPC checks.
alter table public.inventory_operations add unique(organization_id,branch_id,id);
alter table public.sale_reversals add unique(organization_id,branch_id,id);
alter table public.stock_movements add foreign key(organization_id,branch_id,operation_id) references public.inventory_operations(organization_id,branch_id,id),
 add foreign key(organization_id,branch_id,sale_id) references public.sales(organization_id,branch_id,id),
 add foreign key(organization_id,branch_id,reversal_id) references public.sale_reversals(organization_id,branch_id,id);
-- Restrict broad Supabase default EXECUTE privileges on each newly declared RPC
-- and helper, then grant only the intentionally public authenticated boundary.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname='private' and p.proname like 'phase3_%') or (n.nspname='public' and p.proname=any(array[
 'get_pos_context','list_pos_products','lookup_pos_product_by_barcode','open_shift','get_current_shift','close_shift','checkout_sale',
 'receive_stock','adjust_stock','list_inventory','list_stock_movements','list_shifts','list_sales','get_sale','get_sale_by_request','reverse_sale'])) loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
  if f.signature::text like 'public.%' then execute format('grant execute on function %s to authenticated',f.signature); end if;
 end loop;
end; $$;
-- regprocedure may omit the public schema depending on search_path: grant the
-- public RPCs by namespace rather than relying on rendered signature text.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
  and p.proname=any(array['get_pos_context','list_pos_products','lookup_pos_product_by_barcode','open_shift','get_current_shift','close_shift','checkout_sale',
 'receive_stock','adjust_stock','list_inventory','list_stock_movements','list_shifts','list_sales','get_sale','get_sale_by_request','reverse_sale']) loop
  execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end; $$;
grant execute on function private.phase3_can_read(uuid,uuid,uuid,text) to authenticated;

-- Extend branch operational audit without weakening immutable security scope.
create or replace function private.can_read_audit(p_organization_id uuid,p_branch_id uuid,p_entity text,p_entity_id uuid,p_action text,p_metadata jsonb)
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
    ((v_actor.role='manager' and p_entity in ('suppliers','customers','sales','shifts','inventory_operations','sale_reversals')) or
      (v_actor.role='inventory_staff' and p_entity in ('suppliers','inventory_operations')));
exception when invalid_text_representation then return false;
end;
$$;

commit;
