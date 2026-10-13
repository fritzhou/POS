\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,email_confirmed_at) values('b7000000-0000-4000-8000-000000000001','logistics-owner@example.invalid',now()),('b7000000-0000-4000-8000-000000000002','logistics-staff@example.invalid',now()),('b7000000-0000-4000-8000-000000000003','logistics-cashier@example.invalid',now());
set local role authenticated;
set local "request.jwt.claim.sub"='b7000000-0000-4000-8000-000000000001';
select set_config('test.b7_org',organization_id::text,true),set_config('test.b7_source',branch_id::text,true) from public.bootstrap_organization('Logistics fixture','Owner fixture');
select set_config('test.b7_branch_action',public.save_branch(test.id('b7_org'),'b7100000-0000-4000-8000-000000000001',null,null,'Destination','DEST',null,true,'Create delivery destination')::text,true);
select set_config('test.b7_dest',current_setting('test.b7_branch_action')::jsonb->'branch'->>'id',true);
select set_config('test.b7_product',(public.save_product(test.id('b7_org'),null,null,'{"name":"Counted stock","sku":"B7-A","price_minor":100,"unit":"each"}','Create counted product')->>'id'),true);
select public.receive_stock(test.id('b7_org'),test.id('b7_source'),'b7100000-0000-4000-8000-000000000002',jsonb_build_array(jsonb_build_object('product_id',test.id('b7_product'),'quantity',10,'expected_revision',1)),null,null,'Ten physical source units');
select set_config('test.b7_input',jsonb_build_array(jsonb_build_object('product_id',test.id('b7_product'),'quantity',6,'expected_revision',1))::text,true);
select set_config('test.b7_dispatch',public.dispatch_stock_transfer(test.id('b7_org'),test.id('b7_source'),test.id('b7_dest'),'b7100000-0000-4000-8000-000000000003',current_setting('test.b7_input')::jsonb,'Truck reference','Six units physically dispatched',true)::text,true);
select set_config('test.b7_transfer',current_setting('test.b7_dispatch')::jsonb->'document'->>'id',true);
select set_config('test.b7_item',current_setting('test.b7_dispatch')::jsonb->'document'->'items'->0->>'item_id',true);
commit;
