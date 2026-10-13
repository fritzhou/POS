#!/usr/bin/env bash
# Sourced by the checked disposable SQL harness. SQL-only Auth/proof fixtures;
# no provider or cryptographic Edge success is implied by these transaction races.
set -euo pipefail
psql_admin -d "$database_name" <<'SQL'
begin;
insert into auth.users(id,email,email_confirmed_at) values('6e900000-0000-4000-8000-000000000001','expense-races@example.invalid',now());
set local role authenticated;
set local "request.jwt.claim.sub"='6e900000-0000-4000-8000-000000000001';
select set_config('test.exp_race_org',organization_id::text,true),set_config('test.exp_race_branch',branch_id::text,true) from public.bootstrap_organization('Expense concurrency tenant','Expense race owner');
select set_config('test.exp_race_product',(public.save_product(test.id('exp_race_org'),null,null,'{"name":"Offline expense race product","sku":"EXP-RACE-OFFLINE","price_minor":100}','Real ledger race fixture')->>'id'),true);
select public.receive_stock(test.id('exp_race_org'),test.id('exp_race_branch'),'6e910000-0000-4000-8000-000000000001',jsonb_build_array(jsonb_build_object('product_id',test.id('exp_race_product'),'quantity',10,'expected_revision',1)),null,null,'Actual original offline stock');
select set_config('test.exp_race_shift',(public.open_shift(test.id('exp_race_org'),test.id('exp_race_branch'),'6e910000-0000-4000-8000-000000000002',1000,'PHP')->>'id'),true);
reset role;
create table test.expense_race_context as select test.id('exp_race_org') organization_id,test.id('exp_race_branch') branch_id,test.id('exp_race_product') product_id,test.id('exp_race_shift') shift_id;
create function test.expense_race_record(p_request uuid,p_amount bigint default 100,p_reason text default 'Independent duplicate drawer expense') returns jsonb language sql security definer set search_path='' as $$
 select public.record_expense(organization_id,branch_id,p_request,1,'PHP',p_amount,'other','cash_drawer',shift_id,'cash',true,null,null,p_reason) from test.expense_race_context;
$$;
create function test.expense_race_reverse(p_expense uuid,p_request uuid,p_reason text default 'Independent full cash return') returns jsonb language sql security definer set search_path='' as $$
 select public.reverse_expense(organization_id,branch_id,p_request,p_expense,true,null,p_reason) from test.expense_race_context;
$$;
create function test.expense_race_close(p_request uuid,p_count bigint,p_reason text) returns jsonb language sql security definer set search_path='' as $$
 select public.close_shift(organization_id,shift_id,p_request,p_count,p_reason) from test.expense_race_context;
$$;
create function test.expense_race_audit_hold() returns trigger language plpgsql as $$
begin
 if new.reason='Hold expense payout at audit' then perform pg_advisory_xact_lock(600011);perform pg_sleep(1.2);
 elsif new.reason='Hold expense correction at audit' then perform pg_advisory_xact_lock(600012);perform pg_sleep(1.2);
 elsif new.reason='Hold expense close at audit' then perform pg_advisory_xact_lock(600013);perform pg_sleep(1.2);
 elsif new.reason='Hold expense payout before offline ingest' then perform pg_advisory_xact_lock(600014);perform pg_sleep(1.2);end if;
 return new;
end;$$;
create trigger expense_race_audit_hold before insert on public.audit_logs for each row execute function test.expense_race_audit_hold();
commit;
SQL

# Wait on an actual transaction marker, not an assumed transport start time.
expense_wait_marker() {
 local marker="$1" seen=false
 for attempt in {1..80}; do
  if [[ "$(psql_admin -Atq -d "$database_name" -c "select exists(select 1 from pg_locks where locktype='advisory' and objid=$marker and granted)")" == t ]]; then seen=true;break;fi
  sleep 0.02
 done
 if [[ "$seen" != true ]];then echo 'Expense race did not reach its authoritative held transaction marker.' >&2;return 1;fi
}
expense_actor_sql() {
 psql_admin -Atq -d "$database_name" <<SQL
\set VERBOSITY verbose
begin;
set local statement_timeout='8s';
set local role authenticated;
set local "request.jwt.claim.sub"='6e900000-0000-4000-8000-000000000001';
$1
commit;
SQL
}

# Two transports of one actor/request must return the same immutable action.
pids=()
for index in 1 2;do
 expense_actor_sql "select test.expense_race_record('6e910000-0000-4000-8000-000000000003');" > "$result_dir/expense.same.$index.out" 2> "$result_dir/expense.same.$index.err" &
 pids+=("$!")
done
for pid in "${pids[@]}";do wait "$pid";done
expense_id="$(python3 - "$result_dir" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]);a,b=[json.loads((p/f'expense.same.{n}.out').read_text()) for n in (1,2)]
assert a==b and a['expense']['amount_minor']==100
print(a['expense']['id'])
PY
)"
if [[ ! "$expense_id" =~ ^[0-9a-f-]{36}$ ]];then echo 'Expense race result ID invalid.' >&2;exit 1;fi
psql_admin -d "$database_name" <<'SQL'
select test.assert((select count(*) from private.operation_requests where request_id='6e910000-0000-4000-8000-000000000003')=1,'Duplicate expense transports commit one request mapping');
select test.assert((select count(*) from public.expenses where organization_id=(select organization_id from test.expense_race_context))=1,'Duplicate expense transports append one actual payout');
select test.assert(private.phase3_expected_cash((select shift_id from test.expense_race_context))=900,'Duplicate expense transports affect derived drawer once');
SQL

# Different request IDs cannot both append the single full compensation.
pids=()
for index in 1 2;do
 (
  if expense_actor_sql "select test.expense_race_reverse('$expense_id','6e920000-0000-4000-8000-00000000000$index');" > "$result_dir/expense.reverse.$index.out" 2> "$result_dir/expense.reverse.$index.err";then printf '0' > "$result_dir/expense.reverse.$index.status";else printf '%s' "$?" > "$result_dir/expense.reverse.$index.status";fi
 ) &
 pids+=("$!")
done
for pid in "${pids[@]}";do wait "$pid";done
python3 - "$result_dir" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]);statuses=[(p/f'expense.reverse.{n}.status').read_text() for n in (1,2)]
errors=[(p/f'expense.reverse.{n}.err').read_text() for n in (1,2)]
assert sorted(statuses)==['0','3'] and sum('23505:' in e for e in errors)==1
PY
psql_admin -d "$database_name" <<SQL
select test.assert((select count(*) from public.expense_reversals where expense_id='$expense_id')=1,'Competing reversal UUIDs commit one full return');
select test.assert(private.phase3_expected_cash((select shift_id from test.expense_race_context))=1000,'Competing compensation restores original cash once');
SQL

# The paid insert is uncommitted when close starts; the common shift lock forces
# close to include the committed payout rather than freeze stale expected cash.
expense_actor_sql "select test.expense_race_record('6e910000-0000-4000-8000-000000000004',200,'Hold expense payout at audit');" > "$result_dir/expense.payout-close.out" 2> "$result_dir/expense.payout-close.err" &
expense_writer_pid=$!
expense_wait_marker 600011
expense_actor_sql "select test.expense_race_close('6e910000-0000-4000-8000-000000000005',800,'Close after concurrent actual payout');" > "$result_dir/expense.close-payout.out" 2> "$result_dir/expense.close-payout.err" &
expense_close_pid=$!
wait "$expense_writer_pid" "$expense_close_pid"
psql_admin -d "$database_name" <<'SQL'
select test.assert((select expected_cash_minor from public.shift_closures where shift_id=(select shift_id from test.expense_race_context))=800,'Close waits for in-flight payout and freezes reduced expected cash');
SQL

# Open a fresh own drawer, record a payout, then race its actual return vs close.
psql_admin -Atq -d "$database_name" > "$result_dir/expense.return.fixture" <<'SQL'
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='6e900000-0000-4000-8000-000000000001';
select set_config('test.exp_new_shift',(public.open_shift(organization_id,branch_id,'6e910000-0000-4000-8000-000000000006',1000,'PHP')->>'id'),true) from test.expense_race_context;
reset role;
update test.expense_race_context set shift_id=test.id('exp_new_shift');
set local role authenticated;
select test.expense_race_record('6e910000-0000-4000-8000-000000000007');
commit;
SQL
return_expense="$(psql_admin -Atq -d "$database_name" -c "select result_id from private.operation_requests where request_id='6e910000-0000-4000-8000-000000000007'")"
expense_actor_sql "select test.expense_race_reverse('$return_expense','6e910000-0000-4000-8000-000000000008','Hold expense correction at audit');" > "$result_dir/expense.return-close.out" 2> "$result_dir/expense.return-close.err" &
expense_writer_pid=$!
expense_wait_marker 600012
expense_actor_sql "select test.expense_race_close('6e910000-0000-4000-8000-000000000009',1000,'Close after concurrent actual return');" > "$result_dir/expense.close-return.out" 2> "$result_dir/expense.close-return.err" &
expense_close_pid=$!
wait "$expense_writer_pid" "$expense_close_pid"
psql_admin -d "$database_name" <<'SQL'
select test.assert((select expected_cash_minor from public.shift_closures where shift_id=(select shift_id from test.expense_race_context))=1000,'Close waits for full cash return and freezes restored cash');
SQL

# Reverse begins while close has already inserted its uncommitted closure.
# It must wait and then deny new physical-return history for a closed drawer.
psql_admin -Atq -d "$database_name" > "$result_dir/expense.closed.fixture" <<'SQL'
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='6e900000-0000-4000-8000-000000000001';
select set_config('test.exp_new_shift',(public.open_shift(organization_id,branch_id,'6e910000-0000-4000-8000-000000000010',1000,'PHP')->>'id'),true) from test.expense_race_context;
reset role;
update test.expense_race_context set shift_id=test.id('exp_new_shift');
set local role authenticated;
select test.expense_race_record('6e910000-0000-4000-8000-000000000011');
commit;
SQL
closed_expense="$(psql_admin -Atq -d "$database_name" -c "select result_id from private.operation_requests where request_id='6e910000-0000-4000-8000-000000000011'")"
expense_actor_sql "select test.expense_race_close('6e910000-0000-4000-8000-000000000012',900,'Hold expense close at audit');" > "$result_dir/expense.close-first.out" 2> "$result_dir/expense.close-first.err" &
expense_close_pid=$!
expense_wait_marker 600013
# A new payout also begins while close still holds the same drawer row. Its
# failure must append no expense, request mapping or audit after the close wins.
(
 if expense_actor_sql "select test.expense_race_record('6e910000-0000-4000-8000-000000000016',10,'New payout races already held drawer close');" > "$result_dir/expense.payout-after-close.out" 2> "$result_dir/expense.payout-after-close.err";then
  printf '0' > "$result_dir/expense.payout-after-close.status"
 else
  printf '%s' "$?" > "$result_dir/expense.payout-after-close.status"
 fi
) &
expense_record_pid=$!
expense_record_blocked=false
for attempt in {1..80};do
 if [[ "$(psql_admin -Atq -d "$database_name" -c "select exists(select 1 from pg_stat_activity a where a.pid<>pg_backend_pid() and a.state='active' and a.wait_event_type='Lock' and strpos(a.query,'6e910000-0000-4000-8000-000000000016')>0 and cardinality(pg_blocking_pids(a.pid))>0)")" == t ]];then expense_record_blocked=true;break;fi
 sleep 0.01
done
if [[ "$expense_record_blocked" != true ]];then echo 'Close-first payout did not contend on the held drawer transaction.' >&2;exit 1;fi
if expense_actor_sql "select test.expense_race_reverse('$closed_expense','6e910000-0000-4000-8000-000000000013');" > "$result_dir/expense.return-after-close.out" 2> "$result_dir/expense.return-after-close.err";then
 echo 'A new expense reversal committed after the original shift closed.' >&2;exit 1
fi
wait "$expense_close_pid" "$expense_record_pid"
python3 - "$result_dir" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])
assert '40001:' in (p/'expense.return-after-close.err').read_text()
assert (p/'expense.payout-after-close.status').read_text()=='3'
assert '40001:' in (p/'expense.payout-after-close.err').read_text()
PY
psql_admin -d "$database_name" <<SQL
select test.assert(not exists(select 1 from public.expense_reversals where expense_id='$closed_expense'),'Losing reversal race never rewrites closed cash history');
select test.assert(not exists(select 1 from private.operation_requests where request_id='6e910000-0000-4000-8000-000000000016'),'Losing payout race has no accepted request mapping');
select test.assert((select count(*) from public.expenses where shift_id=(select shift_id from test.expense_race_context))=1,'Losing payout race appends no new expense to the original closed drawer');
select test.assert(not exists(select 1 from public.audit_logs where organization_id=(select organization_id from test.expense_race_context) and reason='New payout races already held drawer close'),'Losing payout race appends no expense audit');
select test.assert((select expected_cash_minor from public.shift_closures where shift_id=(select shift_id from test.expense_race_context))=900,'Close-winning race retains the original actual payout');
SQL

# Own drawer expense vs source-backed paid offline ingestion. Ingest holds the
# offline organization counter before waiting on the same shift row; payout
# must finish without ever trying to acquire that counter after its shift lock.
psql_admin -d "$database_name" <<'SQL'
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='6e900000-0000-4000-8000-000000000001';
select set_config('test.exp_new_shift',(public.open_shift(organization_id,branch_id,'6e910000-0000-4000-8000-000000000014',1000,'PHP')->>'id'),true) from test.expense_race_context;
reset role;
update test.expense_race_context set shift_id=test.id('exp_new_shift');
set local role authenticated;
select set_config('test.exp_challenge',public.prepare_offline_device_challenge(organization_id,branch_id,'6e930000-0000-4000-8000-000000000001',repeat('A',43),'Expense ledger race device','android')::text,true) from test.expense_race_context;
set local role service_role;
select public.complete_offline_device_enrollment('6e900000-0000-4000-8000-000000000001',organization_id,branch_id,'6e930000-0000-4000-8000-000000000001',(current_setting('test.exp_challenge')::jsonb->>'challenge_id')::uuid,repeat('A',86)) from test.expense_race_context;
select set_config('test.exp_prepare',public.prepare_offline_grant('6e900000-0000-4000-8000-000000000001',organization_id,branch_id,'6e930000-0000-4000-8000-000000000001','6e930000-0000-4000-8000-000000000002','https://expense-race.invalid','test-key')::text,true) from test.expense_race_context;
select public.finalize_offline_grant('6e900000-0000-4000-8000-000000000001',organization_id,branch_id,'6e930000-0000-4000-8000-000000000001',(current_setting('test.exp_prepare')::jsonb->'claims'->>'grant_id')::uuid,current_setting('test.exp_prepare')::jsonb->'claims',repeat('A',86)) from test.expense_race_context;
reset role;
create table test.expense_offline_context as select c.*,(current_setting('test.exp_prepare')::jsonb->'claims'->>'grant_id')::uuid grant_id,
 jsonb_build_object('event_id','6e940000-0000-4000-8000-000000000001','organization_id',c.organization_id,'branch_id',c.branch_id,'device_id','6e930000-0000-4000-8000-000000000001','actor_id','6e900000-0000-4000-8000-000000000001','event_type','sale.created','schema_version',1,'occurred_at',private.offline_time(clock_timestamp()),
 'payload',jsonb_build_object('id','6e940000-0000-4000-8000-000000000002','shift_id',c.shift_id,'customer_id',null,'receipt_number','EXP-OFFLINE-PAID','currency','PHP','subtotal_minor',100,'discount_minor',0,'tax_minor',0,'total_minor',100,
 'items',jsonb_build_array(jsonb_build_object('id','6e940000-0000-4000-8000-000000000003','product_id',c.product_id,'sku_snapshot','EXP-RACE-OFFLINE','name_snapshot','Offline expense race product','quantity',1,'unit_price_minor',100,'discount_minor',0,'tax_minor',0,'line_total_minor',100)),
 'payments',jsonb_build_array(jsonb_build_object('id','6e940000-0000-4000-8000-000000000004','method','cash','amount_minor',100,'verification_mode','cash','reference',null)))) event,
 jsonb_build_object('grant_id',(current_setting('test.exp_prepare')::jsonb->'claims'->>'grant_id')::uuid,'sequence',1,'payment_evidence',jsonb_build_object('6e940000-0000-4000-8000-000000000004',jsonb_build_object('tendered_minor',100))) authorization_payload from test.expense_race_context c;
create function test.expense_offline_ingest() returns jsonb language sql security definer set search_path='' as $$
 select public.ingest_offline_event('6e900000-0000-4000-8000-000000000001',organization_id,branch_id,'6e930000-0000-4000-8000-000000000001',event,private.offline_digest(event),authorization_payload,repeat('A',86)) from test.expense_offline_context;
$$;
commit;
SQL
expense_actor_sql "select test.expense_race_record('6e910000-0000-4000-8000-000000000015',200,'Hold expense payout before offline ingest');" > "$result_dir/expense.payout-offline.out" 2> "$result_dir/expense.payout-offline.err" &
expense_writer_pid=$!
expense_wait_marker 600014
psql_admin -Atq -d "$database_name" > "$result_dir/expense.offline-payout.out" 2> "$result_dir/expense.offline-payout.err" <<'SQL' &
begin;
set local statement_timeout='8s';
set local role service_role;
select test.expense_offline_ingest();
commit;
SQL
expense_ingest_pid=$!
wait "$expense_writer_pid" "$expense_ingest_pid"
python3 - "$result_dir" <<'PY'
import json,sys
from pathlib import Path
value=json.loads((Path(sys.argv[1])/'expense.offline-payout.out').read_text())
assert value['status']=='accepted'
PY
psql_admin -d "$database_name" <<'SQL'
select test.assert(private.phase3_expected_cash((select shift_id from test.expense_race_context))=900,'In-flight payout and paid offline sale serialize without counter-after-shift deadlock');
select test.assert((select quantity from private.stock_balances where product_id=(select product_id from test.expense_race_context) and branch_id=(select branch_id from test.expense_race_context))=9,'Expense race never mutates authoritative offline stock');
select test.assert((select count(*) from public.sales where id='6e940000-0000-4000-8000-000000000002')=1,'Expense race preserves original paid offline event acceptance');
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='6e900000-0000-4000-8000-000000000001';
select test.expect_error($q$select test.expense_race_close('6e910000-0000-4000-8000-000000000017',900,'Drawer expense cannot release an outstanding signed grant')$q$,'23514','Actual drawer expense and accepted offline event preserve the unreleased signed-grant closure barrier');
commit;
select test.assert(not exists(select 1 from private.operation_requests where request_id='6e910000-0000-4000-8000-000000000017'),'Grant-barrier close denial appends no accepted request');
select test.assert(not exists(select 1 from public.shift_closures where shift_id=(select shift_id from test.expense_race_context)),'Drawer expense never bypasses unreleased signed-grant closure barrier');
drop trigger expense_race_audit_hold on public.audit_logs;
drop function test.expense_race_audit_hold();
SQL
