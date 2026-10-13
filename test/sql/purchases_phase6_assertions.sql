\set ON_ERROR_STOP on
-- Isolated fixtures; root harness provides test.assert/expect_error/id.
begin;
insert into auth.users(id,email,email_confirmed_at) select ('c6000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'purchase-p6-'||n||'@example.invalid',case when n=6 then null else now() end from generate_series(1,6) n;
set local role authenticated;
set local "request.jwt.claim.sub"='c6000000-0000-4000-8000-000000000001';
select set_config('test.purchase_org',organization_id::text,true),set_config('test.purchase_branch',branch_id::text,true) from public.bootstrap_organization('Purchase fixture shop','Purchase fixture owner');
select set_config('test.purchase_settings',(public.get_purchase_context(test.id('purchase_org'),test.id('purchase_branch'))->>'settings_revision'),true);
reset role;
set local "request.jwt.claim.sub"='';
insert into public.branches(id,organization_id,name,code) values('c6100000-0000-4000-8000-000000000002',test.id('purchase_org'),'Purchase second branch','P6SECOND');
insert into public.organization_memberships(id,organization_id,user_id,role,status,all_branches) select ('c6200000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,test.id('purchase_org'),('c6000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,case n when 2 then 'manager' when 3 then 'inventory_staff' when 4 then 'cashier' else 'admin' end,'active',false from generate_series(2,5) n;
insert into public.membership_branches(organization_id,membership_id,branch_id) select organization_id,id,test.id('purchase_branch') from public.organization_memberships where organization_id=test.id('purchase_org') and role<>'owner';
insert into public.suppliers(id,organization_id,branch_id,name) values
 ('c6300000-0000-4000-8000-000000000001',test.id('purchase_org'),null,'Original supplier'),
 ('c6300000-0000-4000-8000-000000000002',test.id('purchase_org'),'c6100000-0000-4000-8000-000000000002','Other branch supplier');
insert into public.products(id,organization_id,sku,name,cost_minor,price_minor) select ('c6400000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,test.id('purchase_org'),'P6-PURCHASE-'||n,'Original product '||n,777,1000 from generate_series(1,3) n;
create function test.purchase_item(p_number integer,p_quantity bigint default 5,p_cost bigint default 125,p_revision bigint default 1) returns jsonb language sql as $$ select jsonb_build_object('product_id',('c6400000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,'quantity',p_quantity,'unit_cost_minor',p_cost,'expected_revision',p_revision); $$;
create function test.purchase_create(p_number integer,p_items jsonb,p_supplier uuid default 'c6300000-0000-4000-8000-000000000001',p_supplier_revision bigint default 1,p_settings bigint default null,p_currency text default 'PHP') returns jsonb language sql as $$ select public.create_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),('c6500000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,p_supplier,p_supplier_revision,coalesce(p_settings,current_setting('test.purchase_settings')::bigint),p_currency,p_items,'PO manual reference','Operator submitted purchase order'); $$;
create function test.purchase_receipt_item(p_order uuid,p_number integer,p_quantity bigint,p_product_revision bigint default 1) returns jsonb language sql as $$ select jsonb_build_object('order_item_id',i.id,'quantity',p_quantity,'expected_product_revision',p_product_revision) from public.purchase_order_items i where i.order_id=p_order and i.product_id=('c6400000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid; $$;
create function test.purchase_receive(p_number integer,p_order uuid,p_revision bigint,p_items jsonb) returns jsonb language sql as $$ select public.receive_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),('c6600000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,p_order,p_revision,p_items,'Delivery manual reference','Physical units received and counted'); $$;
create function test.purchase_cancel(p_number integer,p_order uuid,p_revision bigint) returns jsonb language sql as $$ select public.cancel_purchase_order_remaining(test.id('purchase_org'),test.id('purchase_branch'),('c6700000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,p_order,p_revision,'Supplier remainder explicitly cancelled'); $$;
grant execute on function test.purchase_item(integer,bigint,bigint,bigint),test.purchase_create(integer,jsonb,uuid,bigint,bigint,text),test.purchase_receipt_item(uuid,integer,bigint,bigint),test.purchase_receive(integer,uuid,bigint,jsonb),test.purchase_cancel(integer,uuid,bigint) to authenticated;

set local role authenticated;
set local "request.jwt.claim.sub"='c6000000-0000-4000-8000-000000000001';
select test.assert((public.get_purchase_context(test.id('purchase_org'),test.id('purchase_branch'))->>'currency')='PHP','Purchase context provides authoritative organization currency');
select set_config('test.purchase_create',test.purchase_create(1,jsonb_build_array(test.purchase_item(1),test.purchase_item(2,3,0)))::text,true);
select set_config('test.purchase_order',current_setting('test.purchase_create')::jsonb->>'order_id',true);
select test.assert(current_setting('test.purchase_create')::jsonb->>'kind'='purchase.create','Creation returns immutable purchase action kind');
select test.assert((current_setting('test.purchase_create')::jsonb->'order'->>'created_by')=auth.uid()::text,'Creation actor comes from verified server session');
select test.assert((current_setting('test.purchase_create')::jsonb->'order'->>'ordered_total_minor')::bigint=625,'Purchase total uses exact quantities and recorded minor costs');
select test.assert((current_setting('test.purchase_create')::jsonb->'order'->>'revision')::bigint=1,'New order starts with revision one');
select test.assert((current_setting('test.purchase_create')::jsonb->'order'->>'status')='ordered','New order starts ordered without implied receiving');
select test.assert((current_setting('test.purchase_create')::jsonb->'order'->>'receipt_count')::bigint=0,'New order has no invented physical receipts');
select test.assert(test.purchase_create(1,jsonb_build_array(test.purchase_item(1),test.purchase_item(2,3,0)))=current_setting('test.purchase_create')::jsonb,'Creation replay returns exactly the original action');
select test.expect_error($q$select test.purchase_create(1,jsonb_build_array(test.purchase_item(1,6),test.purchase_item(2,3,0)))$q$,'23505','Purchase UUID rejects changed quantities');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1),test.purchase_item(1)))$q$,'22023','Purchase rejects duplicate product lines');
select test.expect_error($q$select test.purchase_create(2,'[]')$q$,'22023','Purchase rejects zero lines');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1)||'{"actor_user_id":"spoof"}'))$q$,'22023','Purchase rejects unsupported line fields');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1)||'{"quantity":1.5}'))$q$,'22023','Purchase rejects fractional quantities');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1)||'{"unit_cost_minor":"125"}'))$q$,'22023','Purchase rejects string money');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1)||'{"product_id":null}'))$q$,'22023','Purchase rejects missing product identifier');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1,0)))$q$,'22023','Purchase rejects zero quantity');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1,1000001)))$q$,'22023','Purchase rejects excessive quantity');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1,1,-1)))$q$,'22023','Purchase rejects negative recorded cost');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1,2,9007199254740991)))$q$,'22023','Purchase multiplication rejects safe-integer overflow before cast');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1,1,4503599627370496),test.purchase_item(2,1,4503599627370496)))$q$,'22023','Purchase aggregate rejects safe-integer overflow');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1,1,125,2)))$q$,'40001','Purchase rejects stale product revision');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1)),'c6300000-0000-4000-8000-000000000001',2)$q$,'40001','Purchase rejects stale supplier revision');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1)),'c6300000-0000-4000-8000-000000000001',1,999)$q$,'40001','Purchase rejects stale settings revision');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1)),'c6300000-0000-4000-8000-000000000001',1,null,'USD')$q$,'40001','Purchase rejects mismatched current currency');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1)),'c6300000-0000-4000-8000-000000000002')$q$,'42501','Purchase rejects supplier from another branch');
select test.expect_error($q$select test.purchase_create(2,jsonb_build_array(test.purchase_item(1)||'{"product_id":"50000000-0000-4000-8000-000000000002"}'))$q$,'42501','Purchase rejects another tenant product');
select test.expect_error($q$select public.create_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),gen_random_uuid(),'c6300000-0000-4000-8000-000000000001',1,current_setting('test.purchase_settings')::bigint,'PHP',jsonb_build_array(test.purchase_item(1)),null,'x')$q$,'22023','Purchase requires a meaningful reason');
select test.expect_error($q$select public.create_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),gen_random_uuid(),'c6300000-0000-4000-8000-000000000001',1,current_setting('test.purchase_settings')::bigint,'PHP',jsonb_build_array(test.purchase_item(1)),repeat('x',121),'Meaningful purchase reason')$q$,'22023','Purchase rejects overlong reference');
select test.assert(jsonb_array_length(public.list_purchase_orders(test.id('purchase_org'),test.id('purchase_branch')))=1,'Purchase list contains only the authoritative submitted order');
select test.assert(jsonb_array_length(public.list_purchase_orders(test.id('purchase_org'),test.id('purchase_branch'),'received'))=0,'Purchase status filter reads current state');
select test.assert(jsonb_array_length(public.list_purchase_orders(test.id('purchase_org'),test.id('purchase_branch'),null,'ORIGINAL SUPPLIER'))=1,'Purchase supplier query is case-insensitive literal search');
select test.expect_error($q$select public.list_purchase_orders(test.id('purchase_org'),test.id('purchase_branch'),'fake')$q$,'22023','Purchase list rejects unsupported status');
select test.expect_error($q$select public.list_purchase_orders(test.id('purchase_org'),test.id('purchase_branch'),null,'',0,102)$q$,'22023','Purchase list enforces bounded page');
select test.expect_error($q$select public.list_purchase_receipts(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'),-1,51)$q$,'22023','Receipt history enforces bounded offset');
select test.expect_error($q$select public.get_purchase_order(test.id('purchase_org'),'c6100000-0000-4000-8000-000000000002',test.id('purchase_order'))$q$,'42501','Order detail cannot change the document branch');
select test.expect_error($q$select test.purchase_receive(1,test.id('purchase_order'),2,jsonb_build_array(test.purchase_receipt_item(test.id('purchase_order'),1,1)))$q$,'40001','Receipt rejects stale order revision');
select test.expect_error($q$select test.purchase_receive(1,test.id('purchase_order'),1,jsonb_build_array(test.purchase_receipt_item(test.id('purchase_order'),1,6)))$q$,'23514','Receipt rejects quantity beyond remaining units');
select test.expect_error($q$select test.purchase_receive(1,test.id('purchase_order'),1,jsonb_build_array(test.purchase_receipt_item(test.id('purchase_order'),1,1),test.purchase_receipt_item(test.id('purchase_order'),1,1)))$q$,'22023','Receipt rejects duplicate original order lines');
select test.expect_error($q$select test.purchase_receive(1,test.id('purchase_order'),1,jsonb_build_array(test.purchase_receipt_item(test.id('purchase_order'),1,1)||'{"unit_cost_minor":1}'))$q$,'22023','Receipt cannot replace the original negotiated cost');
select test.expect_error($q$select test.purchase_receive(1,test.id('purchase_order'),1,'[{"order_item_id":"c6990000-0000-4000-8000-000000000001","quantity":1,"expected_product_revision":1}]')$q$,'42501','Receipt rejects an unrelated order item');
select set_config('test.purchase_receive',test.purchase_receive(1,test.id('purchase_order'),1,jsonb_build_array(test.purchase_receipt_item(test.id('purchase_order'),1,2)))::text,true);
select set_config('test.purchase_receipt',current_setting('test.purchase_receive')::jsonb->'receipt'->>'id',true);
select test.assert(current_setting('test.purchase_receive')::jsonb->>'kind'='purchase.receive','Receiving returns a distinct immutable action');
select test.assert((current_setting('test.purchase_receive')::jsonb->>'order_revision')::bigint=2,'Receipt freezes the accepted new order revision');
select test.assert((current_setting('test.purchase_receive')::jsonb->'receipt'->>'received_total_minor')::bigint=250,'Partial receipt uses original order cost');
select test.assert((current_setting('test.purchase_receive')::jsonb->'receipt'->'items'->0->>'balance_after')::bigint=2,'Receipt returns actual authoritative movement balance');
select test.assert((current_setting('test.purchase_receive')::jsonb->'receipt'->'items'->0->>'stock_revision')::bigint=1,'Receipt returns stock projection revision');
select test.assert((public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'))->>'status')='partially_received','Partial receipt advances current order status');
select test.assert((public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'))->'items'->0->>'remaining_quantity')::bigint=3,'Partial receipt reduces only received item remainder');
select test.assert((public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'))->>'received_total_minor')::bigint=250,'Current order total derives immutable received evidence');
select test.assert(test.purchase_receive(1,test.id('purchase_order'),1,jsonb_build_array(test.purchase_receipt_item(test.id('purchase_order'),1,2)))=current_setting('test.purchase_receive')::jsonb,'Receiving lost-response replay returns original action before stale revision checks');
select test.assert(test.purchase_create(1,jsonb_build_array(test.purchase_item(1),test.purchase_item(2,3,0)))=current_setting('test.purchase_create')::jsonb,'Creation replay remains initial after partial stock receipt');
select test.assert(not (public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order')) ? 'receipts'),'Order detail never embeds an unbounded receipt history');
select test.assert(jsonb_array_length(public.list_purchase_receipts(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'),0,1))=1,'Receipt history is separately paginated');
select test.assert(not (public.list_purchase_receipts(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'))->0 ? 'items'),'Receipt summary does not embed detail lines');
select test.assert(public.get_purchase_receipt(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_receipt'))=current_setting('test.purchase_receive')::jsonb->'receipt','Receipt detail matches its immutable original action');
reset role;
select test.assert((select count(*) from public.stock_movements where operation_id=(current_setting('test.purchase_receive')::jsonb->'receipt'->>'operation_id')::uuid)=1,'One partial receipt posts one stock movement');
select test.assert((select count(*) from private.operation_requests where organization_id=test.id('purchase_org') and kind='purchase.receive')=1,'One purchase request mapping owns receiving without a second stock.receive UUID insert');
select test.assert((select currency='PHP' and unit_cost_minor=125 and product_revision=1 from private.inventory_cost_evidence where movement_id=(current_setting('test.purchase_receive')::jsonb->'receipt'->'items'->0->>'movement_id')::uuid),'Private stock evidence retains original currency/cost and accepted current revision');
select test.assert((select count(*) from private.offline_changes where organization_id=test.id('purchase_org') and kind='stock')=1,'Purchase receipt emits existing organization offline stock feed');
-- Renames, catalog currency and supplier revision changes never rewrite history.
update public.products set name='Renamed product',sku='P6-RENAMED',currency='USD',cost_minor=888 where id='c6400000-0000-4000-8000-000000000001';
update public.suppliers set name='Renamed supplier' where id='c6300000-0000-4000-8000-000000000001';
set local role authenticated;
set local "request.jwt.claim.sub"='c6000000-0000-4000-8000-000000000001';
select test.assert((public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'))->'items'->0->>'product_name')='Original product 1','Order preserves original product name after catalog rename');
select test.assert((public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'))->>'supplier_name')='Original supplier','Order preserves original supplier snapshot');
select test.assert((public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'))->'items'->0->>'current_product_revision')::bigint=2,'Order detail exposes current revision by original product UUID');
select test.assert((public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'))->'items'->0->>'current_currency')='USD','Current metadata explicitly shows catalog currency change');
select test.assert(test.purchase_create(1,jsonb_build_array(test.purchase_item(1),test.purchase_item(2,3,0)))=current_setting('test.purchase_create')::jsonb,'Immutable creation replay never adopts current catalog metadata');
select test.expect_error($q$select test.purchase_receive(2,test.id('purchase_order'),2,jsonb_build_array(test.purchase_receipt_item(test.id('purchase_order'),1,1)))$q$,'40001','Receipt requires reviewed current product revision after rename');
select set_config('test.purchase_receive2',test.purchase_receive(2,test.id('purchase_order'),2,jsonb_build_array(test.purchase_receipt_item(test.id('purchase_order'),1,1,2)))::text,true);
select test.assert((current_setting('test.purchase_receive2')::jsonb->'receipt'->>'currency')='PHP','Receipt preserves original order currency despite catalog currency change');
select test.assert((current_setting('test.purchase_receive2')::jsonb->'receipt'->'items'->0->>'unit_cost_minor')::bigint=125,'Receipt preserves original negotiated cost after catalog cost change');
select test.assert((current_setting('test.purchase_receive2')::jsonb->'receipt'->'items'->0->>'product_revision')::bigint=2,'Receipt stores reviewed current product revision');
select test.expect_error($q$select test.purchase_cancel(1,test.id('purchase_order'),2)$q$,'40001','Cancellation rejects stale current order revision');
select set_config('test.purchase_cancel',test.purchase_cancel(1,test.id('purchase_order'),3)::text,true);
select test.assert((current_setting('test.purchase_cancel')::jsonb->>'order_revision')::bigint=4,'Cancellation freezes its accepted order revision');
select test.assert((current_setting('test.purchase_cancel')::jsonb->'cancellation'->>'cancelled_total_minor')::bigint=250,'Cancellation records only outstanding negotiated cost');
select test.assert((current_setting('test.purchase_cancel')::jsonb->'cancellation'->'items'->0->>'cancelled_quantity')::bigint=2,'Cancellation records remaining units after earlier receipts');
select test.assert((public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'))->>'status')='cancelled','Partial cancellation closes only outstanding units');
select test.assert((public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'))->'items'->0->>'received_quantity')::bigint=3,'Cancellation preserves earlier physically received quantities');
select test.assert((public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'))->'items'->0->>'remaining_quantity')::bigint=0,'Cancelled order has no collectible remainder');
select test.assert(test.purchase_cancel(1,test.id('purchase_order'),3)=current_setting('test.purchase_cancel')::jsonb,'Cancellation retry returns original immutable evidence');
select test.assert(test.purchase_receive(1,test.id('purchase_order'),1,jsonb_build_array(test.purchase_receipt_item(test.id('purchase_order'),1,2)))=current_setting('test.purchase_receive')::jsonb,'Original receipt replay survives later cancellation and product changes');
select test.expect_error($q$select test.purchase_receive(3,test.id('purchase_order'),4,jsonb_build_array(test.purchase_receipt_item(test.id('purchase_order'),1,1,2)))$q$,'23514','New receiving cannot reopen cancelled remainder');
select test.expect_error($q$select test.purchase_cancel(2,test.id('purchase_order'),4)$q$,'23514','New cancellation cannot duplicate a closed cancellation');
reset role;
select test.assert((select quantity from private.stock_balances where product_id='c6400000-0000-4000-8000-000000000001' and branch_id=test.id('purchase_branch'))=3,'Cancellation never removes prior physical stock');
select test.assert((select cost_minor from public.products where id='c6400000-0000-4000-8000-000000000001')=888,'Receiving never silently overwrites current catalog cost');
select test.assert((select count(*) from public.audit_logs where organization_id=test.id('purchase_org') and action in ('purchase.created','purchase.received','purchase.remaining_cancelled'))=4,'Successful order/receipts/cancellation each append one authoritative audit');
select test.assert((select count(*) from public.inventory_operations where organization_id=test.id('purchase_org'))=2,'Failed requests and cancellation do not append receiving operations');
-- Atomic ledger overflow rollback: first sorted product could post successfully,
-- but a later full balance failure rolls the entire receipt transaction back.
insert into private.stock_balances(organization_id,branch_id,product_id,quantity,revision) values(test.id('purchase_org'),test.id('purchase_branch'),'c6400000-0000-4000-8000-000000000003',9007199254740991,0);
set local role authenticated;
set local "request.jwt.claim.sub"='c6000000-0000-4000-8000-000000000001';
select set_config('test.purchase_atomic_order',test.purchase_create(3,jsonb_build_array(test.purchase_item(2,1,125),test.purchase_item(3,1,125)),'c6300000-0000-4000-8000-000000000001',2)->>'order_id',true);
select test.expect_error($q$select test.purchase_receive(4,test.id('purchase_atomic_order'),1,jsonb_build_array(test.purchase_receipt_item(test.id('purchase_atomic_order'),2,1),test.purchase_receipt_item(test.id('purchase_atomic_order'),3,1)))$q$,'22023','Later stock overflow atomically rolls back a multi-line purchase receipt');
select test.assert((public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_atomic_order'))->>'revision')::bigint=1,'Failed receipt rolls back order projection revision');
reset role;
select test.assert(not exists(select 1 from private.operation_requests where request_id='c6600000-0000-4000-8000-000000000004'),'Failed receipt leaves no accepted request mapping');
select test.assert(not exists(select 1 from public.purchase_receipts where order_id=test.id('purchase_atomic_order')),'Failed receipt leaves no financial receipt evidence');
select test.assert(not exists(select 1 from public.stock_movements where product_id='c6400000-0000-4000-8000-000000000002'),'Failed later line rolls back an earlier ledger movement');
select test.assert(not exists(select 1 from private.stock_balances where product_id='c6400000-0000-4000-8000-000000000002'),'Failed earlier line rolls back newly created stock projection');
-- Complete receiving and exact maximum/zero-cost documents.
set local role authenticated;
set local "request.jwt.claim.sub"='c6000000-0000-4000-8000-000000000001';
select set_config('test.purchase_complete',test.purchase_create(4,jsonb_build_array(test.purchase_item(2,1,0)),'c6300000-0000-4000-8000-000000000001',2)->>'order_id',true);
select test.purchase_receive(5,test.id('purchase_complete'),1,jsonb_build_array(test.purchase_receipt_item(test.id('purchase_complete'),2,1)));
select test.assert((public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_complete'))->>'status')='received','Fully received zero-cost order closes without invented payment');
select test.expect_error($q$select test.purchase_cancel(3,test.id('purchase_complete'),2)$q$,'23514','Fully received order cannot be cancelled');
select test.assert((test.purchase_create(5,jsonb_build_array(test.purchase_item(2,1,9007199254740991)),'c6300000-0000-4000-8000-000000000001',2)->'order'->>'ordered_total_minor')::bigint=9007199254740991,'Purchase accepts exact maximum safe money at quantity one');
-- Current role, branch, verified identity and MFA always precede replay.
set local "request.jwt.claim.sub"='c6000000-0000-4000-8000-000000000003';
select test.assert((public.get_purchase_context(test.id('purchase_org'),test.id('purchase_branch'))->>'currency')='PHP','Assigned InventoryStaff has purchase context without POS permission');
select test.assert(jsonb_array_length(public.list_purchase_orders(test.id('purchase_org'),test.id('purchase_branch')))=4,'InventoryStaff reads authoritative own-branch purchases');
select test.assert((select count(*) from public.audit_logs where organization_id=test.id('purchase_org') and action='purchase.received')=3,'InventoryStaff can read narrowly scoped purchase receipt audits');
select test.expect_error($q$select public.list_purchase_orders(test.id('purchase_org'),'c6100000-0000-4000-8000-000000000002')$q$,'42501','InventoryStaff cannot browse unassigned branch');
select test.assert(not private.can_read_audit(test.id('purchase_org'),test.id('purchase_branch'),'organization_memberships',gen_random_uuid(),'purchase.created','{}'),'Purchase action name alone cannot expose security audit');
select test.assert(not private.can_read_audit(test.id('purchase_org'),test.id('purchase_branch'),'purchase_orders',test.id('purchase_order'),'purchase.received','{}'),'Purchase audit requires matching entity and action');
set local "request.jwt.claim.sub"='c6000000-0000-4000-8000-000000000004';
select test.expect_error($q$select public.get_purchase_context(test.id('purchase_org'),test.id('purchase_branch'))$q$,'42501','Cashier cannot open purchase context');
select test.expect_error($q$select public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'))$q$,'42501','Cashier cannot read procurement costs via RPC');
select test.assert((select count(*) from public.purchase_orders)=0,'Cashier direct RLS reads reveal no purchase headers');
select test.expect_error($q$select test.purchase_create(6,jsonb_build_array(test.purchase_item(2)),'c6300000-0000-4000-8000-000000000001',2)$q$,'42501','Cashier cannot create purchase orders');
set local "request.jwt.claim.sub"='c6000000-0000-4000-8000-000000000002';
select set_config('test.purchase_manager_action',test.purchase_create(6,jsonb_build_array(test.purchase_item(2)),'c6300000-0000-4000-8000-000000000001',2)::text,true);
reset role;
update public.organization_memberships set status='disabled' where user_id='c6000000-0000-4000-8000-000000000002';
set local role authenticated;
select test.expect_error($q$select test.purchase_create(6,jsonb_build_array(test.purchase_item(2)),'c6300000-0000-4000-8000-000000000001',2)$q$,'42501','Disabled actor cannot retrieve prior accepted purchase through replay');
select test.assert((select count(*) from public.purchase_order_items)=0,'Disabled actor direct RLS reads reveal no purchase lines');
set local "request.jwt.claim.sub"='00000000-0000-4000-8000-000000000002';
select test.expect_error($q$select public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'))$q$,'42501','Another tenant cannot inspect purchase documents');
reset role;
insert into private.security_policies(organization_id,require_privileged_mfa) values(test.id('purchase_org'),true);
set local role authenticated;
set local "request.jwt.claim.sub"='c6000000-0000-4000-8000-000000000001';
set local "request.jwt.claims"='{"sub":"c6000000-0000-4000-8000-000000000001","aal":"aal1"}';
select test.expect_error($q$select test.purchase_create(1,jsonb_build_array(test.purchase_item(1),test.purchase_item(2,3,0)))$q$,'42501','Configured Owner MFA is checked before successful purchase replay');
select test.assert((select count(*) from public.purchase_orders)=0,'Configured MFA also protects direct purchase RLS reads');
select test.assert((select count(*) from public.audit_logs where action like 'purchase.%')=0,'Configured MFA protects new purchase operational audit reads');
set local "request.jwt.claims"='{"sub":"c6000000-0000-4000-8000-000000000001","aal":"aal2"}';
select test.assert(test.purchase_create(1,jsonb_build_array(test.purchase_item(1),test.purchase_item(2,3,0)))=current_setting('test.purchase_create')::jsonb,'Current MFA-authenticated replay returns unchanged original purchase');
reset role;
update auth.users set email_confirmed_at=null where id='c6000000-0000-4000-8000-000000000001';
set local role authenticated;
select test.expect_error($q$select test.purchase_create(1,jsonb_build_array(test.purchase_item(1),test.purchase_item(2,3,0)))$q$,'42501','Lost email verification blocks prior accepted purchase replay');
reset role;
update auth.users set email_confirmed_at=now() where id='c6000000-0000-4000-8000-000000000001';
-- Immutable history and explicit function/table privileges.
set local role authenticated;
select test.expect_error('update public.purchase_orders set ordered_total_minor=1','42501','Client cannot alter submitted purchase totals');
select test.expect_error('delete from public.purchase_receipts','42501','Client cannot delete physical receipt evidence');
select test.expect_error('truncate public.purchase_order_items','42501','Client cannot truncate ordered item evidence');
select test.expect_error('select * from private.purchase_order_states','42501','Client cannot directly read purchase state projection');
select test.expect_error('select * from private.purchase_order_item_balances','42501','Client cannot directly read mutable received balances');
select test.expect_error($q$select private.purchase_order_json(test.id('purchase_order'))$q$,'42501','Private serializer is not an authenticated bypass');
select test.expect_error($q$select private.phase6_purchase_prior_can_read_audit(test.id('purchase_org'),test.id('purchase_branch'),'purchase_orders',test.id('purchase_order'),'purchase.created','{}')$q$,'42501','Prior audit helper is not an exposed authorization bypass');
set local role anon;
select test.expect_error($q$select public.get_purchase_context(test.id('purchase_org'),test.id('purchase_branch'))$q$,'42501','Anonymous purchase discovery is denied');
set local role service_role;
select test.expect_error($q$select public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order'))$q$,'42501','Service role has no ordinary purchase RPC execution');
select test.expect_error('select * from private.purchase_order_item_balances','42501','Service role has no direct purchase projection grant');
reset role;
select test.expect_error('update public.purchase_orders set ordered_total_minor=ordered_total_minor','42501','Maintenance UPDATE cannot rewrite purchase headers');
select test.expect_error('delete from public.purchase_order_items','42501','Maintenance DELETE cannot erase ordered items');
select test.expect_error('truncate public.purchase_receipts cascade','42501','Maintenance TRUNCATE cannot erase physical receipts');
select test.expect_error('update public.purchase_receipt_items set quantity=quantity','42501','Maintenance UPDATE cannot rewrite receipt quantities');
select test.expect_error('delete from public.purchase_order_cancellations','42501','Maintenance DELETE cannot erase cancellation evidence');
-- Actual RPC output for the Flutter contract decoder, emitted before rollback.
select 'P6_PURCHASE_FIXTURE '||jsonb_build_object(
 'context',public.get_purchase_context(test.id('purchase_org'),test.id('purchase_branch')),
 'creation',current_setting('test.purchase_create')::jsonb,
 'partial_receipt',current_setting('test.purchase_receive')::jsonb,
 'second_receipt',current_setting('test.purchase_receive2')::jsonb,
 'cancellation',current_setting('test.purchase_cancel')::jsonb,
 'final_order',public.get_purchase_order(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order')),
 'receipts',public.list_purchase_receipts(test.id('purchase_org'),test.id('purchase_branch'),test.id('purchase_order')),
 'create_request',jsonb_build_object('p_organization_id',test.id('purchase_org'),'p_branch_id',test.id('purchase_branch'),'p_request_id','c6500000-0000-4000-8000-000000000001',
  'p_supplier_id','c6300000-0000-4000-8000-000000000001','p_expected_supplier_revision',1,'p_expected_settings_revision',current_setting('test.purchase_settings')::bigint,'p_currency','PHP',
  'p_items',jsonb_build_array(test.purchase_item(1),test.purchase_item(2,3,0)),'p_reference','PO manual reference','p_reason','Operator submitted purchase order'),
 'receive_request',jsonb_build_object('p_organization_id',test.id('purchase_org'),'p_branch_id',test.id('purchase_branch'),'p_request_id','c6600000-0000-4000-8000-000000000001',
  'p_order_id',test.id('purchase_order'),'p_expected_revision',1,'p_items',jsonb_build_array(test.purchase_receipt_item(test.id('purchase_order'),1,2)),
  'p_reference','Delivery manual reference','p_reason','Physical units received and counted'),
 'cancel_request',jsonb_build_object('p_organization_id',test.id('purchase_org'),'p_branch_id',test.id('purchase_branch'),'p_request_id','c6700000-0000-4000-8000-000000000001',
  'p_order_id',test.id('purchase_order'),'p_expected_revision',3,'p_reason','Supplier remainder explicitly cancelled')
)::text;
rollback;
