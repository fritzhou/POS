-- Disposable database only. Mock proof strings exercise SQL's trusted Edge
-- boundary; real Ed25519 verification stays in the separate Edge tests.
begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('a5000000-0000-4000-8000-000000000001','phase5-owner@example.invalid',now()),
 ('a5000000-0000-4000-8000-000000000002','phase5-admin@example.invalid',now()),
 ('a5000000-0000-4000-8000-000000000003','phase5-cashier@example.invalid',now()),
 ('a5000000-0000-4000-8000-000000000004','phase5-other@example.invalid',now());
set local role authenticated;
set local "request.jwt.claim.sub"='a5000000-0000-4000-8000-000000000001';
set local "request.jwt.claims"='{"sub":"a5000000-0000-4000-8000-000000000001","aal":"aal1"}';
select set_config('test.p5_org',organization_id::text,true),set_config('test.p5_branch',branch_id::text,true)
 from public.bootstrap_organization('Phase 5 actual empty business','Security Owner');
select test.assert(public.get_security_policy(test.id('p5_org'))=jsonb_build_object('organization_id',test.id('p5_org'),'revision',1,'idle_lock_minutes',5,'require_privileged_mfa',false),'New business security defaults are truthful and deterministic');
select test.assert(public.list_security_devices(test.id('p5_org'),test.id('p5_branch'))='[]'::jsonb,'No invented enrolled device in empty security inventory');
select test.assert(public.list_security_grants(test.id('p5_org'),test.id('p5_branch'))='[]'::jsonb,'No invented signed grant in empty security inventory');
select test.assert(public.list_security_notifications(test.id('p5_org'),test.id('p5_branch'))='[]'::jsonb,'No synthetic security notifications on empty business');
select test.expect_error($q$select public.list_security_devices(test.id('p5_org'),test.id('p5_branch'),0,101)$q$,'22023','Security page length bounded');
select test.expect_error($q$select public.list_security_devices(test.id('p5_org'),test.id('p5_branch'),-1,50)$q$,'22023','Security offset bounded');
select test.expect_error($q$select * from private.security_policies$q$,'42501','Direct security policy reads denied');
select test.expect_error($q$insert into private.security_notifications(audit_id,organization_id,action,title,message,created_at) values(gen_random_uuid(),test.id('p5_org'),'fake','Fake','Client-authored notification',now())$q$,'42501','Clients cannot create security success notifications');
select test.expect_error($q$select private.security_assert_context_mfa(test.id('p5_org'),auth.uid(),'{"aal":"aal2"}')$q$,'42501','Clients cannot directly invoke trusted stored-claims helper');
select set_config('test.p5_product',(public.save_product(test.id('p5_org'),null,null,'{"name":"Signed original product","sku":"P5-ORIGINAL","price_minor":100}','Paid-evidence security fixture')->>'id'),true);
select public.receive_stock(test.id('p5_org'),test.id('p5_branch'),gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',test.id('p5_product'),'quantity',3,'expected_revision',1)),null,null,'Actual three-unit security fixture');
select set_config('test.p5_shift',(public.open_shift(test.id('p5_org'),test.id('p5_branch'),gen_random_uuid(),1000,'PHP')->>'id'),true);
select set_config('test.p5_device','a5100000-0000-4000-8000-000000000001',true);
select set_config('test.p5_challenge',public.prepare_offline_device_challenge(test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),repeat('A',43),'Original enrolled device','windows')::text,true);
set local role service_role;
select public.complete_offline_device_enrollment('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),(current_setting('test.p5_challenge')::jsonb->>'challenge_id')::uuid,repeat('A',86));
select set_config('test.p5_prepare',public.prepare_offline_grant('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),gen_random_uuid(),'https://example.invalid','test-key')::text,true);
select set_config('test.p5_grant',current_setting('test.p5_prepare')::jsonb->'claims'->>'grant_id',true);
select public.finalize_offline_grant('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),test.id('p5_grant'),current_setting('test.p5_prepare')::jsonb->'claims',repeat('A',86));
reset role;
insert into public.organization_memberships(id,organization_id,user_id,role,status,all_branches) values
 ('a5200000-0000-4000-8000-000000000002',test.id('p5_org'),'a5000000-0000-4000-8000-000000000002','admin','active',false),
 ('a5200000-0000-4000-8000-000000000003',test.id('p5_org'),'a5000000-0000-4000-8000-000000000003','cashier','active',false);
insert into public.membership_branches(organization_id,membership_id,branch_id) values
 (test.id('p5_org'),'a5200000-0000-4000-8000-000000000002',test.id('p5_branch')),
 (test.id('p5_org'),'a5200000-0000-4000-8000-000000000003',test.id('p5_branch'));
create function test.p5_event(p_number integer) returns jsonb language sql as $$
 select jsonb_build_object('event_id',('a5300000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,
 'organization_id',test.id('p5_org'),'branch_id',test.id('p5_branch'),'device_id',test.id('p5_device'),'actor_id','a5000000-0000-4000-8000-000000000001',
 'event_type','sale.created','schema_version',1,'occurred_at',coalesce(nullif(current_setting('test.p5_observed_at',true),''),current_setting('test.p5_prepare')::jsonb->'claims'->>'issued_at'),
 'payload',jsonb_build_object('id',('a5400000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,'shift_id',test.id('p5_shift'),'customer_id',null,'receipt_number','P5-OFFLINE-'||p_number,
 'currency','PHP','subtotal_minor',100,'discount_minor',0,'tax_minor',0,'total_minor',100,
 'items',jsonb_build_array(jsonb_build_object('id',('a5500000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,'product_id',test.id('p5_product'),'sku_snapshot','P5-ORIGINAL','name_snapshot','Signed original product','quantity',1,'unit_price_minor',100,'discount_minor',0,'tax_minor',0,'line_total_minor',100)),
 'payments',jsonb_build_array(jsonb_build_object('id',('a5600000-0000-4000-8000-'||lpad(p_number::text,12,'0'))::uuid,'method','cash','amount_minor',100,'verification_mode','cash','reference',null))));
$$;
create function test.p5_authorization(p_number integer,p_sequence integer) returns jsonb language sql as $$
 select jsonb_build_object('grant_id',test.id('p5_grant'),'sequence',p_sequence,'payment_evidence',jsonb_build_object('a5600000-0000-4000-8000-'||lpad(p_number::text,12,'0'),jsonb_build_object('tendered_minor',100)));
$$;
create function test.p5_ingest(p_number integer,p_sequence integer) returns jsonb language sql security definer set search_path='' as $$
 select public.ingest_offline_event('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),test.p5_event(p_number),private.offline_digest(test.p5_event(p_number)),test.p5_authorization(p_number,p_sequence),repeat('A',86));
$$;
set local role service_role;
select set_config('test.p5_accepted',test.p5_ingest(1,1)::text,true);
select test.assert(current_setting('test.p5_accepted')::jsonb->>'status'='accepted','Actual original paid evidence is accepted before revocation');
set local role authenticated;
select test.assert(jsonb_array_length(public.list_security_devices(test.id('p5_org'),test.id('p5_branch')))=1,'Device inventory derives exactly from actual enrollment');
select test.assert(public.list_security_devices(test.id('p5_org'),test.id('p5_branch'))->0->>'last_sync_at' is not null,'Last sync derives from retained paid event');
select test.assert(public.list_security_grants(test.id('p5_org'),test.id('p5_branch'))->0->>'blocks_shift_close'='true','Signed active grant reports actual shift barrier');
select test.expect_error($q$select public.review_offline_grant(test.id('p5_org'),test.id('p5_branch'),test.id('p5_grant'),gen_random_uuid(),'Lost device during grant',true,1,1,100)$q$,'23514','Live grant cannot be administratively resolved early');
select set_config('test.p5_renamed',public.update_security_device(test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),'a5700000-0000-4000-8000-000000000001','Counter One','Document actual device name')::text,true);
select test.assert(current_setting('test.p5_renamed')::jsonb->>'device_name'='Counter One','Actual enrolled device has administrative display name');
select test.assert(public.update_security_device(test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),'a5700000-0000-4000-8000-000000000001','Counter One','Document actual device name')=current_setting('test.p5_renamed')::jsonb,'Lost device-name response retries same immutable result');
select test.expect_error($q$select public.update_security_device(test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),'a5700000-0000-4000-8000-000000000001','Different name','Document actual device name')$q$,'23505','Same device request cannot silently rewrite name');
select test.expect_error($q$select public.update_security_device(test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),gen_random_uuid(),'   ','Valid reason')$q$,'22023','Blank device display name denied');
select test.expect_error($q$select public.update_security_device(test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),gen_random_uuid(),'Name','x')$q$,'22023','Security mutation requires meaningful reason');
set local "request.jwt.claim.sub"='a5000000-0000-4000-8000-000000000002';
select test.assert(public.list_security_devices(test.id('p5_org'),test.id('p5_branch'))->0->>'can_manage'='false','Scoped Admin cannot manage Owner device');
select test.expect_error($q$select public.revoke_security_device(test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),gen_random_uuid(),'Revoke Owner device')$q$,'42501','Admin cannot revoke superior Owner device');
set local "request.jwt.claim.sub"='a5000000-0000-4000-8000-000000000003';
select test.assert(public.list_security_devices(test.id('p5_org'),test.id('p5_branch'))='[]'::jsonb,'Cashier cannot enumerate another actor devices');
select test.assert(public.list_security_grants(test.id('p5_org'),test.id('p5_branch'))='[]'::jsonb,'Cashier cannot enumerate another actor paid grants');
select test.expect_error($q$select public.update_security_policy(test.id('p5_org'),gen_random_uuid(),1,10,false,'Cashier policy override')$q$,'42501','Cashier cannot mutate organization security policy');
select test.assert(public.list_security_notifications(test.id('p5_org'),test.id('p5_branch'))='[]'::jsonb,'Cashier does not read another actor security notification');
set local "request.jwt.claim.sub"='a5000000-0000-4000-8000-000000000004';
select test.expect_error($q$select public.get_security_policy(test.id('p5_org'))$q$,'42501','Verified outsider cannot read organization security policy');
set local "request.jwt.claim.sub"='a5000000-0000-4000-8000-000000000001';
select set_config('test.p5_revoked',public.revoke_security_device(test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),'a5700000-0000-4000-8000-000000000002','Original device key was removed')::text,true);
select test.assert(current_setting('test.p5_revoked')::jsonb->>'revoked_at' is not null,'Source-backed revocation returns actual server time');
select test.assert(public.revoke_security_device(test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),'a5700000-0000-4000-8000-000000000002','Original device key was removed')=current_setting('test.p5_revoked')::jsonb,'Revocation retries original result without second audit');
select test.assert(jsonb_array_length(public.list_security_notifications(test.id('p5_org'),test.id('p5_branch')))=2,'Actual rename and revoke produce exactly two source-backed notifications');
select set_config('test.p5_notification',public.list_security_notifications(test.id('p5_org'),test.id('p5_branch'))->0->>'id',true);
select set_config('test.p5_read',public.mark_security_notification_read(test.id('p5_org'),test.id('p5_branch'),test.id('p5_notification'))::text,true);
select test.assert(public.mark_security_notification_read(test.id('p5_org'),test.id('p5_branch'),test.id('p5_notification'))=current_setting('test.p5_read')::jsonb,'Notification read receipt retains original per-user time');
select test.expect_error($q$select public.mark_security_notification_read(test.id('p5_org'),test.id('p5_branch'),gen_random_uuid())$q$,'42501','Arbitrary notification cannot be marked read');
set local role service_role;
select test.assert(test.p5_ingest(1,1)=current_setting('test.p5_accepted')::jsonb,'Revoked device recovers exact accepted original proof result');
select test.assert(public.get_offline_verification_context('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),test.id('p5_grant'))->>'public_key'=repeat('A',43),'Edge retrieves retained verification key solely for existing signed grant');
select test.expect_error($q$select public.get_offline_verification_context('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'))$q$,'42501','Revoked device cannot obtain ordinary active-device context');
select test.expect_error($q$select public.prepare_offline_grant('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),gen_random_uuid(),'https://example.invalid','test-key')$q$,'42501','Revoked device receives no new capture grant');
select test.expect_error($q$select public.pull_offline_changes('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),0,100)$q$,'42501','Revoked device cannot pull current catalog');
select test.expect_error($q$select public.release_offline_grant('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),test.id('p5_grant'),1,repeat('A',86))$q$,'42501','Revoked device cannot fabricate ordinary signed final release');
select set_config('test.p5_observed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),true);
select test.expect_error($q$select test.p5_ingest(2,2)$q$,'42501','Observation after actual revocation cannot authorize new captured payment');
-- Advance only disposable immutable fixture time to exercise expiry + review.
reset role;
alter table private.offline_grants disable trigger immutable_history;
update private.offline_grants set issued_at=statement_timestamp()-interval '9 hours',expires_at=statement_timestamp()-interval '1 hour' where id=test.id('p5_grant');
alter table private.offline_grants enable trigger immutable_history;
select set_config('test.p5_observed_at',private.offline_time(statement_timestamp()-interval '8 hours'),true);
set local role authenticated;
select test.expect_error($q$select public.close_shift(test.id('p5_org'),test.id('p5_shift'),gen_random_uuid(),1100,'Expired revoked unreconciled grant')$q$,'23514','Expired revoked grant still blocks shift until explicit review');
select test.assert(public.list_security_grants(test.id('p5_org'),test.id('p5_branch'))->0->>'remaining_exposure_events'='999','Administrator sees actual unknown event exposure before acknowledging review');
select test.assert(public.list_security_grants(test.id('p5_org'),test.id('p5_branch'))->0->>'remaining_exposure_minor'='99999900','Administrator sees actual unknown financial ceiling before acknowledging review');
select test.expect_error($q$select public.review_offline_grant(test.id('p5_org'),test.id('p5_branch'),test.id('p5_grant'),gen_random_uuid(),'Review missing paid events',false,1,1,100)$q$,'22023','Unknown financial exposure must be explicitly acknowledged');
select test.expect_error($q$select public.review_offline_grant(test.id('p5_org'),test.id('p5_branch'),test.id('p5_grant'),gen_random_uuid(),'Review stale paid events',true,0,0,0)$q$,'40001','Stale displayed outcome snapshot cannot resolve grant');
select set_config('test.p5_resolved',public.review_offline_grant(test.id('p5_org'),test.id('p5_branch'),test.id('p5_grant'),'a5700000-0000-4000-8000-000000000003','Reviewed accepted payment; unknown exposure acknowledged',true,1,1,100)::text,true);
select test.assert(current_setting('test.p5_resolved')::jsonb->>'state'='administratively_resolved','Lost-key workflow creates explicit administrative resolution');
select test.assert(current_setting('test.p5_resolved')::jsonb->>'blocks_shift_close'='false','Actual reviewed grant releases only administrative shift barrier');
select test.assert(current_setting('test.p5_resolved')::jsonb->>'remaining_exposure_events'='999','Unknown remaining signed event exposure remains visible');
select test.assert(current_setting('test.p5_resolved')::jsonb->>'remaining_exposure_minor'='99999900','Unknown remaining signed financial ceiling remains visible');
select test.assert(public.review_offline_grant(test.id('p5_org'),test.id('p5_branch'),test.id('p5_grant'),'a5700000-0000-4000-8000-000000000003','Reviewed accepted payment; unknown exposure acknowledged',true,1,1,100)=current_setting('test.p5_resolved')::jsonb,'Lost administrator response recovers exact immutable decision');
select public.close_shift(test.id('p5_org'),test.id('p5_shift'),gen_random_uuid(),1100,'Close only after audited risk review');
set local role service_role;
select set_config('test.p5_late_review',test.p5_ingest(2,2)::text,true);
select test.assert(current_setting('test.p5_late_review')::jsonb->>'status'='review','Late original paid evidence is preserved for financial reconciliation');
select test.assert(current_setting('test.p5_late_review')::jsonb->>'reconciliation_code'='GRANT_ADMINISTRATIVELY_RESOLVED','Late paid evidence identifies administrative resolution cause');
select test.assert(test.p5_ingest(2,2)=current_setting('test.p5_late_review')::jsonb,'Late reviewed proof retries exact original review outcome');
reset role;
select test.assert(not exists(select 1 from private.offline_grant_releases where grant_id=test.id('p5_grant')),'Administrative review never fabricates missing device release signature');
select test.assert(exists(select 1 from public.financial_events where id='a5300000-0000-4000-8000-000000000002'),'Original late paid event retained immutable in financial history');
select test.assert(not exists(select 1 from public.sales where id='a5400000-0000-4000-8000-000000000002'),'Late review does not post sale into already closed shift');
select test.assert((select quantity from private.stock_balances where product_id=test.id('p5_product') and branch_id=test.id('p5_branch'))=2,'Reviewed late evidence leaves physical stock unchanged');
select test.assert((select expected_cash_minor from public.shift_closures where shift_id=test.id('p5_shift'))=1100,'Reviewed late money leaves historical shift closure immutable');
select test.assert((select known_last_sequence from private.security_grant_resolutions where grant_id=test.id('p5_grant'))=1,'Original known-outcome review snapshot stays immutable after late evidence');
select test.assert((select remaining_exposure_events from private.security_grant_resolutions where grant_id=test.id('p5_grant'))=999,'Original unknown-exposure acknowledgement stays immutable');
select test.expect_error($q$update private.security_grant_resolutions set known_last_sequence=2 where grant_id=test.id('p5_grant')$q$,'42501','Even administrative reviewed history cannot be rewritten');
select test.expect_error($q$delete from private.security_notification_reads where notification_id=test.id('p5_notification')$q$,'42501','Notification read history cannot be erased');
select test.assert((select count(*) from public.audit_logs where organization_id=test.id('p5_org') and action='security.device_revoked')=1,'Revocation idempotency commits one authoritative audit');
set local role authenticated;
select test.assert(public.list_security_grants(test.id('p5_org'),test.id('p5_branch'))->0->>'remaining_exposure_events'='998','Late reviewed evidence reduces current remaining exposure while retaining original decision');
select test.assert(jsonb_array_length(public.list_security_notifications(test.id('p5_org'),test.id('p5_branch')))=4,'Administrative decision and actual late paid review produce source-backed alerts');
reset role;
savepoint very_late_evidence;
alter table private.offline_grants disable trigger immutable_history;
update private.offline_grants set issued_at=statement_timestamp()-interval '81 hours',expires_at=statement_timestamp()-interval '73 hours' where id=test.id('p5_grant');
alter table private.offline_grants enable trigger immutable_history;
select set_config('test.p5_observed_at',private.offline_time(statement_timestamp()-interval '80 hours'),true);
select test.assert(test.p5_ingest(3,3)->>'reconciliation_code'='GRANT_ADMINISTRATIVELY_RESOLVED','Administrative review preserves original bounded captured evidence beyond ordinary ingestion grace');
rollback to savepoint very_late_evidence;
savepoint missing_paid_sequence;
set local role authenticated;
select set_config('test.p5_shift',(public.open_shift(test.id('p5_org'),test.id('p5_branch'),gen_random_uuid(),0,'PHP')->>'id'),true);
select set_config('test.p5_device','a5100000-0000-4000-8000-000000000003',true);
select set_config('test.p5_challenge',public.prepare_offline_device_challenge(test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),repeat('D',43),'Actually missing earlier paid sequence','windows')::text,true);
set local role service_role;
select public.complete_offline_device_enrollment('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),(current_setting('test.p5_challenge')::jsonb->>'challenge_id')::uuid,repeat('D',86));
select set_config('test.p5_prepare',public.prepare_offline_grant('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),gen_random_uuid(),'https://example.invalid','test-key')::text,true);
select set_config('test.p5_grant',current_setting('test.p5_prepare')::jsonb->'claims'->>'grant_id',true);
select public.finalize_offline_grant('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),test.id('p5_grant'),current_setting('test.p5_prepare')::jsonb->'claims',repeat('D',86));
set local role authenticated;
select public.revoke_offline_device(test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),'Actual lost key and missing first paid record');
reset role;
alter table private.offline_grants disable trigger immutable_history;
update private.offline_grants set issued_at=statement_timestamp()-interval '9 hours',expires_at=statement_timestamp()-interval '1 hour' where id=test.id('p5_grant');
alter table private.offline_grants enable trigger immutable_history;
select set_config('test.p5_observed_at',private.offline_time(statement_timestamp()-interval '8 hours'),true);
select test.expect_error($q$select test.p5_ingest(102,2)$q$,'23505','Original unresolved grant still rejects a missing earlier paid sequence');
set local role authenticated;
select public.review_offline_grant(test.id('p5_org'),test.id('p5_branch'),test.id('p5_grant'),gen_random_uuid(),'Reviewed zero known outcomes and explicitly accepted all unknown paid exposure',true,0,0,0);
set local role service_role;
select set_config('test.p5_gap_review',test.p5_ingest(102,2)::text,true);
select test.assert(current_setting('test.p5_gap_review')::jsonb->>'status'='review','Administratively resolved grant preserves paid sequence two while sequence one is missing');
select test.assert(current_setting('test.p5_gap_review')::jsonb->>'reconciliation_code'='GRANT_ADMINISTRATIVELY_RESOLVED','Out-of-order proof remains explicit administrative review');
select test.assert(test.p5_ingest(102,2)=current_setting('test.p5_gap_review')::jsonb,'Out-of-order original proof recovers exact immutable review response');
select test.expect_error($q$select test.p5_ingest(103,2)$q$,'23505','Observed sequence cannot bind a different paid event after administrative review');
reset role;
select test.assert((select last_sequence from private.offline_grant_states where grant_id=test.id('p5_grant'))=2,'Highest observed sequence remains distinct from paid outcome count');
select test.assert((select count(*) from private.offline_event_outcomes where grant_id=test.id('p5_grant'))=1,'Missing earlier sequence does not fabricate a financial event');
select test.assert(exists(select 1 from public.financial_events where id='a5300000-0000-4000-8000-000000000102'),'Recovered gapped paid event is retained in immutable financial history');
select test.assert(not exists(select 1 from public.sales where id='a5400000-0000-4000-8000-000000000102'),'Out-of-order review never posts stock or financial receipt');
set local role authenticated;
select test.assert((select value->>'remaining_exposure_events' from jsonb_array_elements(public.list_security_grants(test.id('p5_org'),test.id('p5_branch'))) where value->>'grant_id'=test.id('p5_grant')::text)='999','Unknown event exposure counts actual outcomes and retains missing earlier sequence risk');
\pset format unaligned
\t on
select 'NEXAPOS_GAP_PROJECTION='||jsonb_build_object('provenance','Actual gapped paid-proof RPC projections from isolated Phase 5 mock-Auth SQL tests; never production records',
 'policy',public.get_security_policy(test.id('p5_org')),'devices',public.list_security_devices(test.id('p5_org'),test.id('p5_branch')),
 'grants',public.list_security_grants(test.id('p5_org'),test.id('p5_branch')),'notifications',public.list_security_notifications(test.id('p5_org'),test.id('p5_branch')))::text;
\t off
\pset format aligned
set local role service_role;
select test.assert(test.p5_ingest(101,1)->>'status'='review','Previously missing original paid sequence can arrive later without new payment');
reset role;
select test.assert((select last_sequence from private.offline_grant_states where grant_id=test.id('p5_grant'))=2,'Late earlier sequence cannot move highest observed sequence backward');
select test.assert((select count(*) from private.offline_event_outcomes where grant_id=test.id('p5_grant'))=2,'Recovered missing sequence increases actual paid outcome count once');
select test.assert((select known_last_sequence from private.security_grant_resolutions where grant_id=test.id('p5_grant'))=0,'Out-of-order recovery leaves original zero-known-outcomes decision immutable');
rollback to savepoint missing_paid_sequence;
set local role authenticated;
select public.save_customer(test.id('p5_org'),null,null,jsonb_build_object('name','Actual protected customer','branch_id',test.id('p5_branch'),'email','mfa-customer@example.invalid'),'MFA direct customer read fixture');
select public.save_supplier(test.id('p5_org'),null,null,jsonb_build_object('name','Actual protected supplier','branch_id',test.id('p5_branch'),'email','mfa-supplier@example.invalid'),'MFA direct supplier read fixture');
reset role;
insert into public.profiles(user_id,full_name) values('a5000000-0000-4000-8000-000000000003','Actual Cashier Directory Fixture');
set local role authenticated;
-- Actual provider-verified assurance is represented by mock PostgREST claims.
-- No production client can change those claims through a SQL RPC argument.
select test.expect_error($q$select public.update_security_policy(test.id('p5_org'),gen_random_uuid(),1,5,true,'Require MFA without verification')$q$,'42501','Cannot require MFA from an unverified AAL1 session');
set local "request.jwt.claims"='{"sub":"a5000000-0000-4000-8000-000000000002","aal":"aal2"}';
select test.expect_error($q$select public.update_security_policy(test.id('p5_org'),gen_random_uuid(),1,5,true,'Borrow another actor assurance')$q$,'42501','Another JWT subject AAL2 cannot authorize policy');
set local "request.jwt.claims"='{"sub":"a5000000-0000-4000-8000-000000000001","aal":"aal2"}';
select set_config('test.p5_mfa_policy',public.update_security_policy(test.id('p5_org'),'a5700000-0000-4000-8000-000000000004',1,10,true,'Require verified privileged accounts')::text,true);
select test.assert(current_setting('test.p5_mfa_policy')::jsonb->>'revision'='2','Security policy CAS advances one revision');
select test.assert(public.update_security_policy(test.id('p5_org'),'a5700000-0000-4000-8000-000000000004',1,10,true,'Require verified privileged accounts')=current_setting('test.p5_mfa_policy')::jsonb,'Lost policy response retries original verified policy');
select test.expect_error($q$select public.update_security_policy(test.id('p5_org'),gen_random_uuid(),1,5,true,'Stale policy writer')$q$,'40001','Security policy stale writer cannot overwrite current requirements');
set local "request.jwt.claims"='{"sub":"a5000000-0000-4000-8000-000000000001","aal":"aal1"}';
select test.assert(public.get_security_policy(test.id('p5_org'))->>'require_privileged_mfa'='true','AAL1 reads minimal current policy to reach MFA step-up');
select test.assert((select count(*) from public.products where organization_id=test.id('p5_org'))=0,'AAL1 Owner direct catalog reads cannot bypass MFA RPC gate');
select test.assert((select count(*) from public.sales where organization_id=test.id('p5_org'))=0,'AAL1 Owner direct financial receipt reads denied by restrictive policy');
select test.assert((select count(*) from public.sale_items where organization_id=test.id('p5_org'))=0,'AAL1 Owner direct immutable financial line reads denied');
select test.assert((select count(*) from public.audit_logs where organization_id=test.id('p5_org'))=0,'AAL1 Owner direct audit reads cannot bypass security policy');
select test.assert((select count(*) from public.customers where organization_id=test.id('p5_org'))=0,'AAL1 Owner direct customer contact reads denied');
select test.assert((select count(*) from public.suppliers where organization_id=test.id('p5_org'))=0,'AAL1 Owner direct supplier contact reads denied');
select test.assert((select count(*) from public.profiles where user_id='a5000000-0000-4000-8000-000000000003')=0,'AAL1 Owner cannot read other employee profile through direct table API');
select test.assert((select count(*) from public.profiles where user_id=auth.uid())=1,'Own profile metadata remains available for Auth and MFA setup');
select test.assert((select count(*) from public.organization_memberships where organization_id=test.id('p5_org'))=1,'AAL1 Owner discovers own membership without exposing employee directory');
select test.assert((select count(*) from public.organization_memberships where organization_id=test.id('p5_org') and user_id=auth.uid())=1,'Own role discovery remains available to reach MFA setup');
select test.assert((select count(*) from public.branches where organization_id=test.id('p5_org'))=1,'Current branch metadata remains available for MFA scope discovery');
select test.assert((select count(*) from public.organizations where id=test.id('p5_org'))=1,'Organization metadata remains available for MFA scope discovery');
select test.assert((select count(*) from public.membership_branches where organization_id=test.id('p5_org'))=1,'AAL1 Owner discovers own assignment while other employee assignments remain hidden');
select test.expect_error($q$select public.save_product(test.id('p5_org'),test.id('p5_product'),1,'{"price_minor":999}','Bypass MFA through old catalog RPC')$q$,'42501','Common current-membership gate enforces MFA on existing privileged catalog writes');
select test.expect_error($q$select public.update_security_policy(test.id('p5_org'),gen_random_uuid(),2,5,false,'Disable MFA from AAL1')$q$,'42501','AAL1 cannot turn off already enabled MFA policy');
select test.expect_error($q$select public.revoke_security_device(test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),gen_random_uuid(),'Bypass policy in security RPC')$q$,'42501','Security mutators independently enforce current assurance');
select test.expect_error($q$select public.prepare_offline_device_challenge(test.id('p5_org'),test.id('p5_branch'),gen_random_uuid(),repeat('A',43),'AAL1 challenge bypass','android')$q$,'42501','Direct authenticated enrollment challenge enforces current MFA');
select test.expect_error($q$select public.authorize_offline_operation(test.id('p5_org'),test.id('p5_branch'),test.id('p5_device'),'prepare')$q$,'42501','AAL1 cannot acquire stored privileged service assurance');
set local "request.jwt.claims"='{"sub":"a5000000-0000-4000-8000-000000000001","aal":"aal2"}';
select test.assert((select count(*) from public.products where organization_id=test.id('p5_org'))=1,'AAL2 Owner direct catalog retains original tenant-authorized read');
select test.assert((select count(*) from public.sales where organization_id=test.id('p5_org'))=1,'AAL2 Owner direct financial receipt retains original authorized read');
select test.assert((select count(*) from public.audit_logs where organization_id=test.id('p5_org'))>0,'AAL2 Owner direct audit read succeeds with current assurance');
select test.assert((select count(*) from public.customers where organization_id=test.id('p5_org'))=1,'AAL2 Owner customer contact read succeeds after verification');
select test.assert((select count(*) from public.profiles where user_id='a5000000-0000-4000-8000-000000000003')=1,'AAL2 Owner employee profile read succeeds within existing authority');
select test.assert((select count(*) from public.organization_memberships where organization_id=test.id('p5_org'))=3,'AAL2 Owner reads actual employee directory after step-up');
set local "request.jwt.claim.sub"='a5000000-0000-4000-8000-000000000003';
set local "request.jwt.claims"='{"sub":"a5000000-0000-4000-8000-000000000003","aal":"aal1"}';
select test.assert((select count(*) from public.products where organization_id=test.id('p5_org'))=1,'Cashier catalog access retains existing policy when privileged MFA required');
select test.assert((select count(*) from public.membership_branches where organization_id=test.id('p5_org'))=1,'Cashier still discovers only actual own branch assignment');
set local "request.jwt.claim.sub"='a5000000-0000-4000-8000-000000000001';
set local "request.jwt.claims"='{"sub":"a5000000-0000-4000-8000-000000000001","aal":"aal2"}';
select set_config('test.p5_secure_device','a5100000-0000-4000-8000-000000000002',true);
select set_config('test.p5_secure_challenge',public.prepare_offline_device_challenge(test.id('p5_org'),test.id('p5_branch'),test.id('p5_secure_device'),repeat('B',43),'Actual MFA-bound device','android')::text,true);
set local role service_role;
select test.expect_error($q$select public.complete_offline_device_enrollment('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_secure_device'),(current_setting('test.p5_secure_challenge')::jsonb->>'challenge_id')::uuid,repeat('B',86))$q$,'42501','Service bearer alone cannot invent actual actor MFA proof');
set local role authenticated;
select test.assert(public.authorize_offline_operation(test.id('p5_org'),test.id('p5_branch'),test.id('p5_secure_device'),'enroll')->>'authorized'='true','Actual user bearer creates narrowly scoped current assurance');
set local role service_role;
select test.assert(public.complete_offline_device_enrollment('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_secure_device'),(current_setting('test.p5_secure_challenge')::jsonb->>'challenge_id')::uuid,repeat('B',86))->>'device_id'=test.id('p5_secure_device')::text,'Trusted enrollment consumes actor/device/action verified assurance');
select test.expect_error($q$select public.pull_offline_changes('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_secure_device'),0,100)$q$,'42501','Enrollment assurance cannot authorize another action');
set local role authenticated;
select public.authorize_offline_operation(test.id('p5_org'),test.id('p5_branch'),test.id('p5_secure_device'),'pull');
set local role service_role;
select test.assert(public.pull_offline_changes('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_secure_device'),0,100)->'changes' is not null,'Current user-context pull assurance permits current branch catalog');
reset role;
alter table private.security_offline_authorizations disable trigger immutable_history;
update private.security_offline_authorizations set expires_at=clock_timestamp()-interval '1 second' where device_id=test.id('p5_secure_device') and action='pull';
alter table private.security_offline_authorizations enable trigger immutable_history;
set local role service_role;
select test.expect_error($q$select public.pull_offline_changes('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_secure_device'),0,100)$q$,'42501','Expired actor assurance cannot authorize service catalog access');
select test.expect_error($q$select public.prepare_offline_grant('a5000000-0000-4000-8000-000000000001',test.id('p5_org'),test.id('p5_branch'),test.id('p5_secure_device'),gen_random_uuid(),'https://example.invalid','test-key')$q$,'42501','Service preparation checks independent actual-user assurance');
set local role authenticated;
select test.assert(public.update_security_policy(test.id('p5_org'),gen_random_uuid(),2,5,false,'Verified Owner changed MFA requirement')->>'revision'='3','Verified Owner can disable policy with authoritative audit');
set local role anon;
select test.expect_error($q$select public.get_security_policy(test.id('p5_org'))$q$,'42501','Anonymous policy discovery denied');
select test.expect_error($q$select public.list_security_notifications(test.id('p5_org'),test.id('p5_branch'))$q$,'42501','Anonymous source security notifications denied');
set local role service_role;
select test.expect_error($q$select * from private.security_grant_resolutions$q$,'42501','Service role cannot inspect administrative risk tables directly');
select test.expect_error($q$select public.update_security_policy(test.id('p5_org'),gen_random_uuid(),3,5,false,'Service role override')$q$,'42501','Service role receives no organization policy mutation RPC');
reset role;
rollback;
