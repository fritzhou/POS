#!/usr/bin/env bash
set -euo pipefail
# This always recreates only nexapos_security_test in the isolated TEST container.
# Never point this at a production/user database or deploy mock_supabase.sql.
container_name="${1:-nexapos-postgres-test}"
if [[ "$container_name" != nexapos-postgres-test ]]; then
  echo 'Refusing to modify an arbitrary container; only nexapos-postgres-test is supported.' >&2
  exit 1
fi
# Before ANY SQL mutation, require the exact isolated, pinned disposable server.
# Inspect only structural fields, never environment or credential values.
inspection="$(docker inspect --format '{"network":{{json .HostConfig.NetworkMode}},"ports":{{json .NetworkSettings.Ports}},"port_bindings":{{json .HostConfig.PortBindings}},"image":{{json .Config.Image}},"mounts":{{json .Mounts}},"running":{{json .State.Running}}}' "$container_name")"
printf '%s' "$inspection" | python3 -c '
import json,re,sys
state=json.load(sys.stdin)
expected="postgres@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3"
safe=(state.get("network")=="none" and state.get("running") is True and state.get("image")==expected
      and not state.get("port_bindings") and not any((state.get("ports") or {}).values()))
for mount in state.get("mounts") or []:
    safe=safe and mount.get("Type")=="volume" and bool(re.fullmatch(r"[a-f0-9]{64}",mount.get("Name",""))) and mount.get("Destination")=="/var/lib/postgresql/data"
if not safe:
    sys.exit("Refusing database reset: test container isolation, image, or anonymous-volume checks failed.")
'
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
database_name=nexapos_security_test
psql_admin() { docker exec -i "$container_name" psql -X -U postgres -v ON_ERROR_STOP=1 "$@"; }
run_assertions() {
  printf 'Running assertions: %s\n' "$(basename "$1")"
  psql_admin -d "$database_name" < "$1"
}
psql_admin -d postgres -c "DROP DATABASE IF EXISTS $database_name" -c "CREATE DATABASE $database_name"
run_assertions "$repo_root/test/sql/mock_supabase.sql"
for migration in "$repo_root"/supabase/migrations/*.sql; do
  psql_admin -d "$database_name" < "$migration"
  if [[ "$(basename "$migration")" == 202610090003_verified_owner_bootstrap.sql ]]; then
    # Validate Phase 1 before Phase 2 supersedes direct catalog writes with CAS RPCs.
    run_assertions "$repo_root/test/sql/security_assertions.sql"
  fi
done
if [[ -f "$repo_root/test/sql/phase2_assertions.sql" ]]; then
  run_assertions "$repo_root/test/sql/phase2_assertions.sql"
fi
if [[ -f "$repo_root/test/sql/invitation_assertions.sql" ]]; then
  run_assertions "$repo_root/test/sql/invitation_assertions.sql"
fi

if [[ -f "$repo_root/test/sql/phase3_assertions.sql" ]]; then
  run_assertions "$repo_root/test/sql/phase3_assertions.sql"
fi
if [[ -f "$repo_root/test/sql/phase4_assertions.sql" ]]; then
  run_assertions "$repo_root/test/sql/phase4_assertions.sql"
fi

if [[ -f "$repo_root/test/sql/security_phase5_assertions.sql" ]]; then
  run_assertions "$repo_root/test/sql/security_phase5_assertions.sql"
fi
if [[ -f "$repo_root/test/sql/security_phase5_pin_assertions.sql" ]]; then
  run_assertions "$repo_root/test/sql/security_phase5_pin_assertions.sql"
fi
if [[ -f "$repo_root/test/sql/purchases_phase6_assertions.sql" ]]; then
  run_assertions "$repo_root/test/sql/purchases_phase6_assertions.sql"
fi
if [[ -f "$repo_root/test/sql/expenses_phase6_assertions.sql" ]]; then
  run_assertions "$repo_root/test/sql/expenses_phase6_assertions.sql"
fi
if [[ -f "$repo_root/test/sql/reports_phase6_assertions.sql" ]]; then
  run_assertions "$repo_root/test/sql/reports_phase6_assertions.sql"
fi

if [[ -f "$repo_root/test/sql/logistics_phase6b_assertions.sql" ]]; then
  run_assertions "$repo_root/test/sql/logistics_phase6b_assertions.sql"
fi

if [[ -f "$repo_root/test/sql/invitations_phase6d_assertions.sql" ]]; then
  run_assertions "$repo_root/test/sql/invitations_phase6d_assertions.sql"
fi

printf 'Running assertions: legacy_concurrency\n'
# Multiple independent PostgreSQL connections race on the SAME verified owner.
# Each must return one identical organization, including after lost-response retry.
result_dir="$(mktemp -d)"
trap 'rm -rf "$result_dir"' EXIT
pids=()
for index in {1..8}; do
  psql_admin -Atq -d "$database_name" > "$result_dir/$index" <<'SQL' &
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '00000000-0000-4000-8000-000000000011';
select organization_id from public.bootstrap_organization('Concurrent Shop','Concurrent Owner');
commit;
SQL
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
unique_results="$(cat "$result_dir"/* | sort -u | wc -l)"
if [[ "$unique_results" -ne 1 ]]; then
  echo 'Concurrent bootstrap returned inconsistent IDs' >&2
  exit 1
fi
psql_admin -d "$database_name" <<'SQL'
select test.assert((select count(*) from public.organizations where owner_user_id = '00000000-0000-4000-8000-000000000011') = 1,'Eight concurrent calls create one organization');
select test.assert((select count(*) from public.branches b join public.organizations o on o.id = b.organization_id where o.owner_user_id = '00000000-0000-4000-8000-000000000011') = 1,'Concurrent calls create one Main Branch');
select test.assert((select count(*) from public.organization_memberships where user_id = '00000000-0000-4000-8000-000000000011') = 1,'Concurrent calls create one Owner membership');
select test.assert((select count(*) from public.audit_logs where user_id = '00000000-0000-4000-8000-000000000011' and action = 'organization.bootstrap') = 1,'Concurrent calls create one authoritative audit event');
SQL
# Race two writers against ONE expected revision. Exactly one must commit and
# the other must return the PostgreSQL serialization/CAS conflict, not overwrite.
read -r cas_product cas_organization cas_revision < <(psql_admin -Atq -d "$database_name" -c "select p.id::text || ' ' || p.organization_id::text || ' ' || p.revision::text from public.products p join public.organizations o on o.id=p.organization_id where o.owner_user_id='00000000-0000-4000-8000-000000000001' and p.sku='PHASE2'")
if [[ ! "$cas_product" =~ ^[0-9a-f-]{36}$ || ! "$cas_organization" =~ ^[0-9a-f-]{36}$ || ! "$cas_revision" =~ ^[0-9]+$ ]]; then
  echo 'Concurrent CAS fixture is missing or invalid.' >&2
  exit 1
fi
pids=()
for index in 1 2; do
  (
    if psql_admin -Atq -d "$database_name" > "$result_dir/cas.$index.out" 2> "$result_dir/cas.$index.err" <<SQL
\set VERBOSITY verbose
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '00000000-0000-4000-8000-000000000001';
select public.save_product('$cas_organization'::uuid,'$cas_product'::uuid,$cas_revision,jsonb_build_object('price_minor',6000+$index),'Concurrent catalog CAS validation');
commit;
SQL
    then printf '0' > "$result_dir/cas.$index.status";
    else printf '%s' "$?" > "$result_dir/cas.$index.status";
    fi
  ) &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
python3 - "$result_dir" <<'PY'
from pathlib import Path
import sys
base=Path(sys.argv[1])
statuses=[(base/f'cas.{n}.status').read_text() for n in (1,2)]
errors=[(base/f'cas.{n}.err').read_text() for n in (1,2)]
if sorted(statuses)!=['0','3'] or sum('40001:' in error for error in errors)!=1:
    sys.exit('Concurrent CAS validation failed: expected one commit and one 40001 conflict.')
PY
psql_admin -d "$database_name" <<SQL
select test.assert((select revision from public.products where id='$cas_product'::uuid)=$cas_revision+1,'Concurrent catalog writers increment one revision');
select test.assert((select count(*) from public.audit_logs where entity_id='$cas_product'::uuid and action='products.update' and reason='Concurrent catalog CAS validation')=1,'Concurrent catalog writers commit one authoritative audit event');
SQL
# Two independent actors race for the last physical unit. Product/ledger locks
# must produce exactly one accepted sale and one insufficient-stock failure.
psql_admin -d "$database_name" <<'SQL'
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='00000000-0000-4000-8000-000000000001';
select set_config('test.org_a',id::text,true) from public.organizations where owner_user_id=auth.uid();
select set_config('test.branch_a',id::text,true) from public.branches where organization_id=test.id('org_a') and code='MAIN';
select set_config('test.race_product',(public.save_product(test.id('org_a'),null,null,'{"name":"Last-unit concurrency fixture","sku":"P3-RACE","price_minor":100}','Concurrent checkout fixture')->>'id'),true);
select public.receive_stock(test.id('org_a'),test.id('branch_a'),'99000000-0000-4000-8000-000000000001',
 jsonb_build_array(jsonb_build_object('product_id',test.id('race_product'),'quantity',1,'expected_revision',1)),null,null,'Single physical unit for competing cashiers');
commit;
SQL
read -r race_org race_branch race_product race_settings < <(psql_admin -Atq -d "$database_name" -c "select p.organization_id::text||' '||b.id::text||' '||p.id::text||' '||o.revision::text from public.products p join public.organizations o on o.id=p.organization_id join public.branches b on b.organization_id=p.organization_id and b.code='MAIN' where p.sku='P3-RACE'")
for value in "$race_org" "$race_branch" "$race_product"; do
  if [[ ! "$value" =~ ^[0-9a-f-]{36}$ ]]; then echo 'Financial race fixture identifier invalid.' >&2; exit 1; fi
done
if [[ ! "$race_settings" =~ ^[0-9]+$ ]]; then echo 'Financial race revision invalid.' >&2; exit 1; fi
pids=()
for actor_index in 4 5; do
 (
 actor_uuid="00000000-0000-4000-8000-00000000000$actor_index"
 actor_shift="$(psql_admin -Atq -d "$database_name" -c "select s.id from public.shifts s where s.actor_user_id='$actor_uuid'::uuid and s.organization_id='$race_org'::uuid and not exists(select 1 from public.shift_closures c where c.shift_id=s.id)")"
 if [[ ! "$actor_shift" =~ ^[0-9a-f-]{36}$ ]]; then echo 'Financial race requires an existing test-only open shift.' >&2; exit 1; fi
 if psql_admin -Atq -d "$database_name" > "$result_dir/stock.$actor_index.out" 2> "$result_dir/stock.$actor_index.err" <<SQL
\set VERBOSITY verbose
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='$actor_uuid';
select public.checkout_sale('$race_org','$race_branch','99000000-0000-4000-8000-00000000000$actor_index',
 jsonb_build_object('shift_id','$actor_shift','expected_settings_revision',$race_settings,'items',jsonb_build_array(jsonb_build_object('product_id','$race_product','quantity',1,'expected_revision',1)),
 'discount_minor',0,'payments',jsonb_build_array(jsonb_build_object('method','cash','amount_minor',112,'tendered_minor',112))))->>'id';
commit;
SQL
 then printf '0' > "$result_dir/stock.$actor_index.status"; else printf '%s' "$?" > "$result_dir/stock.$actor_index.status"; fi
 ) &
 pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
python3 - "$result_dir" <<'PY_STOCK'
from pathlib import Path
import sys
base=Path(sys.argv[1]); statuses=[(base/f'stock.{n}.status').read_text() for n in (4,5)]
errors=[(base/f'stock.{n}.err').read_text() for n in (4,5)]
if sorted(statuses)!=['0','3'] or sum('23514:' in error for error in errors)!=1:
    sys.exit('Concurrent stock checkout failed: expected one acceptance and one insufficient-stock failure.')
PY_STOCK
psql_admin -d "$database_name" <<SQL
select test.assert((select count(*) from public.sale_items where product_id='$race_product')=1,'Two competing cashiers sell the last unit exactly once');
select test.assert((select quantity from private.stock_balances where product_id='$race_product' and branch_id='$race_branch')=0,'Concurrent sale never creates negative branch stock');
select test.assert((select count(*) from public.stock_movements where product_id='$race_product')=2,'Stock race commits one receipt and one depletion movement');
select test.assert((select count(*) from private.operation_requests where request_id in ('99000000-0000-4000-8000-000000000004','99000000-0000-4000-8000-000000000005'))=1,'Failed competing checkout has no accepted request record');
SQL
# Two transports retry the same actor/request while the first is committing.
# Both must resolve to one actual immutable receipt rather than double-deplete.
manager_shift="$(psql_admin -Atq -d "$database_name" -c "select s.id from public.shifts s where s.actor_user_id='00000000-0000-4000-8000-000000000004'::uuid and s.organization_id='$race_org'::uuid and not exists(select 1 from public.shift_closures c where c.shift_id=s.id)")"
if [[ ! "$manager_shift" =~ ^[0-9a-f-]{36}$ ]]; then echo 'Idempotency race shift invalid.' >&2; exit 1; fi
pids=()
for index in 1 2; do
 psql_admin -Atq -d "$database_name" > "$result_dir/idem.$index.out" 2> "$result_dir/idem.$index.err" <<SQL &
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='00000000-0000-4000-8000-000000000004';
select public.checkout_sale('$race_org','$race_branch','99000000-0000-4000-8000-000000000010',
 jsonb_build_object('shift_id','$manager_shift','expected_settings_revision',$race_settings,'items',jsonb_build_array(jsonb_build_object('product_id','91000000-0000-4000-8000-000000000002','quantity',1,'expected_revision',1)),
 'discount_minor',0,'payments',jsonb_build_array(jsonb_build_object('method','cash','amount_minor',747,'tendered_minor',747))))->>'id';
commit;
SQL
 pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
python3 - "$result_dir" <<'PY_IDEM'
from pathlib import Path
import re,sys
base=Path(sys.argv[1]); results=[(base/f'idem.{n}.out').read_text().strip() for n in (1,2)]
if results[0]!=results[1] or not re.fullmatch(r'[0-9a-f-]{36}',results[0]):
    sys.exit('Concurrent same-request retry must return one identical accepted sale identifier.')
PY_IDEM
psql_admin -d "$database_name" <<'SQL'
select test.assert((select count(*) from private.operation_requests where request_id='99000000-0000-4000-8000-000000000010')=1,'Concurrent same-request transports commit one request record');
select test.assert((select count(*) from public.stock_movements m join private.operation_requests r on r.result_id=m.sale_id where r.request_id='99000000-0000-4000-8000-000000000010')=1,'Concurrent same-request transports deplete inventory once');
select test.assert((select count(*) from public.audit_logs a join private.operation_requests r on r.result_id=a.entity_id where r.request_id='99000000-0000-4000-8000-000000000010' and a.action='sale.accepted')=1,'Concurrent same-request transports create one financial audit');
SQL
if [[ -f "$repo_root/test/sql/phase4_concurrency.sh" ]]; then
  printf 'Running assertions: phase4_concurrency\n'
  source "$repo_root/test/sql/phase4_concurrency.sh"
fi
if [[ -f "$repo_root/test/sql/security_phase5_concurrency.sh" ]]; then
  printf 'Running assertions: security_phase5_concurrency\n'
  source "$repo_root/test/sql/security_phase5_concurrency.sh"
fi
if [[ -f "$repo_root/test/sql/purchases_phase6_concurrency.sh" ]]; then
  printf 'Running assertions: purchases_phase6_concurrency\n'
  source "$repo_root/test/sql/purchases_phase6_concurrency.sh"
fi
if [[ -f "$repo_root/test/sql/expenses_phase6_concurrency.sh" ]]; then
  printf 'Running assertions: expenses_phase6_concurrency\n'
  source "$repo_root/test/sql/expenses_phase6_concurrency.sh"
fi
if [[ -f "$repo_root/test/sql/reports_phase6_concurrency.sh" ]]; then
  printf 'Running assertions: reports_phase6_concurrency\n'
  source "$repo_root/test/sql/reports_phase6_concurrency.sh"
fi
source "$repo_root/test/sql/logistics_phase6b_concurrency.sh"
source "$repo_root/test/sql/invitations_phase6d_concurrency.sh"
echo 'PostgreSQL security, exact financial arithmetic, atomic rollback and concurrent transaction checks passed.'
