import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexapos/app/theme/app_theme.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/auth/secure_session_storage.dart';
import 'package:nexapos/core/operations/native_operation_journal.dart';
import 'package:nexapos/core/operations/operation_journal.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/core/security/local_database_security.dart';
import 'package:nexapos/features/administration/domain/administration_models.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/invitations/data/supabase_invitation_administration_repository.dart';
import 'package:nexapos/features/invitations/domain/invitation_models.dart';
import 'package:nexapos/features/invitations/domain/invitation_repository.dart';
import 'package:nexapos/features/invitations/presentation/invitations_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _org = 'b8000000-0000-4000-8000-000000000001';
const _user = 'b8000000-0000-4000-8000-000000000002';
const _branch = 'b8000000-0000-4000-8000-000000000003';
const _id = 'b8000000-0000-4000-8000-000000000004';
const _request = 'b8000000-0000-4000-8000-000000000005';
const _emailRequest = 'b8000000-0000-4000-8000-000000000006';
const _other = 'b8000000-0000-4000-8000-000000000009';
final _sql =
    jsonDecode(
          File(
            'test/fixtures/invitations_sql_contract.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
AuthenticatedUser _sqlActor({String? actorId, AppRole role = AppRole.owner}) =>
    AuthenticatedUser(
      userId: actorId ?? _sql['actor_id'] as String,
      email: 'owner@example.test',
      organizationId: _sql['organization_id'] as String,
      membershipId: 'c8000000-0000-4000-8000-000000000099',
      role: role,
      branchIds: (_sql['pending_detail']['branches'] as List)
          .where((b) => b['active'] == true)
          .map((b) => b['id'] as String)
          .toSet(),
      allBranches: role == AppRole.owner,
      businessName: 'Isolated SQL invitation contract',
    );
Map<String, dynamic> _row({bool retryable = false}) => {
  'id': _id,
  'organization_id': _org,
  'invited_by': _user,
  'revision': 1,
  'normalized_email': 'employee@example.test',
  'full_name': 'Invited Employee',
  'requested_role': 'cashier',
  'employee_id': 'STAFF-1',
  'phone': '+639123456789',
  'all_branches': false,
  'branch_ids': [_branch],
  'branches': [
    {'id': _branch, 'name': 'Original branch', 'active': true},
  ],
  'created_at': '2026-10-12T00:00:00Z',
  'expires_at': '2026-10-19T00:00:00Z',
  'accepted_at': null,
  'revoked_at': null,
  'delivery_state': retryable ? 'failed' : 'sending',
  'delivery_claimed_at': '2026-10-12T00:01:00Z',
  'delivery_finished_at': retryable ? '2026-10-12T00:02:00Z' : null,
  'status': 'pending',
  'can_revoke': true,
  'can_retry_delivery': retryable,
  'retry_input': retryable
      ? {
          'organization_id': _org,
          'request_id': _emailRequest,
          'email': 'employee@example.test',
          'full_name': 'Invited Employee',
          'role': 'cashier',
          'branch_ids': [_branch],
          'all_branches': false,
          'employee_id': 'STAFF-1',
          'phone': '+639123456789',
          'reason': 'Original invitation reason',
        }
      : null,
};
Map<String, dynamic> _revocation({String request = _request}) {
  final row = _row()
    ..['revision'] = 2
    ..['status'] = 'revoked'
    ..['revoked_at'] = '2026-10-12T00:03:00Z'
    ..['can_revoke'] = false;
  return {
    'request_id': request,
    'organization_id': _org,
    'actor_id': _user,
    'kind': 'invitation.revoke',
    'invitation': row,
  };
}

AuthenticatedUser _actor({
  AppRole role = AppRole.owner,
  Set<String>? branches,
}) => AuthenticatedUser(
  userId: _user,
  email: 'owner@example.test',
  organizationId: _org,
  membershipId: 'b8000000-0000-4000-8000-000000000007',
  role: role,
  branchIds: branches ?? {_branch},
  allBranches: role == AppRole.owner,
  businessName: 'Isolated invitation test',
);

class _Harness {
  _Harness({NativeOperationJournal? journal, AuthenticatedUser? actor})
    : actor = actor ?? _actor() {
    this.journal =
        journal ??
        NativeOperationJournal(
          executor: NativeDatabase.memory(),
          organizationId: this.actor.organizationId,
          actorId: this.actor.userId,
        );
    client = SupabaseClient(
      'https://project.example.test',
      'test-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = await handler(request);
        return http.Response(
          response.body,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
  }
  final AuthenticatedUser actor;
  late final NativeOperationJournal journal;
  late final SupabaseClient client;
  final requests = <http.Request>[];
  bool recovery = false, closed = false;
  late Future<http.Response> Function(http.Request) handler = (_) async =>
      response(_revocation());
  static http.Response response(Object data, {int status = 200}) =>
      http.Response(
        jsonEncode(data),
        status,
        headers: {'content-type': 'application/json'},
      );
  SupabaseInvitationAdministrationRepository get repository =>
      SupabaseInvitationAdministrationRepository(
        client: client,
        actor: actor,
        journal: journal,
        isRecoverySession: () => recovery,
      );
  Future<void> signIn({String? user}) async {
    user ??= actor.userId;
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token':
            '${encode({'alg': 'HS256'})}.${encode({'sub': user, 'exp': 4102444800})}.test',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'user': {
          'id': user,
          'aud': 'authenticated',
          'email': 'owner@example.test',
          'email_confirmed_at': '2026-10-11T00:00:00Z',
          'created_at': '2026-10-11T00:00:00Z',
          'app_metadata': {},
          'user_metadata': {},
        },
      }),
    );
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    await client.dispose();
    await journal.close();
  }

  Future<InvitationRevocation> revoke() => repository.revoke(
    original: ManagedInvitation.fromRow(_row()),
    reason: 'No longer needed',
    requestId: _request,
  );
}

class _Store implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _Fake implements InvitationAdministrationRepository {
  ManagedInvitation record = ManagedInvitation.fromRow(_row());
  List<PendingOperation> saved = [];
  Completer<ManagedInvitation>? detail;
  Completer<InvitationRevocation>? mutation;
  InvitationFilter? filter;
  PageRequest? page;
  int reads = 0, mutations = 0, deliveries = 0;
  bool hasMore = false;
  bool journalUnavailable = false;
  @override
  String get organizationId => _org;
  @override
  Set<String> get branchIds => {_branch};
  @override
  Future<DataPage<ManagedInvitation>> listInvitations({
    InvitationFilter filter = const InvitationFilter(),
    PageRequest page = const PageRequest(),
  }) async {
    reads++;
    this.filter = filter;
    this.page = page;
    return DataPage(items: [record], hasMore: hasMore, offset: page.offset);
  }

  @override
  Future<ManagedInvitation> invitation(String invitationId) =>
      detail?.future ?? Future.value(record);
  @override
  Future<List<PendingOperation>> pending() async {
    if (journalUnavailable) {
      throw const RepositoryFailure(
        RepositoryFailureType.unavailable,
        'Saved invitation requests could not be read.',
      );
    }
    return saved;
  }

  @override
  Future<InvitationRevocation> revoke({
    required ManagedInvitation original,
    required String reason,
    required String requestId,
  }) async {
    mutations++;
    return mutation?.future ??
        InvitationRevocation.fromRow(_revocation(request: requestId));
  }

  @override
  Future<InvitationRevocation> retry(PendingOperation operation) async {
    mutations++;
    return InvitationRevocation.fromRow(_revocation());
  }

  @override
  Future<InvitationDelivery> retryDelivery(ManagedInvitation original) async {
    deliveries++;
    return InvitationDelivery(
      invitationId: _id,
      expiresAt: record.expiresAt,
      state: InvitationDeliveryState.sending,
    );
  }
}

PendingOperation _pending() => PendingOperation(
  requestId: _request,
  organizationId: _org,
  branchId: _branch,
  actorId: _user,
  type: SupabaseInvitationAdministrationRepository.operationType,
  payload: {
    'p_organization_id': _org,
    'p_invitation_id': _id,
    'p_request_id': _request,
    'p_expected_revision': 1,
    'p_reason': 'No longer needed',
  },
  createdAt: DateTime.utc(2026, 10, 12),
  status: LocalOperationStatus.pending,
  attemptCount: 1,
);

void main() {
  test(
    'invitation sentinel pagination rejects page size 100 before HTTP',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.signIn();
      await expectLater(
        h.repository.listInvitations(page: const PageRequest(limit: 100)),
        throwsA(
          isA<RepositoryFailure>().having(
            (e) => e.type,
            'type',
            RepositoryFailureType.validation,
          ),
        ),
      );
      expect(h.requests, isEmpty);
    },
  );
  for (final key in [
    'pending_detail',
    'sending_detail',
    'failed_detail',
    'accepted_detail',
    'expired_detail',
  ]) {
    test(
      'actual PostgreSQL $key decodes and reads through the authenticated SDK',
      () async {
        final h = _Harness(actor: _sqlActor());
        addTearDown(h.close);
        await h.signIn();
        final row = Map<String, dynamic>.from(_sql[key] as Map);
        h.handler = (request) async {
          expect(
            request.url.path,
            endsWith('/get_managed_employee_invitation'),
          );
          expect(jsonDecode(request.body), {
            'p_organization_id': _sql['organization_id'],
            'p_invitation_id': row['id'],
          });
          return _Harness.response(row);
        };
        final record = await h.repository.invitation(row['id'] as String);
        expect(record.id, row['id']);
        expect(record.status.name, row['status']);
        expect(record.delivery.name, row['delivery_state']);
        expect(record.invitedBy, row['invited_by']);
      },
    );
  }
  for (final key in ['revoke_action', 'inactive_revoke_action']) {
    test(
      'actual PostgreSQL $key confirms exact actor request and revision',
      () async {
        final action = Map<String, dynamic>.from(_sql[key] as Map),
            row = Map<String, dynamic>.from(_sql[key]['invitation'] as Map);
        final actor = _sqlActor(
          actorId: action['actor_id'] as String,
          role: key == 'inactive_revoke_action' ? AppRole.admin : AppRole.owner,
        );
        final h = _Harness(actor: actor);
        addTearDown(h.close);
        await h.signIn();
        row['status'] = 'pending';
        row['revoked_at'] = null;
        row['can_revoke'] = true;
        row['revision'] = (row['revision'] as int) - 1;
        h.handler = (request) async {
          final saved = (await h.journal.pending()).single;
          expect(saved.attemptCount, 1);
          expect(saved.actorId, action['actor_id']);
          expect(saved.requestId, action['request_id']);
          return _Harness.response(action);
        };
        final confirmed = await h.repository.revoke(
          original: ManagedInvitation.fromRow(row),
          reason: 'Review exact original invitation',
          requestId: action['request_id'] as String,
        );
        expect(confirmed.invitation.status, ManagedInvitationStatus.revoked);
        expect(await h.repository.pending(), isEmpty);
        if (key == 'inactive_revoke_action') {
          expect(confirmed.invitation.branches.any((b) => !b.active), true);
        }
      },
    );
  }
  test(
    'actual PostgreSQL scoped list preserves safe historical records',
    () async {
      final h = _Harness(actor: _sqlActor());
      addTearDown(h.close);
      await h.signIn();
      h.handler = (_) async => _Harness.response(_sql['list']!);
      final page = await h.repository.listInvitations();
      expect(page.items.length, (_sql['list'] as List).length);
      expect(page.hasMore, false);
      expect(
        page.items.any((r) => r.status == ManagedInvitationStatus.accepted),
        true,
      );
    },
  );
  test(
    'actual PostgreSQL retry input sends the exact retained Edge payload',
    () async {
      final h = _Harness(actor: _sqlActor());
      addTearDown(h.close);
      await h.signIn();
      final row = Map<String, dynamic>.from(_sql['pending_detail'] as Map);
      h.handler = (request) async {
        if (request.url.path.endsWith('/get_managed_employee_invitation')) {
          return _Harness.response(row);
        }
        expect(jsonDecode(request.body), row['retry_input']);
        return _Harness.response({
          'invitation_id': row['id'],
          'expires_at': row['expires_at'],
          'delivery_state': 'sending',
        }, status: 202);
      };
      expect(
        (await h.repository.retryDelivery(
          ManagedInvitation.fromRow(row),
        )).state,
        InvitationDeliveryState.sending,
      );
      expect(
        h.requests.where((r) => r.url.path.contains('/functions/')),
        hasLength(1),
      );
    },
  );
  test('terminal revocation outranks the retained in-flight email state', () {
    final result = InvitationRevocation.fromRow(_revocation());
    expect(result.invitation.status, ManagedInvitationStatus.revoked);
    expect(result.invitation.delivery, ManagedInvitationDelivery.sending);
    expect(result.invitation.canRevoke, false);
  });
  test(
    'legacy missing branch snapshot remains readable without capabilities',
    () {
      final row = _row()
        ..['branch_ids'] = []
        ..['branches'] = []
        ..['can_revoke'] = false;
      expect(ManagedInvitation.fromRow(row).branches, isEmpty);
    },
  );
  test('inactive original assignments remain in historical documents', () {
    final row = _row();
    (row['branches'] as List).single['active'] = false;
    expect(ManagedInvitation.fromRow(row).branches.single.active, false);
  });
  test(
    'legacy accepted prepared delivery remains readable without actions',
    () {
      final row = _row()
        ..['status'] = 'accepted'
        ..['accepted_at'] = '2026-10-12T00:03:00Z'
        ..['delivery_state'] = 'prepared'
        ..['delivery_claimed_at'] = null
        ..['can_revoke'] = false;
      final record = ManagedInvitation.fromRow(row);
      expect(record.status, ManagedInvitationStatus.accepted);
      expect(record.delivery, ManagedInvitationDelivery.prepared);
      expect(record.canRetryDelivery, false);
    },
  );
  for (final mutation in <String, void Function(Map<String, dynamic>)>{
    'unsafe revision': (r) => r['revision'] = 9007199254740992,
    'fractional revision': (r) => r['revision'] = 1.5,
    'non UTC': (r) => r['created_at'] = '2026-10-12T08:00:00+08:00',
    'invalid calendar': (r) => r['created_at'] = '2026-02-30T00:00:00Z',
    'invalid UUID': (r) => r['invited_by'] = 'owner',
    'non normalized email': (r) =>
        r['normalized_email'] = 'EMPLOYEE@example.test',
    'unknown delivery': (r) => r['delivery_state'] = 'delivered',
    'unknown status': (r) => r['status'] = 'activated',
    'owner target': (r) => r['requested_role'] = 'owner',
    'duplicate branches': (r) => (r['branch_ids'] as List).add(_branch),
    'foreign branch details': (r) =>
        (r['branches'] as List).single['id'] = _other,
    'accepted missing timestamp': (r) => r['status'] = 'accepted',
    'revoked missing timestamp': (r) => r['status'] = 'revoked',
    'terminal revoke capability': (r) {
      r['status'] = 'expired';
    },
    'sending retry capability': (r) => r['can_retry_delivery'] = true,
    'empty branch mutation capability': (r) {
      r['branch_ids'] = [];
      r['branches'] = [];
    },
    'unrestricted cashier': (r) {
      r['all_branches'] = true;
      r['branch_ids'] = [];
      r['branches'] = [];
    },
    'reversed expiry': (r) => r['expires_at'] = r['created_at'],
    'sending missing claim': (r) => r['delivery_claimed_at'] = null,
    'sending finished prematurely': (r) =>
        r['delivery_finished_at'] = '2026-10-12T00:02:00Z',
    'sent missing finish': (r) => r['delivery_state'] = 'sent',
    'prepared has claim': (r) => r['delivery_state'] = 'prepared',
    'claim before creation': (r) =>
        r['delivery_claimed_at'] = '2026-10-11T00:02:00Z',
  }.entries) {
    test('managed document rejects ${mutation.key}', () {
      final row = _row();
      mutation.value(row);
      expect(() => ManagedInvitation.fromRow(row), throwsA(anything));
    });
  }
  for (final field in [
    'request_id',
    'organization_id',
    'email',
    'full_name',
    'role',
    'phone',
    'reason',
    'branch_ids',
    'extra',
  ]) {
    test('original retry payload validates $field', () {
      final row = _row(retryable: true), input = row['retry_input'] as Map;
      input[field] = switch (field) {
        'request_id' => 'new-request',
        'organization_id' => _other,
        'branch_ids' => [_other],
        'reason' => 'x',
        'extra' => true,
        _ => 'changed',
      };
      expect(() => ManagedInvitation.fromRow(row), throwsA(anything));
    });
  }
  test('literal search keeps SQL wildcard characters as ordinary text', () {
    expect(
      const InvitationFilter(search: '  %_staff  ').validatedSearch(),
      '%_staff',
    );
    expect(
      () => const InvitationFilter(search: 'staff\nsecret').validatedSearch(),
      throwsA(isA<RepositoryFailure>()),
    );
  });
  test(
    'revocation persists original intent and attempt before dispatch',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.signIn();
      h.handler = (request) async {
        final saved = (await h.journal.pending()).single;
        expect(saved.attemptCount, 1);
        expect(saved.requestId, _request);
        expect(saved.payload, jsonDecode(request.body));
        return _Harness.response(_revocation());
      };
      expect(
        (await h.revoke()).invitation.status,
        ManagedInvitationStatus.revoked,
      );
      expect(await h.repository.pending(), isEmpty);
    },
  );
  for (final field in [
    'request_id',
    'organization_id',
    'actor_id',
    'kind',
    'invitation_id',
    'revision',
  ]) {
    test('foreign or malformed success $field remains pending', () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.signIn();
      final row = _revocation();
      if (field == 'invitation_id') {
        (row['invitation'] as Map)['id'] = _other;
      } else if (field == 'revision') {
        (row['invitation'] as Map)['revision'] = 3;
      } else {
        row[field] = field == 'kind' ? 'invitation.accept' : _other;
      }
      h.handler = (_) async => _Harness.response(row);
      await expectLater(h.revoke(), throwsA(isA<RepositoryFailure>()));
      expect((await h.repository.pending()).single.attemptCount, 1);
    });
  }
  test('first definitive MFA denial rejects an uncommitted intent', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.signIn();
    h.handler = (_) async => _Harness.response({
      'code': '42501',
      'message': 'MFA required',
    }, status: 403);
    await expectLater(h.revoke(), throwsA(isA<RepositoryFailure>()));
    expect(await h.repository.pending(), isEmpty);
  });
  test(
    'MFA denial after an uncertain response preserves the original intent',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.signIn();
      h.handler = (_) async => _Harness.response({'unconfirmed': true});
      await expectLater(h.revoke(), throwsA(isA<RepositoryFailure>()));
      final original = (await h.repository.pending()).single;
      h.handler = (_) async => _Harness.response({
        'code': '42501',
        'message': 'Membership changed',
      }, status: 403);
      await expectLater(
        h.repository.retry(original),
        throwsA(
          isA<RepositoryFailure>().having(
            (e) => e.type,
            'type',
            RepositoryFailureType.unavailable,
          ),
        ),
      );
      expect((await h.repository.pending()).single.attemptCount, 2);
      expect(
        h.requests.map((r) => jsonDecode(r.body)['p_request_id']).toSet(),
        {_request},
      );
    },
  );
  test('an uncertain revocation blocks a replacement UUID', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.signIn();
    h.handler = (_) async => _Harness.response({'unconfirmed': true});
    await expectLater(h.revoke(), throwsA(anything));
    await expectLater(
      h.repository.revoke(
        original: ManagedInvitation.fromRow(_row()),
        reason: 'Replacement prohibited',
        requestId: _other,
      ),
      throwsA(isA<RepositoryFailure>()),
    );
    expect(h.requests, hasLength(1));
  });
  for (final scenario in [
    'signed out',
    'recovery',
    'cashier',
    'identity switch',
  ]) {
    test('preflight $scenario does not dispatch or create intent', () async {
      final h = _Harness(
        actor: _actor(
          role: scenario == 'cashier' ? AppRole.cashier : AppRole.owner,
        ),
      );
      addTearDown(h.close);
      if (scenario != 'signed out') {
        await h.signIn(user: scenario == 'identity switch' ? _other : _user);
      }
      h.recovery = scenario == 'recovery';
      await expectLater(h.revoke(), throwsA(isA<RepositoryFailure>()));
      expect(h.requests, isEmpty);
      expect(await h.journal.pending(), isEmpty);
    });
  }
  test(
    'Admin cannot revoke an Admin invitation despite malformed capability',
    () async {
      final h = _Harness(actor: _actor(role: AppRole.admin));
      addTearDown(h.close);
      await h.signIn();
      final row = _row()..['requested_role'] = 'admin';
      await expectLater(
        h.repository.revoke(
          original: ManagedInvitation.fromRow(row),
          reason: 'Target denied',
          requestId: _request,
        ),
        throwsA(isA<RepositoryFailure>()),
      );
      expect(h.requests, isEmpty);
    },
  );
  test(
    'historical journal anchor does not replace current server authorization',
    () async {
      final h = _Harness(actor: _actor(branches: {_other}));
      addTearDown(h.close);
      await h.signIn();
      final op = _pending();
      await h.journal.prepare(
        requestId: op.requestId,
        type: op.type,
        branchId: op.branchId,
        payload: op.payload,
      );
      await h.journal.markAttempted(requestId: op.requestId);
      expect(
        await h.repository.retry((await h.repository.pending()).single),
        isA<InvitationRevocation>(),
      );
      expect(jsonDecode(h.requests.single.body)['p_request_id'], _request);
    },
  );
  test(
    'late identity switch prevents confirmation and record exposure',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.signIn();
      h.handler = (_) async {
        await h.signIn(user: _other);
        return _Harness.response(_revocation());
      };
      await expectLater(h.revoke(), throwsA(isA<RepositoryFailure>()));
      expect((await h.journal.pending()).single.attemptCount, 1);
    },
  );
  test(
    'SQLCipher reopen preserves original revocation and excludes plaintext',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nexapos-invitation-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/journal.sqlite');
      final factory = EncryptedDatabaseFactory(store: _Store());
      Future<NativeOperationJournal> open() async => NativeOperationJournal(
        executor: await factory.open(file),
        organizationId: _org,
        actorId: _user,
      );
      final first = _Harness(journal: await open());
      await first.signIn();
      first.handler = (_) async => _Harness.response({'unconfirmed': true});
      await expectLater(first.revoke(), throwsA(anything));
      await first.close();
      expect(
        utf8.decode(await file.readAsBytes(), allowMalformed: true),
        isNot(contains('No longer needed')),
      );
      final second = _Harness(journal: await open());
      addTearDown(second.close);
      await second.signIn();
      final pending = (await second.repository.pending()).single;
      expect(pending.attemptCount, 1);
      expect(pending.payload['p_reason'], 'No longer needed');
      await second.repository.retry(pending);
      expect(await second.repository.pending(), isEmpty);
      expect(jsonDecode(second.requests.single.body)['p_request_id'], _request);
    },
  );
  test(
    'paginated list uses literal filters and rejects foreign records',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.signIn();
      h.handler = (request) async {
        final params = jsonDecode(request.body);
        expect(params['p_search'], '%_staff');
        expect(params['p_status'], 'pending');
        expect(params['p_offset'], 20);
        expect(params['p_limit'], 21);
        return _Harness.response([_row()]);
      };
      final page = await h.repository.listInvitations(
        filter: const InvitationFilter(
          search: '%_staff',
          status: ManagedInvitationStatus.pending,
        ),
        page: const PageRequest(offset: 20, limit: 20),
      );
      expect(page.offset, 20);
      expect(page.items.single.id, _id);
      h.handler = (_) async =>
          _Harness.response([_row()..['organization_id'] = _other]);
      await expectLater(
        h.repository.listInvitations(),
        throwsA(isA<RepositoryFailure>()),
      );
    },
  );
  test(
    'foreign original author cannot retry even with forged capability',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.signIn();
      final original = ManagedInvitation.fromRow(
        _row(retryable: true)..['invited_by'] = _other,
      );
      await expectLater(
        h.repository.retryDelivery(original),
        throwsA(isA<RepositoryFailure>()),
      );
      expect(h.requests, isEmpty);
      h.handler = (_) async =>
          _Harness.response(_row(retryable: true)..['invited_by'] = _other);
      await expectLater(
        h.repository.invitation(_id),
        throwsA(isA<RepositoryFailure>()),
      );
      expect(
        h.requests.where((r) => r.url.path.contains('/functions/')),
        isEmpty,
      );
    },
  );
  test(
    'delivery retry dispatches exact original Edge identity and payload',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.signIn();
      final row = _row(retryable: true);
      h.handler = (request) async {
        if (request.url.path.endsWith('/get_managed_employee_invitation')) {
          return _Harness.response(row);
        }
        expect(jsonDecode(request.body), row['retry_input']);
        return _Harness.response({
          'invitation_id': _id,
          'expires_at': row['expires_at'],
          'delivery_state': 'sent',
        });
      };
      expect(
        (await h.repository.retryDelivery(
          ManagedInvitation.fromRow(row),
        )).state,
        InvitationDeliveryState.sent,
      );
      expect(
        h.requests.where((r) => r.url.path.contains('/functions/')),
        hasLength(1),
      );
    },
  );
  test(
    'changed original retry reason cannot silently supersede a saved request',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.signIn();
      final row = _row(retryable: true), changed = _row(retryable: true);
      (changed['retry_input'] as Map)['reason'] = 'Changed reason';
      h.handler = (_) async => _Harness.response(changed);
      await expectLater(
        h.repository.retryDelivery(ManagedInvitation.fromRow(row)),
        throwsA(isA<RepositoryFailure>()),
      );
      expect(
        h.requests.where((r) => r.url.path.contains('/functions/')),
        isEmpty,
      );
    },
  );

  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'preview and current state fit $width without invented records',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = _Fake();
        Widget page({bool preview = false, AppRole role = AppRole.owner}) =>
            MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: InvitationsPage(
                  repository: repo,
                  role: role,
                  isPreview: preview,
                ),
              ),
            );
        await tester.pumpWidget(page(preview: true));
        await tester.pumpAndSettle();
        expect(find.text('No connected invitations'), findsOneWidget);
        expect(repo.reads, 0);
        expect(find.text('employee@example.test'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        expect(find.text('employee@example.test'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('View invitation'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('View invitation'));
        await tester.pumpAndSettle();
        expect(find.text('Invitation details'), findsOneWidget);
        expect(
          find.text('Email request in progress or outcome unknown'),
          findsWidgets,
        );
        expect(find.text('Retry original email request'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(page(role: AppRole.cashier));
        await tester.pumpAndSettle();
        expect(find.text('Business context changed'), findsOneWidget);
        expect(find.text('employee@example.test'), findsNothing);
        expect(find.text('Revoke invitation'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(repo.mutations, 0);
      },
    );
  }
  testWidgets(
    'reason requires three characters and stale role hides the form',
    (tester) async {
      final repo = _Fake();
      Widget page(AppRole role) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: InvitationsPage(repository: repo, role: role, isPreview: false),
        ),
      );
      await tester.pumpWidget(page(AppRole.owner));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('View invitation'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View invitation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revoke invitation'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('invitation-revoke-reason')),
        'ab',
      );
      await tester.tap(find.text('Confirm revocation'));
      await tester.pumpAndSettle();
      expect(
        find.text('Reason must contain 3 to 500 characters.'),
        findsOneWidget,
      );
      expect(repo.mutations, 0);
      await tester.pumpWidget(page(AppRole.cashier));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('invitation-revoke-reason')), findsNothing);
      expect(find.text('Confirm revocation'), findsNothing);
      expect(repo.mutations, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('late detail never opens under a replacement repository', (
    tester,
  ) async {
    final old = _Fake()..detail = Completer<ManagedInvitation>(),
        next = _Fake();
    Widget page(_Fake repo) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: InvitationsPage(
          repository: repo,
          role: AppRole.owner,
          isPreview: false,
        ),
      ),
    );
    await tester.pumpWidget(page(old));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('View invitation'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View invitation'));
    await tester.pump();
    await tester.pumpWidget(page(next));
    await tester.pumpAndSettle();
    old.detail!.complete(old.record);
    await tester.pumpAndSettle();
    expect(find.text('Invitation details'), findsNothing);
    expect(old.mutations, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'late revocation result cannot enter a replacement business page',
    (tester) async {
      final old = _Fake()..mutation = Completer<InvitationRevocation>();
      final next = _Fake()
        ..record = ManagedInvitation.fromRow(
          _row()..['normalized_email'] = 'replacement@example.test',
        );
      Widget page(_Fake repo) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: InvitationsPage(
            repository: repo,
            role: AppRole.owner,
            isPreview: false,
          ),
        ),
      );
      await tester.pumpWidget(page(old));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('View invitation'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View invitation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revoke invitation'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('invitation-revoke-reason')),
        'Revocation reason',
      );
      await tester.tap(find.text('Confirm revocation'));
      await tester.pump();
      expect(old.mutations, 1);
      await tester.pumpWidget(page(next));
      await tester.pumpAndSettle();
      old.mutation!.complete(InvitationRevocation.fromRow(_revocation()));
      await tester.pumpAndSettle();
      expect(next.mutations, 0);
      expect(next.reads, 1);
      expect(find.textContaining('Invitation revoked.'), findsNothing);
      expect(find.text('employee@example.test'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unreadable journal fails closed before private records or new actions',
    (tester) async {
      final repo = _Fake()..journalUnavailable = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: InvitationsPage(
              repository: repo,
              role: AppRole.owner,
              isPreview: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.reads, 0);
      expect(find.text('employee@example.test'), findsNothing);
      expect(find.text('View invitation'), findsNothing);
      expect(repo.mutations, 0);
      expect(
        find.text('Saved invitation requests could not be read.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'unresolved revocation blocks replacement and email retry actions',
    (tester) async {
      final repo = _Fake()
        ..record = ManagedInvitation.fromRow(_row(retryable: true))
        ..saved = [_pending()];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: InvitationsPage(
              repository: repo,
              role: AppRole.owner,
              isPreview: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Retry original revocation'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry original revocation'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('View invitation'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View invitation'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Revoke invitation'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(
                OutlinedButton,
                'Retry original email request',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(repo.mutations, 0);
      expect(repo.deliveries, 0);
    },
  );
  testWidgets('explicit original delivery retry displays uncertainty honestly', (
    tester,
  ) async {
    final repo = _Fake()
      ..record = ManagedInvitation.fromRow(_row(retryable: true));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: InvitationsPage(
            repository: repo,
            role: AppRole.owner,
            isPreview: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('View invitation'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View invitation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry original email request'));
    await tester.pumpAndSettle();
    expect(repo.deliveries, 0);
    await tester.tap(find.text('Retry original request'));
    await tester.pumpAndSettle();
    expect(repo.deliveries, 1);
    expect(
      find.text(
        'Email request in progress or outcome unknown. No replacement invitation was created.',
      ),
      findsOneWidget,
    );
    expect(repo.mutations, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('search and page navigation retain applied literal filter', (
    tester,
  ) async {
    final repo = _Fake()..hasMore = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: InvitationsPage(
            repository: repo,
            role: AppRole.owner,
            isPreview: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('invitation-search')),
      '%_staff',
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(repo.filter!.search, '%_staff');
    await tester.scrollUntilVisible(
      find.text('Next'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(repo.page!.offset, 20);
    expect(repo.filter!.search, '%_staff');
  });
}
