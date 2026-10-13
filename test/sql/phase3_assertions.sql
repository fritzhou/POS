\set ON_ERROR_STOP on
-- Disposable test fixtures only. These records never enter the Flutter product.
begin;
select set_config('test.org_a',id::text,true) from public.organizations where owner_user_id='00000000-0000-4000-8000-000000000001';
select set_config('test.org_b',id::text,true) from public.organizations where owner_user_id='00000000-0000-4000-8000-000000000002';
select set_config('test.branch_a',id::text,true) from public.branches where organization_id=test.id('org_a') and code='MAIN';
select set_config('test.branch_b',id::text,true) from public.branches where organization_id=test.id('org_b') and code='MAIN';
select set_config('request.jwt.claim.sub','',true);
insert into public.products(id,organization_id,sku,barcode,name,cost_minor,price_minor) values
 ('91000000-0000-4000-8000-000000000001',test.id('org_a'),'P3-333','P3-EXACT-333','Phase3 first',100,333),
 ('91000000-0000-4000-8000-000000000002',test.id('org_a'),'P3-667','P3-EXACT-667','Phase3 second',200,667),
 ('91000000-0000-4000-8000-000000000003',test.id('org_a'),'P3-999','P3-EXACT-999','Phase3 third',300,999),
 ('91000000-0000-4000-8000-000000000004',test.id('org_a'),'P3-ROUND','P3-ROUND','Phase3 rounding',0,2),
 ('91000000-0000-4000-8000-000000000005',test.id('org_a'),'P3-ZERO','P3-ZERO','Phase3 zero',0,0),
 ('91000000-0000-4000-8000-000000000006',test.id('org_a'),'P3-HUGE-A','P3-HUGE-A','Phase3 huge A',0,4503599627370496),
 ('91000000-0000-4000-8000-000000000007',test.id('org_a'),'P3-HUGE-B','P3-HUGE-B','Phase3 huge B',0,4503599627370495);
create function test.p3_item(p_n integer,p_qty bigint default 1) returns jsonb language sql as $$
 select jsonb_build_object('product_id',('91000000-0000-4000-8000-'||lpad(p_n::text,12,'0'))::uuid,'quantity',p_qty,'expected_revision',1);
$$;
create function test.p3_checkout(p_request uuid,p_shift uuid,p_items jsonb,p_total bigint,p_discount bigint default 0,p_reason text default null,p_revision bigint default null)
returns jsonb language sql as $$
 select public.checkout_sale(test.id('org_a'),test.id('branch_a'),p_request,jsonb_build_object('shift_id',p_shift,
 'expected_settings_revision',coalesce(p_revision,(public.get_pos_context(test.id('org_a'),test.id('branch_a'))->>'settings_revision')::bigint),
 'items',p_items,'discount_minor',p_discount,'reason',p_reason,'payments',jsonb_build_array(jsonb_build_object('method','cash','amount_minor',p_total,'tendered_minor',p_total+134))));
$$;
create function test.p3_refund(p_sale uuid,p_shift uuid,p_request uuid,p_qty bigint,p_amount bigint,p_return boolean default true,p_kind text default 'refund')
returns jsonb language sql as $$
 select public.reverse_sale(test.id('org_a'),p_sale,p_request,jsonb_build_object('kind',p_kind,'shift_id',p_shift,'return_stock',p_return,'reason','Confirmed manual refund evidence',
 'items',jsonb_build_array(jsonb_build_object('sale_item_id',public.get_sale(test.id('org_a'),p_sale)->'items'->0->>'id','quantity',p_qty)),
 'payments',case when p_amount=0 then '[]'::jsonb else jsonb_build_array(jsonb_build_object('original_payment_id',public.get_sale(test.id('org_a'),p_sale)->'payments'->0->>'id','amount_minor',p_amount,'manual_confirmed',true)) end));
$$;
grant execute on function test.p3_item(integer,bigint),test.p3_checkout(uuid,uuid,jsonb,bigint,bigint,text,bigint),test.p3_refund(uuid,uuid,uuid,bigint,bigint,boolean,text) to authenticated;
set local role anon;
select test.expect_error('select public.get_pos_context(test.id(''org_a''),test.id(''branch_a''))','42501','Anonymous cannot obtain POS context');
select test.expect_error('select * from public.sales','42501','Anonymous cannot inspect sales');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select test.expect_error('select public.open_shift(test.id(''org_a''),test.id(''branch_a''),gen_random_uuid(),1000,''USD'')','40001','Opening cash rejects changed currency context');
select set_config('test.p3_owner_shift',(public.open_shift(test.id('org_a'),test.id('branch_a'),'92000000-0000-4000-8000-000000000001',10000,'PHP')->>'id'),true);
select test.assert((public.open_shift(test.id('org_a'),test.id('branch_a'),'92000000-0000-4000-8000-000000000001',10000,'PHP')->>'id')::uuid=test.id('p3_owner_shift'),'Open shift stable UUID retry returns actual shift');
select test.expect_error('select public.open_shift(test.id(''org_a''),test.id(''branch_a''),''92000000-0000-4000-8000-000000000001'',20000,''PHP'')','23505','Opening UUID cannot be reused with another amount');
select test.expect_error('select public.open_shift(test.id(''org_a''),''20000000-0000-4000-8000-000000000002'',gen_random_uuid(),0,''PHP'')','23505','One actor cannot open a second concurrent branch shift');
select test.assert((public.get_current_shift(test.id('org_a'),test.id('branch_a'))->>'expected_cash_minor')::bigint=10000,'Opening drawer expected amount is exact');
select test.expect_error('select public.get_pos_context(test.id(''org_b''),test.id(''branch_b''))','42501','POS context refuses another organization');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000006',true);
select test.expect_error('select public.open_shift(test.id(''org_a''),test.id(''branch_a''),gen_random_uuid(),0,''PHP'')','42501','Inventory Staff cannot open a cashier shift');
select set_config('test.p3_receive',(public.receive_stock(test.id('org_a'),test.id('branch_a'),'92000000-0000-4000-8000-000000000002',
 jsonb_build_array(test.p3_item(1,20),test.p3_item(2,20),test.p3_item(3,20),test.p3_item(4,20),test.p3_item(5,20),test.p3_item(6,20),test.p3_item(7,20)),null,'Receipt fixture','Received counted physical units')->>'id'),true);
select test.assert((public.receive_stock(test.id('org_a'),test.id('branch_a'),'92000000-0000-4000-8000-000000000002',
 jsonb_build_array(test.p3_item(1,20),test.p3_item(2,20),test.p3_item(3,20),test.p3_item(4,20),test.p3_item(5,20),test.p3_item(6,20),test.p3_item(7,20)),null,'Receipt fixture','Received counted physical units')->>'id')::uuid=test.id('p3_receive'),'Receiving lost-response retry appends once');
select test.assert((select count(*) from public.stock_movements where operation_id=test.id('p3_receive'))=7,'Stock receipt appends one movement per sorted product');
select test.assert((public.list_inventory(test.id('org_a'),test.id('branch_a'),'P3-333')->0->>'available_quantity')::bigint=20,'Inventory reports ledger-backed branch quantity');
select test.expect_error('select public.adjust_stock(test.id(''org_a''),test.id(''branch_a''),gen_random_uuid(),''91000000-0000-4000-8000-000000000001'',1,''Denied employee adjustment'')','42501','Inventory Staff receives but cannot perform manager adjustment');
select test.expect_error('select public.list_sales(test.id(''org_a''))','42501','Inventory Staff cannot read sale/payment records');
select test.assert(exists(select 1 from public.audit_logs where entity_id=test.id('p3_receive')),'Inventory Staff can read its authorized branch receipt audit');
select test.expect_error('select public.receive_stock(test.id(''org_a''),''20000000-0000-4000-8000-000000000002'',gen_random_uuid(),jsonb_build_array(test.p3_item(1)),null,null,''Unauthorized branch receipt'')','42501','Receiving verifies active assigned branch');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('test.p3_owner_sale',(test.p3_checkout('92000000-0000-4000-8000-000000000003',test.id('p3_owner_shift'),jsonb_build_array(test.p3_item(3),test.p3_item(1),test.p3_item(2)),1866,333,'Authorized discounted fixture')->>'id'),true);
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_owner_sale'))->>'subtotal_minor')::bigint=1999,'Server uses immutable current-price subtotal');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_owner_sale'))->>'tax_minor')::bigint=200,'Golden tax is rounded half-up on each discounted line');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_owner_sale'))->>'total_minor')::bigint=1866,'Golden receipt total exactly matches Dart contract');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_owner_sale'))->'items'->0->>'discount_minor')::bigint=55,'First sorted proportional discount is 55');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_owner_sale'))->'items'->1->>'discount_minor')::bigint=111,'Second sorted proportional discount is 111');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_owner_sale'))->'items'->2->>'discount_minor')::bigint=167,'Last proportional discount exactly releases remainder');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_owner_sale'))->>'receipt_number')='MAIN-000001','Receipt sequence is assigned only on accepted transaction');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_owner_sale'))->'payments'->0->>'change_minor')::bigint=134,'Cash change is tender less applied amount');
select test.assert((public.get_current_shift(test.id('org_a'),test.id('branch_a'))->>'expected_cash_minor')::bigint=11866,'Shift cash adds applied amount rather than tender/change');
select test.assert((test.p3_checkout('92000000-0000-4000-8000-000000000003',test.id('p3_owner_shift'),jsonb_build_array(test.p3_item(3),test.p3_item(1),test.p3_item(2)),1866,333,'Authorized discounted fixture')->>'id')::uuid=test.id('p3_owner_sale'),'Checkout retry returns same accepted receipt');
select test.assert((public.get_sale_by_request(test.id('org_a'),test.id('branch_a'),'92000000-0000-4000-8000-000000000003')->>'id')::uuid=test.id('p3_owner_sale'),'Lost-response inquiry resolves actor request to accepted sale');
select test.expect_error($q$select test.p3_checkout('92000000-0000-4000-8000-000000000003',test.id('p3_owner_shift'),jsonb_build_array(test.p3_item(1)),373)$q$,'23505','Checkout request UUID binds the original complete payload');
select test.expect_error($q$select test.p3_checkout(gen_random_uuid(),test.id('p3_owner_shift'),jsonb_build_array(test.p3_item(1,1000)),372960)$q$,'23514','Checkout cannot consume unavailable stock');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_owner_sale'))->>'receipt_number')='MAIN-000001','Failed insufficient stock cannot advance a receipt counter');
select test.expect_error($q$select test.p3_checkout(gen_random_uuid(),test.id('p3_owner_shift'),jsonb_build_array(test.p3_item(1),test.p3_item(1)),746)$q$,'22023','Checkout rejects duplicate product lines');
select test.expect_error($q$select test.p3_checkout(gen_random_uuid(),test.id('p3_owner_shift'),jsonb_build_array(test.p3_item(5)),1)$q$,'22023','Zero-total checkout is explicitly unsupported');
select test.expect_error($q$select test.p3_checkout(gen_random_uuid(),test.id('p3_owner_shift'),jsonb_build_array(test.p3_item(1)),372)$q$,'22023','Client payment mismatch cannot override server total');
select test.expect_error($q$select test.p3_checkout(gen_random_uuid(),test.id('p3_owner_shift'),jsonb_build_array(test.p3_item(1)),373,0,null,1)$q$,'40001','Checkout rejects stale settings revision');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000005',true);
select test.assert((public.get_pos_context(test.id('org_a'),test.id('branch_a'))->>'tax_bps')::int=1200,'Cashier receives safe actual POS tax/currency context');
select test.assert((public.list_pos_products(test.id('org_a'),test.id('branch_a'),'P3-333')->0->'cost_minor')='null'::jsonb,'Cashier stock-backed browse hides cost');
select test.assert(public.lookup_pos_product_by_barcode(test.id('org_a'),test.id('branch_a'),'P3-EXACT') is null,'Barcode lookup uses equality instead of substring matching');
select test.assert((public.lookup_pos_product_by_barcode(test.id('org_a'),test.id('branch_a'),'P3-EXACT-333')->>'id')='91000000-0000-4000-8000-000000000001','Exact keyboard/scanner barcode resolves the actual product');
select test.assert((public.lookup_pos_product_by_barcode(test.id('org_a'),test.id('branch_a'),'P3-EXACT-333')->'cost_minor')='null'::jsonb,'Exact barcode lookup also masks Cashier cost');
select test.expect_error('select * from private.sale_cost_snapshots','42501','Cashier cannot query immutable private cost snapshots');
select test.expect_error('select * from private.stock_balances','42501','Client cannot read private mutable stock projection');
select test.expect_error('select * from private.operation_requests','42501','Client cannot inspect another actor idempotency payload');
select test.expect_error('select * from private.inventory_cost_evidence','42501','Inventory cost evidence is not an exposed payment field');
select test.expect_error('select public.get_sale(test.id(''org_a''),test.id(''p3_owner_sale''))','42501','Cashier cannot read another cashier or owner sale');
select test.assert((select count(*) from public.sales)=0,'Direct sales RLS enforces Cashier own history');
select test.expect_error('select public.list_stock_movements(test.id(''org_a''),test.id(''branch_a''))','42501','Cashier cannot inspect operational inventory ledger');
select set_config('test.p3_cashier_shift',(public.open_shift(test.id('org_a'),test.id('branch_a'),'92000000-0000-4000-8000-000000000004',5000,'PHP')->>'id'),true);
select test.expect_error($q$select test.p3_checkout(gen_random_uuid(),test.id('p3_cashier_shift'),jsonb_build_array(test.p3_item(1)),372,1,'Cashier forged manager discount')$q$,'42501','Cashier cannot forge discount authority in payload');
select test.expect_error('select public.close_shift(test.id(''org_a''),test.id(''p3_owner_shift''),gen_random_uuid(),11866,''Cashier closes someone else'')','42501','Cashier cannot close another employee shift');
select test.expect_error($q$select public.checkout_sale(test.id('org_a'),test.id('branch_a'),gen_random_uuid(),jsonb_build_object('shift_id',test.id('p3_cashier_shift'),'expected_settings_revision',2,'items',jsonb_build_array(test.p3_item(1)),'discount_minor',0,'payments',jsonb_build_array(jsonb_build_object('method','gcash','amount_minor',373,'reference','Manual-001','manual_confirmed',false))))$q$,'22023','Unconfirmed digital evidence cannot pretend provider authorization');
select set_config('test.p3_cashier_sale',(public.checkout_sale(test.id('org_a'),test.id('branch_a'),'92000000-0000-4000-8000-000000000005',jsonb_build_object('shift_id',test.id('p3_cashier_shift'),'expected_settings_revision',2,'items',jsonb_build_array(test.p3_item(1)),'discount_minor',0,'payments',jsonb_build_array(
 jsonb_build_object('method','cash','amount_minor',173,'tendered_minor',200),jsonb_build_object('method','gcash','amount_minor',200,'reference','Manual-001','manual_confirmed',true))))->>'id'),true);
select test.assert((public.get_current_shift(test.id('org_a'),test.id('branch_a'))->>'expected_cash_minor')::bigint=5173,'Manual digital payment does not increase cash drawer');
select test.assert(jsonb_array_length(public.list_sales(test.id('org_a')))=1,'Cashier bounded history includes only own confirmed sale');
select test.assert((select count(*) from public.sale_items)=1,'Direct child RLS also hides other actor sales');
select test.expect_error('update public.sales set total_minor=1','42501','Client cannot edit original accepted sale');
select test.expect_error('delete from public.sale_items','42501','Client cannot delete accepted line items');
select test.expect_error('insert into public.sale_payments(organization_id,sale_id,method,amount_minor) values(test.id(''org_a''),test.id(''p3_cashier_sale''),''cash'',1)','42501','Client cannot append invented payment to original sale');
select test.expect_error('select test.p3_refund(test.id(''p3_cashier_sale''),test.id(''p3_cashier_shift''),gen_random_uuid(),1,373)','42501','Cashier cannot approve own refund');
select test.expect_error('select public.receive_stock(test.id(''org_a''),test.id(''branch_a''),gen_random_uuid(),jsonb_build_array(test.p3_item(1)),null,null,''Cashier restock attempt'')','42501','Cashier cannot manufacture stock');
select test.expect_error('select public.get_current_shift(test.id(''org_a''),''20000000-0000-4000-8000-000000000002'')','42501','Cashier cannot query another unassigned branch shift');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
select set_config('test.p3_manager_shift',(public.open_shift(test.id('org_a'),test.id('branch_a'),'92000000-0000-4000-8000-000000000006',10000,'PHP')->>'id'),true);
select test.assert(jsonb_array_length(public.list_sales(test.id('org_a')))=2,'Manager reads authorized branch employee sales');
select test.assert(exists(select 1 from public.audit_logs where entity_id=test.id('p3_cashier_sale') and action='sale.accepted'),'Manager sees branch financial operational audit');
select test.assert(jsonb_array_length(public.list_stock_movements(test.id('org_a'),test.id('branch_a')))=11,'Manager ledger sees actual receive and sale movements');
select test.expect_error('select public.adjust_stock(test.id(''org_a''),test.id(''branch_a''),gen_random_uuid(),''91000000-0000-4000-8000-000000000001'',-999,''Counted shortage too large'')','23514','Adjustment cannot create negative inventory');
select test.expect_error('select public.adjust_stock(test.id(''org_a''),test.id(''branch_a''),gen_random_uuid(),''91000000-0000-4000-8000-000000000001'',1,'' '')','22023','Adjustment requires a meaningful reason');
select set_config('test.p3_adjust',(public.adjust_stock(test.id('org_a'),test.id('branch_a'),'92000000-0000-4000-8000-000000000007','91000000-0000-4000-8000-000000000001',2,'Counted actual excess units')->>'id'),true);
select test.assert((public.adjust_stock(test.id('org_a'),test.id('branch_a'),'92000000-0000-4000-8000-000000000007','91000000-0000-4000-8000-000000000001',2,'Counted actual excess units')->>'id')::uuid=test.id('p3_adjust'),'Adjustment stable retry returns one actual adjustment');
select test.assert((public.list_inventory(test.id('org_a'),test.id('branch_a'),'P3-333')->0->>'available_quantity')::bigint=20,'Adjustment changes balance only through signed ledger');
select set_config('test.p3_round_sale',(test.p3_checkout('92000000-0000-4000-8000-000000000008',test.id('p3_manager_shift'),jsonb_build_array(test.p3_item(4,3)),7)->>'id'),true);
select set_config('test.p3_refund_first',(test.p3_refund(test.id('p3_round_sale'),test.id('p3_manager_shift'),'92000000-0000-4000-8000-000000000009',1,2,false)->>'id'),true);
select test.assert((public.list_inventory(test.id('org_a'),test.id('branch_a'),'P3-ROUND')->0->>'available_quantity')::bigint=17,'Money-only refund does not invent a physical stock return');
select test.assert((test.p3_refund(test.id('p3_round_sale'),test.id('p3_manager_shift'),'92000000-0000-4000-8000-000000000009',1,2,false)->>'id')::uuid=test.id('p3_refund_first'),'Reversal retry never pays a second time');
select test.assert((test.p3_refund(test.id('p3_round_sale'),test.id('p3_manager_shift'),'92000000-0000-4000-8000-000000000010',1,2,true)->>'total_minor')::bigint=2,'Second partial unit receives cumulative original minor amount');
select test.assert((test.p3_refund(test.id('p3_round_sale'),test.id('p3_manager_shift'),'92000000-0000-4000-8000-000000000011',1,3,true)->>'total_minor')::bigint=3,'Final partial refund releases exact rounding cent');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_round_sale'))->>'reversed_minor')::bigint=7,'Cumulative refunds exactly equal original immutable total');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_round_sale'))->'items'->0->>'remaining_quantity')::bigint=0,'Remaining refundable unit quantity is bounded from immutable children');
select test.assert((public.list_inventory(test.id('org_a'),test.id('branch_a'),'P3-ROUND')->0->>'available_quantity')::bigint=19,'Only two explicitly physically returned units restore inventory');
select test.expect_error('select test.p3_refund(test.id(''p3_round_sale''),test.id(''p3_manager_shift''),gen_random_uuid(),1,2)','23514','Refund cannot exceed remaining original units');
select test.expect_error('select test.p3_refund(test.id(''p3_round_sale''),test.id(''p3_manager_shift''),gen_random_uuid(),3,7,true,''void'')','23514','Void cannot follow a partial or complete refund');
select set_config('test.p3_void_sale',(test.p3_checkout('92000000-0000-4000-8000-000000000012',test.id('p3_manager_shift'),jsonb_build_array(test.p3_item(2)),747)->>'id'),true);
select test.assert((test.p3_refund(test.id('p3_void_sale'),test.id('p3_manager_shift'),'92000000-0000-4000-8000-000000000013',1,747,true,'void')->>'kind')='void','Void appends distinct full compensating operation');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_void_sale'))->>'total_minor')::bigint=747,'Original total remains unchanged after void');
select test.expect_error('select test.p3_refund(test.id(''p3_void_sale''),test.id(''p3_manager_shift''),gen_random_uuid(),1,747,true,''void'')','23514','An already voided sale cannot be voided again');
select test.expect_error($q$select public.reverse_sale(test.id('org_a'),test.id('p3_cashier_sale'),gen_random_uuid(),jsonb_build_object('kind','refund','shift_id',test.id('p3_manager_shift'),'reason','Missing physical return choice','items',jsonb_build_array(jsonb_build_object('sale_item_id',public.get_sale(test.id('org_a'),test.id('p3_cashier_sale'))->'items'->0->>'id','quantity',1)),'payments','[]'::jsonb))$q$,'22023','Reversal never silently assumes stock physically returned');

-- Maximum exact-platform integer fixture proves NUMERIC div avoids premature
-- division rounding. Regular '/' produced total 4 here instead of exact 3.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.save_business_settings(test.id('org_a'),2,'{"tax_bps":5000}','Golden high precision tax fixture');
select set_config('test.p3_huge_sale',(test.p3_checkout('92000000-0000-4000-8000-000000000014',test.id('p3_owner_shift'),jsonb_build_array(test.p3_item(6),test.p3_item(7)),3,9007199254740989,'Golden exact proportional integer fixture')->>'id'),true);
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_huge_sale'))->'items'->0->>'discount_minor')::bigint=4503599627370494,'Huge cumulative discount uses exact integer division');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_huge_sale'))->>'tax_minor')::bigint=1,'Huge ratio does not create an extra rounded tax cent');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_huge_sale'))->>'total_minor')::bigint=3,'Maximum exact-integer golden receipt matches client');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_owner_sale'))->>'tax_bps')::int=1200,'Historical receipt keeps original tax snapshot after settings change');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_owner_sale'))->>'settings_revision')::int=2,'Historical receipt preserves original settings revision');
select public.save_business_settings(test.id('org_a'),3,'{"tax_bps":1200}','Restore POS fixture settings');
select test.expect_error($q$select test.p3_checkout(gen_random_uuid(),test.id('p3_owner_shift'),jsonb_build_array(test.p3_item(1)||'{"quantity":1.5}'),560)$q$,'22023','Fractional sale quantities are explicitly rejected');
select test.expect_error($q$select public.receive_stock(test.id('org_a'),test.id('branch_a'),gen_random_uuid(),jsonb_build_array(test.p3_item(1)||'{"quantity":1000001}'),null,null,'Beyond unit cap')$q$,'22023','Receiving has the same whole-unit transaction cap');
select test.expect_error($q$select test.p3_checkout(gen_random_uuid(),test.id('p3_owner_shift'),jsonb_build_array(test.p3_item(1)||'{"expected_revision":2}'),373)$q$,'40001','Stale product revision cannot change agreed price');
select public.save_product(test.id('org_a'),'91000000-0000-4000-8000-000000000001',1,'{"active":false}','Inactive product with physical stock');
select test.assert(public.lookup_pos_product_by_barcode(test.id('org_a'),test.id('branch_a'),'P3-EXACT-333') is null,'Inactive product cannot enter POS through scanner');
select test.assert((public.list_inventory(test.id('org_a'),test.id('branch_a'),'P3-333')->0->>'available_quantity')::bigint=20,'Inactive products with stock remain visible in inventory');
select test.assert((public.get_sale(test.id('org_a'),test.id('p3_owner_sale'))->'items'->0->>'unit_price_minor')::bigint=333,'Accepted product price snapshot remains unchanged');
select public.save_product(test.id('org_a'),'91000000-0000-4000-8000-000000000001',2,'{"active":true}','Restore active POS product');
select test.expect_error('select public.adjust_stock(test.id(''org_a''),test.id(''branch_a''),gen_random_uuid(),''50000000-0000-4000-8000-000000000002'',1,''Foreign product stock'')','P0002','Ledger adjustment refuses foreign tenant product');
-- Closed-shift lost-response retry returns the same sale under CURRENT authority.
select set_config('test.p3_original_payload',jsonb_build_object('shift_id',test.id('p3_owner_shift'),'expected_settings_revision',2,'items',jsonb_build_array(test.p3_item(3),test.p3_item(1),test.p3_item(2)),
 'discount_minor',333,'reason','Authorized discounted fixture','payments',jsonb_build_array(jsonb_build_object('method','cash','amount_minor',1866,'tendered_minor',2000)))::text,true);
select test.assert((public.close_shift(test.id('org_a'),test.id('p3_owner_shift'),'92000000-0000-4000-8000-000000000015',11869,'Counted physical drawer closure')->'closure'->>'difference_minor')::bigint=0,'Closing snapshot includes accepted cash and no tender overstatement');
select test.assert((public.close_shift(test.id('org_a'),test.id('p3_owner_shift'),'92000000-0000-4000-8000-000000000015',11869,'Counted physical drawer closure')->>'closing_request_id')='92000000-0000-4000-8000-000000000015','Closing mutation returns its own request identity');
select test.assert(public.get_current_shift(test.id('org_a'),test.id('branch_a')) is null,'Closed shift is absent from current open shift');
select test.assert((public.checkout_sale(test.id('org_a'),test.id('branch_a'),'92000000-0000-4000-8000-000000000003',current_setting('test.p3_original_payload')::jsonb)->>'id')::uuid=test.id('p3_owner_sale'),'Same checkout UUID retry succeeds after shift close/product/settings changes');
select test.expect_error($q$select public.checkout_sale(test.id('org_a'),test.id('branch_a'),gen_random_uuid(),current_setting('test.p3_original_payload')::jsonb)$q$,'40001','New request cannot submit a closed-shift checkout');
select test.assert((select count(*) from public.sales where shift_id=test.id('p3_owner_shift'))=2,'Lost-response retry creates no duplicate sale after closure');
select test.assert((select count(*) from public.stock_movements where sale_id=test.id('p3_owner_sale'))=3,'Lost-response retry creates no duplicate stock movement');
select test.assert((select count(*) from public.audit_logs where action='sale.accepted' and entity_id=test.id('p3_owner_sale'))=1,'Lost-response retry creates no duplicate acceptance audit');
reset role;
select test.expect_error('update public.sales set discount_reason=''Edited history''','42501','Trusted ordinary SQL updates still hit immutable sale trigger');
select test.expect_error('delete from public.stock_movements','42501','Ledger deletion is blocked even for ordinary owner SQL');
select test.expect_error('truncate public.sale_reversal_items','42501','Financial history cannot be truncated accidentally');
select test.expect_error('update public.shift_closures set counted_cash_minor=0','42501','Shift closure cannot be edited to hide a discrepancy');
select test.expect_error('update private.operation_requests set payload=''{}''','42501','Idempotency accepted payload is immutable');
select test.expect_error('update private.sale_cost_snapshots set cost_minor=0','42501','Private original cost snapshots are immutable');
select test.assert((select quantity from private.stock_balances where organization_id=test.id('org_a') and branch_id=test.id('branch_a') and product_id='91000000-0000-4000-8000-000000000001')=
 (select sum(quantity_delta) from public.stock_movements where organization_id=test.id('org_a') and branch_id=test.id('branch_a') and product_id='91000000-0000-4000-8000-000000000001'),'Projection quantity exactly equals signed immutable movement sum');

-- Acceptance rollback covers receipt sequence, ledger, request and payment.
create function test.reject_p3_audit() returns trigger language plpgsql as $$
begin if new.reason='Deliberate phase three audit failure' then raise exception 'Deliberate audit failure' using errcode='23514'; end if;return new;end; $$;
create trigger test_p3_audit_failure before insert on public.audit_logs for each row execute function test.reject_p3_audit();
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
select set_config('test.p3_before_sale_count',(select count(*)::text from public.sales),true);
select test.expect_error($q$select test.p3_checkout('92000000-0000-4000-8000-000000000016',test.id('p3_manager_shift'),jsonb_build_array(test.p3_item(2)),747,0,'Deliberate phase three audit failure')$q$,'23514','Financial audit failure propagates instead of acknowledging sale');
select test.assert((select count(*) from public.sales)=current_setting('test.p3_before_sale_count')::int,'Audit failure rolls back accepted sale and children atomically');
select test.assert(public.get_sale_by_request(test.id('org_a'),test.id('branch_a'),'92000000-0000-4000-8000-000000000016') is null,'Audit failure leaves no accepted idempotency result');
select test.assert((test.p3_checkout('92000000-0000-4000-8000-000000000017',test.id('p3_manager_shift'),jsonb_build_array(test.p3_item(2)),747)->>'receipt_sequence')::int=6,'Audit failure does not consume a branch receipt sequence');
reset role;
drop trigger test_p3_audit_failure on public.audit_logs;drop function test.reject_p3_audit();

-- Present authorization applies to retries too, never a stale JWT claim alone.
update public.organization_memberships set status='disabled' where user_id='00000000-0000-4000-8000-000000000005' and organization_id=test.id('org_a');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000005',true);
select test.expect_error('select public.get_sale(test.id(''org_a''),test.id(''p3_cashier_sale''))','42501','Disabled cashier immediately loses accepted-sale history');
select test.expect_error('select public.get_sale_by_request(test.id(''org_a''),test.id(''branch_a''),''92000000-0000-4000-8000-000000000005'')','42501','Disabled cashier cannot bypass current authority via request inquiry');
select test.assert((select count(*) from public.sales)=0,'Disabled cashier direct financial table reads fail closed');
reset role;
update public.organization_memberships set status='active' where user_id='00000000-0000-4000-8000-000000000005' and organization_id=test.id('org_a');
update auth.users set email_confirmed_at=null where id='00000000-0000-4000-8000-000000000005';
set local role authenticated;
select test.expect_error('select public.get_current_shift(test.id(''org_a''),test.id(''branch_a''))','42501','Email verification is checked from current Auth state');
select test.assert((select count(*) from public.sales)=0,'Unverified current Auth state cannot read prior financial records');
reset role;
update auth.users set email_confirmed_at=now() where id='00000000-0000-4000-8000-000000000005';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000013',true);
select test.assert(jsonb_array_length(public.list_sales(test.id('org_a')))=0,'Another branch cashier sees no foreign branch sale history');
select test.expect_error('select public.get_sale(test.id(''org_a''),test.id(''p3_cashier_sale''))','42501','Explicit sale ID cannot cross cashier assigned branch');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select test.expect_error('select public.get_sale(test.id(''org_a''),test.id(''p3_owner_sale''))','42501','Foreign owner cannot probe sale through another business');
reset role;
select test.assert(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname like 'phase3_%' and p.proname<>'phase3_can_read' and has_function_privilege('authenticated',p.oid,'execute')),'All privileged Phase 3 internal helpers reject application calls');
select test.assert(not has_function_privilege('anon','public.checkout_sale(uuid,uuid,uuid,jsonb)','execute'),'Anonymous default checkout function grant revoked');
select test.assert(not has_function_privilege('service_role','public.checkout_sale(uuid,uuid,uuid,jsonb)','execute'),'Service key cannot impersonate an actor checkout');
select test.assert(not has_table_privilege('authenticated','public.sales','INSERT') and not has_table_privilege('authenticated','public.stock_movements','INSERT'),'Application financial and ledger direct inserts denied');
select test.assert((select bool_and(proconfig @> array['search_path=""']) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.prosecdef),'All Phase 3 security definers fix empty search_path');
select test.assert((select count(*) from public.financial_events)=1,'Online POS does not acknowledge reserved Phase 1 offline envelope');
commit;
