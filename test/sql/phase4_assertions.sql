-- Disposable mock-Auth test database ONLY. Proof strings below intentionally
-- exercise SQL's trusted service boundary; real Ed25519 verification is covered
-- separately in the offline-sync Edge tests. Never deploy these fixtures.
begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('a4000000-0000-4000-8000-000000000001','phase4-owner@example.invalid',now()),
 ('a4000000-0000-4000-8000-000000000002','phase4-other@example.invalid',now()),
 ('a4000000-0000-4000-8000-000000000003','phase4-unverified@example.invalid',null);
set local role authenticated;
set local "request.jwt.claim.sub"='a4000000-0000-4000-8000-000000000001';
select set_config('test.p4_org',organization_id::text,true),set_config('test.p4_branch',branch_id::text,true)
 from public.bootstrap_organization('Phase 4 fixture','Offline Owner');
select public.save_business_settings(test.id('p4_org'),1,'{"tax_bps":1250}','Freeze offline tax fixture');
select set_config('test.p4_product',(public.save_product(test.id('p4_org'),null,null,
 '{"name":"Café 😀 \"frozen\" product","sku":"P4-FIRST","barcode":"P4-BARCODE","price_minor":100,"cost_minor":9999}',
 'Freeze offline product fixture')->>'id'),true);
select public.receive_stock(test.id('p4_org'),test.id('p4_branch'),gen_random_uuid(),
 jsonb_build_array(jsonb_build_object('product_id',test.id('p4_product'),'quantity',2,'expected_revision',1)),null,null,'Two real units for offline race');
select set_config('test.p4_shift',(public.open_shift(test.id('p4_org'),test.id('p4_branch'),gen_random_uuid(),1000,'PHP')->>'id'),true);
select set_config('test.p4_device','a4100000-0000-4000-8000-000000000001',true);
select set_config('test.p4_challenge',public.prepare_offline_device_challenge(test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),repeat('A',43),'SQL fixture device','android')::text,true);
select test.assert(length(current_setting('test.p4_challenge')::jsonb->>'nonce')=43,'Enrollment challenge has bounded base64url nonce');
select test.expect_error('select * from private.offline_devices','42501','Authenticated clients cannot inspect enrolled device registry');
select test.expect_error($q$select public.prepare_offline_grant(auth.uid(),test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),gen_random_uuid(),'https://example.invalid','test-key')$q$,'42501','Authenticated role cannot execute grant preparation service RPC');
select test.expect_error($q$select public.ingest_offline_event(auth.uid(),test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),'{}',repeat('a',64),'{}',repeat('A',86))$q$,'42501','Authenticated client cannot call trusted offline ingestion');
set local role anon;
select test.expect_error($q$select public.prepare_offline_device_challenge(test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),repeat('A',43),'Anonymous device','android')$q$,'42501','Anonymous enrollment denied');
set local role service_role;
select public.complete_offline_device_enrollment('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),
 (current_setting('test.p4_challenge')::jsonb->>'challenge_id')::uuid,repeat('A',86));
select test.assert(public.complete_offline_device_enrollment('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),
 (current_setting('test.p4_challenge')::jsonb->>'challenge_id')::uuid,repeat('A',86))->>'device_id'=test.id('p4_device')::text,'Identical enrollment proof returns original device');
select test.expect_error($q$select public.complete_offline_device_enrollment('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),(current_setting('test.p4_challenge')::jsonb->>'challenge_id')::uuid,repeat('B',86))$q$,'23505','Changed enrollment signature conflicts');
select test.expect_error($q$select public.get_offline_verification_context('a4000000-0000-4000-8000-000000000002',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'))$q$,'42501','Service caller still checks actual actor membership');
select test.expect_error($q$select public.get_offline_verification_context('a4000000-0000-4000-8000-000000000003',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'))$q$,'42501','Service caller rejects unverified Auth identity');
-- A fresh enrollment proof on the same branch is needed when preparation's
-- response is lost. It preserves the original binding and adds public proof.
set local role authenticated;
select set_config('test.p4_challenge_retry',public.prepare_offline_device_challenge(test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),repeat('A',43),'Same actual device','android')::text,true);
select test.expect_error($q$select public.prepare_offline_device_challenge(test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),repeat('B',43),'Replace enrolled key','android')$q$,'23505','Fresh enrollment cannot replace retained public key');
reset role;
insert into public.branches(id,organization_id,code,name) values('a4700000-0000-4000-8000-000000000001',test.id('p4_org'),'P4-SECOND','Second authorized branch');
set local role authenticated;
select set_config('test.p4_challenge_branch',public.prepare_offline_device_challenge(test.id('p4_org'),'a4700000-0000-4000-8000-000000000001',test.id('p4_device'),repeat('A',43),'Same actual device','android')::text,true);
set local role service_role;
select test.assert(public.complete_offline_device_enrollment('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),
 (current_setting('test.p4_challenge_retry')::jsonb->>'challenge_id')::uuid,repeat('B',86))->>'device_id'=test.id('p4_device')::text,'Fresh same-key proof resolves enrollment before a preparation retry');
select test.assert(public.complete_offline_device_enrollment('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),'a4700000-0000-4000-8000-000000000001',test.id('p4_device'),
 (current_setting('test.p4_challenge_branch')::jsonb->>'challenge_id')::uuid,repeat('C',86))->>'branch_id'='a4700000-0000-4000-8000-000000000001','One actor key enrolls a separately proven authorized branch');
select test.assert(public.get_offline_verification_context('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),'a4700000-0000-4000-8000-000000000001',test.id('p4_device'))->>'public_key'=repeat('A',43),'Second branch binding resolves same public key');
reset role;
select test.assert((select count(*) from private.offline_devices where id=test.id('p4_device'))=1,'Branch enrollment retains one OS key identity');
select test.assert((select count(*) from private.offline_device_branches where device_id=test.id('p4_device'))=2,'Branch authorizations are separately retained');
select test.assert((select count(*) from private.offline_device_proofs where device_id=test.id('p4_device'))=3,'Fresh enrollment proofs append without rewriting old evidence');
set local role service_role;
select set_config('test.p4_prepare',public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),
 'a4200000-0000-4000-8000-000000000001','https://example.invalid','test-key')::text,true);
select set_config('test.p4_grant',(current_setting('test.p4_prepare')::jsonb->'claims'->>'grant_id'),true);
select test.assert(public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),
 'a4200000-0000-4000-8000-000000000001','https://example.invalid','test-key')->'claims'=current_setting('test.p4_prepare')::jsonb->'claims','Lost preparation response retries exactly same frozen grant');
select test.expect_error($q$select public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),gen_random_uuid(),'https://example.invalid','test-key')$q$,'23514','A device cannot multiply unreleased grants');
select test.assert(not(current_setting('test.p4_prepare')::jsonb->'snapshot'->'products'->0 ? 'cost_minor'),'Offline product snapshot omits costs even for Owner');
select test.assert(current_setting('test.p4_prepare')::jsonb->'snapshot'->'stock'->0->>'revision'='1','Stock snapshot carries authoritative movement revision');
select test.expect_error($q$select public.finalize_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),test.id('p4_grant'),jsonb_set(current_setting('test.p4_prepare')::jsonb->'claims','{tax_bps}','0'),repeat('A',86))$q$,'23505','Service signing cannot change retained claim tax');
select public.finalize_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),test.id('p4_grant'),current_setting('test.p4_prepare')::jsonb->'claims',repeat('A',86));
select test.assert(public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),'a4200000-0000-4000-8000-000000000001','https://example.invalid','rotated-key')->>'signature'=repeat('A',86),'Lost finalized response returns retained signature across server key rotation');
select test.assert(public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),'a4200000-0000-4000-8000-000000000001','https://example.invalid','rotated-key')->'claims'=current_setting('test.p4_prepare')::jsonb->'claims','Server key rotation preserves original frozen grant claims');
select test.expect_error($q$select public.release_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),test.id('p4_grant'),1,repeat('A',86))$q$,'23514','Release cannot abandon an unsubmitted signed final sequence');
set local role authenticated;
select test.expect_error($q$select public.close_shift(test.id('p4_org'),test.id('p4_shift'),gen_random_uuid(),1000,'Attempt closure with offline grant')$q$,'23514','Unreleased offline grant blocks normal shift closure');
-- A paid local snapshot survives later catalog/tax changes and another online
-- sale consuming physical stock. No repricing is allowed during ingestion.
select public.save_product(test.id('p4_org'),test.id('p4_product'),1,'{"price_minor":5000}','Change price after grant issuance');
select public.save_business_settings(test.id('p4_org'),2,'{"tax_bps":500}','Change tax after grant issuance');
select public.checkout_sale(test.id('p4_org'),test.id('p4_branch'),gen_random_uuid(),jsonb_build_object('shift_id',test.id('p4_shift'),'expected_settings_revision',3,'discount_minor',0,
 'items',jsonb_build_array(jsonb_build_object('product_id',test.id('p4_product'),'quantity',2,'expected_revision',2)),
 'payments',jsonb_build_array(jsonb_build_object('method','cash','amount_minor',10500,'tendered_minor',10500))));
reset role;
create function test.p4_event(p_number integer,p_quantity integer default 1,p_method text default 'cash') returns jsonb language sql as $$
 select jsonb_build_object('event_id',('a4300000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,
  'organization_id',test.id('p4_org'),'branch_id',test.id('p4_branch'),'device_id',test.id('p4_device'),'actor_id','a4000000-0000-4000-8000-000000000001',
  'event_type','sale.created','schema_version',1,'occurred_at',current_setting('test.p4_prepare')::jsonb->'claims'->>'issued_at',
  'payload',jsonb_build_object('id',('a4400000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,'shift_id',test.id('p4_shift'),'customer_id',null,
   'receipt_number','OFFLINE-'||p_number,'currency','PHP','subtotal_minor',100*p_quantity,'discount_minor',0,'tax_minor',(100*p_quantity*1250+5000)/10000,'total_minor',100*p_quantity+(100*p_quantity*1250+5000)/10000,
   'items',jsonb_build_array(jsonb_build_object('id',('a4500000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,'product_id',test.id('p4_product'),
    'sku_snapshot','P4-FIRST','name_snapshot','Café 😀 "frozen" product','quantity',p_quantity,'unit_price_minor',100,'discount_minor',0,
    'tax_minor',(100*p_quantity*1250+5000)/10000,'line_total_minor',100*p_quantity+(100*p_quantity*1250+5000)/10000)),
   'payments',jsonb_build_array(jsonb_build_object('id',('a4600000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,'method',p_method,
    'amount_minor',100*p_quantity+(100*p_quantity*1250+5000)/10000,'verification_mode',case when p_method='cash' then 'cash' else 'manual' end,'reference',case when p_method<>'cash' then 'MANUAL-LOCAL-001' end))));
$$;
create function test.p4_authorization(p_number integer,p_sequence integer,p_cash boolean default true) returns jsonb language sql as $$
 select jsonb_build_object('grant_id',test.id('p4_grant'),'sequence',p_sequence,'payment_evidence',jsonb_build_object('a4600000-0000-4000-8000-'||lpad(p_number::text,12,'0'),
  case when p_cash then jsonb_build_object('tendered_minor',200) else jsonb_build_object('manual_confirmed',true) end));
$$;
create function test.p4_ingest(p_number integer,p_sequence integer,p_method text default 'cash') returns jsonb language sql as $$
 select public.ingest_offline_event('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),
  test.p4_event(p_number,1,p_method),private.offline_digest(test.p4_event(p_number,1,p_method)),test.p4_authorization(p_number,p_sequence,p_method='cash'),repeat('A',86));
$$;
-- These test-only wrappers run as invoker. Hash access merely lets the trusted
-- fixture prepare digest; production grants remain untouched.
grant execute on function test.p4_event(integer,integer,text),test.p4_authorization(integer,integer,boolean),test.p4_ingest(integer,integer,text) to service_role;
select test.assert(private.offline_canonical('{"2":"two","10":"ten","unicode":"Café 😀","line":"\n\t"}'::jsonb)='{"10":"ten","2":"two","line":"\n\t","unicode":"Café 😀"}','SQL canonical bytes preserve lexical numeric keys and Unicode');
select test.assert(private.offline_digest(current_setting('test.p4_prepare')::jsonb->'snapshot')=current_setting('test.p4_prepare')::jsonb->'claims'->>'snapshot_digest','Retained snapshot digest recomputes exactly');
-- SQL helper stays private in production. Test fixture computes event hashes
-- under owner then passes the exact JSON through normal service RPC grants.
select set_config('test.p4_event1',test.p4_event(1)::text,true),set_config('test.p4_digest1',private.offline_digest(test.p4_event(1)),true);
set local role service_role;
select test.expect_error($q$select public.ingest_offline_event('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),current_setting('test.p4_event1')::jsonb,repeat('a',64),test.p4_authorization(1,1),repeat('A',86))$q$,'22023','Wrong event digest cannot accept a paid sale');
select test.expect_error($q$select public.ingest_offline_event('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),current_setting('test.p4_event1')::jsonb,current_setting('test.p4_digest1'),test.p4_authorization(1,2),repeat('A',86))$q$,'23505','Event sequence cannot skip an earlier paid sale');
-- This fixture-only definer computes canonical hashes under the database
-- owner, then invokes the same service RPC. It is never deployed with migrations.
reset role;
create function test.p4_ingest_wire(p_event jsonb,p_authorization jsonb,p_signature text default repeat('A',86)) returns jsonb language sql security definer set search_path='' as $$
 select public.ingest_offline_event('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),p_event,
  private.offline_digest(p_event),p_authorization,p_signature);
$$;
set local role service_role;
select test.expect_error($q$select test.p4_ingest_wire(test.p4_event(1)-'occurred_at',test.p4_authorization(1,1))$q$,'22023','Required immutable observation cannot be omitted');
select test.expect_error($q$select test.p4_ingest_wire(jsonb_set(test.p4_event(1),'{occurred_at}','null'),test.p4_authorization(1,1))$q$,'22023','Null observation cannot fall through SQL time checks');
select test.expect_error($q$select test.p4_ingest_wire(jsonb_set(test.p4_event(1),'{occurred_at}','"2026-02-30T00:00:00Z"'),test.p4_authorization(1,1))$q$,'22023','Invalid calendar observation is rejected');
select test.expect_error($q$select test.p4_ingest_wire(jsonb_set(test.p4_event(1),'{event_id}','null'),test.p4_authorization(1,1))$q$,'22023','Null immutable event identifier is rejected');
select test.expect_error($q$select test.p4_ingest_wire(test.p4_event(1)||'{"client_override":true}',test.p4_authorization(1,1))$q$,'22023','Unknown event fields cannot authorize hidden behavior');
select test.expect_error($q$select test.p4_ingest_wire(jsonb_set(test.p4_event(1),'{actor_id}','"a4000000-0000-4000-8000-000000000002"'),test.p4_authorization(1,1))$q$,'42501','Signed body still must match verified current actor');
select test.expect_error($q$select test.p4_ingest_wire(jsonb_set(test.p4_event(1),'{branch_id}','"a4700000-0000-4000-8000-000000000001"'),test.p4_authorization(1,1))$q$,'42501','A grant cannot cross even another authorized branch');
select test.expect_error($q$select test.p4_ingest_wire(test.p4_event(1),jsonb_set(test.p4_authorization(1,1),'{payment_evidence,a4600000-0000-4000-8000-000000000001,tendered_minor}','112'))$q$,'22023','Cash tender cannot be below immutable paid allocation');
select test.expect_error($q$select test.p4_ingest_wire(test.p4_event(1,1,'gcash'),jsonb_set(test.p4_authorization(1,1,false),'{payment_evidence,a4600000-0000-4000-8000-000000000001,manual_confirmed}','false'))$q$,'22023','Offline digital payment requires explicit manual confirmation');
select test.expect_error($q$select test.p4_ingest_wire(jsonb_set(test.p4_event(1,1,'gcash'),'{payload,payments,0,reference}','null'),test.p4_authorization(1,1,false))$q$,'22023','Offline manual tender requires a retained reference');
select test.expect_error($q$select test.p4_ingest_wire(jsonb_set(test.p4_event(1),'{payload,items,0,tax_minor}','12'),test.p4_authorization(1,1))$q$,'22023','Line tax uses original half-up integer arithmetic');
select test.expect_error($q$select test.p4_ingest_wire(jsonb_set(test.p4_event(1),'{payload,items,0,unit_price_minor}','5000'),test.p4_authorization(1,1))$q$,'22023','Current catalog price cannot replace signed frozen price');
select test.expect_error($q$select test.p4_ingest_wire(jsonb_set(test.p4_event(1),'{payload,discount_minor}','1'),test.p4_authorization(1,1))$q$,'22023','Owner grant does not authorize offline discounts');
select test.expect_error($q$select test.p4_ingest_wire(jsonb_set(test.p4_event(1),'{payload,customer_id}','"a4000000-0000-4000-8000-000000000002"'),test.p4_authorization(1,1))$q$,'22023','Offline receipts cannot invent a customer association');
select test.expect_error($q$select test.p4_ingest_wire(jsonb_set(test.p4_event(1),'{payload,currency}','"USD"'),test.p4_authorization(1,1))$q$,'22023','Frozen shift currency cannot change on ingestion');
select test.expect_error($q$select test.p4_ingest_wire(jsonb_set(test.p4_event(1),'{occurred_at}',to_jsonb(private.offline_time((current_setting('test.p4_prepare')::jsonb->'claims'->>'issued_at')::timestamptz-interval '1 millisecond'))),test.p4_authorization(1,1))$q$,'42501','Observation before signed issuance is rejected');
select test.expect_error($q$select test.p4_ingest_wire(jsonb_set(test.p4_event(1),'{occurred_at}',current_setting('test.p4_prepare')::jsonb->'claims'->'expires_at'),test.p4_authorization(1,1))$q$,'42501','Observation at exact expiry cannot capture a new paid sale');
select test.expect_error($q$select public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),'a4200000-0000-4000-8000-000000000001','https://changed.invalid','test-key')$q$,'23505','Preparation retry cannot change retained issuer');
-- Time simulation only changes the disposable grant rows behind immutable
-- triggers, within savepoints. No production API can alter retained bounds.
reset role;
savepoint expiry_grace;
alter table private.offline_grants disable trigger immutable_history;
update private.offline_grants set issued_at=statement_timestamp()-interval '9 hours',expires_at=statement_timestamp()-interval '1 hour' where id=test.id('p4_grant');
alter table private.offline_grants enable trigger immutable_history;
select test.assert(test.p4_ingest_wire(jsonb_set(test.p4_event(1),'{occurred_at}',to_jsonb(private.offline_time((select issued_at+interval '1 hour' from private.offline_grants where id=test.id('p4_grant'))))),test.p4_authorization(1,1))->>'status'='accepted','Captured within lifetime remains ingestible during 72-hour grace');
rollback to savepoint expiry_grace;
savepoint expiry_late;
alter table private.offline_grants disable trigger immutable_history;
update private.offline_grants set issued_at=statement_timestamp()-interval '81 hours',expires_at=statement_timestamp()-interval '73 hours' where id=test.id('p4_grant');
alter table private.offline_grants enable trigger immutable_history;
select test.expect_error($q$select test.p4_ingest_wire(jsonb_set(test.p4_event(1),'{occurred_at}',to_jsonb(private.offline_time((select issued_at+interval '1 hour' from private.offline_grants where id=test.id('p4_grant'))))),test.p4_authorization(1,1))$q$,'42501','New ingestion beyond 72-hour grace fails without posting');
rollback to savepoint expiry_late;
savepoint grant_amount;
update private.offline_grant_states set total_minor=100000000 where grant_id=test.id('p4_grant');
select test.expect_error($q$select test.p4_ingest_wire(test.p4_event(1),test.p4_authorization(1,1))$q$,'22023','Cumulative original paid total cannot exceed grant ceiling');
rollback to savepoint grant_amount;
savepoint released_empty;
set local role service_role;
select test.assert(public.release_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),test.id('p4_grant'),0,repeat('A',86))->>'status'='released','Signed empty grant release returns explicit released status');
select test.expect_error($q$select test.p4_ingest_wire(test.p4_event(1),test.p4_authorization(1,1))$q$,'23514','Released final boundary blocks every later new event');
set local role authenticated;
select test.assert(public.close_shift(test.id('p4_org'),test.id('p4_shift'),gen_random_uuid(),11500,'Close after verified empty release')->'closure'->>'closed_at' is not null,'Normal shift can close after exact signed final release');
reset role;
rollback to savepoint released_empty;
savepoint localhost_issuer;
select public.release_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),test.id('p4_grant'),0,repeat('A',86));
select test.assert(public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),gen_random_uuid(),'http://127.0.0.1:54321','test-key')->'claims'->>'issuer'='http://127.0.0.1:54321','Explicit local Supabase HTTP origin is supported for development');
select test.expect_error($q$select public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),gen_random_uuid(),'http://remote.example.invalid','test-key')$q$,'22023','Remote cleartext grant issuer is rejected');
select test.expect_error($q$select public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),gen_random_uuid(),'https://example.invalid/path','test-key')$q$,'22023','Grant issuer is a project origin without arbitrary path');
rollback to savepoint localhost_issuer;
savepoint unsigned_reservation;
select public.release_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),test.id('p4_grant'),0,repeat('A',86));
select set_config('test.p4_unsigned',public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),'a4200000-0000-4000-8000-000000000099','https://example.invalid','test-key')::text,true);
set local role authenticated;
select test.expect_error($q$select public.close_shift(test.id('p4_org'),test.id('p4_shift'),gen_random_uuid(),11500,'Unexpired unsigned preparation is still finalizable')$q$,'23514','Unexpired unsigned reservation still blocks a concurrent shift close');
reset role;
alter table private.offline_grants disable trigger immutable_history;
update private.offline_grants set issued_at=statement_timestamp()-interval '9 hours',expires_at=statement_timestamp()-interval '1 hour' where id=(current_setting('test.p4_unsigned')::jsonb->'claims'->>'grant_id')::uuid;
alter table private.offline_grants enable trigger immutable_history;
select set_config('test.p4_after_abandon',public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),'a4200000-0000-4000-8000-000000000100','https://example.invalid','test-key')::text,true);
select test.assert(current_setting('test.p4_after_abandon')::jsonb->'claims'->>'grant_id'<>current_setting('test.p4_unsigned')::jsonb->'claims'->>'grant_id','Expired unsigned zero-event reservation permits a fresh preparation');
select test.assert(exists(select 1 from private.offline_grant_abandonments where grant_id=(current_setting('test.p4_unsigned')::jsonb->'claims'->>'grant_id')::uuid and reason='EXPIRED_UNSIGNED'),'Server abandonment is an append-only retained fact');
select test.assert(exists(select 1 from private.offline_grants where id=(current_setting('test.p4_unsigned')::jsonb->'claims'->>'grant_id')::uuid),'Abandonment preserves original immutable reservation');
select test.expect_error($q$select public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),'a4200000-0000-4000-8000-000000000099','https://example.invalid','test-key')$q$,'NX002','Abandoned stable request returns definite never-authorized expiry code');
select test.expect_error($q$select public.finalize_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),(current_setting('test.p4_unsigned')::jsonb->'claims'->>'grant_id')::uuid,current_setting('test.p4_unsigned')::jsonb->'claims',repeat('A',86))$q$,'NX002','Abandoned unsigned reservation can never be signed later');
alter table private.offline_grants disable trigger immutable_history;
update private.offline_grants set issued_at=statement_timestamp()-interval '9 hours',expires_at=statement_timestamp()-interval '1 hour' where id=(current_setting('test.p4_after_abandon')::jsonb->'claims'->>'grant_id')::uuid;
alter table private.offline_grants enable trigger immutable_history;
set local role authenticated;
select test.assert(public.close_shift(test.id('p4_org'),test.id('p4_shift'),gen_random_uuid(),11500,'Expired unsigned preparation never authorized a sale')->'closure'->>'closed_at' is not null,'Expired unsigned zero-event reservation permits normal closure');
reset role;
select test.assert((select count(*) from private.offline_grant_abandonments)=2,'Only the two expired unsigned reservations are abandoned');
select test.assert(not exists(select 1 from private.offline_grant_abandonments where grant_id=test.id('p4_grant')),'A finalized signed grant is never abandoned by reservation cleanup');
select test.expect_error('delete from private.offline_grant_abandonments','42501','Server abandonment history cannot be removed');
rollback to savepoint unsigned_reservation;
savepoint oversized_catalog;
select public.release_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),test.id('p4_grant'),0,repeat('A',86));
insert into public.products(organization_id,sku,name,price_minor) select test.id('p4_org'),'P4-BOUND-'||n,'Bounded snapshot fixture '||n,1 from generate_series(1,1000)n;
select test.expect_error($q$select public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),gen_random_uuid(),'https://example.invalid','test-key')$q$,'22023','Snapshot exceeding 1000 saleable products is refused explicitly');
rollback to savepoint localhost_issuer;
select public.release_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),test.id('p4_grant'),0,repeat('A',86));
select test.assert(public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),gen_random_uuid(),'http://127.0.0.1:54321','test-key')->'claims'->>'issuer'='http://127.0.0.1:54321','Explicit local Supabase HTTP origin is supported for development');
select test.expect_error($q$select public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),gen_random_uuid(),'http://remote.example.invalid','test-key')$q$,'22023','Remote cleartext grant issuer is rejected');
select test.expect_error($q$select public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),gen_random_uuid(),'https://example.invalid/path','test-key')$q$,'22023','Grant issuer is a project origin without arbitrary path');
rollback to savepoint localhost_issuer;
savepoint unsigned_reservation;
select public.release_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),test.id('p4_grant'),0,repeat('A',86));
select set_config('test.p4_unsigned',public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),'a4200000-0000-4000-8000-000000000099','https://example.invalid','test-key')::text,true);
set local role authenticated;
select test.expect_error($q$select public.close_shift(test.id('p4_org'),test.id('p4_shift'),gen_random_uuid(),11500,'Unexpired unsigned preparation is still finalizable')$q$,'23514','Unexpired unsigned reservation still blocks a concurrent shift close');
reset role;
alter table private.offline_grants disable trigger immutable_history;
update private.offline_grants set issued_at=statement_timestamp()-interval '9 hours',expires_at=statement_timestamp()-interval '1 hour' where id=(current_setting('test.p4_unsigned')::jsonb->'claims'->>'grant_id')::uuid;
alter table private.offline_grants enable trigger immutable_history;
select set_config('test.p4_after_abandon',public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),'a4200000-0000-4000-8000-000000000100','https://example.invalid','test-key')::text,true);
select test.assert(current_setting('test.p4_after_abandon')::jsonb->'claims'->>'grant_id'<>current_setting('test.p4_unsigned')::jsonb->'claims'->>'grant_id','Expired unsigned zero-event reservation permits a fresh preparation');
select test.assert(exists(select 1 from private.offline_grant_abandonments where grant_id=(current_setting('test.p4_unsigned')::jsonb->'claims'->>'grant_id')::uuid and reason='EXPIRED_UNSIGNED'),'Server abandonment is an append-only retained fact');
select test.assert(exists(select 1 from private.offline_grants where id=(current_setting('test.p4_unsigned')::jsonb->'claims'->>'grant_id')::uuid),'Abandonment preserves original immutable reservation');
select test.expect_error($q$select public.prepare_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),'a4200000-0000-4000-8000-000000000099','https://example.invalid','test-key')$q$,'NX002','Abandoned stable request returns definite never-authorized expiry code');
select test.expect_error($q$select public.finalize_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),(current_setting('test.p4_unsigned')::jsonb->'claims'->>'grant_id')::uuid,current_setting('test.p4_unsigned')::jsonb->'claims',repeat('A',86))$q$,'NX002','Abandoned unsigned reservation can never be signed later');
alter table private.offline_grants disable trigger immutable_history;
update private.offline_grants set issued_at=statement_timestamp()-interval '9 hours',expires_at=statement_timestamp()-interval '1 hour' where id=(current_setting('test.p4_after_abandon')::jsonb->'claims'->>'grant_id')::uuid;
alter table private.offline_grants enable trigger immutable_history;
set local role authenticated;
select test.assert(public.close_shift(test.id('p4_org'),test.id('p4_shift'),gen_random_uuid(),11500,'Expired unsigned preparation never authorized a sale')->'closure'->>'closed_at' is not null,'Expired unsigned zero-event reservation permits normal closure');
reset role;
select test.assert((select count(*) from private.offline_grant_abandonments)=2,'Only the two expired unsigned reservations are abandoned');
select test.assert(not exists(select 1 from private.offline_grant_abandonments where grant_id=test.id('p4_grant')),'A finalized signed grant is never abandoned by reservation cleanup');
select test.expect_error('delete from private.offline_grant_abandonments','42501','Server abandonment history cannot be removed');
rollback to savepoint unsigned_reservation;
savepoint oversized_catalog;
set local role service_role;
select set_config('test.p4_accept1',public.ingest_offline_event('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),
 current_setting('test.p4_event1')::jsonb,current_setting('test.p4_digest1'),test.p4_authorization(1,1),repeat('A',86))::text,true);
select test.assert(current_setting('test.p4_accept1')::jsonb->>'status'='accepted','Trusted original paid sale commits despite later stock shortage');
select test.assert(current_setting('test.p4_accept1')::jsonb->'receipt'->>'total_minor'='113','Ingestion preserves original 100 price and 12.5 percent half-up tax');
select test.assert(current_setting('test.p4_accept1')::jsonb->'receipt'->>'request_id'='a4300000-0000-4000-8000-000000000001','Actual receipt carries local event request identity');
select test.assert(current_setting('test.p4_accept1')::jsonb->>'reconciliation_code'='STOCK_DEFICIT','Paid oversell appends explicit reconciliation case');
select test.assert(current_setting('test.p4_accept1')::jsonb->'stock_impacts'->0->>'revision'='3','Acceptance includes exact authoritative third movement revision');
select test.assert(public.ingest_offline_event('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),
 current_setting('test.p4_event1')::jsonb,current_setting('test.p4_digest1'),test.p4_authorization(1,1),repeat('A',86))=current_setting('test.p4_accept1')::jsonb,'Identical retry returns original immutable acceptance');
select test.expect_error($q$select public.ingest_offline_event('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),current_setting('test.p4_event1')::jsonb,current_setting('test.p4_digest1'),jsonb_set(test.p4_authorization(1,1),'{payment_evidence,a4600000-0000-4000-8000-000000000001,tendered_minor}','300'),repeat('A',86))$q$,'23505','Changed tender evidence cannot replay same event');
select test.expect_error('insert into private.offline_sale_sources(sale_id) values(gen_random_uuid())','42501','Service cannot directly invent trusted negative-stock provenance');
select set_config('test.p4_pull',public.pull_offline_changes('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),
 (current_setting('test.p4_prepare')::jsonb->'snapshot'->>'cursor')::bigint,100)::text,true);
select test.assert((current_setting('test.p4_pull')::jsonb->>'cursor')::bigint>(current_setting('test.p4_prepare')::jsonb->'snapshot'->>'cursor')::bigint,'Pull advances through committed post-snapshot changes');
select test.assert(not(current_setting('test.p4_pull')::jsonb::text like '%cost_minor%'),'Cost-free pull never publishes cost snapshots');
select test.assert(exists(select 1 from jsonb_array_elements(current_setting('test.p4_pull')::jsonb->'changes') c where c->>'kind'='stock' and c->'value'->>'quantity'='-1' and c->'value'->>'revision'='3'),'Pull exposes explicit signed stock deficit and revision');
reset role;
select test.assert((select quantity from private.stock_balances where product_id=test.id('p4_product'))=-1,'Signed offline depletion preserves actual deficit');
select test.assert((select count(*) from public.sales where id='a4400000-0000-4000-8000-000000000001')=1,'Retries commit one immutable financial document');
select test.assert((select count(*) from private.offline_event_outcomes where grant_id=test.id('p4_grant'))=1,'Retries reserve one uninterrupted grant sequence');
select test.expect_error('update private.offline_event_outcomes set digest=repeat(''b'',64)','42501','Trusted administrator cannot accidentally edit immutable outcome');
select test.expect_error('delete from private.offline_sale_sources','42501','Source-backed deficit provenance cannot be deleted');
set local role authenticated;
select test.expect_error($q$select public.checkout_sale(test.id('p4_org'),test.id('p4_branch'),gen_random_uuid(),jsonb_build_object('shift_id',test.id('p4_shift'),'expected_settings_revision',3,'discount_minor',0,'items',jsonb_build_array(jsonb_build_object('product_id',test.id('p4_product'),'quantity',1,'expected_revision',2)),'payments',jsonb_build_array(jsonb_build_object('method','cash','amount_minor',5250,'tendered_minor',5250))))$q$,'23514','Ordinary online checkout cannot deepen signed stock deficit');
select test.expect_error($q$select public.adjust_stock(test.id('p4_org'),test.id('p4_branch'),gen_random_uuid(),test.id('p4_product'),-1,'Attempt unsigned negative adjustment')$q$,'23514','Ordinary adjustment cannot authorize negative stock');
select public.receive_stock(test.id('p4_org'),test.id('p4_branch'),gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',test.id('p4_product'),'quantity',1,'expected_revision',2)),null,null,'Actual receipt reduces deficit');
select test.assert(public.list_inventory(test.id('p4_org'),test.id('p4_branch'),'P4-FIRST')->0->>'available_quantity'='0','Positive real receipt reduces existing signed deficit');
select test.assert(public.get_sale(test.id('p4_org'),'a4400000-0000-4000-8000-000000000001')->>'request_id'='a4300000-0000-4000-8000-000000000001','Online receipt history can decode accepted offline sale identity');
reset role;
select set_config('test.p4_event2',test.p4_event(2,1,'gcash')::text,true),set_config('test.p4_digest2',private.offline_digest(test.p4_event(2,1,'gcash')),true);
savepoint original_reference;
select test.assert(test.p4_ingest_wire(jsonb_set(test.p4_event(20,1,'gcash'),'{payload,payments,0,reference}','"  MANUAL-ORIGINAL  "'),test.p4_authorization(20,2,false))->'receipt'->'payments'->0->>'reference'='  MANUAL-ORIGINAL  ','Accepted manual receipt preserves exact signed reference bytes');
rollback to savepoint original_reference;
savepoint old_replay;
alter table private.offline_grants disable trigger immutable_history;
update private.offline_grants set issued_at=statement_timestamp()-interval '81 hours',expires_at=statement_timestamp()-interval '73 hours' where id=test.id('p4_grant');
alter table private.offline_grants enable trigger immutable_history;
set local role service_role;
select test.assert(public.ingest_offline_event('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),current_setting('test.p4_event1')::jsonb,current_setting('test.p4_digest1'),test.p4_authorization(1,1),repeat('A',86))=current_setting('test.p4_accept1')::jsonb,'Accepted exact replay survives expiry and grace without a second posting');
set local role authenticated;
select test.expect_error($q$select public.close_shift(test.id('p4_org'),test.id('p4_shift'),gen_random_uuid(),11613,'Expired grants still may have paid events')$q$,'23514','Even expired unreleased grant prevents normal closure');
reset role;
rollback to savepoint old_replay;
savepoint unverified_now;
update auth.users set email_confirmed_at=null where id='a4000000-0000-4000-8000-000000000001';
select test.expect_error($q$select test.p4_ingest_wire(test.p4_event(1),test.p4_authorization(1,1))$q$,'42501','Current Auth verification is checked before accepted replay');
rollback to savepoint unverified_now;
savepoint branch_inactive;
update public.branches set active=false where id=test.id('p4_branch');
select test.expect_error($q$select test.p4_ingest_wire(test.p4_event(1),test.p4_authorization(1,1))$q$,'42501','Current branch deactivation blocks accepted replay');
select test.expect_error($q$select public.pull_offline_changes('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),0,100)$q$,'42501','Current branch deactivation blocks cached-data pull');
rollback to savepoint branch_inactive;
savepoint membership_disabled;
alter table public.organization_memberships disable trigger enforce_owner_membership;
update public.organization_memberships set status='disabled' where organization_id=test.id('p4_org') and user_id='a4000000-0000-4000-8000-000000000001';
alter table public.organization_memberships enable trigger enforce_owner_membership;
select test.expect_error($q$select test.p4_ingest_wire(test.p4_event(1),test.p4_authorization(1,1))$q$,'42501','Current disabled membership blocks an old accepted replay');
rollback to savepoint membership_disabled;
savepoint assignment_removed;
alter table public.organization_memberships disable trigger enforce_owner_membership;
update public.organization_memberships set role='admin',all_branches=false where organization_id=test.id('p4_org') and user_id='a4000000-0000-4000-8000-000000000001';
alter table public.organization_memberships enable trigger enforce_owner_membership;
delete from public.membership_branches where organization_id=test.id('p4_org');
select test.expect_error($q$select test.p4_ingest_wire(test.p4_event(1),test.p4_authorization(1,1))$q$,'42501','Current explicit branch assignment is checked before replay');
rollback to savepoint assignment_removed;
savepoint tombstone_page;
update public.products set active=false where id=test.id('p4_product');
update public.branches set name='Other branch data must stay scoped' where id='a4700000-0000-4000-8000-000000000001';
set local role service_role;
select set_config('test.p4_tombstone_pull',public.pull_offline_changes('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),(current_setting('test.p4_pull')::jsonb->>'cursor')::bigint,100)::text,true);
select test.assert(exists(select 1 from jsonb_array_elements(current_setting('test.p4_tombstone_pull')::jsonb->'changes')c where c->>'kind'='product' and (c->>'deleted')::boolean),'Deactivated catalog entry is an explicit feed tombstone');
select test.assert(not(current_setting('test.p4_tombstone_pull') like '%Other branch data%'),'Feed excludes context changes belonging to another branch');
select test.assert((current_setting('test.p4_tombstone_pull')::jsonb->>'cursor')::bigint>(select max((x->>'revision')::bigint) from jsonb_array_elements(current_setting('test.p4_tombstone_pull')::jsonb->'changes')x),'Exhausted scoped page safely advances past invisible other-branch changes');
select test.assert(jsonb_array_length(public.pull_offline_changes('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),(current_setting('test.p4_tombstone_pull')::jsonb->>'cursor')::bigint,100)->'changes')=0,'Repeated exhausted cursor does not duplicate old changes');
select test.assert(jsonb_array_length(public.pull_offline_changes('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),0,1)->'changes')=1 and (public.pull_offline_changes('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),0,1)->>'has_more')::boolean,'Bounded feed returns one row and reports remaining scoped changes');
select test.expect_error($q$select public.pull_offline_changes('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),0,101)$q$,'22023','Feed cannot request more than 100 changes');
select test.expect_error($q$select public.pull_offline_changes('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),9007199254740991,100)$q$,'22023','Future cursor cannot skip committed history');
reset role;
rollback to savepoint tombstone_page;
-- Simulate an external privileged emergency close (outside the normal RPC).
-- Only this disposable fixture disables the guard, then immediately restores it.
alter table public.shift_closures disable trigger offline_shift_close_guard;
insert into public.shift_closures(organization_id,branch_id,shift_id,closed_by,counted_cash_minor,expected_cash_minor,difference_minor,reason)
 values(test.id('p4_org'),test.id('p4_branch'),test.id('p4_shift'),'a4000000-0000-4000-8000-000000000001',11613,11613,0,'External emergency test closure');
alter table public.shift_closures enable trigger offline_shift_close_guard;
set local role service_role;
select set_config('test.p4_review2',public.ingest_offline_event('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),
 current_setting('test.p4_event2')::jsonb,current_setting('test.p4_digest2'),test.p4_authorization(2,2,false),repeat('A',86))::text,true);
select test.assert(current_setting('test.p4_review2')::jsonb->>'status'='review' and current_setting('test.p4_review2')::jsonb->>'reconciliation_code'='SHIFT_CLOSED','Late paid event after forced close is preserved for explicit review');
select test.assert(not(current_setting('test.p4_review2')::jsonb ? 'server_receipt_id'),'Review outcome does not fabricate financial acceptance');
select test.assert(public.ingest_offline_event('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),
 current_setting('test.p4_event2')::jsonb,current_setting('test.p4_digest2'),test.p4_authorization(2,2,false),repeat('A',86))=current_setting('test.p4_review2')::jsonb,'Identical review retry preserves one outcome');
select test.expect_error($q$select public.release_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),test.id('p4_grant'),3,repeat('A',86))$q$,'23514','Review recording does not permit abandoning a later paid sequence');
select public.release_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),test.id('p4_grant'),2,repeat('A',86));
select test.assert(public.release_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),test.id('p4_grant'),2,repeat('A',86))->>'final_sequence'='2','Exact signed release retries idempotently');
select test.expect_error($q$select public.release_offline_grant('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),test.id('p4_grant'),1,repeat('A',86))$q$,'23505','Released final boundary cannot change');
reset role;
select test.assert((select expected_cash_minor from public.shift_closures where shift_id=test.id('p4_shift'))=11613,'Late reviewed sale leaves old closure immutable');
select test.assert(not exists(select 1 from public.sales where id='a4400000-0000-4000-8000-000000000002'),'Reviewed event is not posted into closed shift');
select test.assert(exists(select 1 from public.financial_events where id='a4300000-0000-4000-8000-000000000002'),'Original paid event remains retained even when held for review');
select test.assert((select last_sequence from private.offline_grant_states where grant_id=test.id('p4_grant'))=2,'Accepted and reviewed outcomes both advance retained final sequence');
-- Phase 5 preserves exact already-paid replay under current actor authority.
-- Revocation still denies current business pulls and all new authorization.
set local role authenticated;
select public.revoke_offline_device(test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),'Operator reported device compromise');
set local role service_role;
select test.assert(public.ingest_offline_event('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),current_setting('test.p4_event1')::jsonb,current_setting('test.p4_digest1'),test.p4_authorization(1,1),repeat('A',86))=current_setting('test.p4_accept1')::jsonb,'Revoked device recovers the exact original accepted receipt under current actor authority');
select test.expect_error($q$select public.pull_offline_changes('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),test.id('p4_branch'),test.id('p4_device'),0,100)$q$,'42501','Revoked device cannot pull current business data');
select test.expect_error($q$select public.get_offline_verification_context('a4000000-0000-4000-8000-000000000001',test.id('p4_org'),'a4700000-0000-4000-8000-000000000001',test.id('p4_device'))$q$,'42501','Global device revocation covers every proven branch binding');
reset role;
rollback;
