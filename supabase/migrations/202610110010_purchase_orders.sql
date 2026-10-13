-- Phase 6A: immutable purchase orders and physical stock receiving.
begin;
create table public.purchase_orders (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,branch_id uuid not null,
 supplier_id uuid not null,supplier_name text not null,supplier_revision bigint not null check(supplier_revision between 1 and 9007199254740991),
 currency text not null check(currency in ('PHP','USD','EUR','GBP','AUD','CAD','SGD')),settings_revision bigint not null check(settings_revision between 1 and 9007199254740991),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),reference text check(char_length(reference)<=120),
 reason text not null check(char_length(btrim(reason)) between 3 and 1000),ordered_total_minor bigint not null check(ordered_total_minor between 0 and 9007199254740991),
 unique(organization_id,branch_id,id),foreign key(organization_id,branch_id) references public.branches(organization_id,id),
 foreign key(organization_id,supplier_id) references public.suppliers(organization_id,id)
);
create table public.purchase_order_items (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,branch_id uuid not null,order_id uuid not null,product_id uuid not null,
 product_name text not null,sku text not null,unit text not null,product_revision bigint not null check(product_revision between 1 and 9007199254740991),
 ordered_quantity bigint not null check(ordered_quantity between 1 and 1000000),unit_cost_minor bigint not null check(unit_cost_minor between 0 and 9007199254740991),
 line_cost_minor bigint not null check(line_cost_minor between 0 and 9007199254740991),
 unique(order_id,product_id),unique(organization_id,branch_id,order_id,id,product_id),unique(id,ordered_quantity),
 foreign key(organization_id,branch_id,order_id) references public.purchase_orders(organization_id,branch_id,id),
 foreign key(organization_id,product_id) references public.products(organization_id,id),check(line_cost_minor=unit_cost_minor::numeric*ordered_quantity)
);
create table private.purchase_order_states (
 order_id uuid primary key references public.purchase_orders(id),revision bigint not null check(revision between 1 and 9007199254740991),
 status text not null check(status in ('ordered','partially_received','received','cancelled'))
);
create table private.purchase_order_item_balances (
 order_item_id uuid primary key,ordered_quantity bigint not null,received_quantity bigint not null default 0,cancelled_quantity bigint not null default 0,
 foreign key(order_item_id,ordered_quantity) references public.purchase_order_items(id,ordered_quantity),
 check(received_quantity>=0 and cancelled_quantity>=0 and received_quantity+cancelled_quantity<=ordered_quantity)
);
create table public.purchase_receipts (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,branch_id uuid not null,order_id uuid not null,
 operation_id uuid not null unique,order_revision bigint not null check(order_revision between 2 and 9007199254740991),
 received_by uuid not null references auth.users(id),received_at timestamptz not null default now(),currency text not null,
 received_total_minor bigint not null check(received_total_minor between 0 and 9007199254740991),reference text check(char_length(reference)<=120),
 reason text not null check(char_length(btrim(reason)) between 3 and 1000),
 unique(organization_id,branch_id,order_id,id,operation_id),
 foreign key(organization_id,branch_id,order_id) references public.purchase_orders(organization_id,branch_id,id),
 foreign key(organization_id,branch_id,operation_id) references public.inventory_operations(organization_id,branch_id,id)
);
-- A receipt item must identify a movement for its exact tenant, branch, product
-- and inventory operation, not an unrelated same-tenant ledger entry.
alter table public.stock_movements add constraint stock_movement_purchase_scope unique(organization_id,branch_id,product_id,operation_id,id);
create table public.purchase_receipt_items (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,branch_id uuid not null,order_id uuid not null,
 receipt_id uuid not null,operation_id uuid not null,order_item_id uuid not null,product_id uuid not null,
 quantity bigint not null check(quantity between 1 and 1000000),unit_cost_minor bigint not null check(unit_cost_minor between 0 and 9007199254740991),
 line_cost_minor bigint not null check(line_cost_minor between 0 and 9007199254740991),product_revision bigint not null check(product_revision between 1 and 9007199254740991),movement_id uuid not null unique,
 unique(receipt_id,order_item_id),
 foreign key(organization_id,branch_id,order_id,receipt_id,operation_id) references public.purchase_receipts(organization_id,branch_id,order_id,id,operation_id),
 foreign key(organization_id,branch_id,order_id,order_item_id,product_id) references public.purchase_order_items(organization_id,branch_id,order_id,id,product_id),
 foreign key(organization_id,branch_id,product_id,operation_id,movement_id) references public.stock_movements(organization_id,branch_id,product_id,operation_id,id),
 check(line_cost_minor=unit_cost_minor::numeric*quantity)
);
create table public.purchase_order_cancellations (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,branch_id uuid not null,order_id uuid not null unique,
 order_revision bigint not null check(order_revision between 2 and 9007199254740991),actor_user_id uuid not null references auth.users(id),created_at timestamptz not null default now(),
 currency text not null,reason text not null check(char_length(btrim(reason)) between 3 and 1000),
 cancelled_total_minor bigint not null check(cancelled_total_minor between 0 and 9007199254740991),items jsonb not null check(jsonb_typeof(items)='array' and jsonb_array_length(items) between 1 and 100),
 foreign key(organization_id,branch_id,order_id) references public.purchase_orders(organization_id,branch_id,id)
);
create index purchase_order_scope_time on public.purchase_orders(organization_id,branch_id,created_at desc,id);
create index purchase_receipt_order_time on public.purchase_receipts(organization_id,branch_id,order_id,received_at desc,id);
create index purchase_receipt_item_order on public.purchase_receipt_items(order_item_id);

create function private.purchase_can_read(p_org uuid,p_branch uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform private.phase3_require(p_org,p_branch,'stock'); return true;
exception when insufficient_privilege then return false;
end; $$;
do $$ declare t text; begin
 foreach t in array array['purchase_orders','purchase_order_items','purchase_receipts','purchase_receipt_items','purchase_order_cancellations'] loop
  execute format('revoke all on public.%I from public,anon,authenticated,service_role',t);
  execute format('alter table public.%I enable row level security',t);
  execute format('create trigger immutable_history before update or delete on public.%I for each row execute function private.reject_immutable_mutation()',t);
  execute format('create trigger immutable_no_truncate before truncate on public.%I for each statement execute function private.reject_immutable_mutation()',t);
  execute format('create policy purchase_read on public.%I for select to authenticated using(private.purchase_can_read(organization_id,branch_id))',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
 foreach t in array array['purchase_order_states','purchase_order_item_balances'] loop
  execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
  execute format('alter table private.%I enable row level security',t);
 end loop;
end; $$;
create function private.purchase_exact(p_value numeric)
returns bigint language plpgsql immutable set search_path='' as $$
begin
 if p_value is null or p_value<0 or p_value>9007199254740991 or p_value<>trunc(p_value) then
  raise exception 'Purchase amount exceeds the exact integer limit' using errcode='22023'; end if;
 return p_value::bigint;
end; $$;
create function private.purchase_reason(p_reason text,p_reference text)
returns text language plpgsql immutable set search_path='' as $$
begin
 if p_reason is null or char_length(btrim(p_reason)) not between 3 and 1000 or char_length(p_reference)>120 then
  raise exception 'A reason of 3 to 1000 characters and reference up to 120 characters are required' using errcode='22023'; end if;
 return btrim(p_reason);
end; $$;
create function private.purchase_page(p_offset integer,p_limit integer)
returns void language plpgsql immutable set search_path='' as $$
begin
 if p_offset is null or p_offset not between 0 and 1000000 or p_limit is null or p_limit not between 1 and 101 then
  raise exception 'Invalid purchase page' using errcode='22023'; end if;
end; $$;
create function private.purchase_cancellation_json(p_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(c)||jsonb_build_object('created_at',private.offline_time(c.created_at)) from public.purchase_order_cancellations c where c.id=p_id;
$$;
create function private.purchase_order_json(p_id uuid,p_initial boolean default false,p_detail boolean default true)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o public.purchase_orders;s private.purchase_order_states;r jsonb;lines jsonb;received bigint;receipts bigint;
begin
 select * into o from public.purchase_orders where id=p_id; if not found then return null; end if;
 select * into s from private.purchase_order_states where order_id=p_id;
 select private.purchase_exact(coalesce(sum(i.unit_cost_minor::numeric*b.received_quantity),0)) into received
 from public.purchase_order_items i join private.purchase_order_item_balances b on b.order_item_id=i.id where i.order_id=p_id;
 select count(*) into receipts from public.purchase_receipts where order_id=p_id;
 r:=to_jsonb(o)||jsonb_build_object('created_at',private.offline_time(o.created_at),'status',case when p_initial then 'ordered' else s.status end,
  'revision',case when p_initial then 1 else s.revision end,'received_total_minor',case when p_initial then 0 else received end,
  'line_count',(select count(*) from public.purchase_order_items where order_id=p_id),'receipt_count',case when p_initial then 0 else receipts end);
 if p_detail then
  select coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('received_quantity',case when p_initial then 0 else b.received_quantity end,
   'cancelled_quantity',case when p_initial then 0 else b.cancelled_quantity end,'remaining_quantity',case when p_initial then i.ordered_quantity else i.ordered_quantity-b.received_quantity-b.cancelled_quantity end,
   'current_product_revision',case when p_initial then i.product_revision else p.revision end,'current_product_active',case when p_initial then true else p.active end,
   'current_product_name',case when p_initial then i.product_name else p.name end,'current_sku',case when p_initial then i.sku else p.sku end,
   'current_unit',case when p_initial then i.unit else p.unit end,'current_currency',case when p_initial then o.currency else p.currency end) order by i.product_id),'[]')
   into lines from public.purchase_order_items i join private.purchase_order_item_balances b on b.order_item_id=i.id join public.products p on p.id=i.product_id where i.order_id=p_id;
  r:=r||jsonb_build_object('items',lines,'cancellation',case when p_initial then null else
   (select private.purchase_cancellation_json(c.id) from public.purchase_order_cancellations c where c.order_id=p_id) end);
 end if;
 return r;
end; $$;
create function private.purchase_receipt_json(p_id uuid,p_detail boolean default true)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r jsonb;lines jsonb;
begin
 select to_jsonb(x)||jsonb_build_object('received_at',private.offline_time(x.received_at),
  'line_count',(select count(*) from public.purchase_receipt_items i where i.receipt_id=x.id)) into r from public.purchase_receipts x where x.id=p_id;
 if r is null then return null; end if;
 if p_detail then
  select coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('product_name',o.product_name,'sku',o.sku,'unit',o.unit,
   'balance_after',m.balance_after,'stock_revision',m.stock_revision) order by i.product_id),'[]') into lines
  from public.purchase_receipt_items i join public.purchase_order_items o on o.id=i.order_item_id join public.stock_movements m on m.id=i.movement_id where i.receipt_id=p_id;
  r:=r||jsonb_build_object('items',lines);
 end if;
 return r;
end; $$;
create function private.purchase_action(p_request uuid,p_kind text,p_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare document jsonb;order_id uuid;revision bigint;
begin
 if p_kind='purchase.create' then document:=private.purchase_order_json(p_id,true,true); order_id:=p_id; revision:=1;
 elsif p_kind='purchase.receive' then document:=private.purchase_receipt_json(p_id,true); order_id:=(document->>'order_id')::uuid;revision:=(document->>'order_revision')::bigint;
 elsif p_kind='purchase.cancel_remaining' then document:=private.purchase_cancellation_json(p_id);order_id:=(document->>'order_id')::uuid;revision:=(document->>'order_revision')::bigint;
 else raise exception 'Invalid purchase action' using errcode='22023'; end if;
 return jsonb_build_object('request_id',p_request,'kind',p_kind,'order_id',order_id,'order_revision',revision,
  case p_kind when 'purchase.create' then 'order' when 'purchase.receive' then 'receipt' else 'cancellation' end,document);
end; $$;
create function public.get_purchase_context(p_organization_id uuid,p_branch_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'stock');
 select jsonb_build_object('organization_id',o.id,'branch_id',b.id,'branch_name',b.name,'currency',o.currency,'settings_revision',o.revision) into r
 from public.organizations o join public.branches b on b.organization_id=o.id where o.id=p_organization_id and b.id=p_branch_id;
 return r;
end; $$;
create function public.list_purchase_orders(p_organization_id uuid,p_branch_id uuid,p_status text default null,p_query text default '',p_offset integer default 0,p_limit integer default 51)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'stock');perform private.purchase_page(p_offset,p_limit);
 if (p_status is not null and p_status not in ('ordered','partially_received','received','cancelled')) or p_query is null or char_length(p_query)>160 then raise exception 'Invalid purchase filter' using errcode='22023';end if;
 select coalesce(jsonb_agg(private.purchase_order_json(x.id,false,false) order by x.created_at desc,x.id),'[]') into r from
 (select o.id,o.created_at from public.purchase_orders o join private.purchase_order_states s on s.order_id=o.id
  where o.organization_id=p_organization_id and o.branch_id=p_branch_id and (p_status is null or s.status=p_status)
  and (p_query='' or position(lower(p_query) in lower(o.supplier_name||' '||coalesce(o.reference,'')))>0)
  order by o.created_at desc,o.id offset p_offset limit p_limit) x;
 return r;
end; $$;
create function public.get_purchase_order(p_organization_id uuid,p_branch_id uuid,p_order_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'stock');
 if not exists(select 1 from public.purchase_orders where id=p_order_id and organization_id=p_organization_id and branch_id=p_branch_id) then raise exception 'Purchase order unavailable' using errcode='42501';end if;
 return private.purchase_order_json(p_order_id,false,true);
end; $$;
create function public.list_purchase_receipts(p_organization_id uuid,p_branch_id uuid,p_order_id uuid,p_offset integer default 0,p_limit integer default 51)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'stock');perform private.purchase_page(p_offset,p_limit);
 if not exists(select 1 from public.purchase_orders where id=p_order_id and organization_id=p_organization_id and branch_id=p_branch_id) then raise exception 'Purchase order unavailable' using errcode='42501';end if;
 select coalesce(jsonb_agg(private.purchase_receipt_json(x.id,false) order by x.received_at desc,x.id),'[]') into r from
 (select id,received_at from public.purchase_receipts where organization_id=p_organization_id and branch_id=p_branch_id and order_id=p_order_id order by received_at desc,id offset p_offset limit p_limit) x;
 return r;
end; $$;
create function public.get_purchase_receipt(p_organization_id uuid,p_branch_id uuid,p_receipt_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'stock');
 if not exists(select 1 from public.purchase_receipts where id=p_receipt_id and organization_id=p_organization_id and branch_id=p_branch_id) then raise exception 'Purchase receipt unavailable' using errcode='42501';end if;
 return private.purchase_receipt_json(p_receipt_id,true);
end; $$;
create function public.create_purchase_order(p_organization_id uuid,p_branch_id uuid,p_request_id uuid,p_supplier_id uuid,
 p_expected_supplier_revision bigint,p_expected_settings_revision bigint,p_currency text,p_items jsonb,p_reference text default null,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;result_id uuid;reason text;o public.organizations;supplier public.suppliers;p public.products;
 item jsonb;product_id uuid;quantity bigint;cost bigint;total numeric:=0;prepared jsonb:='[]';line_id uuid;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'stock');perform private.offline_counter_lock(p_organization_id);
 payload:=jsonb_build_object('branch_id',p_branch_id,'supplier_id',p_supplier_id,'expected_supplier_revision',p_expected_supplier_revision,
  'expected_settings_revision',p_expected_settings_revision,'currency',p_currency,'items',p_items,'reference',p_reference,'reason',p_reason);
 result_id:=private.phase3_request(p_organization_id,p_request_id,'purchase.create',payload);
 if result_id is not null then return private.purchase_action(p_request_id,'purchase.create',result_id);end if;
 reason:=private.purchase_reason(p_reason,p_reference);
 if p_expected_supplier_revision is null or p_expected_supplier_revision not between 1 and 9007199254740991 or p_expected_settings_revision is null or p_expected_settings_revision not between 1 and 9007199254740991 then raise exception 'Expected purchase revisions required' using errcode='22023';end if;
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'One to 100 unique purchase lines required' using errcode='22023';end if;
 for item in select value from jsonb_array_elements(p_items) loop
  perform private.phase3_check_keys(item,array['product_id','expected_revision','quantity','unit_cost_minor']);
  perform private.offline_uuid(item->'product_id');perform private.phase3_integer(item->'expected_revision',1,9007199254740991);
  quantity:=private.phase3_integer(item->'quantity',1,1000000);cost:=private.phase3_integer(item->'unit_cost_minor',0,9007199254740991);
  total:=total+quantity::numeric*cost;perform private.purchase_exact(total);
 end loop;
 if (select count(distinct (x->>'product_id')::uuid) from jsonb_array_elements(p_items) x)<>jsonb_array_length(p_items) then raise exception 'Duplicate purchase product' using errcode='22023';end if;
 select * into o from public.organizations where id=p_organization_id for share;
 if o.revision<>p_expected_settings_revision or p_currency is distinct from o.currency then raise exception 'Business currency or settings changed; reload purchase' using errcode='40001';end if;
 if o.currency not in ('PHP','USD','EUR','GBP','AUD','CAD','SGD') then raise exception 'Unsupported purchase currency' using errcode='22023';end if;
 select * into supplier from public.suppliers where id=p_supplier_id and organization_id=p_organization_id and active and (branch_id is null or branch_id=p_branch_id) for share;
 if not found then raise exception 'Supplier unavailable in this branch' using errcode='42501';end if;
 if supplier.revision<>p_expected_supplier_revision then raise exception 'Supplier changed; reload purchase' using errcode='40001';end if;
 -- Lock every product in the canonical order before writing any evidence.
 for item in select value from jsonb_array_elements(p_items) order by (value->>'product_id')::uuid loop
  product_id:=(item->>'product_id')::uuid;
  select * into p from public.products where id=product_id and organization_id=p_organization_id and active for update;
  if not found then raise exception 'Purchase product unavailable' using errcode='42501';end if;
  if p.revision<>(item->>'expected_revision')::bigint or p.currency<>o.currency then raise exception 'Product revision or currency changed; reload purchase' using errcode='40001';end if;
  prepared:=prepared||jsonb_build_array(item||jsonb_build_object('product_name',p.name,'sku',p.sku,'unit',p.unit));
 end loop;
 insert into public.purchase_orders(organization_id,branch_id,supplier_id,supplier_name,supplier_revision,currency,settings_revision,created_by,reference,reason,ordered_total_minor)
 values(p_organization_id,p_branch_id,supplier.id,supplier.name,supplier.revision,o.currency,o.revision,auth.uid(),nullif(btrim(p_reference),''),reason,private.purchase_exact(total)) returning id into result_id;
 insert into private.purchase_order_states values(result_id,1,'ordered');
 for item in select value from jsonb_array_elements(prepared) loop
  quantity:=(item->>'quantity')::bigint;cost:=(item->>'unit_cost_minor')::bigint;
  insert into public.purchase_order_items(organization_id,branch_id,order_id,product_id,product_name,sku,unit,product_revision,ordered_quantity,unit_cost_minor,line_cost_minor)
  values(p_organization_id,p_branch_id,result_id,(item->>'product_id')::uuid,item->>'product_name',item->>'sku',item->>'unit',(item->>'expected_revision')::bigint,quantity,cost,private.purchase_exact(quantity::numeric*cost)) returning id into line_id;
  insert into private.purchase_order_item_balances(order_item_id,ordered_quantity) values(line_id,quantity);
 end loop;
 perform private.phase3_save_request(p_organization_id,p_request_id,'purchase.create',payload,result_id);
 perform private.append_action_audit(p_organization_id,'purchase.created','purchase_orders',result_id,p_branch_id,reason,jsonb_build_object('supplier_id',supplier.id,'ordered_total_minor',total,'currency',o.currency,'line_count',jsonb_array_length(p_items)));
 return private.purchase_action(p_request_id,'purchase.create',result_id);
end; $$;
create function public.receive_purchase_order(p_organization_id uuid,p_branch_id uuid,p_request_id uuid,p_order_id uuid,p_expected_revision bigint,p_items jsonb,p_reference text default null,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;result_id uuid;reason text;o public.purchase_orders;state private.purchase_order_states;line public.purchase_order_items;
 p public.products;item jsonb;quantity bigint;remaining bigint;total numeric:=0;prepared jsonb:='[]';operation_id uuid;movement_id uuid;next_revision bigint;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'stock');perform private.offline_counter_lock(p_organization_id);
 payload:=jsonb_build_object('branch_id',p_branch_id,'order_id',p_order_id,'expected_revision',p_expected_revision,'items',p_items,'reference',p_reference,'reason',p_reason);
 result_id:=private.phase3_request(p_organization_id,p_request_id,'purchase.receive',payload);
 if result_id is not null then return private.purchase_action(p_request_id,'purchase.receive',result_id);end if;
 reason:=private.purchase_reason(p_reason,p_reference);
 if p_expected_revision is null or p_expected_revision not between 1 and 9007199254740990 then raise exception 'Expected order revision required' using errcode='22023';end if;
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'One to 100 unique receipt lines required' using errcode='22023';end if;
 for item in select value from jsonb_array_elements(p_items) loop
  perform private.phase3_check_keys(item,array['order_item_id','quantity','expected_product_revision']);
  perform private.offline_uuid(item->'order_item_id');perform private.phase3_integer(item->'quantity',1,1000000);perform private.phase3_integer(item->'expected_product_revision',1,9007199254740991);
 end loop;
 if (select count(distinct (x->>'order_item_id')::uuid) from jsonb_array_elements(p_items) x)<>jsonb_array_length(p_items) then raise exception 'Duplicate receipt order item' using errcode='22023';end if;
 select * into o from public.purchase_orders where id=p_order_id and organization_id=p_organization_id and branch_id=p_branch_id;
 if not found then raise exception 'Purchase order unavailable' using errcode='42501';end if;
 select * into state from private.purchase_order_states where order_id=o.id for update;
 if state.revision<>p_expected_revision then raise exception 'Purchase order changed; reload receipt' using errcode='40001';end if;
 if state.status in ('received','cancelled') then raise exception 'Purchase order is closed' using errcode='23514';end if;
 perform 1 from public.suppliers where id=o.supplier_id and organization_id=p_organization_id and active and (branch_id is null or branch_id=p_branch_id) for share;
 if not found then raise exception 'Supplier unavailable in this branch' using errcode='42501';end if;
 -- Resolve bounded original lines and quantities, then sort the actual product
 -- IDs so this ledger writer has the same lock order as checkout/ad hoc stock.
 for item in select value from jsonb_array_elements(p_items) loop
  select * into line from public.purchase_order_items where id=(item->>'order_item_id')::uuid and order_id=o.id;
  if not found then raise exception 'Receipt item does not belong to this order' using errcode='42501';end if;
  select ordered_quantity-received_quantity-cancelled_quantity into remaining from private.purchase_order_item_balances where order_item_id=line.id;
  quantity:=(item->>'quantity')::bigint;
  if quantity>remaining then raise exception 'Received quantity exceeds remaining order quantity' using errcode='23514';end if;
  total:=total+quantity::numeric*line.unit_cost_minor;perform private.purchase_exact(total);
  prepared:=prepared||jsonb_build_array(item||jsonb_build_object('product_id',line.product_id,'unit_cost_minor',line.unit_cost_minor));
 end loop;
 for item in select value from jsonb_array_elements(prepared) order by (value->>'product_id')::uuid loop
  select * into p from public.products where id=(item->>'product_id')::uuid and organization_id=p_organization_id and active for update;
  if not found then raise exception 'Receipt product unavailable' using errcode='42501';end if;
  if p.revision<>(item->>'expected_product_revision')::bigint then raise exception 'Product changed; review current product before receiving' using errcode='40001';end if;
 end loop;
 next_revision:=state.revision+1;
 insert into public.inventory_operations(organization_id,branch_id,actor_user_id,kind,supplier_id,reference,reason)
 values(p_organization_id,p_branch_id,auth.uid(),'receive',o.supplier_id,nullif(btrim(p_reference),''),reason) returning id into operation_id;
 insert into public.purchase_receipts(organization_id,branch_id,order_id,operation_id,order_revision,received_by,currency,received_total_minor,reference,reason)
 values(p_organization_id,p_branch_id,o.id,operation_id,next_revision,auth.uid(),o.currency,private.purchase_exact(total),nullif(btrim(p_reference),''),reason) returning id into result_id;
 for item in select value from jsonb_array_elements(prepared) order by (value->>'product_id')::uuid loop
  quantity:=(item->>'quantity')::bigint;
  insert into public.stock_movements(organization_id,branch_id,product_id,actor_user_id,quantity_delta,balance_after,operation_id)
  values(p_organization_id,p_branch_id,(item->>'product_id')::uuid,auth.uid(),quantity,0,operation_id) returning id into movement_id;
  insert into private.inventory_cost_evidence(movement_id,unit_cost_minor,currency,product_revision)
  values(movement_id,(item->>'unit_cost_minor')::bigint,o.currency,(item->>'expected_product_revision')::bigint);
  insert into public.purchase_receipt_items(organization_id,branch_id,order_id,receipt_id,operation_id,order_item_id,product_id,quantity,unit_cost_minor,line_cost_minor,product_revision,movement_id)
  values(p_organization_id,p_branch_id,o.id,result_id,operation_id,(item->>'order_item_id')::uuid,(item->>'product_id')::uuid,quantity,(item->>'unit_cost_minor')::bigint,
   private.purchase_exact(quantity::numeric*(item->>'unit_cost_minor')::bigint),(item->>'expected_product_revision')::bigint,movement_id);
  update private.purchase_order_item_balances set received_quantity=received_quantity+quantity where order_item_id=(item->>'order_item_id')::uuid;
 end loop;
 update private.purchase_order_states set revision=next_revision,status=case when exists(
  select 1 from public.purchase_order_items i join private.purchase_order_item_balances b on b.order_item_id=i.id where i.order_id=o.id and b.received_quantity<i.ordered_quantity)
  then 'partially_received' else 'received' end where order_id=o.id;
 perform private.phase3_save_request(p_organization_id,p_request_id,'purchase.receive',payload,result_id);
 perform private.append_action_audit(p_organization_id,'purchase.received','purchase_receipts',result_id,p_branch_id,reason,jsonb_build_object('order_id',o.id,'operation_id',operation_id,'received_total_minor',total,'currency',o.currency,'line_count',jsonb_array_length(p_items)));
 return private.purchase_action(p_request_id,'purchase.receive',result_id);
end; $$;
create function public.cancel_purchase_order_remaining(p_organization_id uuid,p_branch_id uuid,p_request_id uuid,p_order_id uuid,p_expected_revision bigint,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;result_id uuid;reason text;o public.purchase_orders;state private.purchase_order_states;items jsonb;total numeric;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'stock');perform private.offline_counter_lock(p_organization_id);
 payload:=jsonb_build_object('branch_id',p_branch_id,'order_id',p_order_id,'expected_revision',p_expected_revision,'reason',p_reason);
 result_id:=private.phase3_request(p_organization_id,p_request_id,'purchase.cancel_remaining',payload);
 if result_id is not null then return private.purchase_action(p_request_id,'purchase.cancel_remaining',result_id);end if;
 reason:=private.purchase_reason(p_reason,null);
 if p_expected_revision is null or p_expected_revision not between 1 and 9007199254740990 then raise exception 'Expected order revision required' using errcode='22023';end if;
 select * into o from public.purchase_orders where id=p_order_id and organization_id=p_organization_id and branch_id=p_branch_id;
 if not found then raise exception 'Purchase order unavailable' using errcode='42501';end if;
 select * into state from private.purchase_order_states where order_id=o.id for update;
 if state.revision<>p_expected_revision then raise exception 'Purchase order changed; reload cancellation' using errcode='40001';end if;
 if state.status in ('received','cancelled') then raise exception 'Purchase order has no cancellable remainder' using errcode='23514';end if;
 select jsonb_agg(jsonb_build_object('order_item_id',i.id,'product_id',i.product_id,'product_name',i.product_name,'sku',i.sku,'unit',i.unit,
  'cancelled_quantity',i.ordered_quantity-b.received_quantity,'unit_cost_minor',i.unit_cost_minor,
  'line_cost_minor',private.purchase_exact((i.ordered_quantity-b.received_quantity)::numeric*i.unit_cost_minor)) order by i.product_id),
  sum((i.ordered_quantity-b.received_quantity)::numeric*i.unit_cost_minor) into items,total
 from public.purchase_order_items i join private.purchase_order_item_balances b on b.order_item_id=i.id where i.order_id=o.id and i.ordered_quantity>b.received_quantity;
 insert into public.purchase_order_cancellations(organization_id,branch_id,order_id,order_revision,actor_user_id,currency,reason,cancelled_total_minor,items)
 values(p_organization_id,p_branch_id,o.id,state.revision+1,auth.uid(),o.currency,reason,private.purchase_exact(total),items) returning id into result_id;
 update private.purchase_order_item_balances b set cancelled_quantity=b.ordered_quantity-b.received_quantity from public.purchase_order_items i where i.id=b.order_item_id and i.order_id=o.id;
 update private.purchase_order_states set revision=state.revision+1,status='cancelled' where order_id=o.id;
 perform private.phase3_save_request(p_organization_id,p_request_id,'purchase.cancel_remaining',payload,result_id);
 perform private.append_action_audit(p_organization_id,'purchase.remaining_cancelled','purchase_order_cancellations',result_id,p_branch_id,reason,jsonb_build_object('order_id',o.id,'cancelled_total_minor',total,'currency',o.currency,'line_count',jsonb_array_length(items)));
 return private.purchase_action(p_request_id,'purchase.cancel_remaining',result_id);
end; $$;
-- Match entity AND action; purchase visibility never expands security-event
-- access. Rebind the policy because renaming a function preserves its old OID.
alter function private.can_read_audit(uuid,uuid,text,uuid,text,jsonb) rename to phase6_purchase_prior_can_read_audit;
revoke all on function private.phase6_purchase_prior_can_read_audit(uuid,uuid,text,uuid,text,jsonb) from public,anon,authenticated,service_role;
create function private.can_read_audit(p_organization_id uuid,p_branch_id uuid,p_entity text,p_entity_id uuid,p_action text,p_metadata jsonb)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if p_entity in ('purchase_orders','purchase_receipts','purchase_order_cancellations') or p_action like 'purchase.%' then
  if p_branch_id is null or not private.purchase_can_read(p_organization_id,p_branch_id) then return false;end if;
  if p_entity='purchase_orders' and p_action='purchase.created' then
   return exists(select 1 from public.purchase_orders where id=p_entity_id and organization_id=p_organization_id and branch_id=p_branch_id);
  elsif p_entity='purchase_receipts' and p_action='purchase.received' then
   return exists(select 1 from public.purchase_receipts where id=p_entity_id and organization_id=p_organization_id and branch_id=p_branch_id);
  elsif p_entity='purchase_order_cancellations' and p_action='purchase.remaining_cancelled' then
   return exists(select 1 from public.purchase_order_cancellations where id=p_entity_id and organization_id=p_organization_id and branch_id=p_branch_id);
  end if;
  return false;
 end if;
 return private.phase6_purchase_prior_can_read_audit(p_organization_id,p_branch_id,p_entity,p_entity_id,p_action,p_metadata);
end; $$;
drop policy audit_read_authorized on public.audit_logs;
create policy audit_read_authorized on public.audit_logs for select to authenticated using(private.can_read_audit(organization_id,branch_id,entity,entity_id,action,metadata));
do $$ declare f record; begin
 for f in select p.oid::regprocedure signature,n.nspname,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname='private' and p.proname like 'purchase_%') or (n.nspname='public' and p.proname=any(array[
 'get_purchase_context','list_purchase_orders','get_purchase_order','list_purchase_receipts','get_purchase_receipt','create_purchase_order','receive_purchase_order','cancel_purchase_order_remaining'])) loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
  if f.nspname='public' or f.proname='purchase_can_read' then execute format('grant execute on function %s to authenticated',f.signature);end if;
 end loop;
end; $$;
revoke all on function private.can_read_audit(uuid,uuid,text,uuid,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.can_read_audit(uuid,uuid,text,uuid,text,jsonb) to authenticated;
commit;
