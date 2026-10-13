import '../sync/sync_event.dart';
import 'database_scope.dart';

const _maximumMinor = 9007199254740991;

int _exactMinor(BigInt value, String field) {
  if (value.isNegative || value > BigInt.from(_maximumMinor)) {
    throw ArgumentError('$field must be non-negative exact minor units.');
  }
  return value.toInt();
}

int _sumMinor(Iterable<int> values, String field) => _exactMinor(
  values.fold(BigInt.zero, (sum, value) => sum + BigInt.from(value)),
  field,
);

void _nonNegative(int amount, String field) {
  if (amount < 0 || amount > _maximumMinor) {
    throw ArgumentError('$field must be non-negative exact minor units.');
  }
}

void _required(String value, String field) {
  if (value.trim().isEmpty) throw ArgumentError('$field is required.');
}

/// An immutable persistence contract, not an authorized checkout use case.
/// Quantity is positive whole units in schema v1. Fractional units and rounding
/// require a shared server calculation contract before the POS phase.
class SaleLineDraft {
  const SaleLineDraft({
    required this.id,
    required this.productId,
    required this.sku,
    required this.name,
    required this.quantity,
    required this.unitPriceMinor,
    this.discountMinor = 0,
    this.taxMinor = 0,
  });

  final String id;
  final String productId;
  final String sku;
  final String name;
  final int quantity;
  final int unitPriceMinor;
  final int discountMinor;
  final int taxMinor;
  int get subtotalMinor => _exactMinor(
    BigInt.from(quantity) * BigInt.from(unitPriceMinor),
    'Line subtotal',
  );
  int get totalMinor => _exactMinor(
    BigInt.from(subtotalMinor) -
        BigInt.from(discountMinor) +
        BigInt.from(taxMinor),
    'Line total',
  );

  void validate() {
    _required(id, 'Line identifier');
    _required(productId, 'Product identifier');
    _required(sku, 'SKU snapshot');
    _required(name, 'Name snapshot');
    if (quantity <= 0 || quantity > _maximumMinor) {
      throw ArgumentError('Quantity must be positive whole units.');
    }
    _nonNegative(unitPriceMinor, 'Unit price');
    _nonNegative(subtotalMinor, 'Subtotal');
    _nonNegative(discountMinor, 'Discount');
    _nonNegative(taxMinor, 'Tax');
    if (discountMinor > subtotalMinor) {
      throw ArgumentError('Line discount cannot exceed its subtotal.');
    }
    _nonNegative(totalMinor, 'Line total');
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'product_id': productId,
    'sku_snapshot': sku,
    'name_snapshot': name,
    'quantity': quantity,
    'unit_price_minor': unitPriceMinor,
    'discount_minor': discountMinor,
    'tax_minor': taxMinor,
    'line_total_minor': totalMinor,
  };
}

class SalePaymentDraft {
  const SalePaymentDraft({
    required this.id,
    required this.method,
    required this.amountMinor,
    this.reference,
  });

  final String id;
  final String method;
  final int amountMinor;
  final String? reference;

  String get verificationMode => method == 'cash' ? 'cash' : 'manual';

  void validate() {
    _required(id, 'Payment identifier');
    if (!{'cash', 'card', 'gcash', 'maya', 'other'}.contains(method)) {
      throw ArgumentError('Unsupported payment method.');
    }
    _nonNegative(amountMinor, 'Payment');
    if (amountMinor == 0) throw ArgumentError('Payment must be positive.');
    if (reference != null && reference!.length > 200) {
      throw ArgumentError('Payment reference is too long.');
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'method': method,
    'amount_minor': amountMinor,
    'verification_mode': verificationMode,
    'reference': reference,
  };
}

class SaleDraft {
  SaleDraft({
    required this.id,
    required this.eventId,
    required this.scope,
    required this.deviceId,
    required this.shiftId,
    required this.cashierId,
    required this.receiptNumber,
    required this.currency,
    required this.createdAt,
    required List<SaleLineDraft> items,
    required List<SalePaymentDraft> payments,
    this.customerId,
  }) : items = List.unmodifiable(items),
       payments = List.unmodifiable(payments);

  final String id;
  final String eventId;
  final DatabaseScope scope;
  final String deviceId;
  final String shiftId;
  final String cashierId;
  final String? customerId;
  final String receiptNumber;
  final String currency;
  final DateTime createdAt;
  final List<SaleLineDraft> items;
  final List<SalePaymentDraft> payments;

  int get subtotalMinor =>
      _sumMinor(items.map((item) => item.subtotalMinor), 'Sale subtotal');
  int get discountMinor =>
      _sumMinor(items.map((item) => item.discountMinor), 'Sale discount');
  int get taxMinor => _sumMinor(items.map((item) => item.taxMinor), 'Sale tax');
  int get totalMinor => _exactMinor(
    BigInt.from(subtotalMinor) -
        BigInt.from(discountMinor) +
        BigInt.from(taxMinor),
    'Sale total',
  );

  void validate() {
    _required(id, 'Sale identifier');
    _required(deviceId, 'Device identifier');
    _required(shiftId, 'Shift identifier');
    _required(cashierId, 'Cashier identifier');
    _required(receiptNumber, 'Receipt number');
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw ArgumentError('Currency must be a three-letter uppercase code.');
    }
    if (items.isEmpty) {
      throw ArgumentError('A sale requires at least one item.');
    }
    if (items.map((item) => item.id).toSet().length != items.length ||
        payments.map((payment) => payment.id).toSet().length !=
            payments.length) {
      throw ArgumentError('Line and payment identifiers must be unique.');
    }
    for (final item in items) {
      item.validate();
    }
    for (final payment in payments) {
      payment.validate();
    }
    _nonNegative(subtotalMinor, 'Sale subtotal');
    _nonNegative(discountMinor, 'Sale discount');
    _nonNegative(taxMinor, 'Sale tax');
    _nonNegative(totalMinor, 'Sale total');
    final paid = _sumMinor(
      payments.map((payment) => payment.amountMinor),
      'Paid total',
    );
    _nonNegative(paid, 'Paid total');
    if (paid != totalMinor) {
      throw ArgumentError('Payment allocations must equal the sale total.');
    }
  }

  SyncEvent toEvent() => SyncEvent(
    eventId: eventId,
    organizationId: scope.organizationId,
    branchId: scope.branchId,
    deviceId: deviceId,
    actorId: cashierId,
    eventType: 'sale.created',
    occurredAt: createdAt,
    payload: {
      'id': id,
      'shift_id': shiftId,
      'customer_id': customerId,
      'receipt_number': receiptNumber,
      'currency': currency,
      'subtotal_minor': subtotalMinor,
      'discount_minor': discountMinor,
      'tax_minor': taxMinor,
      'total_minor': totalMinor,
      'items': items.map((item) => item.toJson()).toList(),
      'payments': payments.map((payment) => payment.toJson()).toList(),
    },
  );
}
