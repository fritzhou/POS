-- Physically confirmed transfers and supplier returns share the stock ledger.
begin;
alter table public.inventory_operations drop constraint inventory_operations_kind_check;
alter table public.inventory_operations add constraint inventory_operations_kind_check check(kind in ('receive','adjust','transfer_dispatch','transfer_receive','transfer_return','supplier_return'));
create table public.stock_transfers(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,source_branch_id uuid not null,destination_branch_id uuid not null,
 actor_id uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),source_name text not null,destination_name text not null,
 operation_id uuid not null,reference text,reason text not null,physical_confirmed boolean not null check(physical_confirmed),
 unique(organization_id,id),check(source_branch_id<>destination_branch_id),
 foreign key(organization_id,source_branch_id) references public.branches(organization_id,id),foreign key(organization_id,destination_branch_id) references public.branches(organization_id,id),
 foreign key(organization_id,source_branch_id,operation_id) references public.inventory_operations(organization_id,branch_id,id));
create table public.stock_transfer_items(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,transfer_id uuid not null,product_id uuid not null,
 product_name text not null,sku text not null,unit text not null,product_revision bigint not null check(product_revision between 1 and 9007199254740991),
 quantity bigint not null check(quantity between 1 and 1000000),movement_id uuid not null unique references public.stock_movements(id),
 unique(transfer_id,product_id),unique(organization_id,transfer_id,id),
 foreign key(organization_id,transfer_id) references public.stock_transfers(organization_id,id),foreign key(organization_id,product_id) references public.products(organization_id,id));
create table private.stock_transfer_states(transfer_id uuid primary key references public.stock_transfers(id),revision bigint not null default 1 check(revision between 1 and 9007199254740991));
create table private.stock_transfer_balances(item_id uuid primary key references public.stock_transfer_items(id),received bigint not null default 0,returned bigint not null default 0,check(received>=0 and returned>=0));
create table public.stock_transfer_events(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,transfer_id uuid not null,branch_id uuid not null,kind text not null check(kind in ('transfer.receive','transfer.return')),
 actor_id uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),revision bigint not null,
 operation_id uuid not null,reason text not null,reference text,physical_confirmed boolean not null check(physical_confirmed),items jsonb not null,
 foreign key(organization_id,transfer_id) references public.stock_transfers(organization_id,id),foreign key(organization_id,branch_id,operation_id) references public.inventory_operations(organization_id,branch_id,id));
create table public.purchase_returns(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,branch_id uuid not null,receipt_id uuid not null references public.purchase_receipts(id),
 actor_id uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),operation_id uuid not null,
 supplier_id uuid not null,currency text not null,total_minor bigint not null check(total_minor between 0 and 9007199254740991),
 reason text not null,reference text,physical_confirmed boolean not null check(physical_confirmed),
 unique(organization_id,id),foreign key(organization_id,branch_id,operation_id) references public.inventory_operations(organization_id,branch_id,id),foreign key(organization_id,supplier_id) references public.suppliers(organization_id,id));
create table public.purchase_return_items(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,return_id uuid not null,receipt_item_id uuid not null references public.purchase_receipt_items(id),product_id uuid not null,
 quantity bigint not null check(quantity between 1 and 1000000),unit_cost_minor bigint not null check(unit_cost_minor between 0 and 9007199254740991),line_cost_minor bigint not null check(line_cost_minor between 0 and 9007199254740991),
 product_revision bigint not null,movement_id uuid not null unique references public.stock_movements(id),
 unique(return_id,receipt_item_id),foreign key(organization_id,return_id) references public.purchase_returns(organization_id,id),foreign key(organization_id,product_id) references public.products(organization_id,id),check(line_cost_minor=quantity::numeric*unit_cost_minor));
create table private.logistics_actions(id uuid primary key,organization_id uuid not null,branch_id uuid not null,actor_id uuid not null,request_id uuid not null,kind text not null,document jsonb not null);
create index stock_transfers_scope on public.stock_transfers(organization_id,source_branch_id,destination_branch_id,created_at desc,id);
create index stock_transfer_event_scope on public.stock_transfer_events(transfer_id,created_at desc,id);
create index purchase_return_receipt on public.purchase_returns(receipt_id,created_at desc,id);
create index purchase_return_item_source on public.purchase_return_items(receipt_item_id);
create function private.logistics_scope(p_org uuid,p_branch uuid,p_active boolean default false) returns public.organization_memberships language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;b public.branches;
begin
 m:=private.require_active_member(p_org);
 if m.role not in ('owner','admin','manager','inventory_staff') then raise exception 'Stock authority required' using errcode='42501';end if;
 select * into b from public.branches where id=p_branch and organization_id=p_org for share;
 if not found or (p_active and not b.active) or (not m.all_branches and not exists(select 1 from public.membership_branches where organization_id=p_org and membership_id=m.id and branch_id=p_branch)) then raise exception 'Current branch stock authority required' using errcode='42501';end if;
 return m;
end;$$;
create function private.logistics_can_read(p_org uuid,p_branch uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare m public.organization_memberships;
begin
 m:=private.require_active_member(p_org);
 return m.role in ('owner','admin','manager','inventory_staff') and exists(select 1 from public.branches where id=p_branch and organization_id=p_org)
 and (m.all_branches or exists(select 1 from public.membership_branches where organization_id=p_org and membership_id=m.id and branch_id=p_branch));
exception when insufficient_privilege then return false;
end;$$;
do $$declare t text;begin
 foreach t in array array['stock_transfers','stock_transfer_items','stock_transfer_events','purchase_returns','purchase_return_items'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated,service_role',t);
  execute format('create trigger immutable_history before update or delete on public.%I for each row execute function private.reject_immutable_mutation()',t);
  execute format('create trigger immutable_no_truncate before truncate on public.%I for each statement execute function private.reject_immutable_mutation()',t);
 end loop;
 -- Reads use scoped RPCs; action evidence and ledger impacts never leak across endpoints.
 foreach t in array array['stock_transfer_states','stock_transfer_balances','logistics_actions'] loop
  execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
 end loop;
end;$$;
create trigger immutable_history before update or delete on private.logistics_actions for each row execute function private.reject_immutable_mutation();
create trigger immutable_no_truncate before truncate on private.logistics_actions for each statement execute function private.reject_immutable_mutation();
create function private.logistics_transfer_json(p_id uuid,p_detail boolean default true) returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(t)||jsonb_build_object('created_at',private.offline_time(t.created_at),'revision',s.revision,
  'status',case when exists(select 1 from public.stock_transfer_items i join private.stock_transfer_balances b on b.item_id=i.id where i.transfer_id=t.id and b.received+b.returned<i.quantity)
    then case when exists(select 1 from public.stock_transfer_items i join private.stock_transfer_balances b on b.item_id=i.id where i.transfer_id=t.id and b.received+b.returned>0) then 'partially_completed' else 'in_transit' end
    else case when not exists(select 1 from public.stock_transfer_items i join private.stock_transfer_balances b on b.item_id=i.id where i.transfer_id=t.id and b.returned>0) then 'received'
    when not exists(select 1 from public.stock_transfer_items i join private.stock_transfer_balances b on b.item_id=i.id where i.transfer_id=t.id and b.received>0) then 'returned' else 'completed' end end,
  'line_count',(select count(*) from public.stock_transfer_items where transfer_id=t.id),
  'items',case when p_detail then (select jsonb_agg(to_jsonb(i)-'movement_id'||jsonb_build_object('received',b.received,'returned',b.returned,'remaining',i.quantity-b.received-b.returned,'expected_revision',p.revision,'current_unit',p.unit) order by i.product_id)
   from public.stock_transfer_items i join private.stock_transfer_balances b on b.item_id=i.id join public.products p on p.id=i.product_id where i.transfer_id=t.id) else null end)
 from public.stock_transfers t join private.stock_transfer_states s on s.transfer_id=t.id where t.id=p_id;
$$;
create function private.logistics_commit(p_org uuid,p_branch uuid,p_request uuid,p_kind text,p_payload jsonb,p_document jsonb,p_reason text,p_entity text,p_entity_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid:=gen_random_uuid();d jsonb;
begin
 d:=jsonb_build_object('request_id',p_request,'organization_id',p_org,'branch_id',p_branch,'actor_id',auth.uid(),'kind',p_kind,'document',p_document);
 insert into private.logistics_actions values(a,p_org,p_branch,auth.uid(),p_request,p_kind,d);
 perform private.phase3_save_request(p_org,p_request,p_kind,p_payload,a);
 perform private.append_action_audit(p_org,p_kind,p_entity,p_entity_id,p_branch,p_reason,jsonb_build_object('request_id',p_request));
 return d;
end;$$;
create function public.list_stock_transfers(p_organization_id uuid,p_branch_id uuid,p_offset integer default 0,p_limit integer default 51) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 perform private.logistics_scope(p_organization_id,p_branch_id);perform private.purchase_page(p_offset,p_limit);
 select coalesce(jsonb_agg(private.logistics_transfer_json(x.id,false) order by x.created_at desc,x.id),'[]'::jsonb) into r from
 (select id,created_at from public.stock_transfers where organization_id=p_organization_id and p_branch_id in (source_branch_id,destination_branch_id) order by created_at desc,id offset p_offset limit p_limit)x;
 return r;
end;$$;
create function public.get_stock_transfer(p_organization_id uuid,p_branch_id uuid,p_transfer_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.logistics_scope(p_organization_id,p_branch_id);
 if not exists(select 1 from public.stock_transfers where organization_id=p_organization_id and id=p_transfer_id and p_branch_id in (source_branch_id,destination_branch_id)) then raise exception 'Transfer outside current branch scope' using errcode='42501';end if;
 return private.logistics_transfer_json(p_transfer_id);
end;$$;
create function public.list_stock_transfer_events(p_organization_id uuid,p_branch_id uuid,p_transfer_id uuid,p_offset integer default 0,p_limit integer default 51) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 perform public.get_stock_transfer(p_organization_id,p_branch_id,p_transfer_id);perform private.purchase_page(p_offset,p_limit);
 -- All endpoints see physical quantities/history; only own endpoint gets an operation ID. No balances/revisions are stored in this read document.
 select coalesce(jsonb_agg(to_jsonb(x)-'operation_id'||jsonb_build_object('created_at',private.offline_time(x.created_at),'operation_id',case when private.logistics_can_read(p_organization_id,x.branch_id) then x.operation_id else null end) order by x.created_at desc,x.id),'[]'::jsonb) into r from
 (select * from public.stock_transfer_events where transfer_id=p_transfer_id and organization_id=p_organization_id order by created_at desc,id offset p_offset limit p_limit)x;
 return r;
end;$$;
create function public.dispatch_stock_transfer(p_organization_id uuid,p_source_branch_id uuid,p_destination_branch_id uuid,p_request_id uuid,p_items jsonb,p_reference text,p_reason text,p_physical_confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;old_id uuid;t uuid;op uuid;i jsonb;p public.products;move public.stock_movements;items jsonb:='[]';line uuid;v_branch uuid;why text:=btrim(p_reason);
begin
 if p_source_branch_id is null or p_destination_branch_id is null or p_source_branch_id=p_destination_branch_id then raise exception 'Choose different source and destination branches' using errcode='22023';end if;
 for v_branch in select x from unnest(array[p_source_branch_id,p_destination_branch_id])x order by x loop perform private.logistics_scope(p_organization_id,v_branch);end loop;
 perform private.offline_counter_lock(p_organization_id);
 payload:=jsonb_build_object('source_branch_id',p_source_branch_id,'destination_branch_id',p_destination_branch_id,'items',p_items,'reference',p_reference,'reason',why,'physical_confirmed',p_physical_confirmed);
 old_id:=private.phase3_request(p_organization_id,p_request_id,'transfer.dispatch',payload);
 if old_id is not null then return(select document from private.logistics_actions where id=old_id);end if;
 perform private.logistics_scope(p_organization_id,p_source_branch_id,true);perform private.logistics_scope(p_organization_id,p_destination_branch_id,true);
 perform private.purchase_reason(why,p_reference);
 if p_physical_confirmed is distinct from true or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Confirm physically dispatched goods and bounded unique lines' using errcode='22023';end if;
 for i in select value from jsonb_array_elements(p_items) order by value->>'product_id' loop
  perform private.phase3_check_keys(i,array['product_id','quantity','expected_revision']);perform private.offline_uuid(i->'product_id');
  perform private.phase3_integer(i->'quantity',1,1000000);perform private.phase3_integer(i->'expected_revision',1,9007199254740991);
  select * into p from public.products where id=(i->>'product_id')::uuid and organization_id=p_organization_id and active for update;
  if not found then raise exception 'Active transfer product unavailable' using errcode='42501';end if;
  if p.revision<>(i->>'expected_revision')::bigint then raise exception 'Product changed; reload' using errcode='40001';end if;
 end loop;
 if (select count(distinct value->>'product_id') from jsonb_array_elements(p_items))<>jsonb_array_length(p_items) then raise exception 'Duplicate transfer product' using errcode='22023';end if;
 insert into public.inventory_operations(organization_id,branch_id,actor_user_id,kind,reason,reference) values(p_organization_id,p_source_branch_id,auth.uid(),'transfer_dispatch',why,p_reference) returning id into op;
 insert into public.stock_transfers(organization_id,source_branch_id,destination_branch_id,actor_id,source_name,destination_name,operation_id,reference,reason,physical_confirmed)
 select p_organization_id,p_source_branch_id,p_destination_branch_id,auth.uid(),s.name,d.name,op,p_reference,why,true from public.branches s,public.branches d where s.id=p_source_branch_id and d.id=p_destination_branch_id returning id into t;
 insert into private.stock_transfer_states values(t,1);
 for i in select value from jsonb_array_elements(p_items) order by value->>'product_id' loop
  select * into p from public.products where id=(i->>'product_id')::uuid;
  insert into public.stock_movements(organization_id,branch_id,product_id,actor_user_id,quantity_delta,balance_after,operation_id) values(p_organization_id,p_source_branch_id,p.id,auth.uid(),-(i->>'quantity')::bigint,0,op) returning * into move;
  insert into public.stock_transfer_items(organization_id,transfer_id,product_id,product_name,sku,unit,product_revision,quantity,movement_id) values(p_organization_id,t,p.id,p.name,p.sku,p.unit,p.revision,(i->>'quantity')::bigint,move.id) returning id into line;
  insert into private.stock_transfer_balances values(line,0,0);
  items:=items||jsonb_build_array(jsonb_build_object('item_id',line,'product_id',p.id,'quantity',(i->>'quantity')::bigint,'expected_revision',p.revision,'unit',p.unit,'movement_id',move.id,'balance_after',move.balance_after,'stock_revision',move.stock_revision));
 end loop;
 return private.logistics_commit(p_organization_id,p_source_branch_id,p_request_id,'transfer.dispatch',payload,jsonb_build_object('id',t,'transfer_id',t,'revision',1,'source_branch_id',p_source_branch_id,'destination_branch_id',p_destination_branch_id,'operation_id',op,'items',items,'created_at',(select private.offline_time(created_at) from public.stock_transfers where id=t)),why,'stock_transfers',t);
end;$$;
create function public.complete_stock_transfer(p_organization_id uuid,p_branch_id uuid,p_request_id uuid,p_transfer_id uuid,p_expected_revision bigint,p_kind text,p_items jsonb,p_reference text,p_reason text,p_physical_confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;old_id uuid;t public.stock_transfers;s private.stock_transfer_states;i jsonb;l public.stock_transfer_items;b private.stock_transfer_balances;p public.products;op uuid;move public.stock_movements;ev uuid;items jsonb:='[]';safe_items jsonb:='[]';why text:=btrim(p_reason);
begin
 perform private.logistics_scope(p_organization_id,p_branch_id);
 perform private.offline_counter_lock(p_organization_id);
 if p_kind not in ('transfer.receive','transfer.return') or p_kind is null then raise exception 'Select a receipt or physical transit return' using errcode='22023';end if;
 payload:=jsonb_build_object('branch_id',p_branch_id,'transfer_id',p_transfer_id,'expected_revision',p_expected_revision,'kind',p_kind,'items',p_items,'reference',p_reference,'reason',why,'physical_confirmed',p_physical_confirmed);
 old_id:=private.phase3_request(p_organization_id,p_request_id,p_kind,payload);
 if old_id is not null then return(select document from private.logistics_actions where id=old_id);end if;
 perform private.logistics_scope(p_organization_id,p_branch_id,true);
 select * into t from public.stock_transfers where id=p_transfer_id and organization_id=p_organization_id;
 if not found or p_branch_id<>(case when p_kind='transfer.receive' then t.destination_branch_id else t.source_branch_id end) then raise exception 'Wrong physical endpoint' using errcode='42501';end if;
 select * into s from private.stock_transfer_states where transfer_id=t.id for update;
 if p_expected_revision is null or s.revision<>p_expected_revision then raise exception 'Transit quantities changed; reload' using errcode='40001';end if;
 if s.revision>=9007199254740991 then raise exception 'Transfer revision limit' using errcode='22023';end if;
 perform private.purchase_reason(why,p_reference);
 if p_physical_confirmed is distinct from true or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Confirm physical goods and bounded lines' using errcode='22023';end if;
 for i in select value from jsonb_array_elements(p_items) loop
  perform private.phase3_check_keys(i,array['item_id','quantity','expected_revision']);perform private.offline_uuid(i->'item_id');perform private.phase3_integer(i->'quantity',1,1000000);perform private.phase3_integer(i->'expected_revision',1,9007199254740991);
  select * into l from public.stock_transfer_items where id=(i->>'item_id')::uuid and transfer_id=t.id;
  if not found then raise exception 'Foreign transfer item' using errcode='42501';end if;
  select * into b from private.stock_transfer_balances where item_id=l.id;
  if (i->>'quantity')::bigint>l.quantity-b.received-b.returned then raise exception 'Quantity exceeds outstanding transit goods' using errcode='23514';end if;
 end loop;
 if (select count(distinct value->>'item_id') from jsonb_array_elements(p_items))<>jsonb_array_length(p_items) then raise exception 'Duplicate transfer line' using errcode='22023';end if;
 for i in select x.value from jsonb_array_elements(p_items)x join public.stock_transfer_items src on src.id=(x.value->>'item_id')::uuid order by src.product_id loop
  select * into l from public.stock_transfer_items where id=(i->>'item_id')::uuid;
  select * into p from public.products where id=l.product_id and organization_id=p_organization_id for update;
  if p.revision<>(i->>'expected_revision')::bigint then raise exception 'Product revision changed' using errcode='40001';end if;
  if p.unit<>l.unit then raise exception 'Original stock unit requires review; conversion is unavailable' using errcode='23514';end if;
 end loop;
 insert into public.inventory_operations(organization_id,branch_id,actor_user_id,kind,reason,reference) values(p_organization_id,p_branch_id,auth.uid(),case when p_kind='transfer.receive' then 'transfer_receive' else 'transfer_return' end,why,p_reference) returning id into op;
 for i in select x.value from jsonb_array_elements(p_items)x join public.stock_transfer_items src on src.id=(x.value->>'item_id')::uuid order by src.product_id loop
  select * into l from public.stock_transfer_items where id=(i->>'item_id')::uuid;
  insert into public.stock_movements(organization_id,branch_id,product_id,actor_user_id,quantity_delta,balance_after,operation_id) values(p_organization_id,p_branch_id,l.product_id,auth.uid(),(i->>'quantity')::bigint,0,op) returning * into move;
  update private.stock_transfer_balances set received=received+case when p_kind='transfer.receive' then (i->>'quantity')::bigint else 0 end,returned=returned+case when p_kind='transfer.return' then (i->>'quantity')::bigint else 0 end where item_id=l.id;
  safe_items:=safe_items||jsonb_build_array(jsonb_build_object('item_id',l.id,'product_id',l.product_id,'quantity',(i->>'quantity')::bigint,'unit',l.unit));
  items:=items||jsonb_build_array(jsonb_build_object('item_id',l.id,'product_id',l.product_id,'quantity',(i->>'quantity')::bigint,'expected_revision',(i->>'expected_revision')::bigint,'unit',l.unit,'movement_id',move.id,'balance_after',move.balance_after,'stock_revision',move.stock_revision));
 end loop;
 update private.stock_transfer_states set revision=revision+1 where transfer_id=t.id;
 insert into public.stock_transfer_events(organization_id,transfer_id,branch_id,kind,actor_id,revision,operation_id,reason,reference,physical_confirmed,items) values(p_organization_id,t.id,p_branch_id,p_kind,auth.uid(),s.revision+1,op,why,p_reference,true,safe_items) returning id into ev;
 return private.logistics_commit(p_organization_id,p_branch_id,p_request_id,p_kind,payload,jsonb_build_object('id',ev,'transfer_id',t.id,'revision',s.revision+1,'operation_id',op,'items',items,'created_at',(select private.offline_time(created_at) from public.stock_transfer_events where id=ev)),why,'stock_transfer_events',ev);
end;$$;
create function public.get_purchase_receipt_return_context(p_organization_id uuid,p_branch_id uuid,p_receipt_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.purchase_receipts;result jsonb;
begin
 perform private.logistics_scope(p_organization_id,p_branch_id);
 select * into r from public.purchase_receipts where id=p_receipt_id and organization_id=p_organization_id and branch_id=p_branch_id;
 if not found then raise exception 'Original receipt outside branch scope' using errcode='42501';end if;
 select jsonb_build_object('organization_id',p_organization_id,'branch_id',p_branch_id,'receipt_id',r.id,'currency',r.currency,'items',jsonb_agg(jsonb_build_object('item_id',i.id,'product_id',i.product_id,'product_name',o.product_name,'sku',o.sku,'unit',o.unit,'quantity',i.quantity,
  'returned',coalesce((select sum(x.quantity) from public.purchase_return_items x where x.receipt_item_id=i.id),0),'unit_cost_minor',i.unit_cost_minor,'expected_revision',p.revision,'current_unit',p.unit,'on_hand',coalesce(b.quantity,0)) order by i.product_id)) into result
 from public.purchase_receipt_items i join public.purchase_order_items o on o.id=i.order_item_id join public.products p on p.id=i.product_id left join private.stock_balances b on b.organization_id=i.organization_id and b.branch_id=i.branch_id and b.product_id=i.product_id where i.receipt_id=r.id;
 return result;
end;$$;
create function public.return_purchase_receipt(p_organization_id uuid,p_branch_id uuid,p_request_id uuid,p_receipt_id uuid,p_items jsonb,p_reference text,p_reason text,p_physical_confirmed boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb;old_id uuid;r public.purchase_receipts;o public.purchase_orders;l public.purchase_receipt_items;original public.purchase_order_items;p public.products;i jsonb;op uuid;ret uuid;move public.stock_movements;total numeric:=0;previous numeric;items jsonb:='[]';why text:=btrim(p_reason);
begin
 perform private.logistics_scope(p_organization_id,p_branch_id);perform private.offline_counter_lock(p_organization_id);
 payload:=jsonb_build_object('branch_id',p_branch_id,'receipt_id',p_receipt_id,'items',p_items,'reference',p_reference,'reason',why,'physical_confirmed',p_physical_confirmed);
 old_id:=private.phase3_request(p_organization_id,p_request_id,'supplier.return',payload);
 if old_id is not null then return(select document from private.logistics_actions where id=old_id);end if;
 perform private.logistics_scope(p_organization_id,p_branch_id,true);perform private.purchase_reason(why,p_reference);
 if p_physical_confirmed is distinct from true or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Confirm returned physical goods and bounded lines' using errcode='22023';end if;
 select * into r from public.purchase_receipts where id=p_receipt_id and organization_id=p_organization_id and branch_id=p_branch_id for update;
 if not found then raise exception 'Original receipt outside branch scope' using errcode='42501';end if;
 select * into o from public.purchase_orders where id=r.order_id;
 for i in select value from jsonb_array_elements(p_items) loop
  perform private.phase3_check_keys(i,array['item_id','quantity','expected_revision']);perform private.offline_uuid(i->'item_id');perform private.phase3_integer(i->'quantity',1,1000000);perform private.phase3_integer(i->'expected_revision',1,9007199254740991);
  select * into l from public.purchase_receipt_items where id=(i->>'item_id')::uuid and receipt_id=r.id;
  if not found then raise exception 'Foreign purchase receipt item' using errcode='42501';end if;
  select coalesce(sum(quantity),0) into previous from public.purchase_return_items where receipt_item_id=l.id;
  if previous+(i->>'quantity')::bigint>l.quantity then raise exception 'Return exceeds original received quantity' using errcode='23514';end if;
  total:=total+(i->>'quantity')::numeric*l.unit_cost_minor;perform private.purchase_exact(total);
 end loop;
 if (select count(distinct value->>'item_id') from jsonb_array_elements(p_items))<>jsonb_array_length(p_items) then raise exception 'Duplicate return item' using errcode='22023';end if;
 for i in select x.value from jsonb_array_elements(p_items)x join public.purchase_receipt_items src on src.id=(x.value->>'item_id')::uuid order by src.product_id loop
  select * into l from public.purchase_receipt_items where id=(i->>'item_id')::uuid;select * into original from public.purchase_order_items where id=l.order_item_id;
  select * into p from public.products where id=l.product_id and organization_id=p_organization_id for update;
  if p.revision<>(i->>'expected_revision')::bigint then raise exception 'Product changed; reload return' using errcode='40001';end if;
  if p.unit<>original.unit then raise exception 'Original unit differs; physical review required' using errcode='23514';end if;
 end loop;
 insert into public.inventory_operations(organization_id,branch_id,actor_user_id,kind,supplier_id,reason,reference) values(p_organization_id,p_branch_id,auth.uid(),'supplier_return',o.supplier_id,why,p_reference) returning id into op;
 insert into public.purchase_returns(organization_id,branch_id,receipt_id,actor_id,operation_id,supplier_id,currency,total_minor,reason,reference,physical_confirmed) values(p_organization_id,p_branch_id,r.id,auth.uid(),op,o.supplier_id,r.currency,private.purchase_exact(total),why,p_reference,true) returning id into ret;
 for i in select x.value from jsonb_array_elements(p_items)x join public.purchase_receipt_items src on src.id=(x.value->>'item_id')::uuid order by src.product_id loop
  select * into l from public.purchase_receipt_items where id=(i->>'item_id')::uuid;select * into original from public.purchase_order_items where id=l.order_item_id;
  insert into public.stock_movements(organization_id,branch_id,product_id,actor_user_id,quantity_delta,balance_after,operation_id) values(p_organization_id,p_branch_id,l.product_id,auth.uid(),-(i->>'quantity')::bigint,0,op) returning * into move;
  insert into private.inventory_cost_evidence(movement_id,unit_cost_minor,currency,product_revision) values(move.id,l.unit_cost_minor,r.currency,(i->>'expected_revision')::bigint);
  insert into public.purchase_return_items(organization_id,return_id,receipt_item_id,product_id,quantity,unit_cost_minor,line_cost_minor,product_revision,movement_id) values(p_organization_id,ret,l.id,l.product_id,(i->>'quantity')::bigint,l.unit_cost_minor,private.purchase_exact((i->>'quantity')::numeric*l.unit_cost_minor),(i->>'expected_revision')::bigint,move.id);
  items:=items||jsonb_build_array(jsonb_build_object('item_id',l.id,'product_id',l.product_id,'quantity',(i->>'quantity')::bigint,'expected_revision',(i->>'expected_revision')::bigint,'unit',original.unit,'unit_cost_minor',l.unit_cost_minor,'line_cost_minor',private.purchase_exact((i->>'quantity')::numeric*l.unit_cost_minor),'movement_id',move.id,'balance_after',move.balance_after,'stock_revision',move.stock_revision));
 end loop;
 return private.logistics_commit(p_organization_id,p_branch_id,p_request_id,'supplier.return',payload,jsonb_build_object('id',ret,'receipt_id',r.id,'currency',r.currency,'total_minor',private.purchase_exact(total),'operation_id',op,'items',items,'created_at',(select private.offline_time(created_at) from public.purchase_returns where id=ret)),why,'purchase_returns',ret);
end;$$;
create function public.list_purchase_returns(p_organization_id uuid,p_branch_id uuid,p_offset integer default 0,p_limit integer default 51) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 perform private.logistics_scope(p_organization_id,p_branch_id);perform private.purchase_page(p_offset,p_limit);
 select coalesce(jsonb_agg(a.document order by x.created_at desc,x.id),'[]'::jsonb) into r from
 (select * from public.purchase_returns where organization_id=p_organization_id and branch_id=p_branch_id order by created_at desc,id offset p_offset limit p_limit)x
 join private.logistics_actions a on a.document->'document'->>'id'=x.id::text and a.kind='supplier.return';return r;
end;$$;
-- Keep outstanding transit reachable when an administrator deactivates a branch.
alter function private.branch_deactivation_check(uuid,uuid) rename to branch_deactivation_check_base;
create function private.branch_deactivation_check(p_org uuid,p_branch uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.branch_deactivation_check_base(p_org,p_branch);
 if exists(select 1 from public.stock_transfers t join public.stock_transfer_items i on i.transfer_id=t.id join private.stock_transfer_balances b on b.item_id=i.id where t.organization_id=p_org and p_branch in(t.source_branch_id,t.destination_branch_id) and b.received+b.returned<i.quantity) then raise exception 'Resolve goods in transit before branch deactivation' using errcode='23514';end if;
end;$$;
-- Audit extensions retain all previous employee/security branch-snapshot rules.
alter function private.can_read_audit(uuid,uuid,text,uuid,text,jsonb) rename to logistics_prior_can_read_audit;
create function private.can_read_audit(p_org uuid,p_branch uuid,p_entity text,p_id uuid,p_action text,p_metadata jsonb) returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 if (p_entity='branches' and p_action in('branch.create','branch.update')) then perform private.branch_management_member(p_org,p_branch);return true;
 elsif (p_entity='stock_transfers' and p_action='transfer.dispatch') or (p_entity='stock_transfer_events' and p_action in('transfer.receive','transfer.return')) or (p_entity='purchase_returns' and p_action='supplier.return') then return private.logistics_can_read(p_org,p_branch);
 end if;
 return private.logistics_prior_can_read_audit(p_org,p_branch,p_entity,p_id,p_action,p_metadata);
exception when insufficient_privilege then return false;
end;$$;
drop policy audit_read_authorized on public.audit_logs;
create policy audit_read_authorized on public.audit_logs for select to authenticated using(private.can_read_audit(organization_id,branch_id,entity,entity_id,action,metadata));
do $$declare f record;begin
 for f in select p.oid::regprocedure signature,n.nspname,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where
 (n.nspname='private' and (p.proname like 'logistics_%' or p.proname in('branch_deactivation_check','branch_deactivation_check_base')))
 or (n.nspname='public' and p.proname in('list_stock_transfers','get_stock_transfer','list_stock_transfer_events','dispatch_stock_transfer','complete_stock_transfer','get_purchase_receipt_return_context','return_purchase_receipt','list_purchase_returns')) loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
 if f.nspname='public' then execute format('grant execute on function %s to authenticated',f.signature);end if;
 end loop;
end;$$;
revoke all on function private.can_read_audit(uuid,uuid,text,uuid,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.can_read_audit(uuid,uuid,text,uuid,text,jsonb) to authenticated;
commit;
