import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/database/database_scope.dart';
import 'package:nexapos/core/database/sale_draft.dart';
import 'package:nexapos/core/security/access_lock.dart';
import 'package:nexapos/core/sync/outbox_state.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';
import 'package:nexapos/features/offline/domain/offline_workspace.dart';
import 'package:nexapos/features/offline/presentation/offline_receipt_details.dart';
import 'package:nexapos/features/receipts/data/receipt_output_service.dart';
import 'package:nexapos/features/receipts/domain/receipt_document.dart';
import 'package:nexapos/features/receipts/presentation/receipt_output_actions.dart';
import 'package:nexapos/features/receipts/presentation/receipt_output_scope.dart';
import 'package:nexapos/features/sales/presentation/receipt_details.dart';

const _org = 'organization-fixture';
const _branch = 'branch-fixture';
const _sale = 'sale-fixture';
final _time = DateTime.utc(2026, 10, 12, 0, 30);

SaleReceipt _receipt({
  bool reversed = true,
  bool unsupportedCurrency = false,
}) => SaleReceipt(
  id: _sale,
  organizationId: _org,
  branchId: _branch,
  shiftId: 'shift-fixture',
  actorUserId: 'actor-fixture',
  receiptNumber: 'ORIGINAL-20261012-1',
  currency: unsupportedCurrency ? 'ZZZ' : 'PHP',
  createdAt: _time,
  businessName: 'Historical business',
  branchName: 'Original branch',
  address: 'Original address',
  contact: 'Original contact',
  receiptFooter: 'Original footer',
  subtotalMinor: 10000,
  discountMinor: 1000,
  taxBps: 0,
  taxMinor: 0,
  totalMinor: 9000,
  items: [
    SaleItem(
      id: 'line-fixture',
      productId: 'product-fixture',
      name: 'Historical product with a long description for a narrow receipt',
      sku: 'HISTORICAL-SKU-FOR-ORIGINAL-LINE',
      quantity: 2,
      unitPriceMinor: 5000,
      subtotalMinor: 10000,
      discountMinor: 1000,
      taxMinor: 0,
      totalMinor: 9000,
      reversedQuantity: reversed ? 1 : 0,
    ),
  ],
  payments: [
    SalePayment(
      id: 'payment-fixture',
      method: CheckoutPaymentMethod.cash,
      amountMinor: 9000,
      tenderedMinor: 12000,
      reversedMinor: reversed ? 4500 : 0,
    ),
  ],
);

LocalOfflineReceipt _offline() => LocalOfflineReceipt(
  draft: SaleDraft(
    id: _sale,
    eventId: 'original-event-fixture',
    scope: DatabaseScope(organizationId: _org, branchId: _branch),
    deviceId: 'device-fixture',
    shiftId: 'shift-fixture',
    cashierId: 'actor-fixture',
    receiptNumber: 'OFFLINE-ORIGINAL-1',
    currency: 'PHP',
    createdAt: _time,
    items: const [
      SaleLineDraft(
        id: 'line-fixture',
        productId: 'product-fixture',
        name: 'Original offline product',
        sku: 'ORIGINAL-SKU',
        quantity: 2,
        unitPriceMinor: 5000,
        discountMinor: 1000,
        taxMinor: 1080,
      ),
    ],
    payments: const [
      SalePaymentDraft(
        id: 'payment-fixture',
        method: 'gcash',
        amountMinor: 10080,
        reference: 'OPERATOR-REFERENCE',
      ),
    ],
  ),
  status: OutboxStatus.synced,
  sequence: 1,
  grantId: 'SIGNED-GRANT-PRIVATE',
  serverReceiptId: 'linked-server-fixture',
  businessName: 'Offline business',
  branchName: 'Offline branch',
  acceptedAt: _time.add(const Duration(hours: 1)),
);

class _Output implements ReceiptOutputService {
  final documents = <ReceiptDocument>[];
  final papers = <ReceiptPaperFormat>[];
  int prints = 0, shares = 0, nativeCalls = 0;
  ReceiptOutputStatus status = ReceiptOutputStatus.submitted;
  Completer<void>? preparation;
  Object? error;

  Future<ReceiptOutputResult> _run(
    ReceiptDocument document,
    ReceiptPaperFormat paper,
    bool Function() isCurrent,
  ) async {
    documents.add(document);
    papers.add(paper);
    if (preparation != null) await preparation!.future;
    if (!isCurrent()) {
      return const ReceiptOutputResult(ReceiptOutputStatus.scopeChanged, '');
    }
    if (error != null) throw error!;
    nativeCalls++;
    return ReceiptOutputResult(status, '');
  }

  @override
  Future<ReceiptOutputResult> printReceipt(
    ReceiptDocument document, {
    required ReceiptPaperFormat paper,
    required bool Function() isCurrent,
  }) {
    prints++;
    return _run(document, paper, isCurrent);
  }

  @override
  Future<ReceiptOutputResult> shareReceiptPdf(
    ReceiptDocument document, {
    required ReceiptPaperFormat paper,
    required bool Function() isCurrent,
  }) {
    shares++;
    return _run(document, paper, isCurrent);
  }
}

class _Workspace implements OfflineWorkspace {
  int exports = 0;
  Completer<String>? delayedExport;
  @override
  Future<String> exportReceipt(String eventId) async {
    exports++;
    return delayedExport == null
        ? 'PRIVATE SIGNED EVENT AND GRANT'
        : delayedExport!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  double width = 900,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets(
    'output requires an explicit press and preserves original snapshot',
    (tester) async {
      final output = _Output();
      await _mount(
        tester,
        ReceiptDetails(
          receipt: _receipt(),
          outputService: output,
          isCurrent: () => true,
        ),
      );
      expect(output.documents, isEmpty);
      expect(find.text('Original total'), findsOneWidget);
      expect(find.text('Recorded reversals'), findsOneWidget);
      expect(find.text('Reversed units: 1'), findsOneWidget);
      await _tap(tester, 'print-receipt-copy');
      await tester.pumpAndSettle();
      expect(output.prints, 1);
      expect(output.documents.single.totalMinor, 9000);
      expect(output.documents.single.recordedReversalMinor, 4500);
      expect(output.documents.single.businessName, 'Historical business');
      expect(output.documents.single.payments.single.tenderedMinor, 12000);
      expect(output.papers.single, ReceiptPaperFormat.thermal80);
      expect(find.text('Sent to the system print service.'), findsOneWidget);
      expect(find.textContaining('successfully printed'), findsNothing);
      await _tap(tester, 'print-receipt-copy');
      await tester.pumpAndSettle();
      expect(output.prints, 2);
      expect(output.documents.last.totalMinor, 9000);
      expect(find.textContaining('labelled COPY'), findsOneWidget);
    },
  );

  testWidgets(
    'paper selection reaches PDF output and cancellation is explicit',
    (tester) async {
      final output = _Output()..status = ReceiptOutputStatus.cancelled;
      await _mount(
        tester,
        ReceiptOutputActions(
          document: ReceiptDocument.fromSale(_receipt()),
          service: output,
          isCurrent: () => true,
        ),
      );
      await _tap(tester, 'receipt-paper-format');
      await tester.pumpAndSettle();
      await tester.tap(find.text('58 mm receipt').last);
      await tester.pumpAndSettle();
      await _tap(tester, 'share-receipt-pdf');
      await tester.pumpAndSettle();
      expect(output.shares, 1);
      expect(output.papers.single, ReceiptPaperFormat.thermal58);
      expect(find.text('PDF sharing cancelled.'), findsOneWidget);
      expect(find.textContaining('sent to the system'), findsNothing);
    },
  );

  testWidgets('failed output has a sanitized notice and allows retry', (
    tester,
  ) async {
    final output = _Output()..error = StateError('PRIVATE TOKEN EXCEPTION');
    await _mount(
      tester,
      ReceiptOutputActions(
        document: ReceiptDocument.fromSale(_receipt()),
        service: output,
        isCurrent: () => true,
      ),
    );
    await _tap(tester, 'print-receipt-copy');
    await tester.pumpAndSettle();
    expect(find.textContaining('PRIVATE TOKEN'), findsNothing);
    expect(find.textContaining('could not be completed'), findsOneWidget);
    output.error = null;
    await _tap(tester, 'share-receipt-pdf');
    await tester.pumpAndSettle();
    expect(output.shares, 1);
    expect(
      find.text(
        'PDF handed to the system PDF handler. Use its save or share controls.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'scope loss during preparation prevents native output and notices',
    (tester) async {
      var current = true;
      final output = _Output()..preparation = Completer<void>();
      await _mount(
        tester,
        ReceiptOutputActions(
          document: ReceiptDocument.fromSale(_receipt()),
          service: output,
          isCurrent: () => current,
        ),
      );
      await _tap(tester, 'print-receipt-copy');
      expect(find.text('Preparing receipt copy…'), findsOneWidget);
      current = false;
      output.preparation!.complete();
      await tester.pumpAndSettle();
      expect(output.nativeCalls, 0);
      expect(find.byKey(const Key('receipt-output-notice')), findsNothing);
      final print = tester.widget<OutlinedButton>(
        find.byKey(const Key('print-receipt-copy')),
      );
      expect(print.onPressed, isNull);
    },
  );

  testWidgets(
    'unsupported characters preserve history and stop impossible retries',
    (tester) async {
      final output = _Output()
        ..status = ReceiptOutputStatus.unsupportedCharacters;
      await _mount(
        tester,
        ReceiptDetails(
          receipt: _receipt(),
          outputService: output,
          isCurrent: () => true,
        ),
      );
      await _tap(tester, 'print-receipt-copy');
      await tester.pumpAndSettle();
      expect(find.text('Original total'), findsOneWidget);
      expect(find.text('Historical business'), findsOneWidget);
      expect(
        find.text(
          'A character in this receipt is not supported for PDF output. The original record remains readable.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Try again'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('print-receipt-copy')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('share-receipt-pdf')))
            .onPressed,
        isNull,
      );
      expect(output.documents, hasLength(1));
      expect(output.documents.single.totalMinor, 9000);
      expect(output.documents.single.recordedReversalMinor, 4500);
    },
  );

  testWidgets('disposing an output while preparing prevents native handoff', (
    tester,
  ) async {
    final output = _Output()..preparation = Completer<void>();
    await _mount(
      tester,
      ReceiptOutputActions(
        document: ReceiptDocument.fromSale(_receipt()),
        service: output,
        isCurrent: () => true,
      ),
    );
    await _tap(tester, 'share-receipt-pdf');
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    output.preparation!.complete();
    await tester.pumpAndSettle();
    expect(output.nativeCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unscoped receipt output fails closed', (tester) async {
    final output = _Output();
    await _mount(
      tester,
      ReceiptOutputActions(
        document: ReceiptDocument.fromSale(_receipt()),
        service: output,
      ),
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('print-receipt-copy')))
          .onPressed,
      isNull,
    );
    expect(output.documents, isEmpty);
  });

  testWidgets('incomplete source evidence remains readable without output', (
    tester,
  ) async {
    final output = _Output();
    await _mount(
      tester,
      ReceiptDetails(
        receipt: _receipt(unsupportedCurrency: true),
        outputService: output,
        isCurrent: () => true,
      ),
    );
    expect(find.text('Original total'), findsOneWidget);
    expect(find.text('Recorded reversals'), findsOneWidget);
    expect(find.byKey(const Key('receipt-output-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('print-receipt-copy')), findsNothing);
    expect(output.documents, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a lock and unlock invalidate the original output view', (
    tester,
  ) async {
    final access = AccessLock()..bind('actor-fixture');
    addTearDown(access.dispose);
    final output = _Output()..preparation = Completer<void>();
    await _mount(
      tester,
      ReceiptOutputScope(
        identity: 'actor-fixture',
        isAllowed: () => true,
        access: access,
        child: ReceiptOutputActions(
          document: ReceiptDocument.fromSale(_receipt()),
          service: output,
        ),
      ),
    );
    await _tap(tester, 'print-receipt-copy');
    access.lock();
    expect(
      access.unlockVerified(
        actorId: 'actor-fixture',
        generation: access.generation,
      ),
      isTrue,
    );
    output.preparation!.complete();
    await tester.pumpAndSettle();
    expect(output.nativeCalls, 0);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('print-receipt-copy')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('receipt-output-notice')), findsNothing);
  });

  testWidgets('replacing the receipt invalidates an earlier preparation', (
    tester,
  ) async {
    final output = _Output()..preparation = Completer<void>();
    final oldReceipt = _receipt();
    final replacement = _receipt(reversed: false);
    final document = ValueNotifier(ReceiptDocument.fromSale(oldReceipt));
    addTearDown(document.dispose);
    bool current() => true;
    await _mount(
      tester,
      ValueListenableBuilder<ReceiptDocument>(
        valueListenable: document,
        builder: (context, value, child) => ReceiptOutputActions(
          document: value,
          service: output,
          isCurrent: current,
        ),
      ),
    );
    await _tap(tester, 'share-receipt-pdf');
    document.value = ReceiptDocument.fromSale(replacement);
    await tester.pump();
    output.preparation!.complete();
    await tester.pumpAndSettle();
    expect(output.nativeCalls, 0);
    expect(find.byKey(const Key('receipt-output-notice')), findsNothing);
    output.preparation = null;
    await _tap(tester, 'share-receipt-pdf');
    await tester.pumpAndSettle();
    expect(output.nativeCalls, 1);
    expect(output.documents.last.recordedReversalMinor, 0);
    expect(output.documents.last.totalMinor, 9000);
  });

  testWidgets('320px online dialog scrolls and Close never outputs', (
    tester,
  ) async {
    final output = _Output();
    await _mount(
      tester,
      Builder(
        builder: (context) => FilledButton(
          onPressed: () => showReceiptDialog(
            context,
            _receipt(),
            outputService: output,
            isCurrent: () => true,
          ),
          child: const Text('Open receipt'),
        ),
      ),
      width: 320,
    );
    await tester.tap(find.text('Open receipt'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('share-receipt-pdf')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(output.documents, isEmpty);
    expect(find.text('Sale receipt'), findsNothing);
  });

  testWidgets(
    'linked offline customer copy stays provisional without signed proof',
    (tester) async {
      final output = _Output();
      final workspace = _Workspace();
      await _mount(
        tester,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showOfflineReceipt(
              context,
              _offline(),
              workspace,
              outputService: output,
              isCurrent: () => true,
            ),
            child: const Text('Open offline receipt'),
          ),
        ),
        width: 320,
      );
      await tester.tap(find.text('Open offline receipt'));
      await tester.pumpAndSettle();
      expect(find.text('Provisional offline receipt'), findsOneWidget);
      expect(find.textContaining('Asia/Manila'), findsOneWidget);
      expect(find.text('Discount PHP 10.00'), findsOneWidget);
      await _tap(tester, 'share-receipt-pdf');
      await tester.pumpAndSettle();
      final document = output.documents.single;
      expect(document.isProvisional, isTrue);
      expect(document.receiptNumber, 'OFFLINE-ORIGINAL-1');
      expect(document.serverReceiptId, 'linked-server-fixture');
      expect(document.payments.single.tenderedMinor, isNull);
      expect(document.totalMinor, 10080);
      expect(workspace.exports, 0);
      expect(find.textContaining('SIGNED-GRANT-PRIVATE'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scope loss while signed record is loading prevents clipboard disclosure',
    (tester) async {
      var current = true;
      var clipboardWrites = 0;
      final workspace = _Workspace()..delayedExport = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') clipboardWrites++;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await _mount(
        tester,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showOfflineReceipt(
              context,
              _offline(),
              workspace,
              outputService: _Output(),
              isCurrent: () => current,
            ),
            child: const Text('Open offline receipt'),
          ),
        ),
      );
      await tester.tap(find.text('Open offline receipt'));
      await tester.pumpAndSettle();
      await _tap(tester, 'export-offline-receipt');
      expect(workspace.exports, 1);
      current = false;
      workspace.delayedExport!.complete('PRIVATE SIGNED PROOF');
      await tester.pumpAndSettle();
      expect(clipboardWrites, 0);
      expect(find.textContaining('signed event copied'), findsNothing);
    },
  );
  for (final signedReview in [false, true]) {
    testWidgets(
      'closing a preparing ${signedReview ? 'signed review' : 'customer PDF'} blocks output during the exit animation',
      (tester) async {
        var clipboardWrites = 0;
        final workspace = _Workspace()..delayedExport = Completer<String>();
        final output = _Output()..preparation = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') clipboardWrites++;
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await _mount(
          tester,
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => showOfflineReceipt(
                context,
                _offline(),
                workspace,
                outputService: output,
                isCurrent: () => true,
              ),
              child: const Text('Open offline receipt'),
            ),
          ),
        );
        await tester.tap(find.text('Open offline receipt'));
        await tester.pumpAndSettle();
        await _tap(
          tester,
          signedReview ? 'export-offline-receipt' : 'share-receipt-pdf',
        );
        await tester.tap(find.text('Close'));
        // Complete while the popped route remains mounted for its transition.
        workspace.delayedExport!.complete('PRIVATE SIGNED PROOF');
        output.preparation!.complete();
        await tester.pumpAndSettle();
        expect(clipboardWrites, 0);
        expect(output.nativeCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
