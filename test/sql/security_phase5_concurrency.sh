#!/usr/bin/env bash
# Sourced only by isolated test/sql/run.sh, with checked psql_admin/database_name.
# Actual independent connections race on stable UUIDs and financial grant rows.
psql_admin -d "$database_name" <<'SQL'
insert into auth.users(id,email,email_confirmed_at) values('a5c00000-0000-4000-8000-000000000001','phase5-races@example.invalid',now());
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='a5c00000-0000-4000-8000-000000000001';
select set_config('test.p5c_org',organization_id::text,true),set_config('test.p5c_branch',branch_id::text,true) from public.bootstrap_organization('Phase 5 races','Race Owner');
select set_config('test.p5c_product',(public.save_product(test.id('p5c_org'),null,null,'{"name":"Original race product","sku":"P5-RACE","price_minor":100}','Actual security race product')->>'id'),true);
select public.receive_stock(test.id('p5c_org'),test.id('p5c_branch'),gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',test.id('p5c_product'),'quantity',1,'expected_revision',1)),null,null,'Single original paid race unit');
select set_config('test.p5c_shift',(public.open_shift(test.id('p5c_org'),test.id('p5c_branch'),gen_random_uuid(),1000,'PHP')->>'id'),true);
select set_config('test.p5c_challenge',public.prepare_offline_device_challenge(test.id('p5c_org'),test.id('p5c_branch'),'a5c10000-0000-4000-8000-000000000001',repeat('C',43),'Actual review-race device','windows')::text,true);
set local role service_role;
select public.complete_offline_device_enrollment('a5c00000-0000-4000-8000-000000000001',test.id('p5c_org'),test.id('p5c_branch'),'a5c10000-0000-4000-8000-000000000001',(current_setting('test.p5c_challenge')::jsonb->>'challenge_id')::uuid,repeat('C',86));
select set_config('test.p5c_prepare',public.prepare_offline_grant('a5c00000-0000-4000-8000-000000000001',test.id('p5c_org'),test.id('p5c_branch'),'a5c10000-0000-4000-8000-000000000001',gen_random_uuid(),'https://example.invalid','test-key')::text,true);
select set_config('test.p5c_grant',current_setting('test.p5c_prepare')::jsonb->'claims'->>'grant_id',true);
select public.finalize_offline_grant('a5c00000-0000-4000-8000-000000000001',test.id('p5c_org'),test.id('p5c_branch'),'a5c10000-0000-4000-8000-000000000001',test.id('p5c_grant'),current_setting('test.p5c_prepare')::jsonb->'claims',repeat('C',86));
set local role authenticated;
select public.revoke_offline_device(test.id('p5c_org'),test.id('p5c_branch'),'a5c10000-0000-4000-8000-000000000001','Actual lost-key race device');
reset role;
alter table private.offline_grants disable trigger immutable_history;
update private.offline_grants set issued_at=statement_timestamp()-interval '9 hours',expires_at=statement_timestamp()-interval '1 hour' where id=test.id('p5c_grant');
alter table private.offline_grants enable trigger immutable_history;
create table test.p5_concurrency_context as select test.id('p5c_org') organization_id,test.id('p5c_branch') branch_id,test.id('p5c_grant') grant_id,
 jsonb_build_object('event_id','a5c30000-0000-4000-8000-000000000001','organization_id',test.id('p5c_org'),'branch_id',test.id('p5c_branch'),'device_id','a5c10000-0000-4000-8000-000000000001','actor_id','a5c00000-0000-4000-8000-000000000001',
 'event_type','sale.created','schema_version',1,'occurred_at',private.offline_time(statement_timestamp()-interval '8 hours'),
 'payload',jsonb_build_object('id','a5c40000-0000-4000-8000-000000000001','shift_id',test.id('p5c_shift'),'customer_id',null,'receipt_number','P5-RACE-ORIGINAL','currency','PHP','subtotal_minor',100,'discount_minor',0,'tax_minor',0,'total_minor',100,
 'items',jsonb_build_array(jsonb_build_object('id','a5c50000-0000-4000-8000-000000000001','product_id',test.id('p5c_product'),'sku_snapshot','P5-RACE','name_snapshot','Original race product','quantity',1,'unit_price_minor',100,'discount_minor',0,'tax_minor',0,'line_total_minor',100)),
 'payments',jsonb_build_array(jsonb_build_object('id','a5c60000-0000-4000-8000-000000000001','method','cash','amount_minor',100,'verification_mode','cash','reference',null)))) event,
 jsonb_build_object('grant_id',test.id('p5c_grant'),'sequence',1,'payment_evidence',jsonb_build_object('a5c60000-0000-4000-8000-000000000001',jsonb_build_object('tendered_minor',100))) authorization;
create function test.p5_race_ingest() returns jsonb language sql security definer set search_path='' as $$
 select public.ingest_offline_event('a5c00000-0000-4000-8000-000000000001',c.organization_id,c.branch_id,'a5c10000-0000-4000-8000-000000000001',c.event,private.offline_digest(c.event),c."authorization",repeat('C',86)) from test.p5_concurrency_context c;
$$;
create function test.p5_race_review(p_request uuid,p_sequence integer) returns jsonb language sql security definer set search_path='' as $$
 select public.review_offline_grant(organization_id,branch_id,grant_id,p_request,'Reviewed race outcomes and explicitly accepted unknown payment exposure',true,p_sequence,p_sequence,100*p_sequence) from test.p5_concurrency_context;
$$;
create function test.p5_race_policy() returns jsonb language sql security definer set search_path='' as $$
 select public.update_security_policy(organization_id,'a5c70000-0000-4000-8000-000000000001',1,10,false,'Actual duplicate policy request') from test.p5_concurrency_context;
$$;
create function test.p5_race_device(p_revoke boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare c test.p5_concurrency_context;
begin
 select * into c from test.p5_concurrency_context;
 if p_revoke then return public.revoke_security_device(c.organization_id,c.branch_id,'a5c10000-0000-4000-8000-000000000001','a5c70000-0000-4000-8000-000000000002','Actual shared UUID revocation request');end if;
 return public.update_security_device(c.organization_id,c.branch_id,'a5c10000-0000-4000-8000-000000000001','a5c70000-0000-4000-8000-000000000002','Race device renamed','Actual shared UUID rename request');
end; $$;
commit;
SQL

pids=()
for index in 1 2; do
  psql_admin -Atq -d "$database_name" > "$result_dir/security-policy.$index.out" 2> "$result_dir/security-policy.$index.err" <<'SQL' &
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='a5c00000-0000-4000-8000-000000000001';
select test.p5_race_policy();
commit;
SQL
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
python3 - "$result_dir" <<'PY'
from pathlib import Path
import json,sys
base=Path(sys.argv[1]); outcomes=[json.loads((base/f'security-policy.{i}.out').read_text()) for i in (1,2)]
if outcomes[0]!=outcomes[1] or outcomes[0].get('revision')!=2:
    sys.exit('Concurrent identical security policy requests must return one original policy revision.')
PY
psql_admin -d "$database_name" <<'SQL'
select test.assert((select count(*) from private.security_policy_history where organization_id=(select organization_id from test.p5_concurrency_context))=1,'Concurrent identical security policy commits one policy history row');
select test.assert((select count(*) from public.audit_logs where organization_id=(select organization_id from test.p5_concurrency_context) and action='security.policy_updated')=1,'Concurrent identical security policy commits one source audit');
SQL

pids=()
for operation in false true; do
  (
    if psql_admin -Atq -d "$database_name" > "$result_dir/security-device.$operation.out" 2> "$result_dir/security-device.$operation.err" <<SQL
\set VERBOSITY verbose
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='a5c00000-0000-4000-8000-000000000001';
set local statement_timeout='10s';
select test.p5_race_device($operation);
commit;
SQL
    then printf '0' > "$result_dir/security-device.$operation.status";else printf '%s' "$?" > "$result_dir/security-device.$operation.status";fi
  ) &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
python3 - "$result_dir" <<'PY'
from pathlib import Path
import sys
base=Path(sys.argv[1]); statuses=[(base/f'security-device.{i}.status').read_text() for i in ('false','true')]
errors=[(base/f'security-device.{i}.err').read_text() for i in ('false','true')]
if sorted(statuses)!=['0','3'] or sum('23505:' in e for e in errors)!=1:
    sys.exit('Concurrent changed security request must commit once and conflict once without a deadlock.')
PY
psql_admin -d "$database_name" <<'SQL'
select test.assert((select count(*) from private.security_requests where request_id='a5c70000-0000-4000-8000-000000000002')=1,'Concurrent changed device operations keep one immutable request identity');
SQL

pids=()
for operation in ingest review; do
  (
    race_expression='test.p5_race_ingest()'
    if [[ "$operation" == review ]];then race_expression="test.p5_race_review('a5c70000-0000-4000-8000-000000000003',0)";fi
    if psql_admin -Atq -d "$database_name" > "$result_dir/security-review.$operation.out" 2> "$result_dir/security-review.$operation.err" <<SQL
\set VERBOSITY verbose
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='a5c00000-0000-4000-8000-000000000001';
set local statement_timeout='10s';
select $race_expression;
commit;
SQL
    then printf '0' > "$result_dir/security-review.$operation.status";else printf '%s' "$?" > "$result_dir/security-review.$operation.status";fi
  ) &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
python3 - "$result_dir" <<'PY'
from pathlib import Path
import json,sys
base=Path(sys.argv[1]); ingest=(base/'security-review.ingest.status').read_text();review=(base/'security-review.review.status').read_text()
if ingest!='0' or json.loads((base/'security-review.ingest.out').read_text()).get('status')!='review':
    sys.exit('Paid original proof must always commit to review through concurrent administrative resolution.')
if review not in ('0','3') or (review=='3' and '40001:' not in (base/'security-review.review.err').read_text()):
    sys.exit('Concurrent admin must resolve the reviewed snapshot or report its exact stale revision.')
PY
if [[ "$(cat "$result_dir/security-review.review.status")" != 0 ]];then
  psql_admin -Atq -d "$database_name" <<'SQL'
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='a5c00000-0000-4000-8000-000000000001';
select test.p5_race_review('a5c70000-0000-4000-8000-000000000004',1);
commit;
SQL
fi
psql_admin -d "$database_name" <<'SQL'
select test.assert((select count(*) from private.offline_event_outcomes where event_id='a5c30000-0000-4000-8000-000000000001')=1,'Concurrent administrator and uploader retain one immutable original paid event');
select test.assert((select count(*) from private.security_grant_resolutions where grant_id=(select grant_id from test.p5_concurrency_context))=1,'Concurrent administrator and uploader retain one explicit unknown-risk decision');
select test.assert((select known_last_sequence from private.security_grant_resolutions where grant_id=(select grant_id from test.p5_concurrency_context)) in (0,1),'Administrative snapshot reflects outcomes actually committed before its decision');
select test.assert(not exists(select 1 from private.offline_grant_releases where grant_id=(select grant_id from test.p5_concurrency_context)),'Concurrent risk review never invents lost device release proof');
select test.assert((select result->>'status' from private.offline_event_outcomes where event_id='a5c30000-0000-4000-8000-000000000001')='review','Concurrent late paid evidence remains explicit review rather than posted or erased');
SQL
