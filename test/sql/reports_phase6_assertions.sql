\set ON_ERROR_STOP on
-- Isolated, rolled-back historical documents. Backdated frozen fixture rows
-- exercise independent activity clocks; no client RPC accepts these timestamps.
begin;
insert into auth.users(id,email,email_confirmed_at)
select ('d6000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'report-'||n||'@example.invalid',clock_timestamp() from generate_series(1,6) n;
set local role authenticated;
select set_config('request.jwt.claim.sub','d6000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{}',true);
select set_config('test.r6_org',organization_id::text,true),set_config('test.r6_branch',branch_id::text,true)
 from public.bootstrap_organization('Reports fixture shop','Reports fixture owner');
select test.assert(public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')->'currencies'='[]'::jsonb,'Authorized empty sales report truthfully contains no currencies');
select test.assert(public.get_expense_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')->'currencies'='[]'::jsonb,'Authorized empty expense report truthfully contains no currencies');
select test.assert((public.get_inventory_report(test.id('r6_org'),test.id('r6_branch'))->>'catalog_product_count')::int=0,'Authorized empty inventory report has zero observed products');
reset role;
select set_config('request.jwt.claim.sub','',true);
insert into public.branches(id,organization_id,name,code) values('d6010000-0000-4000-8000-000000000002',test.id('r6_org'),'Other report branch','OTHER');
insert into public.organization_memberships(id,organization_id,user_id,role,status)
select ('d6020000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,test.id('r6_org'),('d6000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 case n when 2 then 'manager' when 3 then 'cashier' when 4 then 'inventory_staff' when 5 then 'admin' else 'cashier' end,'active' from generate_series(2,6) n;
insert into public.membership_branches(organization_id,membership_id,branch_id)
select organization_id,id,test.id('r6_branch') from public.organization_memberships where organization_id=test.id('r6_org') and role<>'owner';
insert into public.products(id,organization_id,name,sku,unit,reorder_level,active,cost_minor,price_minor)
select ('d6030000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,test.id('r6_org'),
 case n when 1 then 'Report A stock' when 2 then 'Report B deficit' when 3 then 'Report C never received' when 4 then 'Report D inactive history' when 5 then 'Report E inactive absent' else 'Report F fractional reorder' end,
 'R6-'||n,'each',case n when 1 then 3 when 6 then 2.5 else 0 end,n not in (4,5),987654,100 from generate_series(1,6) n;
-- Projection fixtures represent posted stock observations, including the trusted
-- deficit source already exhaustively validated by the Phase 4 ingest tests.
insert into private.stock_balances(organization_id,branch_id,product_id,quantity,revision)
select test.id('r6_org'),test.id('r6_branch'),('d6030000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 case n when 1 then 7 when 2 then -2 when 4 then 0 else 2 end,case n when 1 then 4 when 2 then 3 when 4 then 2 else 1 end from unnest(array[1,2,4,6]) n;
insert into public.shifts(id,organization_id,branch_id,actor_user_id,currency,opening_cash_minor,opened_at) values
 ('d6040000-0000-4000-8000-000000000001',test.id('r6_org'),test.id('r6_branch'),'d6000000-0000-4000-8000-000000000001','PHP',1000,'2025-01-01'),
 ('d6040000-0000-4000-8000-000000000002',test.id('r6_org'),test.id('r6_branch'),'d6000000-0000-4000-8000-000000000003','PHP',0,'2025-01-01'),
 ('d6040000-0000-4000-8000-000000000003',test.id('r6_org'),test.id('r6_branch'),'d6000000-0000-4000-8000-000000000001','USD',0,'2025-01-01'),
 ('d6040000-0000-4000-8000-000000000004',test.id('r6_org'),'d6010000-0000-4000-8000-000000000002','d6000000-0000-4000-8000-000000000001','PHP',0,'2025-01-01');
insert into public.sales(id,organization_id,branch_id,shift_id,actor_user_id,receipt_sequence,receipt_number,currency,business_snapshot,settings_revision,
 subtotal_minor,discount_minor,tax_bps,tax_minor,total_minor,created_at) values
 ('d6050000-0000-4000-8000-000000000001',test.id('r6_org'),test.id('r6_branch'),'d6040000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000001',1,'REPORT-1','PHP','{}',1,1000,100,1000,90,990,'2025-01-02T10:00:00Z'),
 ('d6050000-0000-4000-8000-000000000002',test.id('r6_org'),test.id('r6_branch'),'d6040000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000001',2,'REPORT-2','PHP','{}',1,200,0,0,0,200,'2025-01-02T23:59:59.999999Z'),
 ('d6050000-0000-4000-8000-000000000003',test.id('r6_org'),test.id('r6_branch'),'d6040000-0000-4000-8000-000000000002','d6000000-0000-4000-8000-000000000003',3,'REPORT-3','PHP','{}',1,300,0,0,0,300,'2025-01-04T12:00:00Z'),
 ('d6050000-0000-4000-8000-000000000004',test.id('r6_org'),test.id('r6_branch'),'d6040000-0000-4000-8000-000000000003','d6000000-0000-4000-8000-000000000001',4,'REPORT-4','USD','{}',1,50,0,0,0,50,'2025-01-02T01:00:00Z');
insert into public.sale_items(id,organization_id,sale_id,product_id,product_name,sku,unit,product_revision,quantity,unit_price_minor,line_subtotal_minor,discount_minor,tax_minor,line_total_minor) values
 ('d6060000-0000-4000-8000-000000000001',test.id('r6_org'),'d6050000-0000-4000-8000-000000000001','d6030000-0000-4000-8000-000000000001','Frozen A','R6-1','each',1,2,250,500,50,45,495),
 ('d6060000-0000-4000-8000-000000000002',test.id('r6_org'),'d6050000-0000-4000-8000-000000000001','d6030000-0000-4000-8000-000000000002','Frozen B','R6-2','each',1,1,500,500,50,45,495);
insert into public.sale_payments(id,organization_id,sale_id,method,amount_minor,tendered_minor,change_minor,reference,manual_confirmed) values
 ('d6070000-0000-4000-8000-000000000001',test.id('r6_org'),'d6050000-0000-4000-8000-000000000001','cash',400,450,50,null,false),
 ('d6070000-0000-4000-8000-000000000002',test.id('r6_org'),'d6050000-0000-4000-8000-000000000001','card',590,null,null,'REAL-MANUAL-REFERENCE',true),
 ('d6070000-0000-4000-8000-000000000003',test.id('r6_org'),'d6050000-0000-4000-8000-000000000002','cash',200,200,0,null,false),
 ('d6070000-0000-4000-8000-000000000004',test.id('r6_org'),'d6050000-0000-4000-8000-000000000003','cash',300,300,0,null,false),
 ('d6070000-0000-4000-8000-000000000005',test.id('r6_org'),'d6050000-0000-4000-8000-000000000004','card',50,null,null,'USD-MANUAL-REFERENCE',true);
insert into public.sale_reversals(id,organization_id,branch_id,sale_id,shift_id,actor_user_id,kind,currency,total_minor,reason,created_at) values
 ('d6080000-0000-4000-8000-000000000001',test.id('r6_org'),test.id('r6_branch'),'d6050000-0000-4000-8000-000000000001','d6040000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000001','refund','PHP',495,'Confirmed partial manual refund','2025-01-03'),
 ('d6080000-0000-4000-8000-000000000002',test.id('r6_org'),test.id('r6_branch'),'d6050000-0000-4000-8000-000000000002','d6040000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000001','void','PHP',200,'Confirmed untouched manual void','2025-01-03'),
 ('d6080000-0000-4000-8000-000000000003',test.id('r6_org'),test.id('r6_branch'),'d6050000-0000-4000-8000-000000000003','d6040000-0000-4000-8000-000000000002','d6000000-0000-4000-8000-000000000003','refund','PHP',100,'Confirmed own-shift manual refund','2025-01-05'),
 ('d6080000-0000-4000-8000-000000000004',test.id('r6_org'),test.id('r6_branch'),'d6050000-0000-4000-8000-000000000001','d6040000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000001','refund','PHP',495,'Confirmed remaining manual refund','2025-01-08');
insert into public.sale_reversal_payments(organization_id,reversal_id,original_payment_id,amount_minor,manual_confirmed) values
 (test.id('r6_org'),'d6080000-0000-4000-8000-000000000001','d6070000-0000-4000-8000-000000000001',100,true),
 (test.id('r6_org'),'d6080000-0000-4000-8000-000000000001','d6070000-0000-4000-8000-000000000002',395,true),
 (test.id('r6_org'),'d6080000-0000-4000-8000-000000000002','d6070000-0000-4000-8000-000000000003',200,true),
 (test.id('r6_org'),'d6080000-0000-4000-8000-000000000003','d6070000-0000-4000-8000-000000000004',100,true),
 (test.id('r6_org'),'d6080000-0000-4000-8000-000000000004','d6070000-0000-4000-8000-000000000001',300,true),
 (test.id('r6_org'),'d6080000-0000-4000-8000-000000000004','d6070000-0000-4000-8000-000000000002',195,true);
-- Retained paid offline evidence alone does not post a sale or inflate reports.
insert into public.financial_events(id,organization_id,branch_id,actor_user_id,event_kind,payload_digest,payload) values
 ('d6090000-0000-4000-8000-000000000001',test.id('r6_org'),test.id('r6_branch'),'d6000000-0000-4000-8000-000000000001','sale.created',decode(repeat('ab',32),'hex'),'{"status":"review","sale_total_minor":500,"observed_at":"2025-01-02T10:00:00Z"}');
insert into public.expenses(id,organization_id,branch_id,actor_user_id,created_at,occurred_at,currency,settings_revision,amount_minor,category,payee,payment_method,manual_confirmed,source,shift_id,reason) values
 ('d6100000-0000-4000-8000-000000000001',test.id('r6_org'),test.id('r6_branch'),'d6000000-0000-4000-8000-000000000001','2025-01-02','2025-01-02','PHP',1,100,'rent','Landlord','cash',true,'external',null,'Confirmed externally funded rent'),
 ('d6100000-0000-4000-8000-000000000002',test.id('r6_org'),test.id('r6_branch'),'d6000000-0000-4000-8000-000000000001','2025-01-02','2025-01-02','PHP',1,40,'transport','Driver','cash',true,'cash_drawer','d6040000-0000-4000-8000-000000000001','Confirmed own drawer physical payout'),
 ('d6100000-0000-4000-8000-000000000003',test.id('r6_org'),test.id('r6_branch'),'d6000000-0000-4000-8000-000000000001','2025-01-04','2025-01-04','USD',1,20,'fees','Service company','cash',true,'external',null,'Confirmed external dollar payment'),
 ('d6100000-0000-4000-8000-000000000004',test.id('r6_org'),test.id('r6_branch'),'d6000000-0000-4000-8000-000000000001','2024-12-20','2024-12-20','PHP',1,70,'maintenance','Repairer','cash',true,'external',null,'Confirmed prior external maintenance');
insert into public.expense_reversals(id,organization_id,branch_id,expense_id,actor_user_id,created_at,occurred_at,currency,amount_minor,manual_confirmed,source,shift_id,reason) values
 ('d6110000-0000-4000-8000-000000000001',test.id('r6_org'),test.id('r6_branch'),'d6100000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000001','2025-01-03','2025-01-03','PHP',100,true,'external',null,'Confirmed external correction'),
 ('d6110000-0000-4000-8000-000000000002',test.id('r6_org'),test.id('r6_branch'),'d6100000-0000-4000-8000-000000000002','d6000000-0000-4000-8000-000000000001','2025-01-03','2025-01-03','PHP',40,true,'cash_drawer','d6040000-0000-4000-8000-000000000001','Confirmed cash returned to own drawer'),
 ('d6110000-0000-4000-8000-000000000003',test.id('r6_org'),test.id('r6_branch'),'d6100000-0000-4000-8000-000000000004','d6000000-0000-4000-8000-000000000001','2025-01-03','2025-01-03','PHP',70,true,'external',null,'Confirmed prior expense reimbursement');
create function test.r6_currency(p_report jsonb,p_currency text) returns jsonb language sql immutable as $$ select value from jsonb_array_elements(p_report->'currencies') where value->>'currency'=p_currency; $$;
create function test.r6_group(p_array jsonb,p_key text,p_label text) returns jsonb language sql immutable as $$ select value from jsonb_array_elements(p_array) where value->>p_key=p_label; $$;
grant execute on function test.r6_currency(jsonb,text),test.r6_group(jsonb,text,text) to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','d6000000-0000-4000-8000-000000000001',true);
select set_config('test.r6_sales',public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')::text,true);
select set_config('test.r6_php',test.r6_currency(current_setting('test.r6_sales')::jsonb,'PHP')::text,true);
select test.assert(current_setting('test.r6_sales')::jsonb->>'source'='server_posted','Sales report explicitly names committed server source');
select test.assert(current_setting('test.r6_sales')::jsonb->>'organization_id'=test.id('r6_org')::text and current_setting('test.r6_sales')::jsonb->>'branch_id'=test.id('r6_branch')::text,'Sales report echoes exact authorized scope');
select test.assert(jsonb_array_length(current_setting('test.r6_sales')::jsonb->'currencies')=2,'Historical currency change produces separate groups');
select test.assert(current_setting('test.r6_php')::jsonb @> '{"sale_count":3,"sales_subtotal_minor":1500,"sales_discount_minor":100,"sales_tax_minor":90,"sales_total_minor":1490,"reversal_count":4,"refund_total_minor":1090,"void_total_minor":200,"reversal_total_minor":1290,"net_sales_minor":200}', 'Document totals avoid split-payment and item join fan-out');
select test.assert(test.r6_currency(current_setting('test.r6_sales')::jsonb,'USD') @> '{"sale_count":1,"sales_total_minor":50,"reversal_count":0,"net_sales_minor":50}','Dollar sale is never summed with peso sales');
select test.assert(test.r6_group(current_setting('test.r6_php')::jsonb->'payments','method','cash') @> '{"sales_minor":900,"reversed_minor":700,"net_minor":200}','Cash payments use applied cash and original-method reversals');
select test.assert(test.r6_group(current_setting('test.r6_php')::jsonb->'payments','method','card') @> '{"sales_minor":590,"reversed_minor":590,"net_minor":0}','Split noncash evidence aggregates exactly once');
select test.assert(jsonb_array_length(current_setting('test.r6_php')::jsonb->'daily')=5,'Sparse daily groups include every activity date without invented inactive days');
select test.assert(test.r6_group(current_setting('test.r6_php')::jsonb->'daily','date','2025-01-02') @> '{"sale_count":2,"sales_total_minor":1190,"reversal_count":0,"net_sales_minor":1190}','UTC sales date uses original immutable sale capture timestamp');
select test.assert(test.r6_group(current_setting('test.r6_php')::jsonb->'daily','date','2025-01-03') @> '{"sale_count":0,"reversal_count":2,"refund_total_minor":495,"void_total_minor":200,"net_sales_minor":-695}','Refund and untouched void contribute on their independent date');
select test.assert(test.r6_currency(public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-08','2025-01-09'),'PHP') @> '{"sale_count":0,"sales_total_minor":0,"reversal_count":1,"reversal_total_minor":495,"net_sales_minor":-495}','Refund-only window is negative despite original sale outside window');
select test.assert(test.r6_currency(public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-02T23:59:59.999999Z','2025-01-03T00:00:00Z'),'PHP')->>'sales_total_minor'='200','Half-open microsecond window includes last original sale and excludes reversal at end');
select test.assert(public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-02T23:59:59.999999Z','2025-01-03T00:00:00Z')->>'from'='2025-01-02T23:59:59.999999Z','Report time echo retains exact requested microseconds');
select test.assert(test.r6_currency(public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09','d6040000-0000-4000-8000-000000000001'),'PHP')->>'sale_count'='2','Privileged optional shift limits all sale activity');
select test.assert((current_setting('test.r6_php')::jsonb->>'sales_total_minor')::int=1490,'Retained review-only financial event never becomes a posted sale total');
select test.assert(not(current_setting('test.r6_php')::jsonb ? 'profit') and not(current_setting('test.r6_php')::jsonb ? 'net_tax_minor'),'Sales report does not invent profit or refunded tax allocation');
select set_config('test.r6_inventory',public.get_inventory_report(test.id('r6_org'),test.id('r6_branch'),' Report ',0,51)::text,true);
select test.assert(current_setting('test.r6_inventory')::jsonb @> '{"source":"server_posted","query":"Report","offset":0,"limit":51,"catalog_product_count":5,"stocked_product_count":2,"deficit_product_count":1,"low_stock_product_count":3}','Inventory metadata and whole-product counters reflect current server projection');
select test.assert(jsonb_array_length(current_setting('test.r6_inventory')::jsonb->'items')=5,'Inactive stock history remains while inactive never-observed product is omitted');
select test.assert(test.r6_group(current_setting('test.r6_inventory')::jsonb->'items','sku','R6-2') @> '{"quantity":-2,"stock_revision":3,"has_movement":true,"is_deficit":true,"is_low_stock":true}','Inventory reports signed deficit and actual revision');
select test.assert(test.r6_group(current_setting('test.r6_inventory')::jsonb->'items','sku','R6-3') @> '{"quantity":0,"stock_revision":0,"has_movement":false,"is_deficit":false,"is_low_stock":true}','Never-received active product has observed zero without fictional history');
select test.assert(test.r6_group(current_setting('test.r6_inventory')::jsonb->'items','sku','R6-4') @> '{"active":false,"quantity":0,"has_movement":true,"is_low_stock":false}','Zero remaining inactive historical stock stays visible');
select test.assert(test.r6_group(current_setting('test.r6_inventory')::jsonb->'items','sku','R6-6')->>'reorder_level'='2.5000','Fractional catalog threshold remains exact decimal text');
select test.assert(not(test.r6_group(current_setting('test.r6_inventory')::jsonb->'items','sku','R6-1') ? 'cost_minor') and not(current_setting('test.r6_inventory')::jsonb ? 'valuation_minor'),'Inventory report excludes private catalog cost and invented valuation');
select test.assert(public.get_inventory_report(test.id('r6_org'),test.id('r6_branch'),'%',0,51)->'items'='[]'::jsonb,'Literal percent query cannot broaden inventory search');
select test.assert((public.get_inventory_report(test.id('r6_org'),test.id('r6_branch'),'_',0,51)->>'catalog_product_count')::int=0,'Literal underscore query cannot broaden inventory search');
select test.assert((public.get_inventory_report(test.id('r6_org'),test.id('r6_branch'),'Report',1,2)->>'catalog_product_count')::int=5 and jsonb_array_length(public.get_inventory_report(test.id('r6_org'),test.id('r6_branch'),'Report',1,2)->'items')=2,'Inventory aggregate covers all matching observations before pagination');
select test.assert(public.get_inventory_report(test.id('r6_org'),test.id('r6_branch'),'Report',1,2)->'items'->0->>'sku'='R6-2','Inventory name/ID ordering is stable across pages');
select test.assert((public.get_inventory_report(test.id('r6_org'),'d6010000-0000-4000-8000-000000000002')->>'stocked_product_count')::int=0,'Second branch never inherits first-branch stock projection');
select set_config('test.r6_expenses',public.get_expense_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')::text,true);
select set_config('test.r6_exp_php',test.r6_currency(current_setting('test.r6_expenses')::jsonb,'PHP')::text,true);
select test.assert(current_setting('test.r6_expenses')::jsonb->>'source'='server_posted','Expense report explicitly names committed server source');
select test.assert(jsonb_array_length(current_setting('test.r6_expenses')::jsonb->'currencies')=2,'Expense report preserves distinct currencies');
select test.assert(current_setting('test.r6_exp_php')::jsonb @> '{"expense_count":2,"expense_total_minor":140,"reversal_count":3,"reversal_total_minor":210,"net_expense_minor":-70}','Expense activity counts originals and independent compensations without fan-out');
select test.assert(test.r6_group(current_setting('test.r6_exp_php')::jsonb->'categories','category','maintenance') @> '{"expense_count":0,"expense_total_minor":0,"reversal_count":1,"reversal_total_minor":70,"net_expense_minor":-70}','Older original category follows its current-window compensation');
select test.assert(test.r6_group(current_setting('test.r6_exp_php')::jsonb->'sources','source','external') @> '{"expense_count":1,"expense_total_minor":100,"reversal_count":2,"reversal_total_minor":170,"net_expense_minor":-70}','External source groups do not absorb drawer effects');
select test.assert(test.r6_group(current_setting('test.r6_exp_php')::jsonb->'sources','source','cash_drawer') @> '{"expense_count":1,"expense_total_minor":40,"reversal_count":1,"reversal_total_minor":40,"net_expense_minor":0}','Drawer source groups preserve actual payout and same-drawer return');
select test.assert(test.r6_group(current_setting('test.r6_exp_php')::jsonb->'daily','date','2025-01-03') @> '{"expense_count":0,"reversal_count":3,"net_expense_minor":-210}','Expense daily reversal timestamp is separate from original timestamp');
select test.assert(test.r6_currency(public.get_expense_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-03','2025-01-04'),'PHP') @> '{"expense_count":0,"net_expense_minor":-210}','Expense reversal-only window may be negative');
select test.assert(test.r6_currency(public.get_expense_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-02'),'PHP') is null,'Expense half-open end excludes original at exact end');
-- Emit actual SQL projections for cross-language parser contract verification.
select 'R6_REPORT_FIXTURE '||jsonb_build_object('sales',current_setting('test.r6_sales')::jsonb,'inventory',current_setting('test.r6_inventory')::jsonb,'expenses',current_setting('test.r6_expenses')::jsonb)::text;
select test.assert(public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2024-01-01T00:00:00Z','2025-01-01T00:00:00Z')->'currencies'='[]'::jsonb,'Exact 366-day leap-year report window is accepted');
set local time zone 'Pacific/Auckland';
select test.assert(test.r6_group(test.r6_currency(public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01T00:00:00Z','2025-01-09T00:00:00Z'),'PHP')->'daily','date','2025-01-02')->>'sales_total_minor'='1190','Report daily date stays UTC when database session timezone differs');
select test.assert(public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01T00:00:00Z','2025-01-09T00:00:00Z')->>'from'='2025-01-01T00:00:00.000000Z','Wire filter echo stays explicit UTC under non-UTC session timezone');
set local time zone 'UTC';
select test.expect_error($q$select public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2026-01-03')$q$,'22023','Sales report rejects greater than 366 days');
select test.expect_error($q$select public.get_expense_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-01')$q$,'22023','Expense report rejects zero-width window');
select test.expect_error($q$select public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'infinity','infinity')$q$,'22023','Sales report rejects infinite bounds');
select test.expect_error($q$select public.get_expense_report(test.id('r6_org'),test.id('r6_branch'),null,'2025-01-09')$q$,'22023','Expense report requires explicit window');
select test.expect_error($q$select public.get_inventory_report(test.id('r6_org'),test.id('r6_branch'),'',0,102)$q$,'22023','Inventory report rejects oversized page');
select test.expect_error($q$select public.get_inventory_report(test.id('r6_org'),test.id('r6_branch'),repeat('x',121),0,51)$q$,'22023','Inventory report bounds query length');
select test.expect_error($q$select public.get_inventory_report(test.id('r6_org'),test.id('r6_branch'),'',-1,51)$q$,'22023','Inventory report rejects negative offset');
select test.expect_error($q$select public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09','d6040000-0000-4000-8000-000000000004')$q$,'42501','Sales report refuses foreign-branch shift');
select set_config('request.jwt.claim.sub','d6000000-0000-4000-8000-000000000003',true);
select test.expect_error($q$select public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')$q$,'42501','Cashier report requires explicit own shift');
select test.expect_error($q$select public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09','d6040000-0000-4000-8000-000000000001')$q$,'42501','Cashier cannot choose another actor shift');
select test.assert(test.r6_currency(public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09','d6040000-0000-4000-8000-000000000002'),'PHP') @> '{"sale_count":1,"sales_total_minor":300,"reversal_total_minor":100,"net_sales_minor":200}','Cashier own-shift report includes only own posted sales and reversal activity');
select test.expect_error($q$select public.get_inventory_report(test.id('r6_org'),test.id('r6_branch'))$q$,'42501','Cashier cannot obtain operational inventory report');
select test.expect_error($q$select public.get_expense_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')$q$,'42501','Cashier cannot obtain expense report');
select set_config('request.jwt.claim.sub','d6000000-0000-4000-8000-000000000004',true);
select test.assert((public.get_inventory_report(test.id('r6_org'),test.id('r6_branch'))->>'catalog_product_count')::int=5,'Inventory Staff may report assigned-branch current stock');
select test.expect_error($q$select public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')$q$,'42501','Inventory Staff cannot report financial sales');
select test.expect_error($q$select public.get_expense_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')$q$,'42501','Inventory Staff cannot report expenses');
select set_config('request.jwt.claim.sub','d6000000-0000-4000-8000-000000000002',true);
select test.assert(jsonb_array_length(public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')->'currencies')=2,'Assigned Manager can report branch sales');
select test.assert(jsonb_array_length(public.get_expense_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')->'currencies')=2,'Assigned Manager can report branch expenses');
select test.expect_error($q$select public.get_inventory_report(test.id('r6_org'),'d6010000-0000-4000-8000-000000000002')$q$,'42501','Assigned Manager report cannot reach unassigned branch');
select set_config('request.jwt.claim.sub','d6000000-0000-4000-8000-000000000005',true);
select test.assert(jsonb_array_length(public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')->'currencies')=2,'Scoped Admin can report only assigned branch');
select test.expect_error($q$select public.get_expense_report(test.id('r6_org'),'d6010000-0000-4000-8000-000000000002','2025-01-01','2025-01-09')$q$,'42501','Scoped Admin cannot promote report to another branch');
reset role;
select set_config('request.jwt.claim.sub','d6000000-0000-4000-8000-000000000001',true);
update auth.users set email_confirmed_at=null where id='d6000000-0000-4000-8000-000000000001';
set local role authenticated;
select test.expect_error($q$select public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')$q$,'42501','Fresh unverified Auth identity cannot report sales');
select test.expect_error($q$select public.get_inventory_report(test.id('r6_org'),test.id('r6_branch'))$q$,'42501','Fresh unverified Auth identity cannot report inventory');
reset role;
update auth.users set email_confirmed_at=clock_timestamp() where id='d6000000-0000-4000-8000-000000000001';
update public.branches set active=false where id=test.id('r6_branch');
set local role authenticated;
select test.expect_error($q$select public.get_expense_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')$q$,'42501','Fresh inactive branch cannot report expenses');
reset role;
update public.branches set active=true where id=test.id('r6_branch');
select set_config('test.r6_foreign_org',id::text,true) from public.organizations where owner_user_id='00000000-0000-4000-8000-000000000001';
select set_config('test.r6_foreign_branch',id::text,true) from public.branches where organization_id=test.id('r6_foreign_org') and code='MAIN';
set local role authenticated;
select test.expect_error($q$select public.get_sales_report(test.id('r6_foreign_org'),test.id('r6_foreign_branch'),'2025-01-01','2025-01-09')$q$,'42501','Verified report owner cannot read another tenant sales');
reset role;
select set_config('request.jwt.claim.sub','d6000000-0000-4000-8000-000000000002',true);
update public.organization_memberships set status='disabled' where organization_id=test.id('r6_org') and user_id='d6000000-0000-4000-8000-000000000002';
set local role authenticated;
select test.expect_error($q$select public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')$q$,'42501','Reports check freshly disabled membership');
reset role;
update public.organization_memberships set status='active' where organization_id=test.id('r6_org') and user_id='d6000000-0000-4000-8000-000000000002';
delete from public.membership_branches where organization_id=test.id('r6_org') and membership_id='d6020000-0000-4000-8000-000000000002';
set local role authenticated;
select test.expect_error($q$select public.get_expense_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')$q$,'42501','Reports check freshly removed branch assignment');
reset role;
insert into private.security_policies(organization_id,require_privileged_mfa) values(test.id('r6_org'),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','d6000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"d6000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select test.expect_error($q$select public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')$q$,'42501','Configured privileged MFA blocks AAL1 sales report');
select test.expect_error($q$select public.get_inventory_report(test.id('r6_org'),test.id('r6_branch'))$q$,'42501','Configured privileged MFA blocks AAL1 inventory report');
select test.expect_error($q$select public.get_expense_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')$q$,'42501','Configured privileged MFA blocks AAL1 expense report');
select set_config('request.jwt.claims','{"sub":"d6000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
select test.assert(jsonb_array_length(public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')->'currencies')=2,'Verified AAL2 privileged report remains authorized');
reset role;
-- Aggregate overflow is constructed from valid individually bounded records.
-- A 366-day half-open window starting at noon can touch 367 UTC dates.
insert into public.sales(id,organization_id,branch_id,shift_id,actor_user_id,receipt_sequence,receipt_number,currency,business_snapshot,settings_revision,subtotal_minor,discount_minor,tax_bps,tax_minor,total_minor,created_at)
select ('d6130000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,test.id('r6_org'),test.id('r6_branch'),'d6040000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000001',20+n,'DAILY-'||n,'PHP','{}',1,1,0,0,0,1,
 case when n=366 then '2024-01-02T11:59:59.999999Z'::timestamptz else '2023-01-01T12:00:00Z'::timestamptz+n*interval '1 day' end from generate_series(0,366) n;
insert into public.expenses(organization_id,branch_id,actor_user_id,created_at,occurred_at,currency,settings_revision,amount_minor,category,payment_method,manual_confirmed,source,reason)
select test.id('r6_org'),test.id('r6_branch'),'d6000000-0000-4000-8000-000000000001',activity_time,activity_time,'PHP',1,1,'other','cash',true,'external','Bounded window touching every UTC date'
from (select case when n=366 then '2024-01-02T11:59:59.999999Z'::timestamptz else '2023-01-01T12:00:00Z'::timestamptz+n*interval '1 day' end activity_time from generate_series(0,366) n) dates;
set local role authenticated;
select test.assert(jsonb_array_length(test.r6_currency(public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2023-01-01T12:00:00Z','2024-01-02T12:00:00Z'),'PHP')->'daily')=367,'A valid 366-day sales window retains all 367 touched UTC dates');
select test.assert(jsonb_array_length(test.r6_currency(public.get_expense_report(test.id('r6_org'),test.id('r6_branch'),'2023-01-01T12:00:00Z','2024-01-02T12:00:00Z'),'PHP')->'daily')=367,'A valid 366-day expense window retains all 367 touched UTC dates');
reset role;
insert into public.sales(id,organization_id,branch_id,shift_id,actor_user_id,receipt_sequence,receipt_number,currency,business_snapshot,settings_revision,subtotal_minor,discount_minor,tax_bps,tax_minor,total_minor,created_at)
select ('d6120000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,test.id('r6_org'),test.id('r6_branch'),'d6040000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000001',10+n,'OVERFLOW-'||n,'PHP','{}',1,
 case n when 1 then 9007199254740991 else 1 end,0,0,0,case n when 1 then 9007199254740991 else 1 end,'2025-01-10' from generate_series(1,2) n;
insert into public.expenses(organization_id,branch_id,actor_user_id,created_at,occurred_at,currency,settings_revision,amount_minor,category,payment_method,manual_confirmed,source,reason)
select test.id('r6_org'),test.id('r6_branch'),'d6000000-0000-4000-8000-000000000001','2025-01-10','2025-01-10','PHP',1,case n when 1 then 9007199254740991 else 1 end,'other','cash',true,'external','Exact individual but overflowing aggregate fixture' from generate_series(1,2) n;
set local role authenticated;
select test.expect_error($q$select public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-10','2025-01-11')$q$,'NX003','Sales aggregate above safe JSON integer fails instead of rounding');
select test.expect_error($q$select public.get_expense_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-10','2025-01-11')$q$,'NX003','Expense aggregate above safe JSON integer fails instead of rounding');
set local role anon;
select test.expect_error($q$select public.get_sales_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')$q$,'42501','Anonymous sales reporting execution is denied');
select test.expect_error($q$select public.get_inventory_report(test.id('r6_org'),test.id('r6_branch'))$q$,'42501','Anonymous inventory reporting execution is denied');
select test.expect_error($q$select public.get_expense_report(test.id('r6_org'),test.id('r6_branch'),'2025-01-01','2025-01-09')$q$,'42501','Anonymous expense reporting execution is denied');
reset role;
select test.assert(not has_function_privilege('service_role','public.get_sales_report(uuid,uuid,timestamptz,timestamptz,uuid)','EXECUTE'),'Service bearer cannot impersonate actor sales report');
select test.assert(not has_function_privilege('authenticated','private.phase6_report_integer(numeric)','EXECUTE'),'Report numeric helper is not a client execution surface');
select test.assert((select bool_and(prosecdef and proconfig @> array['search_path=""']) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('get_sales_report','get_inventory_report','get_expense_report')),'Report RPC definers fix empty search path');
rollback;
