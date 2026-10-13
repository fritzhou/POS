\set ON_ERROR_STOP on
begin;
select set_config('test.org_a',id::text,true) from public.organizations where owner_user_id = '00000000-0000-4000-8000-000000000001';
select set_config('test.org_b',id::text,true) from public.organizations where owner_user_id = '00000000-0000-4000-8000-000000000002';
select set_config('test.branch_a',id::text,true) from public.branches where organization_id = test.id('org_a') and code = 'MAIN';
select set_config('test.branch_b',id::text,true) from public.branches where organization_id = test.id('org_b') and code = 'MAIN';
select set_config('test.owner_membership_a',id::text,true) from public.organization_memberships where organization_id = test.id('org_a') and role = 'owner';
select set_config('request.jwt.claim.sub','',true);
update public.organization_memberships set status = 'active' where id = '30000000-0000-4000-8000-000000000007';
insert into auth.users(id,email,email_confirmed_at) values ('00000000-0000-4000-8000-000000000020','multibranch@example.invalid',now());
insert into public.organization_memberships(id,organization_id,user_id,role,status) values
  ('30000000-0000-4000-8000-000000000020',test.id('org_a'),'00000000-0000-4000-8000-000000000020','cashier','active');
insert into public.membership_branches(membership_id,organization_id,branch_id) values
  ('30000000-0000-4000-8000-000000000020',test.id('org_a'),test.id('branch_a')),
  ('30000000-0000-4000-8000-000000000020',test.id('org_a'),'20000000-0000-4000-8000-000000000002');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select test.assert(jsonb_array_length(public.list_products(test.id('org_a'),p_limit=>1)) = 1,'Product queries obey page limit');
select test.assert(jsonb_array_length(public.list_products(test.id('org_a'),p_query=>'No Such Product')) = 0,'Product server search filters');
select test.expect_error('select public.list_products(test.id(''org_a''),p_limit=>102)','22023','Product query refuses unbounded page');
select test.expect_error('select public.list_products(test.id(''org_b''))','42501','Product RPC refuses foreign tenant');
select test.expect_error($q$update public.products set price_minor=1$q$,'42501','Direct catalog update cannot bypass CAS');
select test.expect_error($q$insert into public.categories(organization_id,name) values(test.id('org_a'),'Bypass')$q$,'42501','Direct category insert cannot bypass RPC');
select test.expect_error($q$select public.save_product(test.id('org_a'),null,null,'{"name":"Forged","sku":"FORGED","organization_id":"00000000-0000-4000-8000-000000000002"}','Test forbidden field')$q$,'22023','Write rejects organization field smuggling');
select set_config('test.created_product',(public.save_product(test.id('org_a'),null,null,
  jsonb_build_object('name','Phase Two Product','sku','PHASE2','cost_minor',2500,'price_minor',5000,'image_path',test.id('org_a')::text || '/catalog/item.png'),
  'Created phase two catalog record')->>'id'),true);
select test.assert((public.list_products(test.id('org_a'),p_query=>'PHASE2')->0->>'cost_minor')::bigint = 2500,'Owner catalog query includes authorized cost');
select test.assert(jsonb_typeof(public.list_products(test.id('org_a'),p_query=>'PHASE2')->0->'reorder_level')='string','Exact decimal quantity is serialized as text');
select test.assert((public.save_product(test.id('org_a'),null,null,'{"name":"Exact Decimal Product","sku":"EXACTDECIMAL","reorder_level":"99999999999999.9999"}','Exact decimal quantity')->>'reorder_level')='99999999999999.9999','Maximum scale quantity survives transport exactly');
select test.assert((public.save_product(test.id('org_a'),test.id('created_product'),1,'{"price_minor":5500}','Adjusted price')->>'revision')::bigint = 2,'Catalog RPC increments revision');
select test.expect_error($q$select public.save_product(test.id('org_a'),test.id('created_product'),1,'{"price_minor":1}','Stale price update')$q$,'40001','Stale catalog writer cannot overwrite');
select test.assert((select price_minor from public.products where id = test.id('created_product')) = 5500,'CAS conflict preserves accepted price');
select test.expect_error($q$select public.save_product(test.id('org_a'),test.id('created_product'),2,'{"revision":500}','Forge server revision')$q$,'22023','RPC rejects revision smuggling');
select test.expect_error($q$select public.save_product(test.id('org_a'),null,null,'{"name":"Negative","sku":"NEGATIVE","price_minor":-1}','Invalid amount check')$q$,'22023','Negative monetary catalog value rejected');
select test.expect_error($q$select public.save_product(test.id('org_a'),null,null,'{"name":"Fractional","sku":"FRACTION","price_minor":1.25}','Fractional minor unit')$q$,'22023','Minor units reject fractional values');
select test.expect_error($q$select public.save_product(test.id('org_a'),null,null,'{"name":"External","sku":"EXTERNAL","image_path":"https://remote.example.invalid/a.png"}','External image attempt')$q$,'22023','Image reference refuses external network URL');
select test.expect_error($q$select public.save_product(test.id('org_a'),null,null,jsonb_build_object('name','Traversal','sku','TRAVERSE','image_path',test.id('org_a')::text || '/../other/file.png'),'Traversal image attempt')$q$,'22023','Image reference refuses path traversal');
select test.expect_error($q$select public.save_product(test.id('org_a'),null,null,jsonb_build_object('name','Foreign Image','sku','FOREIGNIMAGE','image_path',test.id('org_b')::text || '/file.png'),'Foreign image attempt')$q$,'22023','Image reference refuses foreign organization prefix');
select test.expect_error($q$select public.save_product(test.id('org_a'),null,null,jsonb_build_object('name','Query Image','sku','QUERYIMAGE','image_path',test.id('org_a')::text || '/file.png?token=abc'),'Query image attempt')$q$,'22023','Image reference refuses query parameters');
select test.expect_error($q$select public.save_category(test.id('org_a'),null,null,'{"name":"Reasonless"}',' ')$q$,'22023','Mutation requires meaningful reason');
select test.assert(exists(select 1 from public.audit_logs where entity_id=test.id('created_product') and action='products.update' and reason='Adjusted price' and user_id=auth.uid() and role='owner'),'Catalog audit derives actor and preserves reason');

-- Owner creates global and branch-scoped directory rows through the same RPCs.
select set_config('test.supplier_global',(public.save_supplier(test.id('org_a'),null,null,'{"name":"Global Supplier"}','Create global supplier')->>'id'),true);
select set_config('test.supplier_a',(public.save_supplier(test.id('org_a'),null,null,jsonb_build_object('name','Branch A Supplier','branch_id',test.id('branch_a')),'Create branch supplier')->>'id'),true);
select set_config('test.supplier_second',(public.save_supplier(test.id('org_a'),null,null,jsonb_build_object('name','Second Branch Supplier','branch_id','20000000-0000-4000-8000-000000000002'),'Create second supplier')->>'id'),true);
select set_config('test.customer_global',(public.save_customer(test.id('org_a'),null,null,'{"name":"Global Customer"}','Create global customer')->>'id'),true);
select set_config('test.customer_a',(public.save_customer(test.id('org_a'),null,null,jsonb_build_object('name','Branch A Customer','branch_id',test.id('branch_a'),'email','customer@example.invalid'),'Create branch customer')->>'id'),true);
select set_config('test.customer_second',(public.save_customer(test.id('org_a'),null,null,jsonb_build_object('name','Second Branch Customer','branch_id','20000000-0000-4000-8000-000000000002'),'Create second customer')->>'id'),true);
select test.assert((select count(*) from public.suppliers)=3,'Owner directory query sees global and all branches');
select test.expect_error($q$select public.save_supplier(test.id('org_a'),null,null,jsonb_build_object('name','Foreign Branch','branch_id',test.id('branch_b')),'Mixed organization branch')$q$,'42501','Directory create refuses foreign branch');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
select test.assert((select count(*) from public.suppliers)=2,'Manager suppliers include global and assigned branch only');
select test.assert((select count(*) from public.customers)=2,'Manager customers include global and assigned branch only');
select test.assert((public.save_customer(test.id('org_a'),test.id('customer_a'),1,'{"phone":"+63-example"}','Manager customer update')->>'revision')::bigint=2,'Manager may mutate authorized branch customer');
select test.expect_error($q$select public.save_customer(test.id('org_a'),test.id('customer_global'),1,'{"name":"Unauthorized"}','Manager global attempt')$q$,'42501','Manager cannot mutate global directory');
select test.expect_error($q$select public.save_supplier(test.id('org_a'),test.id('supplier_second'),99,'{"name":"Unauthorized"}','Manager branch attempt')$q$,'42501','Unauthorized directory branch checked before revision');
select test.expect_error($q$select public.save_product(test.id('org_a'),test.id('created_product'),2,'{"price_minor":1}','Manager price attempt')$q$,'42501','Manager catalog is read only');
select test.assert(jsonb_array_length(public.list_audit_logs(test.id('org_a'))) >= 2,'Manager has genuine branch operational audit');
select test.assert(not exists(select 1 from jsonb_array_elements(public.list_audit_logs(test.id('org_a'))) e where e->>'entity' not in ('suppliers','customers') or (e->>'branch_id')::uuid<>test.id('branch_a')),'Manager cannot inspect security/global/foreign-branch audit');
select test.expect_error('select public.employee_roster(test.id(''org_a''))','42501','Manager cannot read employee administration');
select test.expect_error('select public.get_business_settings(test.id(''org_a''))','42501','Manager cannot read protected settings RPC');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000006',true);
select test.assert((select count(*) from public.suppliers)=2,'Inventory Staff reads authorized suppliers');
select test.assert((select count(*) from public.customers)=0,'Inventory Staff cannot read customer personal data');
select test.assert((public.save_product(test.id('org_a'),test.id('created_product'),2,'{"price_minor":5600}','Inventory catalog update')->>'revision')::bigint=3,'Inventory Staff can manage shared organization catalog');
select test.assert((public.save_category(test.id('org_a'),null,null,'{"name":"Inventory Category"}','Inventory category created')->>'name')='Inventory Category','Inventory Staff category management works');
select test.assert((public.save_supplier(test.id('org_a'),test.id('supplier_a'),1,'{"contact_name":"Stock Contact"}','Inventory supplier update')->>'revision')::bigint=2,'Inventory Staff may update own branch supplier');
select test.expect_error($q$select public.save_customer(test.id('org_a'),null,null,'{"name":"Forbidden Customer"}','Inventory customer attempt')$q$,'42501','Inventory Staff cannot create customer records');
select test.assert(not exists(select 1 from jsonb_array_elements(public.list_audit_logs(test.id('org_a'))) e where e->>'entity'<>'suppliers' or (e->>'branch_id')::uuid<>test.id('branch_a')),'Inventory Staff audit is branch supplier operations only');
select test.expect_error('select cost_minor from public.products','42501','Direct SELECT does not expose cost via shared database role');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000005',true);
select test.assert((select count(*) from public.suppliers)=0,'Cashier cannot read suppliers');
select test.assert((select count(*) from public.customers)=2,'Cashier can lookup authorized customers');
select test.assert((public.list_products(test.id('org_a'),p_query=>'PHASE2')->0->'cost_minor')='null'::jsonb,'Cashier catalog masks cost server-side');
select test.expect_error('select cost_minor from public.products','42501','Cashier cannot bypass cost mask through direct table');
select test.expect_error($q$select public.save_product(test.id('org_a'),test.id('created_product'),3,'{"price_minor":1}','Cashier price attempt')$q$,'42501','Cashier catalog mutation denied');
select test.expect_error($q$select public.save_customer(test.id('org_a'),test.id('customer_a'),2,'{"name":"Changed"}','Cashier customer attempt')$q$,'42501','Cashier lookup does not confer customer writes');
select test.expect_error('select public.list_audit_logs(test.id(''org_a''))','42501','Cashier cannot query audit RPC');
select test.expect_error('select public.get_business_settings(test.id(''org_a''))','42501','Cashier cannot access protected settings');
select test.expect_error('update public.suppliers set name=''Bypass''','42501','No direct supplier write grant');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000007',true);
select test.assert(not exists(select 1 from jsonb_array_elements(public.employee_roster(test.id('org_a'))) e where (e->>'id')::uuid in ('30000000-0000-4000-8000-000000000013','30000000-0000-4000-8000-000000000020')),'Scoped Admin roster excludes other-branch and mixed-scope employees');
select test.assert(not exists(select 1 from public.organization_memberships where id='30000000-0000-4000-8000-000000000020'),'Direct membership RLS cannot bypass roster scope');
select test.expect_error($q$select public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000007','manager','active',false,array[test.id('branch_a')],2,'Self access attempt')$q$,'42501','Admin cannot modify own access');
select test.expect_error($q$select public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000010','cashier','active',false,array[test.id('branch_a')],1,'Admin peer attempt')$q$,'42501','Admin cannot demote peer Admin');
select test.expect_error($q$select public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000005','admin','active',true,'{}',1,'Grant admin attempt')$q$,'42501','Admin cannot grant Admin or all-branch privilege');
select test.expect_error($q$select public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000013','cashier','active',false,array[test.id('branch_a')],1,'Foreign branch takeover')$q$,'42501','Admin cannot move an employee from another branch');
select test.expect_error($q$select public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000020','cashier','active',false,array[test.id('branch_a')],1,'Trim branch takeover')$q$,'42501','Admin must control all current target branches');
select test.assert((public.save_business_settings(test.id('org_a'),1,'{"tax_bps":1200,"receipt_footer":"Thank you"}','Configured POS settings')->>'revision')::bigint=2,'Admin allowed business/POS settings CAS');
select test.expect_error($q$select public.save_business_settings(test.id('org_a'),1,'{"tax_bps":0}','Stale settings attempt')$q$,'40001','Stale settings writer cannot overwrite');
select test.expect_error($q$select public.save_business_settings(test.id('org_a'),2,'{"owner_user_id":"00000000-0000-4000-8000-000000000007"}','Owner transfer attempt')$q$,'22023','Business settings cannot transfer ownership');
select test.expect_error($q$select public.save_business_settings(test.id('org_a'),2,'{"mfa_required":true}','Pretend security setting')$q$,'22023','Settings cannot fabricate unenforced security policy');
select test.expect_error($q$select public.save_business_settings(test.id('org_a'),2,'{"logo_path":"https://example.invalid/logo.png"}','Unsafe logo attempt')$q$,'22023','Business logo refuses remote URL');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select test.assert(jsonb_array_length(public.employee_roster(test.id('org_a'),p_limit=>1))=1,'Employee roster is bounded');
select test.expect_error('select public.employee_roster(test.id(''org_a''),p_limit=>102)','22023','Employee roster refuses unbounded page');
select test.expect_error($q$select public.change_employee_access(test.id('org_a'),test.id('owner_membership_a'),'admin','disabled',true,'{}',1,'Disable owner attempt')$q$,'42501','Owner cannot be disabled/demoted through employee API');
select test.expect_error($q$select public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000005','owner','active',true,'{}',1,'Owner promotion attempt')$q$,'22023','Employee API cannot assign Owner');
select test.expect_error($q$select public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000005','cashier','active',false,array[test.id('branch_b')],1,'Cross tenant assignment')$q$,'42501','Employee assignment refuses foreign tenant branch');
select test.expect_error($q$select public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000005','cashier','active',false,'{}',1,'Remove all branches')$q$,'22023','Branch scoped employee cannot lose every assignment');
select test.assert((public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000005','admin','active',false,array[test.id('branch_a')],1,'Owner granted scoped Admin')->>'revision')::bigint=2,'Owner can grant scoped Admin transactionally');
select test.assert((public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000005','admin','active',false,array[test.id('branch_a')],2,'Validate response contract')->>'full_name')='Cashier A','Access-change response includes roster full_name');
select test.assert((public.employee_roster(test.id('org_a'),p_status=>'active') @> jsonb_build_array(jsonb_build_object('id','30000000-0000-4000-8000-000000000005','full_name','Cashier A','email','test5@example.invalid'))),'Roster and access-change employee metadata agree');
select test.expect_error($q$select public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000005','cashier','active',false,array[test.id('branch_a')],1,'Stale employee change')$q$,'40001','Employee access CAS prevents stale overwrite');
select public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000005','cashier','active',false,array[test.id('branch_a')],3,'Restore test Cashier');
select test.assert((public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000006','inventory_staff','disabled',false,array['20000000-0000-4000-8000-000000000002'::uuid],1,'Disabled employee safely')->>'revision')::bigint=2,'Employee disable and branch replacement are atomic');
select test.assert(exists(select 1 from public.audit_logs where entity_id='30000000-0000-4000-8000-000000000006' and action='employee.access_changed' and reason='Disabled employee safely' and role='owner' and user_id=auth.uid()),'Employee change writes actor-derived reason audit');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000006',true);
select test.expect_error('select public.list_products(test.id(''org_a''))','42501','Disabled employee loses online RPC access with same JWT');
select test.assert((select count(*) from public.suppliers)=0,'Disabled employee loses directory reads');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000006','inventory_staff','active',false,array[test.id('branch_a')],2,'Restore test Inventory Staff');
select public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000020','cashier','active',false,array[test.id('branch_a')],1,'Removed second branch assignment');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000007',true);
select test.assert(exists(select 1 from public.organization_memberships where id='30000000-0000-4000-8000-000000000020'),'Scoped Admin can read employee after legitimate move into sole scope');
select test.assert(not exists(select 1 from public.audit_logs where entity_id='30000000-0000-4000-8000-000000000020' and entity='organization_memberships'),'Audit keeps complete historical branch snapshot despite current target reassignment');
select test.assert(not exists(select 1 from jsonb_array_elements(public.list_audit_logs(test.id('org_a'))) e where e->>'entity_id'='30000000-0000-4000-8000-000000000020'),'Audit RPC cannot bypass historical security scope');
select test.assert(not exists(select 1 from public.audit_logs where entity_id='30000000-0000-4000-8000-000000000005' and action='employee.access_changed'),'Scoped Admin cannot inspect earlier Admin-target role changes');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000010',true);
select test.assert(exists(select 1 from public.audit_logs where entity_id='30000000-0000-4000-8000-000000000020' and action='employee.access_changed'),'Explicit all-branch Admin can inspect complete security snapshot');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.change_employee_access(test.id('org_a'),'30000000-0000-4000-8000-000000000020','cashier','active',false,array[test.id('branch_a'),'20000000-0000-4000-8000-000000000002'::uuid],2,'Restore multi-branch test employee');
select test.expect_error('select public.list_audit_logs(test.id(''org_a''),p_limit=>1000)','22023','Audit query refuses unbounded page');
select test.expect_error('select public.list_audit_logs(test.id(''org_a''),p_branch_id=>test.id(''branch_b''))','42501','Audit query refuses foreign branch');
select test.assert(not has_function_privilege('anon','public.save_product(uuid,uuid,bigint,jsonb,text)','execute'),'Phase 2 revokes anonymous default RPC execution');
select test.assert(not has_function_privilege('authenticated','private.write_management_record(text,uuid,uuid,bigint,jsonb,text)','execute'),'Generic privileged writer stays private');
select test.assert(not has_function_privilege('authenticated','private.append_action_audit(uuid,text,text,uuid,uuid,text,jsonb)','execute'),'Client cannot forge action audit');
select test.assert((select bool_and(proconfig @> array['search_path=""']) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.prosecdef),'All Phase 2 definers fix search_path');
select test.expect_error('update public.financial_events set payload=''{}''','42501','Phase 2 preserves financial history write denial');
select test.expect_error('delete from public.audit_logs','42501','Phase 2 preserves audit immutability');
reset role;
select test.expect_error($q$update public.organization_memberships set status='disabled' where id=test.id('owner_membership_a')$q$,'23514','Owner cannot be disabled even through ordinary privileged write');

-- An audit failure must roll back record creation, not leave an unaudited row.
create function test.reject_phase2_audit() returns trigger language plpgsql as $$
begin
  if new.reason='Deliberate phase two audit failure' then raise exception 'Deliberate audit failure' using errcode='23514'; end if;
  return new;
end $$;
create trigger test_phase2_audit_failure before insert on public.audit_logs for each row execute function test.reject_phase2_audit();
set local role authenticated;
select test.expect_error($q$select public.save_category(test.id('org_a'),null,null,'{"name":"Atomic Phase Two Category"}','Deliberate phase two audit failure')$q$,'22023','Management propagates audit failure');
select test.assert(not exists(select 1 from public.categories where name='Atomic Phase Two Category'),'Failed management action rolls back the entire record');
reset role;
drop trigger test_phase2_audit_failure on public.audit_logs;
drop function test.reject_phase2_audit();
commit;
