import '../../../core/sync/outbox_state.dart';
import '../../checkout/domain/checkout_models.dart';
import '../../offline/domain/offline_workspace.dart';

enum ReceiptOrigin { server, provisionalOffline }

enum ReceiptPaperFormat { a4, thermal80, thermal58 }

/// A presentation snapshot. It never changes an original sale or acknowledges
/// a payment, a print job, or an offline event.
class ReceiptDocument {
  ReceiptDocument._({
    required this.origin,
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.receiptNumber,
    required this.currency,
    required this.sourceAtUtc,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.totalMinor,
    required List<ReceiptDocumentLine> lines,
    required List<ReceiptDocumentPayment> payments,
    this.taxBps,
    this.businessName,
    this.branchName,
    this.address,
    this.contact,
    this.footer,
    this.eventId,
    this.offlineSequence,
    this.offlineStatus,
    this.serverReceiptId,
    this.serverAcceptedAtUtc,
    this.failureCode,
    this.reconciliationCode,
  }) : lines = List.unmodifiable(lines),
       payments = List.unmodifiable(payments) {
    _validate();
  }

  factory ReceiptDocument.fromSale(SaleReceipt receipt) => ReceiptDocument._(
    origin: ReceiptOrigin.server,
    id: receipt.id,
    organizationId: receipt.organizationId,
    branchId: receipt.branchId,
    receiptNumber: receipt.receiptNumber,
    currency: receipt.currency,
    sourceAtUtc: receipt.createdAt.toUtc(),
    subtotalMinor: receipt.subtotalMinor,
    discountMinor: receipt.discountMinor,
    taxBps: receipt.taxBps,
    taxMinor: receipt.taxMinor,
    totalMinor: receipt.totalMinor,
    businessName: receipt.businessName,
    branchName: receipt.branchName,
    address: receipt.address,
    contact: receipt.contact,
    footer: receipt.receiptFooter,
    lines: [
      for (final item in receipt.items)
        ReceiptDocumentLine._(
          id: item.id,
          productId: item.productId,
          name: item.name,
          sku: item.sku,
          quantity: item.quantity,
          unitPriceMinor: item.unitPriceMinor,
          subtotalMinor: item.subtotalMinor,
          discountMinor: item.discountMinor,
          taxMinor: item.taxMinor,
          totalMinor: item.totalMinor,
          reversedQuantity: item.reversedQuantity,
        ),
    ],
    payments: [
      for (final payment in receipt.payments)
        ReceiptDocumentPayment._(
          id: payment.id,
          method: payment.method,
          amountMinor: payment.amountMinor,
          tenderedMinor: payment.tenderedMinor,
          reference: payment.reference,
          reversedMinor: payment.reversedMinor,
        ),
    ],
  );

  factory ReceiptDocument.fromOffline(LocalOfflineReceipt receipt) {
    final draft = receipt.draft;
    draft.validate();
    return ReceiptDocument._(
      origin: ReceiptOrigin.provisionalOffline,
      id: draft.id,
      organizationId: draft.scope.organizationId,
      branchId: draft.scope.branchId,
      receiptNumber: draft.receiptNumber,
      currency: draft.currency,
      sourceAtUtc: draft.createdAt.toUtc(),
      subtotalMinor: draft.subtotalMinor,
      discountMinor: draft.discountMinor,
      taxMinor: draft.taxMinor,
      totalMinor: draft.totalMinor,
      businessName: receipt.businessName,
      branchName: receipt.branchName,
      eventId: draft.eventId,
      offlineSequence: receipt.sequence,
      offlineStatus: receipt.status,
      serverReceiptId: receipt.serverReceiptId,
      serverAcceptedAtUtc: receipt.acceptedAt?.toUtc(),
      failureCode: receipt.failureCode,
      reconciliationCode: receipt.reconciliationCode,
      lines: [
        for (final item in draft.items)
          ReceiptDocumentLine._(
            id: item.id,
            productId: item.productId,
            name: item.name,
            sku: item.sku,
            quantity: item.quantity,
            unitPriceMinor: item.unitPriceMinor,
            subtotalMinor: item.subtotalMinor,
            discountMinor: item.discountMinor,
            taxMinor: item.taxMinor,
            totalMinor: item.totalMinor,
          ),
      ],
      payments: [
        for (final payment in draft.payments)
          ReceiptDocumentPayment._(
            id: payment.id,
            method: CheckoutPaymentMethod.values.firstWhere(
              (method) => method.name == payment.method,
            ),
            amountMinor: payment.amountMinor,
            reference: payment.reference,
          ),
      ],
    );
  }

  final ReceiptOrigin origin;
  final String id, organizationId, branchId, receiptNumber, currency;
  final DateTime sourceAtUtc;
  final int subtotalMinor, discountMinor, taxMinor, totalMinor;
  final int? taxBps;
  final String? businessName, branchName, address, contact, footer;
  final List<ReceiptDocumentLine> lines;
  final List<ReceiptDocumentPayment> payments;

  /// These describe the original local record. A server link never changes its
  /// origin or replaces its event/receipt identifiers.
  final String? eventId, serverReceiptId, failureCode, reconciliationCode;
  final int? offlineSequence;
  final OutboxStatus? offlineStatus;
  final DateTime? serverAcceptedAtUtc;

  bool get isProvisional => origin == ReceiptOrigin.provisionalOffline;
  int get recordedReversalMinor => _sum(
    payments.map((payment) => payment.reversedMinor),
    'Recorded reversals',
  );

  String get title =>
      isProvisional ? 'PROVISIONAL OFFLINE RECEIPT' : 'SALE RECEIPT';

  String? get offlineStatusLabel => switch (offlineStatus) {
    OutboxStatus.pending => 'PENDING - stored on this device',
    OutboxStatus.syncing => 'SYNCING - awaiting server response',
    OutboxStatus.synced =>
      reconciliationCode == null
          ? 'SYNCED - server receipt linked separately'
          : 'SYNCED - stock reconciliation required',
    OutboxStatus.failed => 'FAILED - original paid record preserved',
    null => null,
  };

  String get suggestedFileName {
    final safe = receiptNumber.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
    // The identifier keeps different receipts with the same number distinct.
    final safeId = id.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
    return '${isProvisional ? 'offline' : 'receipt'}-$safe-$safeId.pdf';
  }

  void _validate() {
    for (final entry in {
      'Receipt identifier': id,
      'Organization identifier': organizationId,
      'Branch identifier': branchId,
      'Receipt number': receiptNumber,
    }.entries) {
      _text(entry.value, entry.key, required: true, maximum: 200);
    }
    if (!const {
      'PHP',
      'USD',
      'EUR',
      'GBP',
      'AUD',
      'CAD',
      'SGD',
    }.contains(currency)) {
      throw const FormatException('Unsupported receipt currency.');
    }
    _date(sourceAtUtc);
    if (taxBps != null && (taxBps! < 0 || taxBps! > 10000)) {
      throw const FormatException('Invalid receipt tax rate.');
    }
    for (final text in [businessName, branchName, address, contact, footer]) {
      if (text != null) _text(text, 'Receipt text');
    }
    if (lines.isEmpty ||
        lines.length > 100 ||
        payments.isEmpty ||
        payments.length > 5) {
      throw const FormatException('Invalid receipt line or payment count.');
    }
    if (lines.map((line) => line.id).toSet().length != lines.length ||
        lines.map((line) => line.productId).toSet().length != lines.length ||
        payments.map((payment) => payment.id).toSet().length !=
            payments.length) {
      throw const FormatException('Duplicate receipt lines or payments.');
    }
    for (final line in lines) {
      line._validate();
    }
    for (final payment in payments) {
      payment._validate();
    }
    for (final amount in [subtotalMinor, discountMinor, taxMinor, totalMinor]) {
      _money(amount);
    }
    if (totalMinor <= 0 ||
        subtotalMinor !=
            _sum(lines.map((line) => line.subtotalMinor), 'Subtotal') ||
        discountMinor !=
            _sum(lines.map((line) => line.discountMinor), 'Discount') ||
        taxMinor != _sum(lines.map((line) => line.taxMinor), 'Tax') ||
        totalMinor != _sum(lines.map((line) => line.totalMinor), 'Total') ||
        totalMinor !=
            _exact(
              BigInt.from(subtotalMinor) -
                  BigInt.from(discountMinor) +
                  BigInt.from(taxMinor),
              'Total',
            ) ||
        totalMinor !=
            _sum(payments.map((payment) => payment.amountMinor), 'Payments')) {
      throw const FormatException('Inconsistent receipt totals.');
    }
    if (isProvisional) {
      _text(
        eventId ?? '',
        'Offline event identifier',
        required: true,
        maximum: 200,
      );
      if (offlineSequence == null ||
          offlineSequence! < 1 ||
          offlineSequence! > 1000 ||
          offlineStatus == null) {
        throw const FormatException('Invalid offline receipt metadata.');
      }
      if ((serverReceiptId == null && serverAcceptedAtUtc != null) ||
          (offlineStatus == OutboxStatus.synced && serverReceiptId == null)) {
        throw const FormatException('Invalid server receipt link.');
      }
      if (serverReceiptId != null) {
        _text(
          serverReceiptId!,
          'Server receipt identifier',
          required: true,
          maximum: 200,
        );
        if (serverAcceptedAtUtc != null) {
          _date(serverAcceptedAtUtc!);
        }
      }
      for (final code in [failureCode, reconciliationCode]) {
        if (code != null) {
          _text(code, 'Review code', required: true, maximum: 200);
        }
      }
    }
  }
}

class ReceiptDocumentLine {
  const ReceiptDocumentLine._({
    required this.id,
    required this.productId,
    required this.name,
    required this.sku,
    required this.quantity,
    required this.unitPriceMinor,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.totalMinor,
    this.reversedQuantity = 0,
  });

  final String id, productId, name, sku;
  final int quantity,
      unitPriceMinor,
      subtotalMinor,
      discountMinor,
      taxMinor,
      totalMinor,
      reversedQuantity;

  void _validate() {
    _text(id, 'Line identifier', required: true, maximum: 200);
    _text(productId, 'Product identifier', required: true, maximum: 200);
    _text(name, 'Product name', required: true);
    _text(sku, 'Product SKU', required: true, maximum: 200);
    if (quantity < 1 ||
        quantity > 1000000 ||
        reversedQuantity < 0 ||
        reversedQuantity > quantity) {
      throw const FormatException('Invalid receipt quantity.');
    }
    for (final amount in [
      unitPriceMinor,
      subtotalMinor,
      discountMinor,
      taxMinor,
      totalMinor,
    ]) {
      _money(amount);
    }
    if (subtotalMinor !=
            _exact(
              BigInt.from(quantity) * BigInt.from(unitPriceMinor),
              'Line subtotal',
            ) ||
        discountMinor > subtotalMinor ||
        totalMinor !=
            _exact(
              BigInt.from(subtotalMinor) -
                  BigInt.from(discountMinor) +
                  BigInt.from(taxMinor),
              'Line total',
            )) {
      throw const FormatException('Inconsistent receipt line amounts.');
    }
  }
}

class ReceiptDocumentPayment {
  const ReceiptDocumentPayment._({
    required this.id,
    required this.method,
    required this.amountMinor,
    this.tenderedMinor,
    this.reference,
    this.reversedMinor = 0,
  });

  final String id;
  final CheckoutPaymentMethod method;
  final int amountMinor, reversedMinor;
  final int? tenderedMinor;
  final String? reference;

  bool get operatorVerified => method != CheckoutPaymentMethod.cash;
  int? get changeMinor =>
      method == CheckoutPaymentMethod.cash && tenderedMinor != null
      ? tenderedMinor! - amountMinor
      : null;

  String get label => switch (method) {
    CheckoutPaymentMethod.cash => 'Cash',
    CheckoutPaymentMethod.card => 'Card',
    CheckoutPaymentMethod.gcash => 'GCash',
    CheckoutPaymentMethod.maya => 'Maya',
    CheckoutPaymentMethod.other => 'Other',
  };

  void _validate() {
    _text(id, 'Payment identifier', required: true, maximum: 200);
    _money(amountMinor);
    _money(reversedMinor);
    if (amountMinor == 0 || reversedMinor > amountMinor) {
      throw const FormatException('Invalid receipt payment amount.');
    }
    if (method == CheckoutPaymentMethod.cash) {
      if (reference != null) {
        throw const FormatException('Invalid receipt cash evidence.');
      }
      if (tenderedMinor != null) {
        _money(tenderedMinor!);
        if (tenderedMinor! < amountMinor) {
          throw const FormatException('Cash tender is below its allocation.');
        }
      }
    } else {
      if (tenderedMinor != null) {
        throw const FormatException('Manual payments cannot have cash tender.');
      }
      _text(
        reference ?? '',
        'Manual payment reference',
        required: true,
        maximum: 200,
      );
    }
  }
}

void _text(
  String value,
  String field, {
  bool required = false,
  int maximum = 4000,
}) {
  if ((required && value.trim().isEmpty) ||
      value.length > maximum ||
      value.runes.any(
        (rune) =>
            (rune < 32 && rune != 10 && rune != 13 && rune != 9) || rune == 127,
      )) {
    throw FormatException('Invalid $field.');
  }
  // A Dart string can contain an unpaired UTF-16 surrogate. Reject it before
  // rune iteration or PDF encoding substitutes a replacement glyph.
  final units = value.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index + 1 >= units.length ||
          units[index + 1] < 0xdc00 ||
          units[index + 1] > 0xdfff) {
        throw FormatException('Invalid $field Unicode.');
      }
      index++;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw FormatException('Invalid $field Unicode.');
    }
  }
}

void _date(DateTime value) {
  if (!value.isUtc || value.year < 1 || value.year > 9999) {
    throw const FormatException('Invalid receipt timestamp.');
  }
}

void _money(int value) {
  _exact(BigInt.from(value), 'Receipt amount');
}

int _sum(Iterable<int> values, String field) => _exact(
  values.fold(BigInt.zero, (sum, value) => sum + BigInt.from(value)),
  field,
);

int _exact(BigInt value, String field) {
  if (value.isNegative || value > BigInt.from(maximumExactInteger)) {
    throw FormatException('$field exceeds exact non-negative minor units.');
  }
  return value.toInt();
}
