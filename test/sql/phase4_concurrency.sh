#!/usr/bin/env bash
# Sourced only by run.sh after its pinned-image/isolation checks. All data below
# exists solely in nexapos_security_test with mock Auth and test proof strings.
set -euo pipefail
psql_admin -Atq -d "$database_name" > "$result_dir/p4.fixture" <<'SQL'
begin;
insert into auth.users(id,email,email_confirmed_at) values('a4900000-0000-4000-8000-000000000001','p4-race@example.invalid',now());
set local role authenticated;
set local "request.jwt.claim.sub"='a4900000-0000-4000-8000-000000000001';
select set_config('test.p4_race_org',organization_id::text,true),set_config('test.p4_race_branch',branch_id::text,true) from public.bootstrap_organization('Offline concurrency fixture','SQL-only owner');
reset role;
insert into public.products(id,organization_id,sku,name,price_minor) values
 ('a4910000-0000-4000-8000-000000000001',test.id('p4_race_org'),'P4-RACE-A','Feed race A',100),
 ('a4910000-0000-4000-8000-000000000002',test.id('p4_race_org'),'P4-RACE-B','Feed race B',200);
set local role authenticated;
select public.receive_stock(test.id('p4_race_org'),test.id('p4_race_branch'),gen_random_uuid(),'[{"product_id":"a4910000-0000-4000-8000-000000000001","quantity":10,"expected_revision":1},{"product_id":"a4910000-0000-4000-8000-000000000002","quantity":10,"expected_revision":1}]',null,null,'Real fixture stock');
select public.open_shift(test.id('p4_race_org'),test.id('p4_race_branch'),'a4920000-0000-4000-8000-000000000001',0,'PHP');
select set_config('test.p4_race_challenge',public.prepare_offline_device_challenge(test.id('p4_race_org'),test.id('p4_race_branch'),'a4930000-0000-4000-8000-000000000001',repeat('A',43),'Concurrency fixture','android')::text,true);
set local role service_role;
select public.complete_offline_device_enrollment('a4900000-0000-4000-8000-000000000001',test.id('p4_race_org'),test.id('p4_race_branch'),'a4930000-0000-4000-8000-000000000001',(current_setting('test.p4_race_challenge')::jsonb->>'challenge_id')::uuid,repeat('A',86));
select set_config('test.p4_race_prepare',public.prepare_offline_grant('a4900000-0000-4000-8000-000000000001',test.id('p4_race_org'),test.id('p4_race_branch'),'a4930000-0000-4000-8000-000000000001','a4940000-0000-4000-8000-000000000001','https://race.invalid','test-key')::text,true);
select public.finalize_offline_grant('a4900000-0000-4000-8000-000000000001',test.id('p4_race_org'),test.id('p4_race_branch'),'a4930000-0000-4000-8000-000000000001',(current_setting('test.p4_race_prepare')::jsonb->'claims'->>'grant_id')::uuid,current_setting('test.p4_race_prepare')::jsonb->'claims',repeat('A',86));
commit;
SQL
read -r p4_org p4_branch p4_shift p4_grant p4_cursor < <(psql_admin -Atq -d "$database_name" -c "select g.organization_id::text||' '||g.branch_id::text||' '||g.shift_id::text||' '||g.id::text||' '||(g.snapshot->>'cursor') from private.offline_grants g where actor_id='a4900000-0000-4000-8000-000000000001'")
for value in "$p4_org" "$p4_branch" "$p4_shift" "$p4_grant"; do
 if [[ ! "$value" =~ ^[0-9a-f-]{36}$ ]]; then echo 'Offline concurrency fixture identifier invalid.' >&2; exit 1; fi
done
if [[ ! "$p4_cursor" =~ ^[0-9]+$ ]]; then echo 'Offline concurrency fixture cursor invalid.' >&2; exit 1; fi
# Writer A has already allocated a feed revision but deliberately commits late.
# Writer B and the pull begin only after A signals its held transaction lock.
psql_admin -Atq -d "$database_name" > "$result_dir/p4.writer.a" 2> "$result_dir/p4.writer.a.err" <<SQL &
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='a4900000-0000-4000-8000-000000000001';
select public.save_product('$p4_org','a4910000-0000-4000-8000-000000000001',1,'{"price_minor":101}','Late commit feed fixture');
select pg_advisory_xact_lock(494001);
select pg_sleep(1.5);
commit;
SQL
p4_writer_a_pid=$!
marker_seen=false
for attempt in {1..60}; do
 if [[ "$(psql_admin -Atq -d "$database_name" -c "select exists(select 1 from pg_locks where locktype='advisory' and objid=494001 and granted)")" == t ]]; then marker_seen=true; break; fi
 # No arbitrary long sleep: each short poll asks the actual database lock state.
 sleep 0.02
done
if [[ "$marker_seen" != true ]]; then echo 'Late-commit feed writer did not acquire its expected lock.' >&2; exit 1; fi
psql_admin -Atq -d "$database_name" > "$result_dir/p4.writer.b" 2> "$result_dir/p4.writer.b.err" <<SQL &
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='a4900000-0000-4000-8000-000000000001';
select public.save_product('$p4_org','a4910000-0000-4000-8000-000000000002',1,'{"price_minor":202}','Competing feed fixture');
commit;
SQL
p4_writer_b_pid=$!
psql_admin -Atq -d "$database_name" > "$result_dir/p4.pull.first" 2> "$result_dir/p4.pull.first.err" <<SQL &
begin;
set local role service_role;
select public.pull_offline_changes('a4900000-0000-4000-8000-000000000001','$p4_org','$p4_branch','a4930000-0000-4000-8000-000000000001',$p4_cursor,100);
commit;
SQL
p4_pull_pid=$!
wait "$p4_writer_a_pid" "$p4_writer_b_pid" "$p4_pull_pid"
p4_next_cursor="$(python3 - "$result_dir/p4.pull.first" <<'PY'
import json,sys
page=json.load(open(sys.argv[1])); revisions=[x['revision'] for x in page['changes']]
if not any(x['id']=='a4910000-0000-4000-8000-000000000001' and x['value']['price_minor']==101 for x in page['changes']):
 sys.exit('Pull skipped a feed change that allocated before a later commit.')
if revisions!=sorted(set(revisions)):
 sys.exit('Pull feed revisions are not strictly increasing.')
print(page['cursor'])
PY
)"
psql_admin -Atq -d "$database_name" > "$result_dir/p4.pull.second" <<SQL
begin;
set local role service_role;
select public.pull_offline_changes('a4900000-0000-4000-8000-000000000001','$p4_org','$p4_branch','a4930000-0000-4000-8000-000000000001',$p4_next_cursor,100);
commit;
SQL
python3 - "$result_dir/p4.pull.first" "$result_dir/p4.pull.second" <<'PY'
import json,sys
first,second=[json.load(open(p)) for p in sys.argv[1:]]
changes=first['changes']+second['changes']; ids=[c['id'] for c in changes]
expected={'a4910000-0000-4000-8000-000000000001','a4910000-0000-4000-8000-000000000002'}
if set(ids)!=expected or len(ids)!=2 or second['cursor']<first['cursor']:
 sys.exit('Concurrent feed pulls must retain each committed writer exactly once.')
PY
psql_admin -d "$database_name" <<SQL
select test.assert((select count(*) from private.offline_changes where organization_id='$p4_org' and revision>$p4_cursor)=2,'Late and competing feed writers each commit one retained change');
select test.assert((select max(revision)-min(revision) from private.offline_changes where organization_id='$p4_org' and revision>$p4_cursor)=1,'Commit-order counter produces uninterrupted writer revisions');
select test.assert((select revision from private.offline_change_counters where organization_id='$p4_org')=$p4_cursor+2,'Committed organization cursor covers both concurrent writers');
SQL
# Two independent uploads retry exactly one paid offline event. Its signed
# frozen price is 100 even though the catalog was concurrently changed to 101.
psql_admin -Atq -d "$database_name" > "$result_dir/p4.event" <<SQL
select jsonb_build_object('event_id','a4950000-0000-4000-8000-000000000001','organization_id',g.organization_id,'branch_id',g.branch_id,
 'device_id',g.device_id,'actor_id',g.actor_id,'event_type','sale.created','schema_version',1,'occurred_at',g.claims->>'issued_at',
 'payload',jsonb_build_object('id','a4960000-0000-4000-8000-000000000001','shift_id',g.shift_id,'customer_id',null,'receipt_number','OFFLINE-CONCURRENT-1','currency','PHP','subtotal_minor',100,'discount_minor',0,'tax_minor',0,'total_minor',100,
 'items',jsonb_build_array(jsonb_build_object('id','a4970000-0000-4000-8000-000000000001','product_id','a4910000-0000-4000-8000-000000000001','sku_snapshot','P4-RACE-A','name_snapshot','Feed race A','quantity',1,'unit_price_minor',100,'discount_minor',0,'tax_minor',0,'line_total_minor',100)),
 'payments',jsonb_build_array(jsonb_build_object('id','a4980000-0000-4000-8000-000000000001','method','cash','amount_minor',100,'verification_mode','cash','reference',null))))
 from private.offline_grants g where id='$p4_grant';
SQL
# Write exact JSON inside an SQL literal using proper single-quote escaping.
# The fixture has no external strings, credentials, shell substitution or secrets.
python3 - "$result_dir/p4.event" "$result_dir/p4.ingest.sql" "$p4_org" "$p4_branch" "$p4_grant" <<'PY'
from pathlib import Path
import json,sys
value=json.loads(Path(sys.argv[1]).read_text()); literal=json.dumps(value,ensure_ascii=False).replace("'","''")
auth=json.dumps({'grant_id':sys.argv[5],'sequence':1,'payment_evidence':{'a4980000-0000-4000-8000-000000000001':{'tendered_minor':100}}})
Path(sys.argv[2]+'.digest').write_text(f"select private.offline_digest('{literal}'::jsonb);\n")
Path(sys.argv[2]).write_text(f"begin;\nset local role service_role;\nselect public.ingest_offline_event('a4900000-0000-4000-8000-000000000001','{sys.argv[3]}','{sys.argv[4]}','a4930000-0000-4000-8000-000000000001','{literal}'::jsonb,'P4_FIXTURE_DIGEST','{auth}'::jsonb,repeat('A',86));\ncommit;\n")
PY
# Digest is computed once by the disposable database owner; the real upload
# connections still execute as service_role and cannot access private helpers.
p4_digest="$(psql_admin -Atq -d "$database_name" < "$result_dir/p4.ingest.sql.digest")"
if [[ ! "$p4_digest" =~ ^[0-9a-f]{64}$ ]]; then echo 'Offline concurrency digest invalid.' >&2; exit 1; fi
python3 - "$result_dir/p4.ingest.sql" "$p4_digest" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); p.write_text(p.read_text().replace('P4_FIXTURE_DIGEST',sys.argv[2]))
PY
pids=()
for index in 1 2; do
 psql_admin -Atq -d "$database_name" < "$result_dir/p4.ingest.sql" > "$result_dir/p4.ingest.$index" 2> "$result_dir/p4.ingest.$index.err" &
 pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
python3 - "$result_dir/p4.ingest.1" "$result_dir/p4.ingest.2" <<'PY'
import json,sys
first,second=[json.load(open(p)) for p in sys.argv[1:]]
if first!=second or first.get('status')!='accepted' or first['receipt']['total_minor']!=100:
 sys.exit('Concurrent offline uploads must return the same original paid receipt.')
PY
psql_admin -d "$database_name" <<SQL
select test.assert((select count(*) from private.offline_event_outcomes where grant_id='$p4_grant')=1,'Concurrent offline upload retries retain one outcome');
select test.assert((select quantity from private.stock_balances where branch_id='$p4_branch' and product_id='a4910000-0000-4000-8000-000000000001')=9,'Concurrent offline upload depletes stock once');
select test.assert((select total_minor from private.offline_grant_states where grant_id='$p4_grant')=100,'Concurrent offline upload spends grant total once');
select test.assert((select count(*) from public.financial_events where id='a4950000-0000-4000-8000-000000000001')=1,'Concurrent offline upload appends one immutable original event');
SQL
# Preparation and normal close compete for the same online-opened shift.
# The retained unsigned reservation is still finalizable and must block close.
psql_admin -Atq -d "$database_name" > "$result_dir/p4.release" <<SQL
begin;
set local role service_role;
select public.release_offline_grant('a4900000-0000-4000-8000-000000000001','$p4_org','$p4_branch','a4930000-0000-4000-8000-000000000001','$p4_grant',1,repeat('A',86));
commit;
SQL
psql_admin -Atq -d "$database_name" > "$result_dir/p4.prepare.race" 2> "$result_dir/p4.prepare.race.err" <<SQL &
begin;
set local role service_role;
select public.prepare_offline_grant('a4900000-0000-4000-8000-000000000001','$p4_org','$p4_branch','a4930000-0000-4000-8000-000000000001','a4940000-0000-4000-8000-000000000002','https://race.invalid','test-key');
select pg_advisory_xact_lock(494002);
select pg_sleep(1);
commit;
SQL
p4_prepare_pid=$!
marker_seen=false
for attempt in {1..60}; do
 if [[ "$(psql_admin -Atq -d "$database_name" -c "select exists(select 1 from pg_locks where locktype='advisory' and objid=494002 and granted)")" == t ]]; then marker_seen=true; break; fi
 sleep 0.02
done
if [[ "$marker_seen" != true ]]; then echo 'Concurrent preparation did not acquire its expected lock.' >&2; exit 1; fi
(
 if psql_admin -Atq -d "$database_name" > "$result_dir/p4.close.race" 2> "$result_dir/p4.close.race.err" <<SQL
\set VERBOSITY verbose
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='a4900000-0000-4000-8000-000000000001';
select public.close_shift('$p4_org','$p4_shift','a4990000-0000-4000-8000-000000000001',100,'Competing close with uncommitted preparation');
commit;
SQL
 then printf '0' > "$result_dir/p4.close.race.status"; else printf '%s' "$?" > "$result_dir/p4.close.race.status"; fi
) &
p4_close_pid=$!
wait "$p4_prepare_pid" "$p4_close_pid"
python3 - "$result_dir" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
if (p/'p4.close.race.status').read_text()!='3' or '23514:' not in (p/'p4.close.race.err').read_text():
 sys.exit('Concurrent close must see the committed finalizable offline preparation and refuse closure.')
PY
psql_admin -d "$database_name" <<SQL
select test.assert(not exists(select 1 from public.shift_closures where shift_id='$p4_shift'),'Concurrent close cannot silently close a newly authorized offline shift');
select test.assert((select count(*) from private.offline_grants where shift_id='$p4_shift' and request_id='a4940000-0000-4000-8000-000000000002')=1,'Concurrent preparation retains one exact frozen grant reservation');
select test.assert((select count(*) from private.offline_grant_releases r join private.offline_grants g on g.id=r.grant_id where g.shift_id='$p4_shift')=1,'New preparation does not rewrite or release its preceding paid grant');
SQL
