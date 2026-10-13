# Sourced only by run.sh after its pinned isolated-container checks. This uses
# persistent disposable fixtures and independent PostgreSQL connections.
psql_admin -d "$database_name" <<'D6_SETUP'
insert into auth.users(id,email,email_confirmed_at,encrypted_password)
select ('d9000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'invitation-race-'||n||'@example.invalid',now(),'fixture-password-present'
from generate_series(1,8)n;
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='d9000000-0000-4000-8000-000000000001';
select public.bootstrap_organization('Invitation concurrency shop','Invitation race owner');
commit;
create table test.d6_race_invitations(n integer primary key,organization_id uuid not null,branch_id uuid not null,invitation_id uuid not null);
grant select on test.d6_race_invitations to authenticated,service_role;
do $$declare o uuid;b uuid;i uuid;n integer;c jsonb;begin
 select id into o from public.organizations where owner_user_id='d9000000-0000-4000-8000-000000000001';
 select id into b from public.branches where organization_id=o and code='MAIN';
 perform set_config('request.jwt.claim.sub','d9000000-0000-4000-8000-000000000001',true);
 for n in 2..8 loop
  i:=(public.prepare_employee_invitation(o,('d9100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
   'invitation-race-'||n||'@example.invalid','Race employee '||n,'cashier',array[b],false,null,null,'Add race employee '||n)->>'id')::uuid;
  insert into test.d6_race_invitations values(n,o,b,i);
  if n in (3,4,5) then
   c:=public.claim_invitation_delivery(i);perform public.finish_invitation_delivery(i,(c->>'claim_id')::uuid,true,null);
  end if;
 end loop;
end;$$;
D6_SETUP

# Multiple transports retry one immutable UUID while its first commit is racing.
d6_pids=()
for d6_index in 1 2; do
 psql_admin -Atq -d "$database_name" > "$result_dir/d6-idem.$d6_index.out" 2> "$result_dir/d6-idem.$d6_index.err" <<'D6_IDEM' &
begin;
set local lock_timeout='10s';
set local statement_timeout='15s';
set local role authenticated;
set local "request.jwt.claim.sub"='d9000000-0000-4000-8000-000000000001';
select public.revoke_employee_invitation_action(organization_id,invitation_id,'d9400000-0000-4000-8000-000000000001',1,'Single immutable race cancellation')
from test.d6_race_invitations where n=2;
commit;
D6_IDEM
 d6_pids+=("$!")
done
for d6_pid in "${d6_pids[@]}"; do wait "$d6_pid"; done
python3 - "$result_dir" <<'D6_IDEM_CHECK'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); outputs=[json.loads((p/f'd6-idem.{n}.out').read_text()) for n in (1,2)]
if outputs[0]!=outputs[1] or outputs[0]['invitation']['status']!='revoked':
    sys.exit('Concurrent original invitation request did not recover the same immutable result.')
D6_IDEM_CHECK
psql_admin -d "$database_name" <<'D6_IDEM_ASSERT'
select test.assert((select count(*) from private.operation_requests where request_id='d9400000-0000-4000-8000-000000000001')=1,'Concurrent invitation transports create one durable request receipt');
select test.assert((select count(*) from public.audit_logs a join test.d6_race_invitations i on i.invitation_id=a.entity_id where i.n=2 and a.action='invitation.revoked')=1,'Concurrent invitation transports append exactly one cancellation audit');
select test.assert((select revision from public.employee_invitations where id=(select invitation_id from test.d6_race_invitations where n=2))=2,'Concurrent revocation consumes exactly one invitation revision');
D6_IDEM_ASSERT

# An unscheduled acceptance and cancellation race must produce exactly one
# authoritative business outcome, never accepted and revoked simultaneously.
d6_pids=()
(
 set +e
 psql_admin -Atq -d "$database_name" > "$result_dir/d6-accept.out" 2> "$result_dir/d6-accept.err" <<'D6_ACCEPT'
\set VERBOSITY verbose
begin;
set local lock_timeout='10s';
set local statement_timeout='15s';
set local role authenticated;
set local "request.jwt.claim.sub"='d9000000-0000-4000-8000-000000000003';
select public.accept_employee_invitation(invitation_id) from test.d6_race_invitations where n=3;
commit;
D6_ACCEPT
 printf '%s' "$?" > "$result_dir/d6-accept.status"
) &
d6_pids+=("$!")
(
 set +e
 psql_admin -Atq -d "$database_name" > "$result_dir/d6-revoke.out" 2> "$result_dir/d6-revoke.err" <<'D6_REVOKE'
\set VERBOSITY verbose
begin;
set local lock_timeout='10s';
set local statement_timeout='15s';
set local role authenticated;
set local "request.jwt.claim.sub"='d9000000-0000-4000-8000-000000000001';
select public.revoke_employee_invitation_action(organization_id,invitation_id,'d9400000-0000-4000-8000-000000000003',3,'Race cancellation versus acceptance')
from test.d6_race_invitations where n=3;
commit;
D6_REVOKE
 printf '%s' "$?" > "$result_dir/d6-revoke.status"
) &
d6_pids+=("$!")
for d6_pid in "${d6_pids[@]}"; do wait "$d6_pid"; done
python3 - "$result_dir" <<'D6_RACE_CHECK'
import sys
from pathlib import Path
p=Path(sys.argv[1]); statuses=[(p/f'd6-{kind}.status').read_text() for kind in ('accept','revoke')]
errors=[(p/f'd6-{kind}.err').read_text() for kind in ('accept','revoke')]
if sorted(statuses)!=['0','3'] or sum(('42501:' in e or '23514:' in e) for e in errors)!=1:
    sys.exit('Invitation acceptance versus revocation must have one acceptance and one scoped terminal denial.')
D6_RACE_CHECK
psql_admin -d "$database_name" <<'D6_RACE_ASSERT'
select test.assert((select (accepted_at is not null)::integer+(revoked_at is not null)::integer from public.employee_invitations where id=(select invitation_id from test.d6_race_invitations where n=3))=1,'Acceptance versus cancellation commits exactly one terminal invitation state');
select test.assert((select count(*) from public.audit_logs where entity_id=(select invitation_id from test.d6_race_invitations where n=3) and action in ('invitation.accepted','invitation.revoked'))=1,'Acceptance versus cancellation appends exactly one terminal audit');
select test.assert((select count(*) from public.organization_memberships where user_id='d9000000-0000-4000-8000-000000000003')=(select (accepted_at is not null)::integer from public.employee_invitations where id=(select invitation_id from test.d6_race_invitations where n=3)),'Only winning acceptance creates an actual membership');
D6_RACE_ASSERT

# Deterministic both-order checks use the same row lock as the real RPCs and
# verify the losing operation only after the winning transaction has committed.
psql_admin -d "$database_name" <<'D6_ORDER_ASSERT'
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='d9000000-0000-4000-8000-000000000004';
select public.accept_employee_invitation(invitation_id) from test.d6_race_invitations where n=4;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='d9000000-0000-4000-8000-000000000001';
select test.expect_error($q$select public.revoke_employee_invitation_action(organization_id,invitation_id,'d9400000-0000-4000-8000-000000000004',3,'Acceptance already committed') from test.d6_race_invitations where n=4$q$,'23514','Committed acceptance cannot be undone by an old invitation view');
select public.revoke_employee_invitation_action(organization_id,invitation_id,'d9400000-0000-4000-8000-000000000005',3,'Cancellation committed first') from test.d6_race_invitations where n=5;
commit;
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='d9000000-0000-4000-8000-000000000005';
select test.expect_error($q$select public.accept_employee_invitation(invitation_id) from test.d6_race_invitations where n=5$q$,'42501','Committed cancellation cannot be undone by an arriving Auth link');
commit;
D6_ORDER_ASSERT

# Service delivery claims race independently. Exactly one receives a claim;
# unknown sending is permanent and no transport can take over its UUID.
d6_pids=()
for d6_index in 1 2; do
 psql_admin -Atq -d "$database_name" > "$result_dir/d6-claim.$d6_index.out" 2> "$result_dir/d6-claim.$d6_index.err" <<'D6_CLAIM' &
begin;
set local lock_timeout='10s';
set local statement_timeout='15s';
set local role service_role;
select coalesce(public.claim_invitation_delivery(invitation_id)::text,'null') from test.d6_race_invitations where n=6;
commit;
D6_CLAIM
 d6_pids+=("$!")
done
for d6_pid in "${d6_pids[@]}"; do wait "$d6_pid"; done
python3 - "$result_dir" <<'D6_CLAIM_CHECK'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); values=[json.loads((p/f'd6-claim.{n}.out').read_text()) for n in (1,2)]
if sum(v is None for v in values)!=1 or sum(v is not None and v['delivery_state']=='sending' for v in values)!=1:
    sys.exit('Concurrent delivery transports must produce exactly one provider claim and one no-op.')
D6_CLAIM_CHECK
psql_admin -d "$database_name" <<'D6_CLAIM_ASSERT'
select test.assert((select revision from public.employee_invitations where id=(select invitation_id from test.d6_race_invitations where n=6))=2,'Concurrent delivery claims consume exactly one revision');
begin;
set local role authenticated;
set local "request.jwt.claim.sub"='d9000000-0000-4000-8000-000000000001';
select public.revoke_employee_invitation_action(organization_id,invitation_id,'d9400000-0000-4000-8000-000000000006',2,'Cancel already claimed invitation') from test.d6_race_invitations where n=6;
select public.revoke_employee_invitation_action(organization_id,invitation_id,'d9400000-0000-4000-8000-000000000007',1,'Cancel before delivery claim') from test.d6_race_invitations where n=7;
commit;
begin;
set local role service_role;
select test.expect_error($q$select public.claim_invitation_delivery(invitation_id) from test.d6_race_invitations where n=7$q$,'23514','Cancellation committed before claim prevents provider dispatch');
commit;
select test.assert((select accepted_at is null and revoked_at is not null and delivery_state='sending' from public.employee_invitations where id=(select invitation_id from test.d6_race_invitations where n=6)),'Cancellation after provider claim preserves unknown mail evidence without membership');
D6_CLAIM_ASSERT
