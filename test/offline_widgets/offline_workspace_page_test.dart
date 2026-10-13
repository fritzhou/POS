import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/app/theme/app_theme.dart';
import 'package:nexapos/core/database/database_scope.dart';
import 'package:nexapos/core/database/sale_draft.dart';
import 'package:nexapos/core/sync/outbox_state.dart';
import 'package:nexapos/features/administration/domain/administration_models.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';
import 'package:nexapos/features/offline/domain/offline_workspace.dart';
import 'package:nexapos/features/offline/presentation/offline_workspace_page.dart';
import 'package:nexapos/features/people/domain/people_repository.dart';

const organization = '00000000-0000-4000-8000-000000000001';
const branch = '00000000-0000-4000-8000-000000000002';
const productId = '00000000-0000-4000-8000-000000000003';
const eventId = '00000000-0000-4000-8000-000000000004';
const actor = '00000000-0000-4000-8000-000000000005';
const shiftId = '00000000-0000-4000-8000-000000000006';
const product = PosProduct(
  id: productId,
  organizationId: organization,
  name: 'Fixture product',
  sku: 'FIXTURE-SKU',
  priceMinor: 1001,
  currency: 'PHP',
  unit: 'each',
  revision: 4,
  availableQuantity: 3,
  barcode: '0123456789012',
);

class FixturePeople implements PeopleRepository {
  int branchReads = 0;
  @override
  Future<List<BranchOption>> listBranches() async {
    branchReads++;
    return const [
      BranchOption(id: branch, name: 'Fixture branch', code: 'FIXTURE'),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FixtureWorkspace implements OfflineWorkspace {
  bool configured = true, active = true, prepared = true, released = false;
  bool expired = false,
      failWrite = false,
      wrongReceipt = false,
      failSync = false,
      loseWriteResponse = false,
      requireExplicitEntry = false;
  bool blocked = false, failPrepare = false, failEnter = false;
  int maxEvents = 1000, eventCount = 0, maxTotalMinor = 100000000;
  DateTime? estimatedServerTime;
  Completer<OfflineWorkspaceStatus>? delayedPreparation;
  final calls = <OfflineCheckoutRequest>[];
  final intents = <OfflineCheckoutRequest>[];
  final receipts = <LocalOfflineReceipt>[];
  final barcodes = <String>[];
  final searches = <String>[];
  final preparedBranches = <String>[];
  final retries = <String>[];
  final selectedBranches = <String?>[];
  int syncCalls = 0, suspendCalls = 0, leaveCalls = 0, exportCalls = 0;
  final snapshotTime = DateTime.utc(2026, 10, 10, 1);
  final syncTime = DateTime.utc(2026, 10, 10, 2);

  OfflineWorkspaceStatus get current => OfflineWorkspaceStatus(
    configured: configured,
    active: active,
    pendingCount: receipts
        .where(
          (receipt) =>
              receipt.status != OutboxStatus.synced &&
              receipt.status != OutboxStatus.failed,
        )
        .length,
    failedCount: receipts
        .where((receipt) => receipt.status == OutboxStatus.failed)
        .length,
    branchId: prepared ? branch : null,
    branchName: prepared ? 'Fixture branch' : null,
    grantId: prepared ? 'fixture-grant' : null,
    expiresAt: prepared
        ? expired
              ? DateTime.utc(2000)
              : DateTime.utc(2100)
        : null,
    snapshotAt: prepared ? snapshotTime : null,
    lastSyncAt: prepared ? syncTime : null,
    unresolvedPaymentCount: intents.length,
    eventCount: eventCount,
    maxEvents: maxEvents,
    maxTotalMinor: maxTotalMinor,
    estimatedServerTime: estimatedServerTime,
    released: released,
    blockedReason: blocked ? 'authorization_unavailable' : null,
  );

  @override
  Future<OfflineWorkspaceStatus> status({String? branchId}) async {
    selectedBranches.add(branchId);
    return current;
  }

  @override
  Future<OfflineWorkspaceStatus> prepareOnline(String branchId) async {
    preparedBranches.add(branchId);
    if (delayedPreparation != null) return delayedPreparation!.future;
    if (failPrepare) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Offline preparation requires remembered-device consent.',
      );
    }
    prepared = true;
    return current;
  }

  @override
  Future<OfflineWorkspaceStatus> enterOffline(String branchId) async {
    if (failEnter) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Reconcile the uncertain online checkout first.',
      );
    }
    active = true;
    return current;
  }

  @override
  Future<void> leaveOffline() async {
    leaveCalls++;
    active = false;
  }

  @override
  Future<void> suspend() async {
    suspendCalls++;
    active = false;
  }

  @override
  Future<PosContext> context() async => const PosContext(
    branchId: branch,
    branchName: 'Fixture branch',
    businessName: 'Fixture business',
    currency: 'PHP',
    taxBps: 1200,
    settingsRevision: 7,
  );
  @override
  Future<List<OfflineCategory>> categories() async => const [];
  @override
  Future<Shift?> currentShift() async => Shift(
    id: shiftId,
    organizationId: organization,
    branchId: branch,
    actorUserId: actor,
    openedAt: snapshotTime,
    openingCashMinor: 0,
    expectedCashMinor: 0,
    currency: 'PHP',
  );
  @override
  Future<DataPage<PosProduct>> searchProducts({
    String query = '',
    String? categoryId,
    PageRequest page = const PageRequest(),
  }) async {
    searches.add(query);
    return DataPage(
      items:
          query.isEmpty ||
              product.name.toLowerCase().contains(query.toLowerCase())
          ? [product]
          : [],
      hasMore: false,
      offset: page.offset,
    );
  }

  @override
  Future<PosProduct?> lookupProductByBarcode(String barcode) async {
    barcodes.add(barcode);
    return product.barcode == barcode ? product : null;
  }

  @override
  Future<void> recordPaymentFragment({
    required String requestId,
    required List<CartLine> lines,
    required int index,
    required CheckoutPayment payment,
  }) async {
    final prior = intents
        .where((intent) => intent.requestId == requestId)
        .firstOrNull;
    final payments = [...?prior?.payments];
    if (index == payments.length) payments.add(payment);
    intents.removeWhere((intent) => intent.requestId == requestId);
    intents.add(
      OfflineCheckoutRequest(
        requestId: requestId,
        lines: lines,
        payments: payments,
        expectedTotalMinor: CartTotals.calculate(
          lines: lines,
          taxBps: 1200,
        ).totalMinor,
      ),
    );
  }

  @override
  Future<LocalOfflineReceipt> checkout(OfflineCheckoutRequest request) async {
    calls.add(request);
    if (receipts.any((receipt) => receipt.draft.eventId == request.requestId)) {
      return receipts.firstWhere(
        (receipt) => receipt.draft.eventId == request.requestId,
      );
    }
    if (!intents.any((intent) => intent.requestId == request.requestId)) {
      intents.add(request);
    }
    if (requireExplicitEntry && !active) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Enter the prepared offline workspace explicitly before selling.',
      );
    }
    if (expired) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Grant expired after tender confirmation. Preserved payment evidence needs review.',
      );
    }
    if (failWrite) {
      throw StateError('sensitive backend failure must never be displayed');
    }
    final receipt = createReceipt(request, wrongId: wrongReceipt);
    receipts.add(receipt);
    intents.removeWhere((intent) => intent.requestId == request.requestId);
    eventCount++;
    if (loseWriteResponse) {
      throw StateError('local commit succeeded but its response was lost');
    }
    return receipt;
  }

  @override
  Future<List<OfflineCheckoutRequest>> pendingPaymentIntents({
    String? branchId,
  }) async => [...intents];
  @override
  Future<List<LocalOfflineReceipt>> listReceipts({String? branchId}) async => [
    ...receipts,
  ];
  @override
  Future<String> exportReceipt(String eventId) async {
    exportCalls++;
    return '{"original_event_id":"$eventId"}';
  }

  @override
  Future<OfflineSyncSummary> synchronize(String branchId) async {
    syncCalls++;
    if (failSync) throw StateError('invalid receipt private details');
    return const OfflineSyncSummary(
      accepted: 0,
      failed: 0,
      remaining: 1,
      pulled: 0,
      stoppedReason: 'unavailable',
    );
  }

  @override
  Future<bool> retryFailed({
    required String branchId,
    required String eventId,
  }) async {
    retries.add(eventId);
    return false;
  }

  @override
  Future<OfflineWorkspaceStatus> releaseGrant(String branchId) async {
    released = true;
    active = false;
    return current;
  }
}

LocalOfflineReceipt createReceipt(
  OfflineCheckoutRequest request, {
  bool wrongId = false,
  OutboxStatus status = OutboxStatus.pending,
  String? reconciliationCode,
  String? serverReceiptId,
}) {
  final totals = CartTotals.calculate(lines: request.lines, taxBps: 1200);
  return LocalOfflineReceipt(
    draft: SaleDraft(
      id: request.requestId,
      eventId: wrongId ? eventId : request.requestId,
      scope: DatabaseScope(organizationId: organization, branchId: branch),
      deviceId: 'fixture-device',
      shiftId: shiftId,
      cashierId: actor,
      receiptNumber: 'OFFLINE-FIXTURE-1',
      currency: 'PHP',
      createdAt: DateTime.utc(2026, 10, 10, 3),
      items: totals.lines
          .map(
            (line) => SaleLineDraft(
              id: '${line.line.product.id}-line',
              productId: line.line.product.id,
              sku: line.line.product.sku,
              name: line.line.product.name,
              quantity: line.line.quantity,
              unitPriceMinor: line.line.product.priceMinor,
              taxMinor: line.taxMinor,
            ),
          )
          .toList(),
      payments: [
        for (var i = 0; i < request.payments.length; i++)
          SalePaymentDraft(
            id: 'fixture-payment-$i',
            method: request.payments[i].method.name,
            amountMinor: request.payments[i].amountMinor,
            reference: request.payments[i].reference,
          ),
      ],
    ),
    status: status,
    sequence: 1,
    grantId: 'fixture-grant',
    businessName: 'Fixture business',
    branchName: 'Fixture branch',
    reconciliationCode: reconciliationCode,
    serverReceiptId: serverReceiptId,
  );
}

OfflineCheckoutRequest pendingRequest() => OfflineCheckoutRequest(
  requestId: eventId,
  lines: const [CartLine(product: product, quantity: 1)],
  payments: const [
    CheckoutPayment(
      method: CheckoutPaymentMethod.cash,
      amountMinor: 1121,
      tenderedMinor: 1200,
    ),
  ],
);

Future<void> mount(
  WidgetTester tester,
  FixtureWorkspace workspace, {
  FixturePeople? people,
  double width = 1100,
  VoidCallback? onLock,
  String? initialBranchId,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: OfflineWorkspacePage(
        workspace: workspace,
        initialBranchId: initialBranchId,
        peopleRepository: people,
        onLock: onLock,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> tender(WidgetTester tester, {VoidCallback? beforeSave}) async {
  await tap(tester, find.byKey(const Key('offline-checkout')));
  expect(find.text('Save provisional receipt'), findsOneWidget);
  expect(find.textContaining('only after the server confirms'), findsNothing);
  await tester.enterText(find.byKey(const Key('cash-received')), '12.00');
  await tap(tester, find.byKey(const Key('payment-confirmed')));
  await tap(tester, find.byKey(const Key('add-payment')));
  beforeSave?.call();
  await tap(tester, find.byKey(const Key('submit-payment')));
}

void main() {
  testWidgets('requires configured signing, displays no fabricated catalog', (
    tester,
  ) async {
    final workspace = FixtureWorkspace()
      ..configured = false
      ..active = false
      ..prepared = false;
    await mount(tester, workspace);
    expect(find.text('Offline signing · Not Yet Connected'), findsOneWidget);
    expect(find.text(product.name), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('prepare-offline')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('explicit branch preparation precedes explicit offline entry', (
    tester,
  ) async {
    final workspace = FixtureWorkspace()
      ..active = false
      ..prepared = false;
    final people = FixturePeople();
    await mount(tester, workspace, people: people);
    expect(workspace.preparedBranches, isEmpty);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('prepare-offline')))
          .onPressed,
      isNull,
    );
    await tap(tester, find.byKey(const Key('offline-branch')));
    await tap(tester, find.text('Fixture branch').last);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('prepare-offline')))
          .onPressed,
      isNull,
    );
    await tap(tester, find.byKey(const Key('offline-device-consent')));
    await tap(tester, find.byKey(const Key('prepare-offline')));
    expect(workspace.preparedBranches, [branch]);
    expect(workspace.active, isFalse);
    await tap(tester, find.byKey(const Key('enter-offline')));
    expect(workspace.active, isTrue);
    expect(find.text(product.name), findsOneWidget);
    expect(people.branchReads, 1);
  });

  testWidgets('uncertain online checkout prevents explicit entry', (
    tester,
  ) async {
    final workspace = FixtureWorkspace()
      ..active = false
      ..failEnter = true;
    await mount(tester, workspace);
    await tap(tester, find.byKey(const Key('enter-offline')));
    expect(
      find.text('Reconcile the uncertain online checkout first.'),
      findsOneWidget,
    );
    expect(find.text(product.name), findsNothing);
    expect(workspace.calls, isEmpty);
  });

  testWidgets('blocked recovery or authority state never permits payment', (
    tester,
  ) async {
    final workspace = FixtureWorkspace()..blocked = true;
    await mount(tester, workspace);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('offline-add-$productId')))
          .onPressed,
      isNull,
    );
    expect(workspace.calls, isEmpty);
  });

  testWidgets(
    'cached age, pending state and open-online shift remain explicit',
    (tester) async {
      final workspace = FixtureWorkspace()
        ..receipts.add(createReceipt(pendingRequest()));
      await mount(tester, workspace);
      expect(find.text('Pending: 1 · Failed: 0'), findsOneWidget);
      expect(find.textContaining('Last successful sync:'), findsOneWidget);
      expect(
        find.textContaining('Cached shift opened online:'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Projected quantity 3 · uncertain'),
        findsOneWidget,
      );
      expect(find.text('Employees'), findsNothing);
      expect(find.text('Refund'), findsNothing);
    },
  );

  testWidgets('exact barcode and cached search do not invent products', (
    tester,
  ) async {
    final workspace = FixtureWorkspace();
    await mount(tester, workspace);
    await tester.enterText(
      find.byKey(const Key('offline-product-search')),
      'missing',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('No cached products match.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('offline-barcode')), '0123');
    await tap(tester, find.byTooltip('Look up exact barcode'));
    expect(find.textContaining('that exact barcode'), findsOneWidget);
    expect(workspace.barcodes, ['0123']);
    await tester.enterText(
      find.byKey(const Key('offline-barcode')),
      product.barcode!,
    );
    await tap(tester, find.byTooltip('Look up exact barcode'));
    expect(find.text('Total PHP 11.21'), findsOneWidget);
  });

  testWidgets(
    'counted cash creates provisional local receipt and keeps original identity',
    (tester) async {
      final workspace = FixtureWorkspace();
      await mount(tester, workspace);
      await tap(tester, find.byKey(const Key('offline-add-$productId')));
      expect(find.text('Total PHP 11.21'), findsOneWidget);
      await tender(tester);
      expect(find.text('Provisional offline receipt'), findsOneWidget);
      expect(find.text('PENDING · stored on this device'), findsOneWidget);
      expect(workspace.calls.single.payments.single.tenderedMinor, 1200);
      expect(
        workspace.receipts.single.draft.eventId,
        workspace.calls.single.requestId,
      );
      expect(workspace.receipts.single.draft.taxMinor, 120);
    },
  );

  testWidgets(
    'unknown local write freezes tender and retries identical request',
    (tester) async {
      final workspace = FixtureWorkspace()..failWrite = true;
      await mount(tester, workspace);
      await tap(tester, find.byKey(const Key('offline-add-$productId')));
      await tender(tester);
      expect(find.text('Local checkout needs reconciliation'), findsOneWidget);
      expect(find.textContaining('sensitive backend failure'), findsNothing);
      final original = workspace.calls.single;
      workspace.failWrite = false;
      await tap(tester, find.byKey(const Key('retry-local-checkout')));
      expect(workspace.calls.length, 2);
      expect(identical(workspace.calls[0], workspace.calls[1]), isTrue);
      expect(workspace.receipts.single.draft.eventId, original.requestId);
    },
  );

  testWidgets('wrong local receipt response leaves original intent frozen', (
    tester,
  ) async {
    final workspace = FixtureWorkspace()..wrongReceipt = true;
    await mount(tester, workspace);
    await tap(tester, find.byKey(const Key('offline-add-$productId')));
    await tender(tester);
    expect(find.text('Local checkout needs reconciliation'), findsOneWidget);
    expect(find.text('Provisional offline receipt'), findsNothing);
  });

  testWidgets('grant expiry before payment blocks new capture', (tester) async {
    final workspace = FixtureWorkspace();
    await mount(tester, workspace);
    await tap(tester, find.byKey(const Key('offline-add-$productId')));
    workspace.expired = true;
    await tap(tester, find.byKey(const Key('offline-checkout')));
    expect(find.textContaining('Do not collect payment'), findsOneWidget);
    expect(find.text('Record payment'), findsNothing);
    expect(workspace.calls, isEmpty);
  });

  testWidgets(
    'expiry during payment preserves durable evidence for manual review',
    (tester) async {
      final workspace = FixtureWorkspace();
      await mount(tester, workspace);
      await tap(tester, find.byKey(const Key('offline-add-$productId')));
      await tender(tester, beforeSave: () => workspace.expired = true);
      expect(
        workspace.intents.single.requestId,
        workspace.calls.single.requestId,
      );
      expect(find.text('Local checkout needs reconciliation'), findsOneWidget);
      expect(find.text('Provisional offline receipt'), findsNothing);
    },
  );

  testWidgets(
    'restored paid intent survives restart and still allows locking',
    (tester) async {
      final workspace = FixtureWorkspace()
        ..expired = true
        ..intents.add(pendingRequest());
      var locked = false;
      await mount(tester, workspace, onLock: () => locked = true);
      expect(find.text('Local checkout needs reconciliation'), findsOneWidget);
      expect(find.text(eventId), findsOneWidget);
      await tap(tester, find.byTooltip('Lock offline workspace'));
      expect(locked, isTrue);
      expect(workspace.intents.single.requestId, eventId);
    },
  );

  testWidgets(
    'grant amount allowance prevents collecting unsupported payment',
    (tester) async {
      final workspace = FixtureWorkspace()..maxTotalMinor = 1000;
      await mount(tester, workspace);
      await tap(tester, find.byKey(const Key('offline-add-$productId')));
      await tap(tester, find.byKey(const Key('offline-checkout')));
      expect(find.textContaining('remaining grant allowance'), findsOneWidget);
      expect(find.text('Record payment'), findsNothing);
    },
  );

  testWidgets(
    'unvalidated sync failure preserves pending original and sanitizes errors',
    (tester) async {
      final workspace = FixtureWorkspace()
        ..failSync = true
        ..receipts.add(createReceipt(pendingRequest()));
      await mount(tester, workspace);
      await tap(tester, find.text('Sync'));
      await tap(tester, find.byKey(const Key('synchronize-offline')));
      expect(workspace.receipts.single.status, OutboxStatus.pending);
      expect(find.textContaining('private details'), findsNothing);
      expect(find.text('Pending: 1 · Failed: 0'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('release-offline-grant')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'failed immutable paid event displays manual review and original export',
    (tester) async {
      final workspace = FixtureWorkspace()
        ..receipts.add(
          createReceipt(pendingRequest(), status: OutboxStatus.failed),
        );
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester, workspace);
      await tap(tester, find.text('Receipts'));
      await tap(tester, find.text('OFFLINE-FIXTURE-1'));
      await tap(tester, find.byKey(const Key('export-offline-receipt')));
      expect(copied, contains(eventId));
      expect(workspace.exportCalls, 1);
      expect(workspace.receipts.single.status, OutboxStatus.failed);
    },
  );

  testWidgets('explicit resume branch stays inactive until entry', (
    tester,
  ) async {
    final workspace = FixtureWorkspace()..active = false;
    final people = FixturePeople();
    await mount(tester, workspace, people: people, initialBranchId: branch);
    expect(workspace.selectedBranches.first, branch);
    expect(people.branchReads, 0);
    expect(workspace.active, isFalse);
    expect(find.text(product.name), findsNothing);
    await tap(tester, find.byKey(const Key('enter-offline')));
    expect(workspace.active, isTrue);
    expect(find.text(product.name), findsOneWidget);
  });

  testWidgets(
    'restored intent permits explicit entry and retries without another tender',
    (tester) async {
      final workspace = FixtureWorkspace()
        ..active = false
        ..requireExplicitEntry = true
        ..intents.add(pendingRequest());
      await mount(tester, workspace, initialBranchId: branch);
      expect(workspace.active, isFalse);
      await tap(tester, find.byKey(const Key('enter-offline')));
      expect(workspace.active, isTrue);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('offline-checkout')))
            .onPressed,
        isNull,
      );
      await tap(tester, find.byKey(const Key('retry-local-checkout')));
      expect(workspace.calls.single.requestId, eventId);
      expect(workspace.calls.single.payments.single.tenderedMinor, 1200);
      expect(workspace.intents, isEmpty);
      expect(workspace.receipts, hasLength(1));
      expect(find.text('Record payment'), findsNothing);
      expect(find.text('Provisional offline receipt'), findsOneWidget);
    },
  );

  testWidgets(
    'lost committed response retries its original receipt after expiry',
    (tester) async {
      final workspace = FixtureWorkspace()..loseWriteResponse = true;
      await mount(tester, workspace);
      await tap(tester, find.byKey(const Key('offline-add-$productId')));
      await tender(tester);
      final originalId = workspace.calls.single.requestId;
      expect(workspace.receipts, hasLength(1));
      expect(find.text('Local checkout needs reconciliation'), findsOneWidget);
      workspace.expired = true;
      await tap(tester, find.byKey(const Key('retry-local-checkout')));
      expect(workspace.calls.map((request) => request.requestId), [
        originalId,
        originalId,
      ]);
      expect(workspace.receipts, hasLength(1));
      expect(workspace.eventCount, 1);
      expect(find.text('Provisional offline receipt'), findsOneWidget);
    },
  );

  testWidgets('server anchored time prevents raw device offset expiry', (
    tester,
  ) async {
    final workspace = FixtureWorkspace()
      ..expired = true
      ..estimatedServerTime = DateTime.utc(1999);
    await mount(tester, workspace);
    expect(
      find.text('Authorization expired · new sales blocked'),
      findsNothing,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('offline-add-$productId')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('event allowance blocks new cart and collection', (tester) async {
    final workspace = FixtureWorkspace()
      ..maxEvents = 2
      ..eventCount = 2;
    await mount(tester, workspace);
    expect(find.text('Grant usage: 2/2 sales'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('offline-add-$productId')))
          .onPressed,
      isNull,
    );
    expect(workspace.calls, isEmpty);
  });

  testWidgets(
    'unresolved intent allows original event sync and blocks release',
    (tester) async {
      final workspace = FixtureWorkspace()
        ..intents.add(pendingRequest())
        ..receipts.add(createReceipt(pendingRequest()));
      await mount(tester, workspace);
      await tap(tester, find.text('Sync'));
      await tap(tester, find.byKey(const Key('synchronize-offline')));
      expect(workspace.syncCalls, 1);
      expect(workspace.intents.single.requestId, eventId);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('release-offline-grant')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('replacing scope ignores the previous prepare response', (
    tester,
  ) async {
    final oldWorkspace = FixtureWorkspace()
      ..active = false
      ..delayedPreparation = Completer<OfflineWorkspaceStatus>();
    await mount(tester, oldWorkspace, initialBranchId: branch);
    await tap(tester, find.byKey(const Key('offline-device-consent')));
    await tap(tester, find.byKey(const Key('prepare-offline')));
    final newWorkspace = FixtureWorkspace()
      ..configured = false
      ..active = false
      ..prepared = false;
    await mount(tester, newWorkspace);
    oldWorkspace.delayedPreparation!.complete(oldWorkspace.current);
    await tester.pumpAndSettle();
    expect(find.text('Offline signing · Not Yet Connected'), findsOneWidget);
    expect(
      find.textContaining('Signed authorization and a complete'),
      findsNothing,
    );
    expect(find.text(product.name), findsNothing);
  });

  testWidgets(
    'manual digital tender requires actual verification and reference',
    (tester) async {
      final workspace = FixtureWorkspace();
      await mount(tester, workspace, width: 320);
      await tap(tester, find.byKey(const Key('offline-add-$productId')));
      await tap(tester, find.byKey(const Key('offline-checkout')));
      await tap(tester, find.byKey(const Key('payment-method')));
      await tap(tester, find.text('GCash').last);
      await tap(tester, find.byKey(const Key('add-payment')));
      expect(workspace.calls, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('submit-payment')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const Key('payment-reference')),
        ' ACTUAL-REFERENCE-123 ',
      );
      await tap(tester, find.byKey(const Key('payment-confirmed')));
      await tap(tester, find.byKey(const Key('add-payment')));
      expect(
        find.textContaining('Manual Payment Verification'),
        findsOneWidget,
      );
      await tap(tester, find.byKey(const Key('submit-payment')));
      expect(workspace.calls.single.payments.single.manualConfirmed, isTrue);
      expect(
        workspace.calls.single.payments.single.reference,
        'ACTUAL-REFERENCE-123',
      );
      expect(workspace.calls.single.payments.single.tenderedMinor, isNull);
      expect(
        find.textContaining('no provider API approval is claimed'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('320px accepted stock conflict preserves original and exports', (
    tester,
  ) async {
    final request = pendingRequest();
    final receipt = createReceipt(
      request,
      status: OutboxStatus.synced,
      reconciliationCode: 'STOCK_DEFICIT',
      serverReceiptId: 'server-authoritative-receipt',
    );
    final workspace = FixtureWorkspace()..receipts.add(receipt);
    await mount(tester, workspace, width: 320);
    await tap(tester, find.text('Sync'));
    expect(find.text('SYNCED · stock reconciliation required'), findsOneWidget);
    await tap(tester, find.text('Review and copy original record'));
    expect(find.text('Provisional offline receipt'), findsOneWidget);
    expect(
      find.textContaining('Do not collect another payment'),
      findsOneWidget,
    );
    await tap(tester, find.byKey(const Key('export-offline-receipt')));
    expect(workspace.exportCalls, 1);
    expect(identical(workspace.receipts.single, receipt), isTrue);
    expect(workspace.receipts.single.draft.eventId, request.requestId);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '320px cached workspace and provisional tender are usable without overflow',
    (tester) async {
      final workspace = FixtureWorkspace();
      await mount(tester, workspace, width: 320);
      expect(tester.takeException(), isNull);
      await tap(tester, find.byKey(const Key('offline-add-$productId')));
      await tender(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Provisional offline receipt'), findsOneWidget);
    },
  );

  testWidgets(
    'cancelled partial tender restores original order and collects only remaining amount',
    (tester) async {
      final workspace = FixtureWorkspace();
      await mount(tester, workspace);
      await tap(tester, find.byKey(const Key('offline-add-$productId')));
      await tap(tester, find.byKey(const Key('offline-checkout')));
      await tester.enterText(
        find.byKey(const Key('payment-applied-amount')),
        '6.00',
      );
      await tester.enterText(find.byKey(const Key('cash-received')), '6.00');
      await tap(tester, find.byKey(const Key('payment-confirmed')));
      await tap(tester, find.byKey(const Key('add-payment')));
      final originalId = workspace.intents.single.requestId;
      expect(workspace.intents.single.partial, isTrue);
      await tap(tester, find.text('Cancel'));
      expect(find.text('Continue remaining payment'), findsOneWidget);
      expect(workspace.calls, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('offline-checkout')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester, workspace);
      expect(find.text(originalId), findsOneWidget);
      await tap(tester, find.byKey(const Key('retry-local-checkout')));
      expect(find.text('Remaining: PHP 5.21'), findsOneWidget);
      expect(find.byTooltip('Remove payment'), findsNothing);
      await tester.enterText(find.byKey(const Key('cash-received')), '6.00');
      await tap(tester, find.byKey(const Key('payment-confirmed')));
      await tap(tester, find.byKey(const Key('add-payment')));
      await tap(tester, find.byKey(const Key('submit-payment')));
      expect(workspace.calls.single.requestId, originalId);
      expect(
        workspace.calls.single.payments.map((payment) => payment.amountMinor),
        [600, 521],
      );
      expect(workspace.receipts, hasLength(1));
    },
  );

  testWidgets(
    'expired restored partial payment is readable and cannot collect its remainder',
    (tester) async {
      final workspace = FixtureWorkspace()..expired = true;
      workspace.intents.add(
        OfflineCheckoutRequest(
          requestId: eventId,
          lines: const [CartLine(product: product, quantity: 1)],
          expectedTotalMinor: 1121,
          payments: const [
            CheckoutPayment(
              method: CheckoutPaymentMethod.cash,
              amountMinor: 600,
              tenderedMinor: 600,
            ),
          ],
        ),
      );
      await mount(tester, workspace);
      expect(find.text('Continue remaining payment'), findsOneWidget);
      expect(find.textContaining('Saved 6.00 of 11.21'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('retry-local-checkout')),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Record payment'), findsNothing);
      expect(workspace.calls, isEmpty);
    },
  );
}
