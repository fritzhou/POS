import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/app/theme/app_theme.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/security/domain/security_models.dart';
import 'package:nexapos/features/security/domain/security_repository.dart';
import 'package:nexapos/features/security/presentation/security_page.dart';

const _org = '11111111-1111-1111-1111-111111111111';
const _actor = '22222222-2222-2222-2222-222222222222';
const _branch = '44444444-4444-4444-4444-444444444444';
const _deviceId = '55555555-5555-5555-5555-555555555555';
const _grantId = '77777777-7777-7777-7777-777777777777';
const _noticeId = '99999999-9999-9999-9999-999999999999';
const _policy = SecurityPolicy(
  organizationId: _org,
  idleLockMinutes: 5,
  requirePrivilegedMfa: false,
  revision: 1,
);

SecurityDevice _device({bool canManage = true}) => SecurityDevice(
  deviceId: _deviceId,
  organizationId: _org,
  branchId: _branch,
  actorId: _actor,
  name: 'Till 1',
  platform: SecurityDevicePlatform.windows,
  enrolledAt: DateTime.utc(2026, 10, 11, 0),
  canManage: canManage,
);
SecurityOfflineGrant _grant({bool canReview = true}) => SecurityOfflineGrant(
  grantId: _grantId,
  organizationId: _org,
  branchId: _branch,
  deviceId: _deviceId,
  actorId: _actor,
  shiftId: '88888888-8888-8888-8888-888888888888',
  issuedAt: DateTime.utc(2026, 10, 11),
  expiresAt: DateTime.utc(2026, 10, 11, 8),
  lastSequence: 2,
  totalMinor: 113,
  maxEvents: 1000,
  maxTotalMinor: 100000000,
  outcomeCount: 2,
  reviewCount: 1,
  remainingExposureEvents: 998,
  remainingExposureMinor: 99999887,
  state: SecurityGrantState.expired,
  canReview: canReview,
  currency: 'PHP',
  blocksShiftClose: true,
);
SecurityNotice _notice({DateTime? readAt}) => SecurityNotice(
  id: _noticeId,
  organizationId: _org,
  branchId: _branch,
  action: 'security.device.revoked',
  title: 'Offline device revoked',
  message: 'An administrator revoked the enrolled offline device.',
  occurredAt: DateTime.utc(2026, 10, 11, 12),
  readAt: readAt,
);

class _Repository implements SecurityRepository {
  int loads = 0;
  SecurityPolicy policy = _policy;
  List<SecurityDevice> devices = [_device()];
  List<SecurityOfflineGrant> grants = [_grant()];
  List<SecurityNotice> notices = [_notice()];
  final devicePages = <PageRequest>[];
  final mutationCalls = <SecurityMutation>[];
  final markReadCalls = <String>[];
  List<SecurityMutation> pending = [];
  RepositoryFailure? failure;
  RepositoryFailure? mutationFailure;
  RepositoryFailure? readFailure;
  Completer<SecurityMutationResult>? mutationCompleter;

  @override
  String get organizationId => _org;
  @override
  Set<String> get branchIds => {_branch};
  @override
  Future<SecurityPolicy> loadPolicy() async {
    loads++;
    if (failure != null) throw failure!;
    return policy;
  }

  @override
  Future<List<SecurityMutation>> pendingMutations() async =>
      List.unmodifiable(pending);
  @override
  Future<DataPage<SecurityDevice>> listDevices({
    required String branchId,
    PageRequest page = const PageRequest(),
  }) async {
    devicePages.add(page);
    return DataPage(
      items: devices,
      hasMore: page.offset == 0 && devices.isNotEmpty,
      offset: page.offset,
    );
  }

  @override
  Future<DataPage<SecurityOfflineGrant>> listGrants({
    required String branchId,
    PageRequest page = const PageRequest(),
  }) async => DataPage(items: grants, hasMore: false, offset: page.offset);
  @override
  Future<DataPage<SecurityNotice>> listNotices({
    required String branchId,
    PageRequest page = const PageRequest(),
  }) async => DataPage(items: notices, hasMore: false, offset: page.offset);
  @override
  Future<DateTime> markNoticeRead({
    required String branchId,
    required String noticeId,
  }) async {
    markReadCalls.add(noticeId);
    if (readFailure != null) throw readFailure!;
    final time = DateTime.utc(2026, 10, 11, 13);
    notices = [_notice(readAt: time)];
    return time;
  }

  @override
  Future<SecurityMutationResult> mutate(SecurityMutation mutation) async {
    mutationCalls.add(mutation);
    pending = [mutation];
    if (mutationFailure != null) throw mutationFailure!;
    if (mutationCompleter != null) return mutationCompleter!.future;
    pending = [];
    if (mutation.kind == SecurityMutationKind.policy) {
      policy = SecurityPolicy(
        organizationId: _org,
        idleLockMinutes: mutation.idleLockMinutes!,
        requirePrivilegedMfa: mutation.requirePrivilegedMfa!,
        revision: mutation.expectedRevision! + 1,
      );
      return SecurityMutationResult(
        requestId: mutation.requestId,
        kind: mutation.kind,
        policy: policy,
      );
    }
    return SecurityMutationResult(
      requestId: mutation.requestId,
      kind: mutation.kind,
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Repository repository, {
  AppRole role = AppRole.owner,
  bool preview = false,
  SecurityPageSection section = SecurityPageSection.overview,
  Size size = const Size(850, 1000),
  ValueChanged<SecurityPolicy>? onPolicyChanged,
  List<Widget> extraSections = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SecurityPage(
          repository: repository,
          role: role,
          isPreview: preview,
          initialSection: section,
          onPolicyChanged: onPolicyChanged,
          extraSections: extraSections,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _reason(WidgetTester tester, String reason) async {
  final finder = find.byKey(const Key('security-mutation-reason'));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, reason);
}

void main() {
  testWidgets('preview loads no records and creates no fake inventory', (
    tester,
  ) async {
    final repo = _Repository();
    await _pump(tester, repo, preview: true);
    expect(repo.loads, 0);
    expect(find.text('Till 1'), findsNothing);
    expect(
      find.text('Security management requires a verified account'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('security-edit-policy')), findsNothing);
  });

  testWidgets('empty security sections describe actual inventory boundaries', (
    tester,
  ) async {
    final repo = _Repository()
      ..devices = []
      ..grants = []
      ..notices = [];
    await _pump(tester, repo, section: SecurityPageSection.devices);
    expect(find.text('No enrolled offline devices'), findsOneWidget);
    expect(
      find.textContaining('does not represent all Auth sessions'),
      findsOneWidget,
    );
    await _tap(tester, find.byKey(const Key('security-section-grants')));
    expect(find.text('No offline grants'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('security-section-notices')));
    expect(find.text('No security notices'), findsOneWidget);
    expect(find.textContaining('Email delivery'), findsOneWidget);
  });

  testWidgets('cashier views own inventory without device or policy changes', (
    tester,
  ) async {
    final repo = _Repository();
    await _pump(
      tester,
      repo,
      role: AppRole.cashier,
      section: SecurityPageSection.devices,
    );
    expect(find.text('Till 1'), findsOneWidget);
    expect(find.text('Revoke device'), findsNothing);
    expect(find.text('Rename device'), findsNothing);
    await _tap(tester, find.byKey(const Key('security-section-overview')));
    expect(find.text('Idle lock: 5 minutes'), findsOneWidget);
    expect(find.byKey(const Key('security-edit-policy')), findsNothing);
    expect(repo.mutationCalls, isEmpty);
  });

  testWidgets('server capabilities control owner device and grant actions', (
    tester,
  ) async {
    final repo = _Repository()
      ..devices = [_device(canManage: false)]
      ..grants = [_grant(canReview: false)];
    await _pump(tester, repo, section: SecurityPageSection.devices);
    expect(find.text('Till 1'), findsOneWidget);
    expect(find.text('Revoke device'), findsNothing);
    await _tap(tester, find.byKey(const Key('security-section-grants')));
    expect(find.text('Review lost-key grant'), findsNothing);
    expect(find.textContaining('Blocks normal shift closure'), findsOneWidget);
  });

  testWidgets(
    'policy inputs validate before dispatch and server confirmation',
    (tester) async {
      final repo = _Repository()..mutationCompleter = Completer();
      SecurityPolicy? applied;
      await _pump(tester, repo, onPolicyChanged: (value) => applied = value);
      await _tap(tester, find.byKey(const Key('security-edit-policy')));
      await tester.enterText(
        find.byKey(const Key('security-mutation-value')),
        '61',
      );
      await _reason(tester, 'Protect workspace');
      await _tap(tester, find.byKey(const Key('security-confirm-mutation')));
      expect(repo.mutationCalls, isEmpty);
      expect(find.text('Enter 1 to 60 minutes.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('security-mutation-value')),
        '7',
      );
      await tester.tap(find.byKey(const Key('security-confirm-mutation')));
      await tester.pump();
      expect(repo.mutationCalls.single.idleLockMinutes, 7);
      expect(repo.mutationCalls.single.expectedRevision, 1);
      expect(applied, isNull);
      expect(find.text('Security policy saved by the server.'), findsNothing);
      repo.policy = const SecurityPolicy(
        organizationId: _org,
        idleLockMinutes: 7,
        requirePrivilegedMfa: false,
        revision: 2,
      );
      repo.pending = [];
      repo.mutationCompleter!.complete(
        SecurityMutationResult(
          requestId: repo.mutationCalls.single.requestId,
          kind: SecurityMutationKind.policy,
          policy: repo.policy,
        ),
      );
      await tester.pumpAndSettle();
      expect(applied?.idleLockMinutes, 7);
      expect(find.text('Security policy saved by the server.'), findsOneWidget);
      expect(find.text('Saved revision 2'), findsOneWidget);
    },
  );

  testWidgets('lost response retains exact request for explicit retry', (
    tester,
  ) async {
    final repo = _Repository()
      ..mutationFailure = const RepositoryFailure(
        RepositoryFailureType.unavailable,
        'The original request remains unconfirmed.',
      );
    await _pump(tester, repo, section: SecurityPageSection.devices);
    await _tap(tester, find.text('Rename device'));
    await tester.enterText(
      find.byKey(const Key('security-mutation-value')),
      'Front counter',
    );
    await _reason(tester, 'Till relocated');
    await _tap(tester, find.byKey(const Key('security-confirm-mutation')));
    expect(repo.mutationCalls.length, 1);
    final original = repo.mutationCalls.single;
    expect(find.text('Device name saved by the server.'), findsNothing);
    expect(find.text('Unconfirmed security requests'), findsOneWidget);
    repo.mutationFailure = null;
    await _tap(tester, find.byKey(Key('security-retry-${original.requestId}')));
    expect(repo.mutationCalls.length, 2);
    expect(identical(repo.mutationCalls.last, original), true);
    expect(find.text('Device name saved by the server.'), findsOneWidget);
  });

  testWidgets('startup presents durable original request without dispatch', (
    tester,
  ) async {
    final pending = SecurityMutation.revokeDevice(
      requestId: '66666666-6666-6666-6666-666666666666',
      branchId: _branch,
      deviceId: _deviceId,
      reason: 'Lost terminal',
    );
    final repo = _Repository()..pending = [pending];
    await _pump(tester, repo, section: SecurityPageSection.devices);
    expect(repo.mutationCalls, isEmpty);
    expect(find.text('Unconfirmed security requests'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Revoke device'),
          )
          .onPressed,
      isNull,
    );
    await _tap(tester, find.byKey(Key('security-retry-${pending.requestId}')));
    expect(repo.mutationCalls.single, same(pending));
  });

  testWidgets(
    'lost-key review requires reason and explicit payment risk acknowledgement',
    (tester) async {
      final repo = _Repository();
      await _pump(tester, repo, section: SecurityPageSection.grants);
      await _tap(tester, find.byKey(const Key('security-review-$_grantId')));
      expect(
        find.textContaining('Unknown sales may already have been paid'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('security-confirm-mutation')),
            )
            .onPressed,
        isNull,
      );
      await _reason(
        tester,
        'Recovered receipt export before lost-key resolution',
      );
      await _tap(tester, find.byKey(const Key('security-acknowledge-risk')));
      await _tap(tester, find.byKey(const Key('security-confirm-mutation')));
      final call = repo.mutationCalls.single;
      expect(call.acknowledgeUnknownPaidEvents, true);
      expect(call.expectedOutcomeCount, 2);
      expect(call.expectedLastSequence, 2);
      expect(call.expectedTotalMinor, 113);
      expect(find.textContaining('Unknown paid events remain'), findsOneWidget);
    },
  );

  testWidgets('cancelled revocation never dispatches', (tester) async {
    final repo = _Repository();
    await _pump(tester, repo, section: SecurityPageSection.devices);
    await _tap(tester, find.text('Revoke device'));
    expect(find.textContaining('already disconnected device'), findsOneWidget);
    await _tap(tester, find.widgetWithText(TextButton, 'Cancel'));
    expect(repo.mutationCalls, isEmpty);
  });

  testWidgets('security notices mark read only after source response', (
    tester,
  ) async {
    final repo = _Repository();
    await _pump(tester, repo, section: SecurityPageSection.notices);
    expect(find.text('Offline device revoked'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('security-read-$_noticeId')));
    expect(repo.markReadCalls, [_noticeId]);
    expect(find.byKey(const Key('security-read-$_noticeId')), findsNothing);
    expect(find.textContaining('· Read'), findsOneWidget);
  });

  testWidgets('revoked notice access clears source data immediately', (
    tester,
  ) async {
    final repo = _Repository()
      ..readFailure = const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Current access is no longer available.',
      );
    await _pump(tester, repo, section: SecurityPageSection.notices);
    await _tap(tester, find.byKey(const Key('security-read-$_noticeId')));
    expect(find.text('Offline device revoked'), findsNothing);
    expect(find.text('Current access is no longer available.'), findsOneWidget);
  });

  testWidgets(
    'reload denial clears visible inventory rather than retaining stale authorization',
    (tester) async {
      final repo = _Repository();
      await _pump(tester, repo, section: SecurityPageSection.devices);
      expect(find.text('Till 1'), findsOneWidget);
      repo.failure = const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Current access is no longer available.',
      );
      await _tap(tester, find.byKey(const Key('security-reload')));
      expect(find.text('Till 1'), findsNothing);
      expect(
        find.text('Current access is no longer available.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('device paging is bounded by source offset and exact row count', (
    tester,
  ) async {
    final repo = _Repository();
    await _pump(tester, repo, section: SecurityPageSection.devices);
    await _tap(tester, find.byKey(const Key('security-next')));
    expect(repo.devicePages.map((page) => page.offset), [0, 1]);
    expect(repo.devicePages.every((page) => page.limit == 20), true);
  });

  testWidgets(
    'membership replacement while confirmation is open prevents old write',
    (tester) async {
      final first = _Repository();
      final second = _Repository();
      await _pump(tester, first);
      await _tap(tester, find.byKey(const Key('security-edit-policy')));
      await _reason(tester, 'Previous business reason');
      await _pump(tester, second);
      await _tap(tester, find.byKey(const Key('security-confirm-mutation')));
      expect(first.mutationCalls, isEmpty);
      expect(second.mutationCalls, isEmpty);
    },
  );

  testWidgets(
    'source sections and irreversible review remain usable at 320px',
    (tester) async {
      final repo = _Repository();
      await _pump(
        tester,
        repo,
        section: SecurityPageSection.grants,
        size: const Size(320, 640),
      );
      await _tap(tester, find.byKey(const Key('security-review-$_grantId')));
      await _reason(tester, 'Preserve recovered records');
      await _tap(tester, find.byKey(const Key('security-acknowledge-risk')));
      expect(tester.takeException(), isNull);
      await _tap(tester, find.widgetWithText(TextButton, 'Cancel'));
      await tester.scrollUntilVisible(
        find.byKey(const Key('security-section-devices')),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await _tap(tester, find.byKey(const Key('security-section-devices')));
      await _tap(tester, find.text('Revoke device'));
      expect(tester.takeException(), isNull);
      await _tap(tester, find.widgetWithText(TextButton, 'Cancel'));
      await _tap(tester, find.byKey(const Key('security-section-notices')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account capability sections render only with loaded current policy',
    (tester) async {
      final repo = _Repository();
      await _pump(
        tester,
        repo,
        extraSections: [const Text('Real account security section')],
      );
      expect(find.text('Real account security section'), findsOneWidget);
      repo.failure = const RepositoryFailure(
        RepositoryFailureType.unavailable,
        'Policy unavailable.',
      );
      await _tap(tester, find.byKey(const Key('security-reload')));
      expect(find.text('Real account security section'), findsNothing);
    },
  );
}
