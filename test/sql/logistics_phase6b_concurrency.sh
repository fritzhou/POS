# Sourced only by the guarded disposable-container runner.
psql_admin -Atq -d "$database_name" -f /dev/stdin < "$repo_root/test/sql/logistics_phase6b_race_setup.sql" > "$result_dir/logistics.setup.out"
logistics_scope="$(psql_admin -Atq -d "$database_name" -c "select organization_id||'|'||source_branch_id||'|'||destination_branch_id||'|'||id from public.stock_transfers where actor_id='b7000000-0000-4000-8000-000000000001'")"
IFS='|' read -r logistics_org logistics_source logistics_destination logistics_transfer <<< "$logistics_scope"
logistics_item="$(psql_admin -Atq -d "$database_name" -c "select id from public.stock_transfer_items where transfer_id='$logistics_transfer'")"
logistics_product="$(psql_admin -Atq -d "$database_name" -c "select product_id from public.stock_transfer_items where transfer_id='$logistics_transfer'")"
for logistics_id in "$logistics_org" "$logistics_source" "$logistics_destination" "$logistics_transfer" "$logistics_item" "$logistics_product"; do
 [[ "$logistics_id" =~ ^[0-9a-f-]{36}$ ]] || { echo 'Invalid logistics fixture scope.' >&2; exit 1; }
done
pids=()
for index in 1 2; do
 if [[ "$index" = 1 ]]; then logistics_branch="$logistics_destination"; logistics_kind=transfer.receive; else logistics_branch="$logistics_source"; logistics_kind=transfer.return; fi
 (
 if psql_admin -Atq -d "$database_name" > "$result_dir/logistics.$index.out" 2> "$result_dir/logistics.$index.err" <<SQL
\set VERBOSITY verbose
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='b7000000-0000-4000-8000-000000000001';
select public.complete_stock_transfer('$logistics_org','$logistics_branch','b7900000-0000-4000-8000-00000000000$index','$logistics_transfer',1,'$logistics_kind',jsonb_build_array(jsonb_build_object('item_id','$logistics_item','quantity',6,'expected_revision',1)),null,'Actual competing physical confirmation',true)->'document'->>'id';
commit;
SQL
 then printf 0 > "$result_dir/logistics.$index.status"; else printf '%s' "$?" > "$result_dir/logistics.$index.status"; fi
 ) &
 pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
python3 - "$result_dir" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); statuses=[(p/f'logistics.{i}.status').read_text() for i in (1,2)];errors=[(p/f'logistics.{i}.err').read_text() for i in (1,2)]
assert sorted(statuses)==['0','3'] and sum('40001:' in e for e in errors)==1, 'Receipt and transit return must serialize one revision with one stale rejection'
PY
psql_admin -d "$database_name" <<SQL
select test.assert((select count(*) from public.stock_transfer_events where transfer_id='$logistics_transfer')=1,'Competing receipt and transit return commit exactly one physical document');
select test.assert((select received+returned from private.stock_transfer_balances where item_id='$logistics_item')=6,'Competing endpoints never account for transit goods twice');
select test.assert((select sum(quantity) from private.stock_balances where organization_id='$logistics_org' and product_id='$logistics_product')=10,'Competing endpoint actions preserve exact physical goods');
SQL
pids=()
for index in 1 2; do
 psql_admin -Atq -d "$database_name" > "$result_dir/logistics.idem.$index.out" <<SQL &
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='b7000000-0000-4000-8000-000000000001';
select public.dispatch_stock_transfer('$logistics_org','$logistics_source','$logistics_destination','b7900000-0000-4000-8000-000000000003',jsonb_build_array(jsonb_build_object('product_id','$logistics_product','quantity',2,'expected_revision',1)),null,'Two physically dispatched goods',true)->'document'->>'id';
commit;
SQL
 pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
python3 - "$result_dir" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]);a=[(p/f'logistics.idem.{i}.out').read_text().strip() for i in (1,2)]
assert a[0]==a[1] and re.fullmatch('[0-9a-f-]{36}',a[0]), 'Concurrent dispatch retries must return the same committed document'
PY
psql_admin -d "$database_name" <<SQL
select test.assert((select count(*) from private.operation_requests where request_id='b7900000-0000-4000-8000-000000000003')=1,'Concurrent dispatch transports persist one accepted request');
select test.assert((select count(*) from public.stock_transfers where organization_id='$logistics_org')=2,'Concurrent dispatch transports create one additional transfer');
select test.assert((select sum(quantity) from private.stock_balances where organization_id='$logistics_org' and product_id='$logistics_product')=8,'Concurrent dispatch retries deplete stock once');
SQL
