import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/operations/native_operation_journal.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/security/data/security_decoders.dart';
import 'package:nexapos/features/security/data/security_wire.dart';
import 'package:nexapos/features/security/data/supabase_security_repository.dart';
import 'package:nexapos/features/security/domain/security_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _org = '11111111-1111-1111-1111-111111111111';
const _actorId = '22222222-2222-2222-2222-222222222222';
const _member = '33333333-3333-3333-3333-333333333333';
const _branch = '44444444-4444-4444-4444-444444444444';
const _device = '55555555-5555-5555-5555-555555555555';
const _request = '66666666-6666-6666-6666-666666666666';
const _grant = '77777777-7777-7777-7777-777777777777';
const _shift = '88888888-8888-8888-8888-888888888888';
const _other = '99999999-9999-9999-9999-999999999999';

AuthenticatedUser _actor({AppRole role = AppRole.owner}) => AuthenticatedUser(
  userId: _actorId,
  email: 'owner@example.test',
  organizationId: _org,
  membershipId: _member,
  role: role,
  branchIds: {_branch},
  allBranches: true,
  businessName: 'Test business',
);

Map<String, dynamic> _policy({int revision = 1}) => {
  'organization_id': _org,
  'revision': revision,
  'idle_lock_minutes': 5,
  'require_privileged_mfa': false,
};
Map<String, dynamic> _deviceRow() => {
  'device_id': _device,
  'organization_id': _org,
  'branch_id': _branch,
  'actor_id': _actorId,
  'device_name': 'Till 1',
  'platform': 'windows',
  'enrolled_at': '2026-10-11T12:00:00.123456Z',
  'last_sync_at': null,
  'revoked_at': null,
  'revocation_reason': null,
  'can_manage': true,
};
Map<String, dynamic> _grantRow() => {
  'grant_id': _grant,
  'organization_id': _org,
  'branch_id': _branch,
  'actor_id': _actorId,
  'device_id': _device,
  'shift_id': _shift,
  'issued_at': '2026-10-11T00:00:00Z',
  'expires_at': '2026-10-11T08:00:00Z',
  'max_events': 1000,
  'max_total_minor': 100000000,
  'last_sequence': 2,
  'outcome_count': 2,
  'review_count': 1,
  'total_minor': 113,
  'remaining_exposure_events': 998,
  'remaining_exposure_minor': 99999887,
  'state': 'expired',
  'released_at': null,
  'administratively_resolved_at': null,
  'currency': 'PHP',
  'blocks_shift_close': true,
  'can_review': true,
};
Map<String, dynamic> _noticeRow() => {
  'id': _other,
  'organization_id': _org,
  'branch_id': null,
  'action': 'security.policy.updated',
  'title': 'Security policy changed',
  'message':
      'The organization security policy was updated by an authorized administrator.',
  'created_at': '2026-10-11T12:00:00Z',
  'read_at': null,
};

SecurityMutation _rename() => SecurityMutation.renameDevice(
  requestId: _request,
  branchId: _branch,
  deviceId: _device,
  deviceName: 'Counter 2',
  reason: 'Till moved',
);

TypeMatcher<RepositoryFailure> _failure(RepositoryFailureType type) =>
    isA<RepositoryFailure>()
        .having((value) => value.type, 'type', type)
        .having(
          (value) => value.message,
          'sanitized',
          isNot(contains('PRIVATE')),
        );

class _Harness {
  _Harness() {
    client = SupabaseClient(
      'https://project.example.test',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (handler != null) return handler!(request);
        return response(payload, status, request);
      }),
    );
    journal = NativeOperationJournal(
      executor: NativeDatabase.memory(),
      organizationId: _org,
      actorId: _actorId,
    );
  }
  late final SupabaseClient client;
  late final NativeOperationJournal journal;
  final requests = <http.Request>[];
  Object? payload;
  int status = 200;
  Future<http.Response> Function(http.Request)? handler;

  Future<void> signIn({String userId = _actorId, bool verified = true}) async {
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    await client.auth.recoverSession(
      jsonEncode({
        'access_token':
            '${part({'alg': 'HS256'})}.${part({'sub': userId, 'exp': 4102444800})}.test-signature',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'user': {
          'id': userId,
          'aud': 'authenticated',
          'email': 'owner@example.test',
          'email_confirmed_at': verified ? '2026-10-11T00:00:00Z' : null,
          'created_at': '2026-10-11T00:00:00Z',
          'app_metadata': {},
          'user_metadata': {},
        },
      }),
    );
  }

  SupabaseSecurityRepository repository({
    AppRole role = AppRole.owner,
    bool Function()? isRecoverySession,
  }) => SupabaseSecurityRepository(
    client: client,
    actor: _actor(role: role),
    journal: journal,
    isRecoverySession: isRecoverySession,
  );

  static http.Response response(
    Object? payload,
    int status,
    http.Request request,
  ) => http.Response(
    jsonEncode(payload),
    status,
    headers: {'content-type': 'application/json'},
    request: request,
  );
  Map<String, dynamic> get body =>
      jsonDecode(requests.last.body) as Map<String, dynamic>;
  Future<void> close() async {
    await client.dispose();
    await journal.close();
  }
}

void main() {
  late _Harness transport;
  setUp(() => transport = _Harness());
  tearDown(() => transport.close());

  test(
    'actual isolated SQL projections decode without invented security state',
    () async {
      final fixture = securityRow(
        jsonDecode(
          await File('test/fixtures/security_sql_contract.json').readAsString(),
        ),
      );
      expect(fixture['provenance'], contains('isolated mock-Auth'));
      final policyRow = securityRow(fixture['policy']);
      final org = securityId(policyRow, 'organization_id');
      final deviceRow = securityRows(fixture['devices']).single;
      final branch = securityId(deviceRow, 'branch_id');
      final policy = securityPolicyFromRow(policyRow, organizationId: org);
      final device = securityDeviceFromRow(
        deviceRow,
        organizationId: org,
        branchId: branch,
      );
      final grant = securityGrantFromRow(
        securityRows(fixture['grants']).single,
        organizationId: org,
        branchId: branch,
      );
      final notices = securityRows(fixture['notifications'])
          .map(
            (row) => securityNoticeFromRow(
              row,
              organizationId: org,
              branchId: branch,
            ),
          )
          .toList();
      expect(policy.idleLockMinutes, 10);
      expect(device.revoked, true);
      expect(grant.deviceId, device.deviceId);
      expect(grant.state, SecurityGrantState.administrativelyResolved);
      expect(grant.blocksShiftClose, false);
      expect(grant.lastSequence, 1);
      expect(grant.outcomeCount, 1);
      expect(grant.reviewCount, 1);
      expect(grant.totalMinor, 100);
      expect(grant.remainingExposureEvents, 999);
      expect(grant.remainingExposureMinor, 99999900);
      expect(
        notices.map((notice) => notice.action),
        containsAll([
          'security.offline_paid_event_review',
          'security.grant_administratively_resolved',
          'security.policy_updated',
          'security.device_revoked',
        ]),
      );
    },
  );

  test('missing session and recovery cannot load or mutate security', () async {
    await expectLater(
      transport.repository().loadPolicy(),
      throwsA(_failure(RepositoryFailureType.unauthenticated)),
    );
    await transport.signIn();
    await expectLater(
      transport.repository(isRecoverySession: () => true).mutate(_rename()),
      throwsA(_failure(RepositoryFailureType.unauthenticated)),
    );
    expect(transport.requests, isEmpty);
    expect(await transport.journal.pending(), isEmpty);
  });

  test(
    'actual SQL gapped paid proof keeps count-based unresolved exposure',
    () async {
      final fixture = securityRow(
        jsonDecode(
          await File(
            'test/fixtures/security_sql_gap_contract.json',
          ).readAsString(),
        ),
      );
      final rows = securityRows(fixture['grants']);
      final gapped = rows.singleWhere(
        (row) => row['outcome_count'] < row['last_sequence'],
      );
      final org = securityId(gapped, 'organization_id');
      final branch = securityId(gapped, 'branch_id');
      final grant = securityGrantFromRow(
        gapped,
        organizationId: org,
        branchId: branch,
      );
      expect(grant.lastSequence, 2);
      expect(grant.outcomeCount, 1);
      expect(grant.reviewCount, 1);
      expect(grant.totalMinor, 100);
      expect(grant.remainingExposureEvents, 999);
      expect(grant.remainingExposureMinor, 99999900);
      expect(grant.blocksShiftClose, false);
      expect(grant.state, SecurityGrantState.administrativelyResolved);
    },
  );

  test('unverified and replacement actor cannot read a tenant', () async {
    await transport.signIn(verified: false);
    await expectLater(
      transport.repository().loadPolicy(),
      throwsA(_failure(RepositoryFailureType.unauthenticated)),
    );
    await transport.signIn(userId: _other);
    await expectLater(
      transport.repository().loadPolicy(),
      throwsA(_failure(RepositoryFailureType.unauthenticated)),
    );
    expect(transport.requests, isEmpty);
  });

  test('policy loads only the selected organization', () async {
    await transport.signIn();
    transport.payload = _policy();
    final policy = await transport.repository().loadPolicy();
    expect(policy.idleLockMinutes, 5);
    expect(policy.requirePrivilegedMfa, false);
    expect(
      transport.requests.single.url.path,
      '/rest/v1/rpc/get_security_policy',
    );
    expect(transport.body, {'p_organization_id': _org});
  });

  test('cross-tenant and malformed policy never become defaults', () async {
    await transport.signIn();
    for (final bad in [
      {..._policy(), 'organization_id': _other},
      {..._policy(), 'idle_lock_minutes': 0},
      {..._policy(), 'idle_lock_minutes': 61},
      {..._policy(), 'idle_lock_minutes': '5'},
      {..._policy(), 'require_privileged_mfa': 'true'},
      {..._policy(), 'revision': 0},
    ]) {
      transport.payload = bad;
      await expectLater(
        transport.repository().loadPolicy(),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
    }
  });

  test('device list carries branch scope and bounded overfetch', () async {
    await transport.signIn();
    transport.payload = [
      _deviceRow(),
      {..._deviceRow(), 'device_id': _other},
    ];
    final page = await transport.repository().listDevices(
      branchId: _branch,
      page: const PageRequest(offset: 10, limit: 1),
    );
    expect(page.items.single.name, 'Till 1');
    expect(page.items.single.lastSyncAt, isNull);
    expect(page.items.single.revoked, false);
    expect(page.hasMore, true);
    expect(transport.body, {
      'p_organization_id': _org,
      'p_branch_id': _branch,
      'p_offset': 10,
      'p_limit': 2,
    });
  });

  test('overfetched cross-branch device rejects the entire page', () async {
    await transport.signIn();
    transport.payload = [
      _deviceRow(),
      {..._deviceRow(), 'branch_id': _other},
    ];
    await expectLater(
      transport.repository().listDevices(
        branchId: _branch,
        page: const PageRequest(limit: 1),
      ),
      throwsA(_failure(RepositoryFailureType.unavailable)),
    );
  });

  test('invalid branch and page fail before transport', () async {
    await transport.signIn();
    await expectLater(
      transport.repository().listDevices(branchId: _other),
      throwsA(_failure(RepositoryFailureType.permissionDenied)),
    );
    await expectLater(
      transport.repository().listGrants(
        branchId: _branch,
        page: const PageRequest(limit: 101),
      ),
      throwsA(_failure(RepositoryFailureType.validation)),
    );
    expect(transport.requests, isEmpty);
  });

  test(
    'maximum page respects server maximum without losing next hint',
    () async {
      await transport.signIn();
      transport.payload = List.generate(100, (_) => _noticeRow());
      final page = await transport.repository().listNotices(
        branchId: _branch,
        page: const PageRequest(limit: 100),
      );
      expect(transport.body['p_limit'], 100);
      expect(page.hasMore, true);
      expect(page.items.length, 100);
    },
  );

  test(
    'grant preserves actual barrier, bounds and known outcome summary',
    () async {
      await transport.signIn();
      transport.payload = [_grantRow()];
      final row = (await transport.repository().listGrants(
        branchId: _branch,
      )).items.single;
      expect(row.totalMinor, 113);
      expect(row.outcomeCount, 2);
      expect(row.remainingExposureEvents, 998);
      expect(row.currency, 'PHP');
      expect(row.blocksShiftClose, true);
      transport.payload = [
        {..._grantRow(), 'state': 'unsigned', 'blocks_shift_close': false},
      ];
      expect(
        (await transport.repository().listGrants(
          branchId: _branch,
        )).items.single.blocksShiftClose,
        false,
      );
    },
  );

  test(
    'grant malformed time, counts and state cannot authorize review',
    () async {
      await transport.signIn();
      for (final bad in [
        {..._grantRow(), 'expires_at': '2026-10-11T09:00:00Z'},
        {..._grantRow(), 'max_events': 1001},
        {..._grantRow(), 'outcome_count': 3},
        {..._grantRow(), 'review_count': 3},
        {..._grantRow(), 'remaining_exposure_minor': 100000001},
        {..._grantRow(), 'state': 'administratively_resolved'},
        {..._grantRow(), 'state': 'unknown'},
        {..._grantRow(), 'currency': 'php'},
      ]) {
        transport.payload = [bad];
        await expectLater(
          transport.repository().listGrants(branchId: _branch),
          throwsA(_failure(RepositoryFailureType.unavailable)),
        );
      }
    },
  );

  test('security dates reject calendar normalization and invalid offsets', () {
    for (final value in [
      '2026-02-30T12:00:00Z',
      '2026-10-11T24:00:00Z',
      '2026-10-11T12:00:00+99:00',
      '2026-10-11',
    ]) {
      expect(() => securityTime({'at': value}, 'at'), throwsFormatException);
    }
    expect(
      securityTime({'at': '2026-10-11T12:00:00+08:00'}, 'at'),
      DateTime.utc(2026, 10, 11, 4),
    );
  });

  test(
    'administrative review preserves gapped paid proof without reducing exposure by sequence',
    () async {
      await transport.signIn();
      final gapped = {
        ..._grantRow(),
        'state': 'administratively_resolved',
        'administratively_resolved_at': '2026-10-11T12:00:00Z',
        'last_sequence': 5,
        'outcome_count': 2,
        'review_count': 2,
        'can_review': false,
        'blocks_shift_close': false,
      };
      transport.payload = [gapped];
      final grant = (await transport.repository().listGrants(
        branchId: _branch,
      )).items.single;
      expect(grant.lastSequence, 5);
      expect(grant.outcomeCount, 2);
      expect(grant.reviewCount, 2);
      expect(grant.remainingExposureEvents, 998);
      expect(grant.totalMinor, 113);
      for (final malformed in [
        {...gapped, 'outcome_count': 6},
        {
          ...gapped,
          'outcome_count': 0,
          'review_count': 0,
          'remaining_exposure_events': 1000,
        },
        {...gapped, 'remaining_exposure_events': 995},
        {...gapped, 'remaining_exposure_minor': 99999886},
        {...gapped, 'state': 'expired', 'administratively_resolved_at': null},
      ]) {
        transport.payload = [malformed];
        await expectLater(
          transport.repository().listGrants(branchId: _branch),
          throwsA(_failure(RepositoryFailureType.unavailable)),
        );
      }
    },
  );

  test('owner device rename sends exact immutable audited intent', () async {
    await transport.signIn();
    transport.payload = {..._deviceRow(), 'device_name': 'Counter 2'};
    final result = await transport.repository().mutate(_rename());
    expect(result.device!.name, 'Counter 2');
    expect(transport.body, {
      'p_organization_id': _org,
      'p_request_id': _request,
      'p_branch_id': _branch,
      'p_device_id': _device,
      'p_device_name': 'Counter 2',
      'p_reason': 'Till moved',
    });
    expect(await transport.journal.pending(), isEmpty);
  });

  test('cashier cannot manufacture a management mutation', () async {
    await transport.signIn();
    await expectLater(
      transport.repository(role: AppRole.cashier).mutate(_rename()),
      throwsA(_failure(RepositoryFailureType.permissionDenied)),
    );
    expect(transport.requests, isEmpty);
    expect(await transport.journal.pending(), isEmpty);
  });

  test('management changes require durable journal before dispatch', () async {
    await transport.signIn();
    final repository = SupabaseSecurityRepository(
      client: transport.client,
      actor: _actor(),
    );
    await expectLater(
      repository.mutate(_rename()),
      throwsA(_failure(RepositoryFailureType.notConnected)),
    );
    expect(transport.requests, isEmpty);
  });

  test(
    'malformed successful rename remains pending rather than confirmed',
    () async {
      await transport.signIn();
      transport.payload = _deviceRow();
      await expectLater(
        transport.repository().mutate(_rename()),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
      expect((await transport.journal.pending()).single.attemptCount, 1);
      expect(
        (await transport.repository().pendingMutations()).single.deviceName,
        'Counter 2',
      );
    },
  );

  test(
    'lost success retries same ID and payload and confirms original',
    () async {
      await transport.signIn();
      transport.handler = (_) async =>
          throw const SocketException('PRIVATE lost response');
      await expectLater(
        transport.repository().mutate(_rename()),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
      final original = transport.requests.single.body;
      final restored = (await transport.repository().pendingMutations()).single;
      transport.handler = null;
      transport.payload = {..._deviceRow(), 'device_name': 'Counter 2'};
      final result = await transport.repository().mutate(restored);
      expect(result.requestId, _request);
      expect(transport.requests.last.body, original);
      expect(await transport.journal.pending(), isEmpty);
    },
  );

  test(
    'later denial cannot reject an earlier uncertain security change',
    () async {
      await transport.signIn();
      transport.handler = (_) async =>
          throw const SocketException('PRIVATE lost response');
      await expectLater(
        transport.repository().mutate(_rename()),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
      transport.handler = null;
      transport.status = 403;
      transport.payload = {
        'code': '42501',
        'message': 'PRIVATE access removed',
      };
      await expectLater(
        transport.repository().mutate(_rename()),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
      expect((await transport.journal.pending()).single.attemptCount, 2);
    },
  );

  test(
    'first definitive rollback rejects the original administrative intent',
    () async {
      await transport.signIn();
      transport.status = 409;
      transport.payload = {'code': '40001', 'message': 'PRIVATE stale state'};
      await expectLater(
        transport.repository().mutate(_rename()),
        throwsA(_failure(RepositoryFailureType.conflict)),
      );
      expect(await transport.journal.pending(), isEmpty);
      final calls = transport.requests.length;
      await expectLater(
        transport.repository().mutate(_rename()),
        throwsA(_failure(RepositoryFailureType.conflict)),
      );
      expect(transport.requests.length, calls);
    },
  );

  test(
    'policy changed values or tenant cannot confirm a durable update',
    () async {
      await transport.signIn();
      final input = SecurityMutation.policy(
        requestId: _request,
        expectedRevision: 1,
        idleLockMinutes: 7,
        requirePrivilegedMfa: true,
        reason: 'Protect checkout',
      );
      transport.payload = {..._policy(revision: 2), 'idle_lock_minutes': 7};
      await expectLater(
        transport.repository().mutate(input),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
      transport.payload = {
        ..._policy(revision: 2),
        'idle_lock_minutes': 7,
        'require_privileged_mfa': true,
      };
      final saved = await transport.repository().mutate(input);
      expect(saved.policy!.revision, 2);
      expect(transport.body['p_expected_revision'], 1);
      expect(await transport.journal.pending(), isEmpty);
    },
  );

  test(
    'review binds displayed paid counts and explicit unknown risk',
    () async {
      await transport.signIn();
      final input = SecurityMutation.reviewGrant(
        requestId: _request,
        branchId: _branch,
        grantId: _grant,
        reason: 'Device lost after report recovery',
        acknowledgeUnknownPaidEvents: true,
        expectedLastSequence: 2,
        expectedOutcomeCount: 2,
        expectedTotalMinor: 113,
      );
      transport.payload = {
        ..._grantRow(),
        'state': 'administratively_resolved',
        'administratively_resolved_at': '2026-10-11T12:00:00Z',
        'can_review': false,
        'blocks_shift_close': false,
      };
      final result = await transport.repository().mutate(input);
      expect(result.grant!.blocksShiftClose, false);
      expect(result.grant!.remainingExposureEvents, 998);
      expect(transport.body['p_expected_last_sequence'], 2);
      expect(transport.body['p_expected_outcome_count'], 2);
      expect(transport.body['p_expected_total_minor'], 113);
      expect(transport.body['p_acknowledge_unknown_paid_events'], true);
    },
  );

  test('review without acknowledgement never dispatches', () async {
    await transport.signIn();
    final input = SecurityMutation.reviewGrant(
      requestId: _request,
      branchId: _branch,
      grantId: _grant,
      reason: 'Lost key',
      acknowledgeUnknownPaidEvents: false,
      expectedLastSequence: 2,
      expectedOutcomeCount: 2,
      expectedTotalMinor: 113,
    );
    await expectLater(
      transport.repository().mutate(input),
      throwsA(_failure(RepositoryFailureType.validation)),
    );
    expect(transport.requests, isEmpty);
  });

  test(
    'revocation requires canonical revoked outcome on same device',
    () async {
      await transport.signIn();
      final input = SecurityMutation.revokeDevice(
        requestId: _request,
        branchId: _branch,
        deviceId: _device,
        reason: 'Lost terminal',
      );
      transport.payload = _deviceRow();
      await expectLater(
        transport.repository().mutate(input),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
      transport.payload = {
        ..._deviceRow(),
        'revoked_at': '2026-10-11T13:00:00Z',
        'revocation_reason': 'Lost terminal',
      };
      expect(
        (await transport.repository().mutate(input)).device!.revoked,
        true,
      );
    },
  );

  test('read acknowledgement matches the actual notice ID', () async {
    await transport.signIn();
    transport.payload = {'id': _other, 'read_at': '2026-10-11T13:00:00Z'};
    expect(
      await transport.repository().markNoticeRead(
        branchId: _branch,
        noticeId: _other,
      ),
      DateTime.utc(2026, 10, 11, 13),
    );
    expect(transport.body, {
      'p_organization_id': _org,
      'p_branch_id': _branch,
      'p_notification_id': _other,
    });
    transport.payload = {'id': _device, 'read_at': '2026-10-11T13:00:00Z'};
    await expectLater(
      transport.repository().markNoticeRead(
        branchId: _branch,
        noticeId: _other,
      ),
      throwsA(_failure(RepositoryFailureType.unavailable)),
    );
  });

  test(
    'notification supports org-wide notice but rejects other branch',
    () async {
      await transport.signIn();
      transport.payload = [_noticeRow()];
      final notice = (await transport.repository().listNotices(
        branchId: _branch,
      )).items.single;
      expect(notice.branchId, isNull);
      expect(notice.readAt, isNull);
      transport.payload = [
        {..._noticeRow(), 'branch_id': _other},
      ];
      await expectLater(
        transport.repository().listNotices(branchId: _branch),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
    },
  );

  test('delayed response is discarded after account replacement', () async {
    await transport.signIn();
    final response = Completer<http.Response>();
    final started = Completer<http.Request>();
    transport.handler = (request) {
      started.complete(request);
      return response.future;
    };
    final pending = transport.repository().loadPolicy();
    final request = await started.future;
    await transport.signIn(userId: _other);
    final expectation = expectLater(
      pending,
      throwsA(_failure(RepositoryFailureType.unauthenticated)),
    );
    response.complete(_Harness.response(_policy(), 200, request));
    await expectation;
  });

  test('decoder failures contain no backend message or key material', () {
    expect(
      () => securityDeviceFromRow(
        {..._deviceRow(), 'platform': 'PRIVATE'},
        organizationId: _org,
        branchId: _branch,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(() => securityRow({'secret': 'PRIVATE'}), returnsNormally);
    expect(() => securityRows({'secret': 'PRIVATE'}), throwsFormatException);
  });
}
