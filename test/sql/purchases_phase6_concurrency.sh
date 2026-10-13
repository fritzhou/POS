#!/usr/bin/env bash
set -euo pipefail
# Append fixtures only inside the same verified disposable PostgreSQL service.
# May be sourced by run.sh or run directly against the separate purchase DB.
purchase_container_name="${container_name:-nexapos-postgres-test}"
purchase_database_name="${database_name:-${1:-nexapos_security_test}}"
if [[ "$purchase_container_name" != nexapos-postgres-test || ! "$purchase_database_name" =~ ^nexapos_(security_test|purchase_phase6_test)$ ]]; then
 echo 'Refusing purchase fixtures outside the named disposable test databases.' >&2; exit 1
fi
purchase_inspection="$(docker inspect --format '{"network":{{json .HostConfig.NetworkMode}},"ports":{{json .NetworkSettings.Ports}},"port_bindings":{{json .HostConfig.PortBindings}},"image":{{json .Config.Image}},"mounts":{{json .Mounts}},"running":{{json .State.Running}}}' "$purchase_container_name")"
printf '%s' "$purchase_inspection" | python3 -c '
import json,re,sys
s=json.load(sys.stdin)
safe=(s.get("network")=="none" and s.get("running") is True and s.get("image")=="postgres@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3" and not s.get("port_bindings") and not any((s.get("ports") or {}).values()))
for m in s.get("mounts") or []:
 safe=safe and m.get("Type")=="volume" and bool(re.fullmatch(r"[a-f0-9]{64}",m.get("Name",""))) and m.get("Destination")=="/var/lib/postgresql/data"
if not safe: sys.exit("Refusing purchase fixtures: test container isolation, image or anonymous-volume check failed.")
'
purchase_psql() { docker exec -i "$purchase_container_name" psql -X -U postgres -v ON_ERROR_STOP=1 -d "$purchase_database_name" "$@"; }
purchase_result_dir="$(mktemp -d)"
purchase_psql > "$purchase_result_dir/fixture.log" <<'SQL'
begin;
insert into auth.users(id,email,email_confirmed_at) values('c6800000-0000-4000-8000-000000000001','purchase-concurrency@example.invalid',now());
set local role authenticated;
set local "request.jwt.claim.sub"='c6800000-0000-4000-8000-000000000001';
select set_config('test.purchase_race_org',organization_id::text,true),set_config('test.purchase_race_branch',branch_id::text,true) from public.bootstrap_organization('Purchase concurrency shop','Purchase concurrency owner');
reset role;
set local "request.jwt.claim.sub"='';
insert into public.suppliers(id,organization_id,name) values('c6810000-0000-4000-8000-000000000001',test.id('purchase_race_org'),'Purchase concurrency supplier');
insert into public.products(id,organization_id,sku,name,cost_minor,price_minor) values('c6820000-0000-4000-8000-000000000001',test.id('purchase_race_org'),'P6-RACE','Purchase concurrency product',777,1000);
commit;
SQL
read -r purchase_race_org purchase_race_branch purchase_race_settings < <(purchase_psql -Atq -c "select o.id::text||' '||b.id::text||' '||o.revision::text from public.organizations o join public.branches b on b.organization_id=o.id and b.code='MAIN' where o.owner_user_id='c6800000-0000-4000-8000-000000000001'")
for purchase_value in "$purchase_race_org" "$purchase_race_branch"; do
 if [[ ! "$purchase_value" =~ ^[0-9a-f-]{36}$ ]]; then echo 'Purchase race UUID fixture invalid.' >&2; exit 1;fi
done
if [[ ! "$purchase_race_settings" =~ ^[0-9]+$ ]]; then echo 'Purchase race settings fixture invalid.' >&2;exit 1;fi
# Eight simultaneous transports record one submitted PO under the original UUID.
purchase_pids=()
for purchase_index in {1..8}; do
 purchase_psql -Atq > "$purchase_result_dir/create.$purchase_index.out" 2> "$purchase_result_dir/create.$purchase_index.err" <<SQL &
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='c6800000-0000-4000-8000-000000000001';
select public.create_purchase_order('$purchase_race_org','$purchase_race_branch','c6830000-0000-4000-8000-000000000001','c6810000-0000-4000-8000-000000000001',1,$purchase_race_settings,'PHP',
 '[{"product_id":"c6820000-0000-4000-8000-000000000001","quantity":5,"unit_cost_minor":125,"expected_revision":1}]',null,'Concurrent order submission');
commit;
SQL
 purchase_pids+=("$!")
done
for purchase_pid in "${purchase_pids[@]}"; do wait "$purchase_pid";done
purchase_race_order="$(python3 - "$purchase_result_dir" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);docs=[json.loads((p/f'create.{n}.out').read_text()) for n in range(1,9)]
if any(d!=docs[0] for d in docs): sys.exit('Concurrent purchase creation returned inconsistent original action documents.')
print(docs[0]['order_id'])
PY
)"
if [[ ! "$purchase_race_order" =~ ^[0-9a-f-]{36}$ ]]; then echo 'Purchase created order UUID invalid.' >&2;exit 1;fi
purchase_race_item="$(purchase_psql -Atq -c "select id from public.purchase_order_items where order_id='$purchase_race_order'")"
if [[ ! "$purchase_race_item" =~ ^[0-9a-f-]{36}$ ]]; then echo 'Purchase order item UUID invalid.' >&2;exit 1;fi
purchase_psql <<SQL
select test.assert((select count(*) from public.purchase_orders where organization_id='$purchase_race_org')=1,'Eight concurrent purchase transports submit one immutable order');
select test.assert((select count(*) from private.operation_requests where request_id='c6830000-0000-4000-8000-000000000001')=1,'Concurrent purchase create has one actor/request mapping');
select test.assert((select count(*) from public.audit_logs where organization_id='$purchase_race_org' and action='purchase.created')=1,'Concurrent create writes one purchase audit');
SQL
# Same receipt UUID transported twice must append exactly one physical movement.
purchase_pids=()
for purchase_index in 1 2; do
 purchase_psql -Atq > "$purchase_result_dir/receive.$purchase_index.out" 2> "$purchase_result_dir/receive.$purchase_index.err" <<SQL &
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='c6800000-0000-4000-8000-000000000001';
select public.receive_purchase_order('$purchase_race_org','$purchase_race_branch','c6840000-0000-4000-8000-000000000001','$purchase_race_order',1,
 '[{"order_item_id":"$purchase_race_item","quantity":1,"expected_product_revision":1}]',null,'Concurrent one-unit receipt');
commit;
SQL
 purchase_pids+=("$!")
done
for purchase_pid in "${purchase_pids[@]}"; do wait "$purchase_pid";done
python3 - "$purchase_result_dir" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);a=json.loads((p/'receive.1.out').read_text());b=json.loads((p/'receive.2.out').read_text())
if a!=b:sys.exit('Concurrent same-UUID receiving must return the same complete immutable receipt action.')
PY
purchase_psql <<SQL
select test.assert((select count(*) from public.purchase_receipts where order_id='$purchase_race_order')=1,'Concurrent same-UUID receiving appends one physical receipt');
select test.assert((select count(*) from public.stock_movements where product_id='c6820000-0000-4000-8000-000000000001')=1,'Concurrent same-UUID receiving appends one stock movement');
select test.assert((select quantity from private.stock_balances where product_id='c6820000-0000-4000-8000-000000000001' and branch_id='$purchase_race_branch')=1,'Concurrent same-UUID receiving adds physical stock once');
select test.assert((select revision from private.purchase_order_states where order_id='$purchase_race_order')=2,'Concurrent same-UUID receiving advances order once');
select test.assert((select count(*) from private.inventory_cost_evidence e join public.stock_movements m on m.id=e.movement_id where m.product_id='c6820000-0000-4000-8000-000000000001')=1,'Concurrent same-UUID receiving records one original-cost evidence');
SQL
# Two different receipt UUIDs against the SAME expected revision: one accepted,
# one CAS conflict. The loser must append no receipt, mapping, stock or audit.
purchase_pids=()
for purchase_index in 2 3; do
 (
 if purchase_psql -Atq > "$purchase_result_dir/cas.$purchase_index.out" 2> "$purchase_result_dir/cas.$purchase_index.err" <<SQL
\set VERBOSITY verbose
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='c6800000-0000-4000-8000-000000000001';
select public.receive_purchase_order('$purchase_race_org','$purchase_race_branch','c6840000-0000-4000-8000-00000000000$purchase_index','$purchase_race_order',2,
 '[{"order_item_id":"$purchase_race_item","quantity":3,"expected_product_revision":1}]',null,'Competing partial purchase receipt');
commit;
SQL
 then printf '0' > "$purchase_result_dir/cas.$purchase_index.status";else printf '%s' "$?" > "$purchase_result_dir/cas.$purchase_index.status";fi
 ) &
 purchase_pids+=("$!")
done
for purchase_pid in "${purchase_pids[@]}";do wait "$purchase_pid";done
python3 - "$purchase_result_dir" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);statuses=[(p/f'cas.{n}.status').read_text() for n in (2,3)];errors=[(p/f'cas.{n}.err').read_text() for n in (2,3)]
if sorted(statuses)!=['0','3'] or sum('40001:' in e for e in errors)!=1:sys.exit('Competing purchase receipts must commit once and reject the stale revision once.')
PY
purchase_psql <<SQL
select test.assert((select count(*) from public.purchase_receipts where order_id='$purchase_race_order')=2,'Different concurrent receipt UUIDs accept one current-revision request');
select test.assert((select quantity from private.stock_balances where product_id='c6820000-0000-4000-8000-000000000001' and branch_id='$purchase_race_branch')=4,'Competing receipts never over-receive remaining order quantity');
select test.assert((select count(*) from private.operation_requests where request_id in ('c6840000-0000-4000-8000-000000000002','c6840000-0000-4000-8000-000000000003'))=1,'CAS loser has no accepted purchase request');
select test.assert((select count(*) from public.audit_logs where organization_id='$purchase_race_org' and action='purchase.received')=2,'CAS loser cannot create an authoritative receipt audit');
SQL
# Receipt and cancellation serialize on one order revision. A cancellation that
# loses may be retried only after operator review with a NEW current revision.
purchase_close_order="$(purchase_psql -Atq <<SQL
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='c6800000-0000-4000-8000-000000000001';
select public.create_purchase_order('$purchase_race_org','$purchase_race_branch','c6830000-0000-4000-8000-000000000002','c6810000-0000-4000-8000-000000000001',1,$purchase_race_settings,'PHP',
 '[{"product_id":"c6820000-0000-4000-8000-000000000001","quantity":5,"unit_cost_minor":125,"expected_revision":1}]',null,'Receipt cancellation race')->>'order_id';
commit;
SQL
)"
purchase_close_item="$(purchase_psql -Atq -c "select id from public.purchase_order_items where order_id='$purchase_close_order'")"
for purchase_value in "$purchase_close_order" "$purchase_close_item";do if [[ ! "$purchase_value" =~ ^[0-9a-f-]{36}$ ]];then echo 'Purchase close race fixture invalid.' >&2;exit 1;fi;done
purchase_pids=()
for purchase_index in 1 2;do
 (
 if [[ "$purchase_index" == 1 ]];then purchase_close_sql="select public.receive_purchase_order('$purchase_race_org','$purchase_race_branch','c6840000-0000-4000-8000-000000000004','$purchase_close_order',1,'[{\"order_item_id\":\"$purchase_close_item\",\"quantity\":1,\"expected_product_revision\":1}]',null,'Racing physical receipt');";
 else purchase_close_sql="select public.cancel_purchase_order_remaining('$purchase_race_org','$purchase_race_branch','c6850000-0000-4000-8000-000000000001','$purchase_close_order',1,'Racing supplier remainder cancellation');";fi
 if purchase_psql -Atq > "$purchase_result_dir/close.$purchase_index.out" 2> "$purchase_result_dir/close.$purchase_index.err" <<SQL
\set VERBOSITY verbose
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='c6800000-0000-4000-8000-000000000001';
$purchase_close_sql
commit;
SQL
 then printf '0' > "$purchase_result_dir/close.$purchase_index.status";else printf '%s' "$?" > "$purchase_result_dir/close.$purchase_index.status";fi
 ) &
 purchase_pids+=("$!")
done
for purchase_pid in "${purchase_pids[@]}";do wait "$purchase_pid";done
python3 - "$purchase_result_dir" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);statuses=[(p/f'close.{n}.status').read_text() for n in (1,2)];errors=[(p/f'close.{n}.err').read_text() for n in (1,2)]
if sorted(statuses)!=['0','3'] or sum('40001:' in e for e in errors)!=1:sys.exit('Purchase receipt/cancellation race must commit one action and reject one stale revision.')
PY
purchase_psql <<SQL
select test.assert((select revision from private.purchase_order_states where order_id='$purchase_close_order')=2,'Receipt and cancellation race advances one order revision');
select test.assert((select count(*) from public.purchase_receipts where order_id='$purchase_close_order')+(select count(*) from public.purchase_order_cancellations where order_id='$purchase_close_order')=1,'Receipt and cancellation race commits one immutable action');
select test.assert((select count(*) from private.operation_requests where request_id in ('c6840000-0000-4000-8000-000000000004','c6850000-0000-4000-8000-000000000001'))=1,'Receipt/cancellation race loser has no accepted request evidence');
select test.assert((select received_quantity+cancelled_quantity<=ordered_quantity from private.purchase_order_item_balances where order_item_id='$purchase_close_item'),'Receipt/cancellation race never double-closes order quantities');
SQL
# Replay the first receipt after later receipts: stable full action, original
# stock balance/revision, original accepted order revision, no fresh receiving.
purchase_psql -Atq > "$purchase_result_dir/replay.out" <<SQL
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='c6800000-0000-4000-8000-000000000001';
select public.receive_purchase_order('$purchase_race_org','$purchase_race_branch','c6840000-0000-4000-8000-000000000001','$purchase_race_order',1,
 '[{"order_item_id":"$purchase_race_item","quantity":1,"expected_product_revision":1}]',null,'Concurrent one-unit receipt');
commit;
SQL
python3 - "$purchase_result_dir" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);a=json.loads((p/'receive.1.out').read_text());b=json.loads((p/'replay.out').read_text())
if a!=b:sys.exit('Original receipt replay changed after a later accepted receipt.')
PY
purchase_psql <<SQL
select test.assert((select count(*) from private.operation_requests where organization_id='$purchase_race_org' and kind='purchase.receive')=(select count(*) from public.purchase_receipts where organization_id='$purchase_race_org'),'Purchase races retain one actor/request per committed physical receipt');
select test.assert((select count(*) from private.offline_changes where organization_id='$purchase_race_org' and kind='stock')=(select count(*) from public.stock_movements where organization_id='$purchase_race_org'),'Committed purchase stock writes retain contiguous authoritative offline feed evidence');
SQL
rm -rf "$purchase_result_dir"
echo 'Purchase concurrent create, same-request receipt, receipt CAS and receipt/cancellation checks passed.'
