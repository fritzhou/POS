#!/usr/bin/env bash
# Sourced ONLY by isolated test/sql/run.sh after its pinned-image/network/volume
# checks. No database reset or production connection belongs in this script.
# Writers use real authorized RPCs; readers verify each returned report snapshot
# against independent cross-group invariants while those commits are happening.
psql_admin -d "$database_name" <<'SQL'
begin;
insert into auth.users(id,email,email_confirmed_at) values('d6c00000-0000-4000-8000-000000000001','report-concurrency@example.invalid',clock_timestamp());
set local role authenticated;
set local "request.jwt.claim.sub"='d6c00000-0000-4000-8000-000000000001';
select set_config('test.r6c_org',organization_id::text,true),set_config('test.r6c_branch',branch_id::text,true) from public.bootstrap_organization('Report snapshot race shop','Report snapshot race owner');
select set_config('test.r6c_product',(public.save_product(test.id('r6c_org'),null,null,'{"name":"Report snapshot sale item","sku":"R6-SNAPSHOT","price_minor":100}','Real report snapshot fixture product')->>'id'),true);
select public.receive_stock(test.id('r6c_org'),test.id('r6c_branch'),gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',test.id('r6c_product'),'quantity',80,'expected_revision',1)),null,null,'Physical units for concurrent report snapshots');
select set_config('test.r6c_shift',(public.open_shift(test.id('r6c_org'),test.id('r6c_branch'),gen_random_uuid(),10000,'PHP')->>'id'),true);
reset role;
create table test.r6c_context as select test.id('r6c_org') organization_id,test.id('r6c_branch') branch_id,test.id('r6c_product') product_id,test.id('r6c_shift') shift_id,
 (select revision from public.organizations where id=test.id('r6c_org')) settings_revision;
create function test.r6c_write(p_number integer) returns void language plpgsql security definer set search_path='' as $$
declare c test.r6c_context;sale jsonb;expense jsonb;product jsonb;refund_payments jsonb;
begin
 select * into c from test.r6c_context;
 sale:=public.checkout_sale(c.organization_id,c.branch_id,('d6c10000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,
  jsonb_build_object('shift_id',c.shift_id,'expected_settings_revision',c.settings_revision,'items',jsonb_build_array(jsonb_build_object('product_id',c.product_id,'quantity',1,'expected_revision',1)),
   'discount_minor',0,'payments',jsonb_build_array(jsonb_build_object('method','cash','amount_minor',40,'tendered_minor',50),
   jsonb_build_object('method','card','amount_minor',60,'manual_confirmed',true,'reference','Manual report-race card reference'))));
 expense:=public.record_expense(c.organization_id,c.branch_id,('d6c20000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,c.settings_revision,'PHP',7,
  case when p_number%2=0 then 'transport' else 'fees' end,case when p_number%2=0 then 'cash_drawer' else 'external' end,
  case when p_number%2=0 then c.shift_id else null end,'cash',true,'Actual manually paid race expense',null,'Operator confirmed report-race physical payment');
 if p_number%3=0 then
  perform public.reverse_expense(c.organization_id,c.branch_id,('d6c30000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,(expense->'expense'->>'id')::uuid,true,null,'Confirmed report-race compensation and actual drawer return when applicable');
 end if;
 if p_number%4=0 then
  select jsonb_agg(jsonb_build_object('original_payment_id',p->>'id','amount_minor',(p->>'amount_minor')::bigint,'manual_confirmed',true,'reference','Manual returned report-race payment')) into refund_payments from jsonb_array_elements(sale->'payments') p;
  perform public.reverse_sale(c.organization_id,(sale->>'id')::uuid,('d6c40000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,
   jsonb_build_object('kind',case when p_number%8=0 then 'void' else 'refund' end,'shift_id',c.shift_id,'return_stock',false,'reason','Confirmed report-race manual sale compensation',
    'items',jsonb_build_array(jsonb_build_object('sale_item_id',sale->'items'->0->>'id','quantity',1)),'payments',refund_payments));
 end if;
 product:=public.save_product(c.organization_id,null,null,jsonb_build_object('name','Report committed stock '||lpad(p_number::text,3,'0'),'sku','R6-COMMIT-'||p_number,'unit','pack','price_minor',0),'Create actual concurrently committed stock observation');
 perform public.receive_stock(c.organization_id,c.branch_id,('d6c50000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,
  jsonb_build_array(jsonb_build_object('product_id',product->>'id','quantity',2,'expected_revision',1)),null,null,'Two counted packs in concurrent report transaction');
end; $$;
create function test.r6c_sample() returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('sales',public.get_sales_report(c.organization_id,c.branch_id,statement_timestamp()-interval '1 day',statement_timestamp()+interval '1 day'),
  'expenses',public.get_expense_report(c.organization_id,c.branch_id,statement_timestamp()-interval '1 day',statement_timestamp()+interval '1 day'),
  'inventory',public.get_inventory_report(c.organization_id,c.branch_id,'',0,101)) from test.r6c_context c;
$$;
revoke all on function test.r6c_write(integer),test.r6c_sample() from public,anon,authenticated,service_role;
grant execute on function test.r6c_write(integer),test.r6c_sample() to authenticated;
commit;
SQL
python3 - "$result_dir" <<'PY'
from pathlib import Path
import sys
base=Path(sys.argv[1])
writer=['set role authenticated;',"set \"request.jwt.claim.sub\"='d6c00000-0000-4000-8000-000000000001';",'set statement_timeout=\'10s\';','select pg_advisory_lock(61234001);']
for n in range(1,21):
    writer.extend(['begin;',f'select test.r6c_write({n});','select pg_sleep(0.02);','commit;'])
writer.append('select pg_advisory_unlock(61234001);')
(base/'r6.writer.sql').write_text('\n'.join(writer)+'\n')
reader=['set role authenticated;',"set \"request.jwt.claim.sub\"='d6c00000-0000-4000-8000-000000000001';",'set statement_timeout=\'10s\';']
for _ in range(100):
    reader.extend(['select test.r6c_sample();','select pg_sleep(0.004);'])
(base/'r6.reader.sql').write_text('\n'.join(reader)+'\n')
PY
psql_admin -Atq -d "$database_name" < "$result_dir/r6.writer.sql" > "$result_dir/r6.writer.out" 2> "$result_dir/r6.writer.err" &
r6_writer_pid=$!
r6_marker_seen=false
for attempt in {1..60}; do
 if [[ "$(psql_admin -Atq -d "$database_name" -c "select exists(select 1 from pg_locks where locktype='advisory' and objid=61234001 and granted)")" == t ]];then r6_marker_seen=true;break;fi
 sleep 0.01
done
if [[ "$r6_marker_seen" != true ]];then echo 'Report snapshot writer failed to start its actual transaction stream.' >&2;exit 1;fi
pids=()
for reader_index in 1 2; do
 psql_admin -Atq -d "$database_name" < "$result_dir/r6.reader.sql" > "$result_dir/r6.reader.$reader_index.out" 2> "$result_dir/r6.reader.$reader_index.err" &
 pids+=("$!")
done
wait "$r6_writer_pid"
for pid in "${pids[@]}";do wait "$pid";done
psql_admin -Atq -d "$database_name" > "$result_dir/r6.final.out" <<'SQL'
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='d6c00000-0000-4000-8000-000000000001';
select test.r6c_sample();
commit;
SQL
python3 - "$result_dir" <<'PY'
from pathlib import Path
import json,sys
base=Path(sys.argv[1]);sales_counts=[];samples=0
for reader in (1,2):
    rows=[json.loads(line) for line in (base/f'r6.reader.{reader}.out').read_text().splitlines() if line.startswith('{')]
    if len(rows)!=100:sys.exit('Concurrent report reader must return every complete authorized snapshot.')
    for sample in rows:
        samples+=1
        for report in (sample['sales'],sample['expenses'],sample['inventory']):
            if report.get('source')!='server_posted':sys.exit('Report snapshot lost its authoritative source label.')
        for currency in sample['sales']['currencies']:
            sales_counts.append(currency['sale_count'])
            for field,payment_field in (('sales_total_minor','sales_minor'),('reversal_total_minor','reversed_minor'),('net_sales_minor','net_minor')):
                if currency[field]!=sum(p[payment_field] for p in currency['payments']):
                    sys.exit('Concurrent sale report mixed document and payment snapshots.')
            for field in ('sale_count','sales_subtotal_minor','sales_discount_minor','sales_tax_minor','sales_total_minor','reversal_count','refund_total_minor','void_total_minor','reversal_total_minor','net_sales_minor'):
                if currency[field]!=sum(d[field] for d in currency['daily']):
                    sys.exit('Concurrent sale report mixed aggregate and daily activity snapshots.')
            if currency['sales_total_minor']-currency['reversal_total_minor']!=currency['net_sales_minor']:
                sys.exit('Concurrent sale snapshot violates exact net arithmetic.')
        for currency in sample['expenses']['currencies']:
            for groups in ('categories','sources','daily'):
                for field in ('expense_count','expense_total_minor','reversal_count','reversal_total_minor','net_expense_minor'):
                    if currency[field]!=sum(g[field] for g in currency[groups]):
                        sys.exit('Concurrent expense report mixed category/source/daily snapshots.')
        inventory=sample['inventory'];items=inventory['items']
        if inventory['catalog_product_count']!=len(items) or inventory['stocked_product_count']!=sum(i['quantity']>0 for i in items) or inventory['deficit_product_count']!=sum(i['is_deficit'] for i in items) or inventory['low_stock_product_count']!=sum(i['is_low_stock'] for i in items):
            sys.exit('Concurrent inventory report mixed count and current-stock page snapshots.')
        if any(not i['has_movement'] or i['stock_revision']<1 for i in items):
            sys.exit('Concurrent stock snapshots fabricated or lost committed receipt evidence.')
final=json.loads((base/'r6.final.out').read_text())
final_sales=final['sales']['currencies'][0]
if final_sales['sale_count']!=20 or final_sales['sales_total_minor']!=2000 or final_sales['reversal_total_minor']!=500 or final_sales['net_sales_minor']!=1500:
    sys.exit('Final report snapshot must contain every actually committed financial batch.')
if samples!=200 or not sales_counts or min(sales_counts)>=20 or len(set(sales_counts+[20]))<2:
    sys.exit('Report race must observe changing committed activity, including the final complete batch.')
PY
psql_admin -d "$database_name" <<'SQL'
select test.assert((select count(*) from public.sales where organization_id=(select organization_id from test.r6c_context))=20,'Report race commits twenty actual server sales while readers inspect snapshots');
select test.assert((select count(*) from public.sale_payments where organization_id=(select organization_id from test.r6c_context))=40,'Report race retains both real split payments per accepted sale');
select test.assert((select count(*) from public.sale_reversals where organization_id=(select organization_id from test.r6c_context))=5,'Report race appends actual manual refunds and untouched voids');
select test.assert((select count(*) from public.expenses where organization_id=(select organization_id from test.r6c_context))=20,'Report race commits twenty manually confirmed external and drawer expenses');
select test.assert((select count(*) from public.expense_reversals where organization_id=(select organization_id from test.r6c_context))=6,'Report race keeps full expense compensations immutable');
select test.assert((select count(*) from private.stock_balances where organization_id=(select organization_id from test.r6c_context))=21,'Report race retains twenty-one actually received stock observations');
select test.assert((select private.phase3_expected_cash(shift_id) from test.r6c_context)=10551,'Report race drawer math excludes external expenses and includes actual cash return evidence');
SQL
