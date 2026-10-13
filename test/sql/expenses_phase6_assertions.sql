\set ON_ERROR_STOP on
begin;
-- Fresh isolated tenant: no assumptions about earlier test cash/settings/grants.
insert into auth.users(id,email,email_confirmed_at) values
 ('6e000000-0000-4000-8000-000000000001','expense-owner@example.invalid',now()),
 ('6e000000-0000-4000-8000-000000000002','expense-manager@example.invalid',now()),
 ('6e000000-0000-4000-8000-000000000003','expense-cashier@example.invalid',now()),
 ('6e000000-0000-4000-8000-000000000004','expense-stock@example.invalid',now()),
 ('6e000000-0000-4000-8000-000000000005','expense-other-owner@example.invalid',now()),
 ('6e000000-0000-4000-8000-000000000006','expense-scoped-admin@example.invalid',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','6e000000-0000-4000-8000-000000000001',true);
select set_config('test.exp_org',organization_id::text,true),set_config('test.exp_branch',branch_id::text,true) from public.bootstrap_organization('Expense Shop','Expense Owner');
reset role;
insert into public.branches(id,organization_id,name,code) values ('6e100000-0000-4000-8000-000000000002',test.id('exp_org'),'Expense second branch','EX-SECOND');
insert into public.organization_memberships(id,organization_id,user_id,role,status,all_branches)
select ('6e200000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,test.id('exp_org'),('6e000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 case n when 2 then 'manager' when 3 then 'cashier' when 4 then 'inventory_staff' else 'admin' end,'active',false from generate_series(2,6) n where n<>5;
insert into public.membership_branches(membership_id,organization_id,branch_id)
select id,organization_id,test.id('exp_branch') from public.organization_memberships where organization_id=test.id('exp_org') and user_id in ('6e000000-0000-4000-8000-000000000002','6e000000-0000-4000-8000-000000000003','6e000000-0000-4000-8000-000000000004','6e000000-0000-4000-8000-000000000006');
create function test.exp_record(p_request uuid,p_amount bigint,p_source text default 'external',p_shift uuid default null,p_method text default 'cash',p_confirmed boolean default true,p_reference text default null,
 p_revision bigint default 1,p_currency text default 'PHP',p_category text default 'other',p_reason text default 'Operator confirmed expense evidence')
returns jsonb language sql as $$ select public.record_expense(test.id('exp_org'),test.id('exp_branch'),p_request,p_revision,p_currency,p_amount,p_category,p_source,p_shift,p_method,p_confirmed,null,p_reference,p_reason); $$;
create function test.exp_reverse(p_expense uuid,p_request uuid,p_confirmed boolean default true,p_reference text default null,p_reason text default 'Confirmed full expense correction')
returns jsonb language sql as $$ select public.reverse_expense(test.id('exp_org'),test.id('exp_branch'),p_request,p_expense,p_confirmed,p_reference,p_reason); $$;
grant execute on function test.exp_record(uuid,bigint,text,uuid,text,boolean,text,bigint,text,text,text),test.exp_reverse(uuid,uuid,boolean,text,text) to authenticated,anon,service_role;
set local role authenticated;
select test.assert(public.get_expense_context(test.id('exp_org'),test.id('exp_branch'))->'own_open_shift'='null'::jsonb,'Expense context starts without fabricated own drawer');
select test.assert(public.list_expenses(test.id('exp_org'),test.id('exp_branch'))='[]'::jsonb,'Authorized actual empty expense list is empty');
select set_config('test.exp_shift',(public.open_shift(test.id('exp_org'),test.id('exp_branch'),'6e300000-0000-4000-8000-000000000001',1000,'PHP')->>'id'),true);
select test.assert((public.get_expense_context(test.id('exp_org'),test.id('exp_branch'))->'own_open_shift'->>'expected_cash_minor')::bigint=1000,'Expense context returns actual own open shift projection');
select set_config('test.exp_external',(test.exp_record('6e300000-0000-4000-8000-000000000002',250)->'expense'->>'id'),true);
select test.assert((public.get_current_shift(test.id('exp_org'),test.id('exp_branch'))->>'expected_cash_minor')::bigint=1000,'Externally funded cash never reduces POS drawer cash');
select test.assert((test.exp_record('6e300000-0000-4000-8000-000000000002',250)->'expense'->>'id')::uuid=test.id('exp_external'),'External expense stable UUID returns exact original document');
select test.assert((public.get_expense(test.id('exp_org'),test.id('exp_branch'),test.id('exp_external'))->>'request_id')='6e300000-0000-4000-8000-000000000002','Expense read carries server-derived accepted request identity');
select test.expect_error($q$select test.exp_record('6e300000-0000-4000-8000-000000000002',251)$q$,'23505','Changed expense details cannot reuse a request UUID');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),0)$q$,'22023','Zero expense amount is rejected');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),-1)$q$,'22023','Negative expense amount is rejected');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),9007199254740992)$q$,'22023','Unsafe JSON integer expense is rejected');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),100,p_confirmed=>false)$q$,'22023','Manual payment confirmation cannot be inferred');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),100,p_confirmed=>null)$q$,'22023','Null manual evidence cannot authorize an expense');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),100,p_method=>'card')$q$,'22023','Noncash expense requires an actual manual reference');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),100,p_method=>'card',p_reference=>'xx')$q$,'22023','Noncash reference has meaningful minimum length');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),100,p_source=>'invented')$q$,'22023','Unknown payout source is rejected');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),100,p_source=>'external',p_shift=>test.id('exp_shift'))$q$,'22023','External payment cannot carry a drawer shift');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),100,p_source=>'cash_drawer')$q$,'22023','Drawer payment requires an explicit shift');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),100,p_source=>'cash_drawer',p_shift=>test.id('exp_shift'),p_method=>'card',p_reference=>'Verified noncash ref')$q$,'22023','A drawer payout must be cash');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),100,p_category=>'provider_payout')$q$,'22023','Unsupported category is rejected');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),100,p_reason=>' ')$q$,'22023','Expense reason must be meaningful');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),100,p_revision=>2)$q$,'40001','New expense rejects stale settings CAS');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),100,p_currency=>'USD')$q$,'40001','New expense refuses changed expected currency');
select set_config('test.exp_card',(test.exp_record('6e300000-0000-4000-8000-000000000003',125,p_method=>'card',p_reference=>'Bank statement reference')->'expense'->>'id'),true);
select test.assert((public.get_expense(test.id('exp_org'),test.id('exp_branch'),test.id('exp_card'))->>'manual_confirmed')::boolean,'Card expense retains manual evidence without claiming provider delivery');
select set_config('test.exp_drawer',(test.exp_record('6e300000-0000-4000-8000-000000000004',300,'cash_drawer',test.id('exp_shift'))->'expense'->>'id'),true);
select set_config('test.exp_fixture_context',public.get_expense_context(test.id('exp_org'),test.id('exp_branch'))::text,true);
select test.assert((public.get_current_shift(test.id('exp_org'),test.id('exp_branch'))->>'expected_cash_minor')::bigint=700,'Confirmed own cash expense reduces immutable derived drawer cash');
select test.expect_error($q$select test.exp_reverse(test.id('exp_drawer'),gen_random_uuid(),false)$q$,'22023','Drawer reversal requires actual returned-cash confirmation');
select set_config('test.exp_drawer_reverse',(test.exp_reverse(test.id('exp_drawer'),'6e300000-0000-4000-8000-000000000005')->'reversal'->>'id'),true);
select set_config('test.exp_fixture_record',test.exp_record('6e300000-0000-4000-8000-000000000004',300,'cash_drawer',test.id('exp_shift'))::text,true);
select set_config('test.exp_fixture_reversal',test.exp_reverse(test.id('exp_drawer'),'6e300000-0000-4000-8000-000000000005')::text,true);
select set_config('test.exp_fixture_current',public.get_expense(test.id('exp_org'),test.id('exp_branch'),test.id('exp_drawer'))::text,true);
set local time zone 'Asia/Manila';
select test.assert(test.exp_record('6e300000-0000-4000-8000-000000000004',300,'cash_drawer',test.id('exp_shift'))=current_setting('test.exp_fixture_record')::jsonb,'Expense action replay retains exact UTC timestamps under Asia Manila session timezone');
select test.assert(test.exp_reverse(test.id('exp_drawer'),'6e300000-0000-4000-8000-000000000005')=current_setting('test.exp_fixture_reversal')::jsonb,'Expense reversal replay retains exact UTC timestamps under Asia Manila session timezone');
select test.assert(public.get_expense(test.id('exp_org'),test.id('exp_branch'),test.id('exp_drawer'))=current_setting('test.exp_fixture_current')::jsonb,'Current expense and nested reversal timestamps stay UTC under Asia Manila session timezone');
select test.assert(public.get_expense_context(test.id('exp_org'),test.id('exp_branch'))->'own_open_shift'->>'opened_at'=current_setting('test.exp_fixture_context')::jsonb->'own_open_shift'->>'opened_at','Own drawer opened time stays UTC under Asia Manila session timezone');
select test.assert((public.list_expenses(test.id('exp_org'),test.id('exp_branch'))->0->>'occurred_at') like '%Z','Expense list emits explicit UTC timestamps under Asia Manila session timezone');
set local time zone 'UTC';
select test.assert((public.get_current_shift(test.id('exp_org'),test.id('exp_branch'))->>'expected_cash_minor')::bigint=1000,'Full drawer reversal restores original exact cash amount');
select test.assert((test.exp_reverse(test.id('exp_drawer'),'6e300000-0000-4000-8000-000000000005')->'reversal'->>'id')::uuid=test.id('exp_drawer_reverse'),'Reversal retry does not return cash twice');
select test.expect_error($q$select test.exp_reverse(test.id('exp_drawer'),gen_random_uuid())$q$,'23505','Different UUID cannot reverse an expense twice');
select test.assert(public.get_expense(test.id('exp_org'),test.id('exp_branch'),test.id('exp_drawer'))->'reversal'->>'id'=test.id('exp_drawer_reverse')::text,'Current detail exposes original plus full compensation');
select test.assert(test.exp_record('6e300000-0000-4000-8000-000000000004',300,'cash_drawer',test.id('exp_shift'))->'expense'->'reversal'='null'::jsonb,'Record action replay remains original immutable snapshot after reversal');
select test.assert((public.get_expense(test.id('exp_org'),test.id('exp_branch'),test.id('exp_drawer'))->>'amount_minor')::bigint=300,'Original expense amount never changes after compensation');
select set_config('test.exp_external_reverse',(test.exp_reverse(test.id('exp_external'),'6e300000-0000-4000-8000-000000000006')->'reversal'->>'id'),true);
select test.assert((public.get_current_shift(test.id('exp_org'),test.id('exp_branch'))->>'expected_cash_minor')::bigint=1000,'External correction never invents returned POS drawer cash');
select test.expect_error($q$select public.list_expenses(test.id('exp_org'),test.id('exp_branch'),now(),now())$q$,'22023','Expense time interval is half-open and must be ordered');
select test.expect_error($q$select public.list_expenses(test.id('exp_org'),test.id('exp_branch'),p_from=>now())$q$,'22023','One-sided expense time window is rejected');
select test.expect_error($q$select public.list_expenses(test.id('exp_org'),test.id('exp_branch'),now()-interval '367 days',now())$q$,'22023','Expense time windows are bounded to 366 days');
select test.expect_error($q$select public.list_expenses(test.id('exp_org'),test.id('exp_branch'),'-infinity'::timestamptz,now())$q$,'22023','Expense time windows require finite instants');
select test.assert(jsonb_array_length(public.list_expenses(test.id('exp_org'),test.id('exp_branch'),now()-interval '365 days',now()+interval '1 day'))=3,'366-day expense window boundary is accepted');
select test.expect_error($q$select public.list_expenses(test.id('exp_org'),test.id('exp_branch'),p_limit=>102)$q$,'22023','Expense paging enforces maximum bounded limit');
select test.expect_error($q$select public.list_expenses(test.id('exp_org'),test.id('exp_branch'),p_offset=>-1)$q$,'22023','Expense paging rejects negative offset');
select test.assert(jsonb_array_length(public.list_expenses(test.id('exp_org'),test.id('exp_branch'),p_limit=>1))=1,'Expense list is bounded with stable document ordering');
select test.assert(jsonb_array_length(public.list_expenses(test.id('exp_org'),test.id('exp_branch'),p_category=>'rent'))=0,'Category filter does not fabricate unrelated records');
select test.assert(jsonb_array_length(public.list_audit_logs(test.id('exp_org'),p_entity=>'expenses',p_branch_id=>test.id('exp_branch')))=3,'Owner sees source-backed expense audit records');
-- Manager can record/inspect current branch, but cannot use another actor drawer.
select set_config('request.jwt.claim.sub','6e000000-0000-4000-8000-000000000002',true);
select test.assert((select count(*) from public.expenses)=3,'Manager direct RLS reads retain authorized branch expense history');
select test.assert(jsonb_array_length(public.list_audit_logs(test.id('exp_org'),p_entity=>'expenses',p_branch_id=>test.id('exp_branch')))=3,'Manager audit wrapper exposes exact operational expense pairs');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),100,'cash_drawer',test.id('exp_shift'))$q$,'42501','Manager cannot payout from owner drawer');
select set_config('test.exp_manager_shift',(public.open_shift(test.id('exp_org'),test.id('exp_branch'),'6e300000-0000-4000-8000-000000000007',0,'PHP')->>'id'),true);
select set_config('test.exp_negative_drawer',(test.exp_record('6e300000-0000-4000-8000-000000000008',200,'cash_drawer',test.id('exp_manager_shift'))->'expense'->>'id'),true);
select test.assert((public.get_current_shift(test.id('exp_org'),test.id('exp_branch'))->>'expected_cash_minor')::bigint=-200,'Expected cash is a projection; confirmation does not invent positive-cash availability rule');
select set_config('request.jwt.claim.sub','6e000000-0000-4000-8000-000000000001',true);
select test.expect_error($q$select test.exp_reverse(test.id('exp_negative_drawer'),gen_random_uuid())$q$,'42501','Owner cannot claim cash returned to manager original drawer');
select set_config('request.jwt.claim.sub','6e000000-0000-4000-8000-000000000003',true);
select test.expect_error($q$select test.exp_record(gen_random_uuid(),100)$q$,'42501','Cashier expense authoring is denied');
select test.expect_error($q$select public.get_expense_context(test.id('exp_org'),test.id('exp_branch'))$q$,'42501','Cashier cannot inspect manager expense context');
select test.assert((select count(*) from public.expenses)=0,'Cashier cannot bypass expense RPC through table reads');
select set_config('request.jwt.claim.sub','6e000000-0000-4000-8000-000000000004',true);
select test.expect_error($q$select test.exp_record(gen_random_uuid(),100)$q$,'42501','Inventory staff cannot record business expense');
select test.assert((select count(*) from public.expense_reversals)=0,'Inventory staff cannot directly inspect financial expense reversals');
select set_config('request.jwt.claim.sub','6e000000-0000-4000-8000-000000000006',true);
select test.assert((select count(*) from public.expenses)=4,'Scoped Admin may inspect assigned branch expense history');
select test.expect_error($q$select public.get_expense_context(test.id('exp_org'),'6e100000-0000-4000-8000-000000000002')$q$,'42501','Scoped Admin expense access cannot cross branch');
select set_config('request.jwt.claim.sub','6e000000-0000-4000-8000-000000000005',true);
select * from public.bootstrap_organization('Expense Foreign Shop','Foreign Owner');
select test.expect_error($q$select public.get_expense(test.id('exp_org'),test.id('exp_branch'),test.id('exp_drawer'))$q$,'42501','Foreign tenant cannot inspect an expense by known ID');
select test.assert((select count(*) from public.expenses)=0,'Expense direct RLS refuses foreign tenant');
reset role;
-- Direct writes and immutable history remain closed even to service/maintenance.
set local role authenticated;
select test.expect_error($q$insert into public.expenses default values$q$,'42501','Authenticated clients cannot insert expense history directly');
reset role;
set local role service_role;
select test.expect_error($q$select * from public.expenses$q$,'42501','Service role has no direct expense history access');
select test.expect_error($q$select public.get_expense_context(test.id('exp_org'),test.id('exp_branch'))$q$,'42501','Service role cannot call authenticated expense context boundary');
reset role;
select test.expect_error($q$update public.expenses set amount_minor=1$q$,'42501','Original expense updates are denied by immutable trigger');
select test.expect_error($q$delete from public.expense_reversals$q$,'42501','Expense reversal deletion is denied');
select test.expect_error($q$truncate public.expenses,public.expense_reversals$q$,'42501','Expense history cannot be truncated');
select test.assert(not has_function_privilege('anon','public.record_expense(uuid,uuid,uuid,bigint,text,bigint,text,text,uuid,text,boolean,text,text,text)','EXECUTE'),'Anonymous expense execution revoked');
select test.assert(not has_function_privilege('authenticated','private.phase6_expense_json(uuid,boolean)','EXECUTE'),'Private expense serializer is not an alternate public boundary');
-- Current MFA and membership are required even before accepted replay.
insert into private.security_policies(organization_id,revision,idle_lock_minutes,require_privileged_mfa) values(test.id('exp_org'),1,5,true);
set local role authenticated;
select set_config('request.jwt.claim.sub','6e000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"6e000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select test.expect_error($q$select test.exp_record('6e300000-0000-4000-8000-000000000002',250)$q$,'42501','Accepted expense replay still requires current privileged MFA');
select test.assert((select count(*) from public.expenses)=0,'Expense restrictive RLS enforces privileged MFA');
select set_config('request.jwt.claims','{"sub":"6e000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
select test.assert((test.exp_record('6e300000-0000-4000-8000-000000000002',250)->'expense'->>'id')::uuid=test.id('exp_external'),'Verified MFA session can recover original accepted expense');
reset role;
update private.security_policies set require_privileged_mfa=false where organization_id=test.id('exp_org');
-- Audit failure must roll back original, request mapping and drawer projection.
create function test.reject_expense_audit() returns trigger language plpgsql as $$begin if new.reason='Deliberate phase six expense audit failure' then raise exception 'Expense audit fixture rollback' using errcode='23514';end if;return new;end;$$;
create trigger reject_expense_audit before insert on public.audit_logs for each row execute function test.reject_expense_audit();
set local role authenticated;
select test.expect_error($q$select test.exp_record('6e300000-0000-4000-8000-000000000009',50,'cash_drawer',test.id('exp_shift'),p_reason=>'Deliberate phase six expense audit failure')$q$,'23514','Expense and drawer effect roll back if audit append fails');
select test.assert((public.get_current_shift(test.id('exp_org'),test.id('exp_branch'))->>'expected_cash_minor')::bigint=1000,'Failed audit leaves actual drawer expectation unchanged');
reset role;
select test.assert(not exists(select 1 from private.operation_requests where request_id='6e300000-0000-4000-8000-000000000009'),'Failed expense has no accepted request mapping');
drop trigger reject_expense_audit on public.audit_logs;
drop function test.reject_expense_audit();
-- A new payout remains frozen in its original closure. Replays recover original.
set local role authenticated;
select set_config('test.exp_closed_drawer',(test.exp_record('6e300000-0000-4000-8000-000000000010',100,'cash_drawer',test.id('exp_shift'))->'expense'->>'id'),true);
select test.assert((public.close_shift(test.id('exp_org'),test.id('exp_shift'),'6e300000-0000-4000-8000-000000000011',900,'Count actual expense drawer')->'closure'->>'expected_cash_minor')::bigint=900,'Closure captures original expense-reduced expected cash');
select test.expect_error($q$select test.exp_reverse(test.id('exp_closed_drawer'),gen_random_uuid())$q$,'40001','New physical cash reversal after original drawer close is denied');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),10,'cash_drawer',test.id('exp_shift'))$q$,'40001','New payout cannot alter a closed shift');
select test.assert((test.exp_record('6e300000-0000-4000-8000-000000000010',100,'cash_drawer',test.id('exp_shift'))->'expense'->>'id')::uuid=test.id('exp_closed_drawer'),'Accepted payout replay succeeds after original drawer close');
select test.assert((test.exp_reverse(test.id('exp_drawer'),'6e300000-0000-4000-8000-000000000005')->'reversal'->>'id')::uuid=test.id('exp_drawer_reverse'),'Accepted reversal replay succeeds after original drawer close');
select public.save_business_settings(test.id('exp_org'),1,'{"currency":"USD"}','Changed expense business currency');
select test.assert((test.exp_record('6e300000-0000-4000-8000-000000000010',100,'cash_drawer',test.id('exp_shift'))->'expense'->>'currency')='PHP','Replay returns original currency after settings changed');
select test.expect_error($q$select test.exp_record(gen_random_uuid(),10)$q$,'40001','New external expense must honor current currency/settings');
select public.save_business_settings(test.id('exp_org'),2,'{"currency":"PHP"}','Restore expense report fixture currency');
reset role;
select test.assert((select expected_cash_minor from public.shift_closures where shift_id=test.id('exp_shift'))=900,'Expense reversal denial cannot rewrite original shift closure');
-- Exact signed bounds are enforced before committing a paid record.
set local role authenticated;
select set_config('test.exp_bound_shift',(public.open_shift(test.id('exp_org'),test.id('exp_branch'),'6e300000-0000-4000-8000-000000000012',0,'PHP')->>'id'),true);
select set_config('test.exp_max',(test.exp_record('6e300000-0000-4000-8000-000000000013',9007199254740991,'cash_drawer',test.id('exp_bound_shift'),p_revision=>3)->'expense'->>'id'),true);
select test.assert((public.get_current_shift(test.id('exp_org'),test.id('exp_branch'))->>'expected_cash_minor')::bigint=-9007199254740991,'Maximum exact negative drawer projection is represented as integer');
select test.expect_error($q$select test.exp_record('6e300000-0000-4000-8000-000000000014',1,'cash_drawer',test.id('exp_bound_shift'),p_revision=>3)$q$,'22023','Expense beyond negative exact-cash bound rolls back');
select test.exp_reverse(test.id('exp_max'),'6e300000-0000-4000-8000-000000000015');
select test.assert((public.get_current_shift(test.id('exp_org'),test.id('exp_branch'))->>'expected_cash_minor')::bigint=0,'Maximum full compensation returns exact drawer projection to zero');
select set_config('test.exp_short_reference',(test.exp_record('6e300000-0000-4000-8000-000000000017',1,p_reference=>'x',p_revision=>3)->'expense'->>'id'),true);
select test.assert(public.get_expense(test.id('exp_org'),test.id('exp_branch'),test.id('exp_short_reference'))->>'reference'='x','Cash expense permits a one-character optional note/reference');
select test.assert(test.exp_reverse(test.id('exp_short_reference'),'6e300000-0000-4000-8000-000000000018',p_reference=>'r')->'reversal'->>'reference'='r','Full reversal permits one-character optional reference');
select public.close_shift(test.id('exp_org'),test.id('exp_bound_shift'),'6e300000-0000-4000-8000-000000000016',0,'Closed exact-limit expense fixture');
reset role;
select test.assert(not exists(select 1 from private.operation_requests where request_id='6e300000-0000-4000-8000-000000000014'),'Overflow expense leaves no accepted request');
select test.assert((select count(*) from public.audit_logs where action='expense.recorded' and entity_id=test.id('exp_closed_drawer'))=1,'Accepted replay appends one expense audit only');
select test.assert((select count(*) from public.audit_logs where action='expense.reversed' and entity_id=test.id('exp_drawer_reverse'))=1,'Accepted compensation replay appends one audit only');
-- Cash-sales/refunds and expense effects share the same existing projection.
set local role authenticated;
select set_config('test.exp_math_shift',(public.open_shift(test.id('exp_org'),test.id('exp_branch'),'6e300000-0000-4000-8000-000000000019',1000,'PHP')->>'id'),true);
select set_config('test.exp_math_product',(public.save_product(test.id('exp_org'),null,null,'{"name":"Expense cash projection product","sku":"EXP-CASH-PROJECTION","price_minor":100}','Expense cash projection fixture')->>'id'),true);
select public.receive_stock(test.id('exp_org'),test.id('exp_branch'),'6e300000-0000-4000-8000-000000000020',jsonb_build_array(jsonb_build_object('product_id',test.id('exp_math_product'),'quantity',2,'expected_revision',1)),null,null,'Received expense math fixture stock');
select set_config('test.exp_math_sale',(public.checkout_sale(test.id('exp_org'),test.id('exp_branch'),'6e300000-0000-4000-8000-000000000021',jsonb_build_object('shift_id',test.id('exp_math_shift'),'expected_settings_revision',3,'items',jsonb_build_array(jsonb_build_object('product_id',test.id('exp_math_product'),'quantity',1,'expected_revision',1)),'discount_minor',0,'payments',jsonb_build_array(jsonb_build_object('method','cash','amount_minor',100,'tendered_minor',100))))->>'id'),true);
select test.assert((public.get_current_shift(test.id('exp_org'),test.id('exp_branch'))->>'expected_cash_minor')::bigint=1100,'Expense cash projection retains original cash sale contribution');
select set_config('test.exp_math_payout',(test.exp_record('6e300000-0000-4000-8000-000000000022',200,'cash_drawer',test.id('exp_math_shift'),p_revision=>3)->'expense'->>'id'),true);
select test.assert((public.get_current_shift(test.id('exp_org'),test.id('exp_branch'))->>'expected_cash_minor')::bigint=900,'Sales and cash payout combine without changing original sale');
select public.reverse_sale(test.id('exp_org'),test.id('exp_math_sale'),'6e300000-0000-4000-8000-000000000023',jsonb_build_object('kind','refund','shift_id',test.id('exp_math_shift'),'reason','Original cash returned without physical product','return_stock',false,
 'items',jsonb_build_array(jsonb_build_object('sale_item_id',(public.get_sale(test.id('exp_org'),test.id('exp_math_sale'))->'items'->0->>'id'),'quantity',1)),
 'payments',jsonb_build_array(jsonb_build_object('original_payment_id',(public.get_sale(test.id('exp_org'),test.id('exp_math_sale'))->'payments'->0->>'id'),'amount_minor',100,'manual_confirmed',true))));
select test.assert((public.get_current_shift(test.id('exp_org'),test.id('exp_branch'))->>'expected_cash_minor')::bigint=800,'Existing cash refund and drawer expense both reduce cash projection');
select test.exp_reverse(test.id('exp_math_payout'),'6e300000-0000-4000-8000-000000000024');
select test.assert((public.close_shift(test.id('exp_org'),test.id('exp_math_shift'),'6e300000-0000-4000-8000-000000000025',1000,'Counted all cash compensation')->'closure'->>'expected_cash_minor')::bigint=1000,'Closure derives opening plus sales minus refunds minus expenses plus expense returns exactly');
reset role;
update public.organization_memberships set status='disabled' where organization_id=test.id('exp_org') and user_id='6e000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','6e000000-0000-4000-8000-000000000002',true);
select test.expect_error($q$select test.exp_record('6e300000-0000-4000-8000-000000000008',200,'cash_drawer',test.id('exp_manager_shift'))$q$,'42501','Disabled membership cannot recover an accepted payout before current authority');
reset role;
update public.organization_memberships set status='active' where organization_id=test.id('exp_org') and user_id='6e000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','6e000000-0000-4000-8000-000000000001',true);
select test.expect_error($q$select test.exp_record(gen_random_uuid(),1,p_reference=>repeat('x',121),p_revision=>3)$q$,'22023','Cash reference cannot exceed 120 characters');
reset role;
-- Save fixture IDs in immutable accepted request rows; concurrency script discovers
-- tenant by the dedicated test owner's verified identity, not prior session GUCs.
\pset tuples_only on
\pset format unaligned
select 'E6_EXPENSE_FIXTURE '||jsonb_build_object('version',1,'context',current_setting('test.exp_fixture_context')::jsonb,'record_action',current_setting('test.exp_fixture_record')::jsonb,'reversal_action',current_setting('test.exp_fixture_reversal')::jsonb,'current_expense',current_setting('test.exp_fixture_current')::jsonb)::text;
\pset tuples_only off
\pset format aligned
commit;
