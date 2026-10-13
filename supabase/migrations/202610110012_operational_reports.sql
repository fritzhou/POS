-- Phase 6A: authoritative operational reports. Each report aggregate and its
-- nested groups share ONE SQL statement snapshot. No local/unposted event is a
-- sale source, no split-tender/item join can multiply document totals.
begin;
create function private.phase6_report_integer(p_value numeric)
returns bigint language plpgsql immutable set search_path='' as $$
begin
 if p_value is null or p_value <> trunc(p_value) or p_value not between -9007199254740991 and 9007199254740991 then
  raise exception 'Report exceeds exact integer range; choose a narrower activity window or product filter' using errcode='NX003';
 end if;
 return p_value::bigint;
end; $$;
create function private.phase6_report_window(p_from timestamptz,p_to timestamptz)
returns void language plpgsql immutable set search_path='' as $$
begin
 if p_from is null or p_to is null or not isfinite(p_from) or not isfinite(p_to) or p_from>=p_to or p_to-p_from>interval '366 days' then
  raise exception 'Select a finite UTC activity window greater than zero and at most 366 days' using errcode='22023';
 end if;
end; $$;
create function private.phase6_report_time(p_time timestamptz)
returns text language sql immutable set search_path='' as $$
 select to_char(p_time at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
$$;
create function private.phase6_sales_metrics(p_sale_count numeric,p_subtotal numeric,p_discount numeric,p_tax numeric,p_sales numeric,
 p_reversal_count numeric,p_refund numeric,p_void numeric,p_reversed numeric)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('sale_count',private.phase6_report_integer(p_sale_count),
 'sales_subtotal_minor',private.phase6_report_integer(p_subtotal),'sales_discount_minor',private.phase6_report_integer(p_discount),
 'sales_tax_minor',private.phase6_report_integer(p_tax),'sales_total_minor',private.phase6_report_integer(p_sales),
 'reversal_count',private.phase6_report_integer(p_reversal_count),'refund_total_minor',private.phase6_report_integer(p_refund),
 'void_total_minor',private.phase6_report_integer(p_void),'reversal_total_minor',private.phase6_report_integer(p_reversed),
 'net_sales_minor',private.phase6_report_integer(p_sales-p_reversed));
$$;
create function private.phase6_expense_metrics(p_count numeric,p_expense numeric,p_reversal_count numeric,p_reversed numeric)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('expense_count',private.phase6_report_integer(p_count),
 'expense_total_minor',private.phase6_report_integer(p_expense),'reversal_count',private.phase6_report_integer(p_reversal_count),
 'reversal_total_minor',private.phase6_report_integer(p_reversed),'net_expense_minor',private.phase6_report_integer(p_expense-p_reversed));
$$;
create function public.get_sales_report(p_organization_id uuid,p_branch_id uuid,p_from timestamptz,p_to timestamptz,p_shift_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.organization_memberships;r jsonb;
begin
 m:=private.phase3_require(p_organization_id,p_branch_id,'pos');
 perform private.phase6_report_window(p_from,p_to);
 if m.role='cashier' and p_shift_id is null then raise exception 'Cashier sales reports require an explicitly selected own shift' using errcode='42501'; end if;
 if p_shift_id is not null then
  perform 1 from public.shifts where id=p_shift_id and organization_id=p_organization_id and branch_id=p_branch_id
   and (m.role<>'cashier' or actor_user_id=auth.uid());
  if not found then raise exception 'The selected shift is outside the current authorized scope' using errcode='42501'; end if;
 end if;
 with sale_activity as materialized (
  select s.id,s.currency,(s.created_at at time zone 'UTC')::date activity_date,
   s.subtotal_minor::numeric subtotal,s.discount_minor::numeric discount,s.tax_minor::numeric tax,s.total_minor::numeric amount
  from public.sales s where s.organization_id=p_organization_id and s.branch_id=p_branch_id and s.created_at>=p_from and s.created_at<p_to
   and (p_shift_id is null or s.shift_id=p_shift_id)
 ), reversal_activity as materialized (
  select r.id,r.currency,(r.created_at at time zone 'UTC')::date activity_date,r.kind,r.total_minor::numeric amount
  from public.sale_reversals r where r.organization_id=p_organization_id and r.branch_id=p_branch_id and r.created_at>=p_from and r.created_at<p_to
   and (p_shift_id is null or r.shift_id=p_shift_id)
 ), activity as materialized (
  select currency,activity_date,1::numeric sale_count,subtotal,discount,tax,amount sales,0::numeric reversal_count,0::numeric refund,0::numeric void,0::numeric reversed from sale_activity
  union all select currency,activity_date,0,0,0,0,0,1,case when kind='refund' then amount else 0 end,case when kind='void' then amount else 0 end,amount from reversal_activity
 ), totals as (
  select currency,sum(sale_count) sale_count,sum(subtotal) subtotal,sum(discount) discount,sum(tax) tax,sum(sales) sales,
   sum(reversal_count) reversal_count,sum(refund) refund,sum(void) void,sum(reversed) reversed from activity group by currency
 ), daily as (
  select currency,activity_date,sum(sale_count) sale_count,sum(subtotal) subtotal,sum(discount) discount,sum(tax) tax,sum(sales) sales,
   sum(reversal_count) reversal_count,sum(refund) refund,sum(void) void,sum(reversed) reversed from activity group by currency,activity_date
 ), payment_activity as (
  select s.currency,p.method,p.amount_minor::numeric sales,0::numeric reversed from sale_activity s
   join public.sale_payments p on p.sale_id=s.id and p.organization_id=p_organization_id
  union all select r.currency,p.method,0,rp.amount_minor::numeric from reversal_activity r
   join public.sale_reversal_payments rp on rp.reversal_id=r.id and rp.organization_id=p_organization_id
   join public.sale_payments p on p.id=rp.original_payment_id and p.organization_id=rp.organization_id
 ), payment_totals as (
  select currency,method,sum(sales) sales,sum(reversed) reversed from payment_activity group by currency,method
 )
 select jsonb_build_object('organization_id',p_organization_id,'branch_id',p_branch_id,
  'generated_at',private.phase6_report_time(statement_timestamp()),'source','server_posted',
  'from',private.phase6_report_time(p_from),'to',private.phase6_report_time(p_to),'shift_id',p_shift_id,
  'currencies',coalesce((select jsonb_agg(jsonb_build_object('currency',t.currency)||private.phase6_sales_metrics(t.sale_count,t.subtotal,t.discount,t.tax,t.sales,t.reversal_count,t.refund,t.void,t.reversed)
   ||jsonb_build_object('payments',coalesce((select jsonb_agg(jsonb_build_object('method',p.method,
    'sales_minor',private.phase6_report_integer(p.sales),'reversed_minor',private.phase6_report_integer(p.reversed),
    'net_minor',private.phase6_report_integer(p.sales-p.reversed)) order by p.method) from payment_totals p where p.currency=t.currency),'[]'::jsonb),
    'daily',coalesce((select jsonb_agg(jsonb_build_object('date',to_char(d.activity_date,'YYYY-MM-DD'))||private.phase6_sales_metrics(d.sale_count,d.subtotal,d.discount,d.tax,d.sales,d.reversal_count,d.refund,d.void,d.reversed)
    order by d.activity_date) from daily d where d.currency=t.currency),'[]'::jsonb)) order by t.currency) from totals t),'[]'::jsonb)) into r;
 return r;
end; $$;
create function public.get_inventory_report(p_organization_id uuid,p_branch_id uuid,p_query text default '',p_offset integer default 0,p_limit integer default 51)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;v_query text:=btrim(coalesce(p_query,''));
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'stock');
 if p_query is null or char_length(v_query)>120 or p_offset is null or p_offset not between 0 and 1000000 or p_limit is null or p_limit not between 1 and 101 then
  raise exception 'Select a valid inventory product filter and page' using errcode='22023';
 end if;
 with observed as materialized (
  select p.id product_id,p.name,p.sku,p.unit,p.active,p.reorder_level,coalesce(b.quantity,0)::numeric quantity,coalesce(b.revision,0)::numeric stock_revision,
   coalesce(b.revision>0,false) has_movement,coalesce(b.quantity,0)<0 is_deficit,
   p.active and coalesce(b.quantity,0)<=p.reorder_level is_low_stock
  from public.products p left join private.stock_balances b on b.organization_id=p.organization_id and b.branch_id=p_branch_id and b.product_id=p.id
  where p.organization_id=p_organization_id and (p.active or b.product_id is not null)
   and (v_query='' or strpos(lower(p.name),lower(v_query))>0 or strpos(lower(p.sku),lower(v_query))>0)
 ), page as (select * from observed order by name,product_id offset p_offset limit p_limit)
 select jsonb_build_object('organization_id',p_organization_id,'branch_id',p_branch_id,'generated_at',private.phase6_report_time(statement_timestamp()),
  'source','server_posted','query',v_query,'offset',p_offset,'limit',p_limit,
  'catalog_product_count',private.phase6_report_integer((select count(*)::numeric from observed)),
  'stocked_product_count',private.phase6_report_integer((select count(*)::numeric from observed where quantity>0)),
  'deficit_product_count',private.phase6_report_integer((select count(*)::numeric from observed where is_deficit)),
  'low_stock_product_count',private.phase6_report_integer((select count(*)::numeric from observed where is_low_stock)),
  'items',coalesce((select jsonb_agg(jsonb_build_object('product_id',product_id,'name',name,'sku',sku,'unit',unit,'active',active,
   'reorder_level',reorder_level::text,'quantity',private.phase6_report_integer(quantity),'stock_revision',private.phase6_report_integer(stock_revision),
   'has_movement',has_movement,'is_deficit',is_deficit,'is_low_stock',is_low_stock) order by name,product_id) from page),'[]'::jsonb)) into r;
 return r;
end; $$;
create function public.get_expense_report(p_organization_id uuid,p_branch_id uuid,p_from timestamptz,p_to timestamptz)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 perform private.phase3_require(p_organization_id,p_branch_id,'manage');
 perform private.phase6_report_window(p_from,p_to);
 with activity as materialized (
  select e.currency,e.category,e.source,(e.occurred_at at time zone 'UTC')::date activity_date,
   1::numeric expense_count,e.amount_minor::numeric expense,0::numeric reversal_count,0::numeric reversed
  from public.expenses e where e.organization_id=p_organization_id and e.branch_id=p_branch_id and e.occurred_at>=p_from and e.occurred_at<p_to
  union all select e.currency,e.category,e.source,(r.created_at at time zone 'UTC')::date,0,0,1,r.amount_minor::numeric
  from public.expense_reversals r join public.expenses e on e.id=r.expense_id and e.organization_id=r.organization_id and e.branch_id=r.branch_id
  where r.organization_id=p_organization_id and r.branch_id=p_branch_id and r.created_at>=p_from and r.created_at<p_to
 ), totals as (
  select currency,sum(expense_count) expense_count,sum(expense) expense,sum(reversal_count) reversal_count,sum(reversed) reversed from activity group by currency
 ), categories as (
  select currency,category,sum(expense_count) expense_count,sum(expense) expense,sum(reversal_count) reversal_count,sum(reversed) reversed from activity group by currency,category
 ), sources as (
  select currency,source,sum(expense_count) expense_count,sum(expense) expense,sum(reversal_count) reversal_count,sum(reversed) reversed from activity group by currency,source
 ), daily as (
  select currency,activity_date,sum(expense_count) expense_count,sum(expense) expense,sum(reversal_count) reversal_count,sum(reversed) reversed from activity group by currency,activity_date
 )
 select jsonb_build_object('organization_id',p_organization_id,'branch_id',p_branch_id,
  'generated_at',private.phase6_report_time(statement_timestamp()),'source','server_posted','from',private.phase6_report_time(p_from),'to',private.phase6_report_time(p_to),
  'currencies',coalesce((select jsonb_agg(jsonb_build_object('currency',t.currency)||private.phase6_expense_metrics(t.expense_count,t.expense,t.reversal_count,t.reversed)
  ||jsonb_build_object('categories',coalesce((select jsonb_agg(jsonb_build_object('category',c.category)||private.phase6_expense_metrics(c.expense_count,c.expense,c.reversal_count,c.reversed) order by c.category)
   from categories c where c.currency=t.currency),'[]'::jsonb),
   'sources',coalesce((select jsonb_agg(jsonb_build_object('source',s.source)||private.phase6_expense_metrics(s.expense_count,s.expense,s.reversal_count,s.reversed) order by s.source)
   from sources s where s.currency=t.currency),'[]'::jsonb),
   'daily',coalesce((select jsonb_agg(jsonb_build_object('date',to_char(d.activity_date,'YYYY-MM-DD'))||private.phase6_expense_metrics(d.expense_count,d.expense,d.reversal_count,d.reversed) order by d.activity_date)
   from daily d where d.currency=t.currency),'[]'::jsonb)) order by t.currency) from totals t),'[]'::jsonb)) into r;
 return r;
end; $$;
-- No client accesses private helpers or report underlying private projections.
revoke all on function private.phase6_report_integer(numeric),private.phase6_report_window(timestamptz,timestamptz),private.phase6_report_time(timestamptz),
 private.phase6_sales_metrics(numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric),private.phase6_expense_metrics(numeric,numeric,numeric,numeric) from public,anon,authenticated,service_role;
revoke all on function public.get_sales_report(uuid,uuid,timestamptz,timestamptz,uuid),public.get_inventory_report(uuid,uuid,text,integer,integer),
 public.get_expense_report(uuid,uuid,timestamptz,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.get_sales_report(uuid,uuid,timestamptz,timestamptz,uuid),public.get_inventory_report(uuid,uuid,text,integer,integer),
 public.get_expense_report(uuid,uuid,timestamptz,timestamptz) to authenticated;
commit;
