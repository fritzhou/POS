-- Disposable nexapos_security_test ONLY, after production migrations and the
-- test-only Auth mocks. Every created business/identity/operation rolls back.
-- The resulting JSON is a test fixture, never application demonstration data.
begin;
create temporary table contract_fixture(name text primary key, value jsonb not null);
grant all on contract_fixture to authenticated;
insert into auth.users(id,email,email_confirmed_at) values
 ('90000000-0000-4000-8000-000000000001','contract-owner@example.invalid',now()),
 ('90000000-0000-4000-8000-000000000002','contract-cashier@example.invalid',now());
set local role authenticated;
set local "request.jwt.claim.sub" = '90000000-0000-4000-8000-000000000001';
do $$
declare
 org uuid; branch uuid; first_product uuid; second_product uuid; low_product uuid; high_product uuid;
 context jsonb; stock jsonb; initial_shift jsonb; first_closure jsonb; sale jsonb; second_shift jsonb; reversal jsonb;
begin
 select organization_id,branch_id into org,branch
  from public.bootstrap_organization('Server contract fixture','Contract Owner');
 perform public.save_business_settings(org,1,'{"tax_bps":5000,"receipt_footer":"Contract footer"}', 'Contract tax settings');
 first_product := (public.save_product(org,null,null,
  '{"name":"First contract product","sku":"CONTRACT-FIRST","barcode":"CONTRACT-FIRST","price_minor":0,"cost_minor":123}',
  'Create contract product')->>'id')::uuid;
 second_product := (public.save_product(org,null,null,
  '{"name":"Second contract product","sku":"CONTRACT-SECOND","barcode":"CONTRACT-SECOND","price_minor":0,"cost_minor":456}',
  'Create contract product')->>'id')::uuid;
 low_product := least(first_product,second_product);
 high_product := greatest(first_product,second_product);
 perform public.save_product(org,low_product,1,'{"price_minor":4503599627370496}','Set exact contract price');
 perform public.save_product(org,high_product,1,'{"price_minor":4503599627370495}','Set exact contract price');
 context := public.get_pos_context(org,branch);
 stock := public.receive_stock(org,branch,'91000000-0000-4000-8000-000000000001',
  jsonb_build_array(jsonb_build_object('product_id',low_product,'quantity',1,'expected_revision',2),
   jsonb_build_object('product_id',high_product,'quantity',1,'expected_revision',2)),
  null,'Contract delivery','Collect server stock contract');
 insert into contract_fixture values ('stock_receive',stock);
 insert into contract_fixture values ('stock_adjust',public.adjust_stock(org,branch,
  '91000000-0000-4000-8000-000000000002',low_product,1,'Collect server adjustment contract'));
 insert into contract_fixture values ('context',context);
 insert into contract_fixture values ('products_before_sale',public.list_pos_products(org,branch));
 insert into contract_fixture values ('barcode_product',public.lookup_pos_product_by_barcode(org,branch,'CONTRACT-FIRST'));
 initial_shift := public.open_shift(org,branch,'91000000-0000-4000-8000-000000000003',0,'PHP');
 insert into contract_fixture values ('shift_open',initial_shift);
 sale := public.checkout_sale(org,branch,'91000000-0000-4000-8000-000000000004',jsonb_build_object(
  'shift_id',initial_shift->>'id','expected_settings_revision',context->'settings_revision',
  'items',jsonb_build_array(jsonb_build_object('product_id',low_product,'quantity',1,'expected_revision',2),
   jsonb_build_object('product_id',high_product,'quantity',1,'expected_revision',2)),
  'discount_minor',9007199254740989,'reason','Collect exact financial contract',
  'payments',jsonb_build_array(jsonb_build_object('method','cash','amount_minor',3,'tendered_minor',5))));
 if (sale->>'total_minor')::bigint <> 3 then raise exception 'Exact numeric division contract failed'; end if;
 insert into contract_fixture values ('sale',sale);
 insert into contract_fixture values ('sale_by_request',public.get_sale_by_request(org,branch,'91000000-0000-4000-8000-000000000004'));
 first_closure := public.close_shift(org,(initial_shift->>'id')::uuid,'91000000-0000-4000-8000-000000000005',3,'Collect first cash count');
 insert into contract_fixture values ('shift_closed',first_closure);
 second_shift := public.open_shift(org,branch,'91000000-0000-4000-8000-000000000006',0,'PHP');
 reversal := public.reverse_sale(org,(sale->>'id')::uuid,'91000000-0000-4000-8000-000000000007',jsonb_build_object(
  'kind','refund','reason','Collect original payment refund','return_stock',true,'shift_id',second_shift->>'id',
  'items',(select jsonb_agg(jsonb_build_object('sale_item_id',x->>'id','quantity',x->'quantity')) from jsonb_array_elements(sale->'items') x),
  'payments',(select jsonb_agg(jsonb_build_object('original_payment_id',x->>'id','amount_minor',x->'amount_minor','manual_confirmed',true)) from jsonb_array_elements(sale->'payments') x)));
 insert into contract_fixture values ('reversal',reversal);
 insert into contract_fixture values ('sale_after_refund',public.get_sale(org,(sale->>'id')::uuid));
 insert into contract_fixture values ('shift_negative',public.get_current_shift(org,branch));
 insert into contract_fixture values ('shift_closed_after_refund',public.close_shift(org,(second_shift->>'id')::uuid,
  '91000000-0000-4000-8000-000000000008',0,'Count actual empty drawer'));
 perform public.save_product(org,low_product,2,'{"active":false}','Keep inactive product stock visible');
 insert into contract_fixture values ('inventory',public.list_inventory(org,branch));
 insert into contract_fixture values ('movements',public.list_stock_movements(org,branch));
 insert into contract_fixture values ('sales_list',public.list_sales(org,branch));
 insert into contract_fixture values ('shifts_list',public.list_shifts(org,branch));
 insert into contract_fixture values ('meta',jsonb_build_object('source','PostgreSQL 17, migration 006, isolated mock Auth, rollback-only fixture',
  'organization_id',org,'branch_id',branch,'owner_id','90000000-0000-4000-8000-000000000001',
  'cashier_id','90000000-0000-4000-8000-000000000002','low_product_id',low_product,'high_product_id',high_product));
end $$;
reset role;
insert into public.profiles(user_id,full_name) values('90000000-0000-4000-8000-000000000002','Contract Cashier');
insert into public.organization_memberships(id,organization_id,user_id,role,status,all_branches)
 select '92000000-0000-4000-8000-000000000001',(value->>'organization_id')::uuid,
  '90000000-0000-4000-8000-000000000002','cashier','active',false from contract_fixture where name='meta';
insert into public.membership_branches(membership_id,organization_id,branch_id)
 select '92000000-0000-4000-8000-000000000001',(value->>'organization_id')::uuid,(value->>'branch_id')::uuid from contract_fixture where name='meta';
set local role authenticated;
set local "request.jwt.claim.sub" = '90000000-0000-4000-8000-000000000002';
do $$ declare org uuid; branch uuid; begin
 select (value->>'organization_id')::uuid,(value->>'branch_id')::uuid into org,branch from contract_fixture where name='meta';
 insert into contract_fixture values ('cashier_context',public.get_pos_context(org,branch));
 insert into contract_fixture values ('cashier_products',public.list_pos_products(org,branch));
 insert into contract_fixture values ('cashier_sales',public.list_sales(org,branch));
end $$;
reset role;
select jsonb_pretty(jsonb_object_agg(name,value)) from contract_fixture;
rollback;
