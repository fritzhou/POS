import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/app/theme/app_theme.dart';
import 'package:nexapos/core/services/payment_service.dart';
import 'package:nexapos/features/checkout/presentation/pos_payment_dialog.dart';

Future<void> pumpDialog(
  WidgetTester tester, {
  Size size = const Size(800, 800),
  int total = 10000,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: PosPaymentDialog(totalMinor: total, currency: 'PHP'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> addCash(
  WidgetTester tester, {
  String applied = '100.00',
  String received = '100.00',
}) async {
  await tester.ensureVisible(find.byKey(const Key('payment-applied-amount')));
  await tester.enterText(
    find.byKey(const Key('payment-applied-amount')),
    applied,
  );
  await tester.ensureVisible(find.byKey(const Key('cash-received')));
  await tester.enterText(find.byKey(const Key('cash-received')), received);
  await tester.ensureVisible(find.byKey(const Key('payment-confirmed')));
  await tester.tap(find.byKey(const Key('payment-confirmed')));
  await tester.ensureVisible(find.byKey(const Key('add-payment')));
  await tester.tap(find.byKey(const Key('add-payment')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'cash cannot be submitted before counted evidence and shows exact change',
    (tester) async {
      await pumpDialog(tester);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('submit-payment')))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(const Key('cash-received')), '120.01');
      await tester.tap(find.byKey(const Key('add-payment')));
      await tester.pump();
      expect(
        find.text('Count and confirm enough cash for this payment.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('payment-confirmed')));
      await tester.tap(find.byKey(const Key('add-payment')));
      await tester.pumpAndSettle();
      expect(find.text('Cash counted · Change 20.01'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('submit-payment')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual tender requires actual operator confirmation and reference',
    (tester) async {
      await pumpDialog(tester);
      await tester.tap(find.byKey(const Key('payment-method')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GCash').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-payment')));
      await tester.pump();
      expect(
        find.text(
          'Confirm the payment in the actual provider or terminal and enter its reference.',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('payment-reference')),
        'actual-operator-record',
      );
      await tester.tap(find.byKey(const Key('payment-confirmed')));
      await tester.tap(find.byKey(const Key('add-payment')));
      await tester.pumpAndSettle();
      expect(
        find.text('Manual Payment Verification · actual-operator-record'),
        findsOneWidget,
      );
      expect(
        find.textContaining('provider APIs are not connected'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('submit-payment')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('split payments must cover exact remaining amount', (
    tester,
  ) async {
    await pumpDialog(tester);
    await addCash(tester, applied: '40.00', received: '50.00');
    expect(find.text('Remaining: PHP 60.00'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('submit-payment')))
          .onPressed,
      isNull,
    );
    await addCash(tester, applied: '60.01', received: '60.01');
    expect(
      find.textContaining('no more than the remaining total'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('payment-applied-amount')),
      '60.00',
    );
    await tester.tap(find.byKey(const Key('add-payment')));
    await tester.pumpAndSettle();
    expect(find.text('Remaining: PHP 0.00'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('submit-payment')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('five-payment bound is enforced before submission', (
    tester,
  ) async {
    await pumpDialog(tester, total: 600);
    for (var i = 0; i < 5; i++) {
      await tester.ensureVisible(
        find.byKey(const Key('payment-applied-amount')),
      );
      await addCash(tester, applied: '1.00', received: '1.00');
    }
    expect(find.byKey(const Key('add-payment')), findsNothing);
    expect(find.textContaining('at most five payments'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('submit-payment')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('phone payment form is scrollable without overflow', (
    tester,
  ) async {
    await pumpDialog(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('cash-received')));
    await tester.enterText(find.byKey(const Key('cash-received')), '100.00');
    await tester.ensureVisible(find.byKey(const Key('payment-confirmed')));
    await tester.tap(find.byKey(const Key('payment-confirmed')));
    await tester.ensureVisible(find.byKey(const Key('add-payment')));
    await tester.tap(find.byKey(const Key('add-payment')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog result is tender evidence rather than sale success', (
    tester,
  ) async {
    List<TenderEvidence>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<List<TenderEvidence>>(
                  context: context,
                  builder: (_) => const PosPaymentDialog(
                    totalMinor: 10000,
                    currency: 'PHP',
                  ),
                );
              },
              child: const Text('Pay'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();
    await addCash(tester);
    await tester.tap(find.byKey(const Key('submit-payment')));
    await tester.pumpAndSettle();
    expect(result, hasLength(1));
    expect(result!.single.appliedMinor, 10000);
    expect(result!.single.providerAuthorized, isFalse);
    expect(find.textContaining('Sale completed'), findsNothing);
  });

  testWidgets(
    'durable tender appears only after its awaited write and cannot be removed',
    (tester) async {
      final write = Completer<void>();
      TenderEvidence? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosPaymentDialog(
              totalMinor: 10000,
              currency: 'PHP',
              onRecordTender: (index, tender) async {
                expect(index, 0);
                saved = tender;
                await write.future;
              },
            ),
          ),
        ),
      );
      await addCash(tester);
      expect(saved?.appliedMinor, 10000);
      expect(find.textContaining('Cash counted · Change'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('add-payment')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      write.complete();
      await tester.pumpAndSettle();
      expect(find.text('Cash counted · Change 0.00'), findsOneWidget);
      expect(find.byTooltip('Remove payment'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('submit-payment')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'uncertain durable write retries the original evidence and locks editing',
    (tester) async {
      final attempts = <TenderEvidence>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosPaymentDialog(
              totalMinor: 10000,
              currency: 'PHP',
              onRecordTender: (index, tender) async {
                expect(index, 0);
                attempts.add(tender);
                if (attempts.length == 1) throw StateError('private failure');
              },
            ),
          ),
        ),
      );
      await addCash(tester, received: '120.00');
      expect(find.text('Retry saving original payment'), findsOneWidget);
      expect(find.textContaining('private failure'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('cash-received')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('submit-payment')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('add-payment')));
      await tester.pumpAndSettle();
      expect(attempts, hasLength(2));
      expect(identical(attempts.first, attempts.last), isTrue);
      expect(find.text('Cash counted · Change 20.00'), findsOneWidget);
    },
  );
}
