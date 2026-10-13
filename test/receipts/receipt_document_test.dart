import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/sync/outbox_state.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';
import 'package:nexapos/features/receipts/domain/receipt_document.dart';

import 'receipt_fixtures.dart';

void main() {
  test(
    'server document keeps original amounts and separate reversal annotations',
    () {
      final source = saleReceiptFixture(
        reversedQuantity: 1,
        reversedMinor: 126,
      );
      final document = ReceiptDocument.fromSale(source);
      expect(document.origin, ReceiptOrigin.server);
      expect(document.isProvisional, isFalse);
      expect(document.totalMinor, 252);
      expect(document.lines.single.quantity, 2);
      expect(document.lines.single.reversedQuantity, 1);
      expect(document.payments.single.amountMinor, 252);
      expect(document.recordedReversalMinor, 126);
      expect(document.businessName, 'Original business');
      expect(document.footer, 'Original footer');
      expect(document.sourceAtUtc, DateTime.utc(2026, 10, 12, 3, 4, 5));
      expect(document.serverAcceptedAtUtc, isNull);
      expect(() => document.lines.clear(), throwsUnsupportedError);
      expect(() => document.payments.clear(), throwsUnsupportedError);
      expect(source.totalMinor, 252);
    },
  );

  test(
    'cash copy uses original received and change, manual payment has no cash',
    () {
      final cash = ReceiptDocument.fromSale(
        saleReceiptFixture(method: CheckoutPaymentMethod.cash),
      );
      expect(cash.payments.single.tenderedMinor, 352);
      expect(cash.payments.single.changeMinor, 100);
      expect(cash.payments.single.operatorVerified, isFalse);
      final manual = ReceiptDocument.fromSale(saleReceiptFixture());
      expect(manual.payments.single.changeMinor, isNull);
      expect(manual.payments.single.operatorVerified, isTrue);
      expect(manual.payments.single.reference, 'MANUAL-REFERENCE');
    },
  );

  test(
    'synced offline copy stays provisional with separate original and accepted IDs and times',
    () {
      // Device observation is not a trusted server clock. Acceptance may precede
      // the observation and must retain both without ordering or relabeling them.
      final accepted = DateTime.utc(2026, 10, 12, 2);
      final source = offlineReceiptFixture(
        status: OutboxStatus.synced,
        serverReceiptId: receiptFixtureLinked,
        acceptedAt: accepted,
        reconciliationCode: 'stock_review',
      );
      final document = ReceiptDocument.fromOffline(source);
      expect(document.isProvisional, isTrue);
      expect(document.title, 'PROVISIONAL OFFLINE RECEIPT');
      expect(document.id, receiptFixtureId);
      expect(document.eventId, receiptFixtureEvent);
      expect(document.serverReceiptId, receiptFixtureLinked);
      expect(document.sourceAtUtc, DateTime.utc(2026, 10, 12, 3, 4, 5));
      expect(document.serverAcceptedAtUtc, accepted);
      expect(
        document.offlineStatusLabel,
        contains('stock reconciliation required'),
      );
      expect(document.taxBps, isNull);
      expect(document.payments.single.tenderedMinor, isNull);
      expect(document.payments.single.changeMinor, isNull);
      expect(document.totalMinor, source.draft.totalMinor);
    },
  );

  for (final status in [
    OutboxStatus.pending,
    OutboxStatus.syncing,
    OutboxStatus.failed,
  ]) {
    test(
      '$status preserves original offline payment without server success',
      () {
        final document = ReceiptDocument.fromOffline(
          offlineReceiptFixture(status: status),
        );
        expect(document.isProvisional, isTrue);
        expect(document.serverReceiptId, isNull);
        expect(document.serverAcceptedAtUtc, isNull);
        expect(document.payments.single.amountMinor, 252);
        expect(document.offlineStatusLabel, isNot(contains('SYNCED')));
      },
    );
  }

  test('historical allocated cash omits unrecorded tender and change', () {
    final document = ReceiptDocument.fromSale(
      saleReceiptFixture(
        method: CheckoutPaymentMethod.cash,
        omitCashTender: true,
      ),
    );
    expect(document.totalMinor, 252);
    expect(document.payments.single.amountMinor, 252);
    expect(document.payments.single.tenderedMinor, isNull);
    expect(document.payments.single.changeMinor, isNull);
  });

  test(
    'missing server identity is rejected without inventing acceptance time',
    () {
      expect(
        () => ReceiptDocument.fromOffline(
          offlineReceiptFixture(status: OutboxStatus.synced),
        ),
        throwsFormatException,
      );
      final linked = ReceiptDocument.fromOffline(
        offlineReceiptFixture(
          status: OutboxStatus.synced,
          serverReceiptId: receiptFixtureLinked,
        ),
      );
      expect(linked.isProvisional, isTrue);
      expect(linked.serverReceiptId, receiptFixtureLinked);
      expect(linked.serverAcceptedAtUtc, isNull);
      expect(
        () => ReceiptDocument.fromOffline(
          offlineReceiptFixture(acceptedAt: DateTime.utc(2026)),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'invalid original sums, over-reversal and unsupported manual evidence are rejected',
    () {
      expect(
        () => ReceiptDocument.fromSale(saleReceiptFixture(totalMinor: 251)),
        throwsFormatException,
      );
      expect(
        () => ReceiptDocument.fromSale(saleReceiptFixture(reversedQuantity: 3)),
        throwsFormatException,
      );
      expect(
        () => ReceiptDocument.fromSale(saleReceiptFixture(reversedMinor: 253)),
        throwsFormatException,
      );
      expect(
        () => ReceiptDocument.fromSale(saleReceiptFixture(reference: '')),
        throwsFormatException,
      );
      expect(
        () => ReceiptDocument.fromSale(saleReceiptFixture(tenderedMinor: 500)),
        throwsFormatException,
      );
      expect(
        () => ReceiptDocument.fromSale(
          saleReceiptFixture(
            method: CheckoutPaymentMethod.cash,
            tenderedMinor: 251,
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => ReceiptDocument.fromOffline(
          offlineReceiptFixture(paymentMinor: 251),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'whole quantities, line bounds and exact aggregate money are validated',
    () {
      expect(
        () => ReceiptDocument.fromSale(saleReceiptFixture(quantity: 1000001)),
        throwsFormatException,
      );
      expect(
        () => ReceiptDocument.fromOffline(
          offlineReceiptFixture(quantity: 1000001),
        ),
        throwsFormatException,
      );
      expect(
        () => ReceiptDocument.fromSale(saleReceiptFixture(count: 101)),
        throwsFormatException,
      );
      expect(
        () => ReceiptDocument.fromSale(
          saleReceiptFixture(unitPriceMinor: maximumExactInteger),
        ),
        throwsFormatException,
      );
      final exact = ReceiptDocument.fromSale(
        saleReceiptFixture(
          quantity: 1,
          unitPriceMinor: maximumExactInteger,
          discountMinor: 0,
          taxMinor: 0,
        ),
      );
      expect(exact.totalMinor, maximumExactInteger);
    },
  );

  test(
    'receipt text is preserved, controls rejected, file name cannot select a path',
    () {
      final unicode = ReceiptDocument.fromSale(
        saleReceiptFixture(name: 'Café 茶 (\\) < & >'),
      );
      expect(unicode.lines.single.name, 'Café 茶 (\\) < & >');
      expect(
        () => ReceiptDocument.fromSale(
          saleReceiptFixture(name: 'Hidden\u0000data'),
        ),
        throwsFormatException,
      );
      expect(
        () => ReceiptDocument.fromSale(
          saleReceiptFixture(name: String.fromCharCode(0xd800)),
        ),
        throwsFormatException,
      );
      expect(
        () => ReceiptDocument.fromSale(
          saleReceiptFixture(name: String.fromCharCode(0xdc00)),
        ),
        throwsFormatException,
      );
      final document = ReceiptDocument.fromSale(saleReceiptFixture());
      expect(
        document.suggestedFileName,
        'receipt-ORIGINAL-0001-$receiptFixtureId.pdf',
      );
      expect(document.suggestedFileName, isNot(contains('/')));
    },
  );
}
