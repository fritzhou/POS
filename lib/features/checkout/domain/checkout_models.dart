import 'package:uuid/uuid.dart';

import '../../catalog/domain/repository_support.dart';

const maximumExactInteger = 9007199254740991;

String validatePosCurrency(String value) {
  final currency = validateCurrency(value);
  if (!const {
    'PHP',
    'USD',
    'EUR',
    'GBP',
    'AUD',
    'CAD',
    'SGD',
  }.contains(currency)) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Checkout supports PHP, USD, EUR, GBP, AUD, CAD and SGD with two decimal places.',
    );
  }
  return currency;
}

int signedExactInteger(int value) {
  if (BigInt.from(value).abs() > BigInt.from(maximumExactInteger)) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'This transaction is too large.',
    );
  }
  return value;
}

int wholeQuantity(int value) {
  if (value < 1 || value > 1000000) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Enter a whole-unit quantity from 1 to 1,000,000.',
    );
  }
  return value;
}

int checkedAmount(BigInt value) {
  if (value.isNegative || value > BigInt.from(maximumExactInteger)) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'This transaction is too large.',
    );
  }
  return value.toInt();
}

class PosContext {
  const PosContext({
    required this.branchId,
    required this.branchName,
    required this.businessName,
    required this.currency,
    required this.taxBps,
    required this.settingsRevision,
    this.address,
    this.contact,
    this.receiptFooter,
  });
  final String branchId, branchName, businessName, currency;
  final int taxBps, settingsRevision;
  final String? address, contact, receiptFooter;
}

class PosProduct {
  const PosProduct({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.sku,
    required this.priceMinor,
    required this.currency,
    required this.unit,
    required this.revision,
    required this.availableQuantity,
    this.barcode,
    this.categoryId,
    this.costMinor,
    this.imagePath,
    this.active = true,
  });
  final String id, organizationId, name, sku, currency, unit;
  final int priceMinor, revision, availableQuantity;
  final int? costMinor;
  final bool active;
  final String? barcode, categoryId, imagePath;
}

class CartLine {
  const CartLine({required this.product, required this.quantity});
  final PosProduct product;
  final int quantity;
  CartLine withQuantity(int value) =>
      CartLine(product: product, quantity: value);
}

class CalculatedCartLine {
  const CalculatedCartLine({
    required this.line,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.totalMinor,
  });
  final CartLine line;
  final int subtotalMinor, discountMinor, taxMinor, totalMinor;
}

/// Prices are tax exclusive. Sort by UUID, allocate the discount using
/// cumulative integer proportions, then round each net line's tax half-up.
/// BigInt intermediates keep this identical on native Dart and JavaScript.
class CartTotals {
  CartTotals._({
    required List<CalculatedCartLine> lines,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.totalMinor,
  }) : lines = List.unmodifiable(lines);
  final List<CalculatedCartLine> lines;
  final int subtotalMinor, discountMinor, taxMinor, totalMinor;

  factory CartTotals.calculate({
    required List<CartLine> lines,
    required int taxBps,
    int discountMinor = 0,
  }) {
    if (lines.isEmpty || lines.length > 100 || taxBps < 0 || taxBps > 10000) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Choose 1 to 100 products and a valid tax rate.',
      );
    }
    final sorted = [...lines]
      ..sort(
        (a, b) =>
            a.product.id.toLowerCase().compareTo(b.product.id.toLowerCase()),
      );
    final seen = <String>{};
    final currencies = <String>{};
    var subtotal = BigInt.zero;
    for (final line in sorted) {
      validateId(line.product.id);
      if (!seen.add(line.product.id.toLowerCase())) {
        throw const RepositoryFailure(
          RepositoryFailureType.validation,
          'Combine duplicate products into one cart line.',
        );
      }
      currencies.add(validatePosCurrency(line.product.currency));
      validateMinor(line.product.priceMinor);
      wholeQuantity(line.quantity);
      subtotal +=
          BigInt.from(line.product.priceMinor) * BigInt.from(line.quantity);
    }
    if (currencies.length != 1) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Products in a sale must use the same currency.',
      );
    }
    final subtotalMinor = checkedAmount(subtotal);
    validateMinor(discountMinor);
    final discount = BigInt.from(discountMinor);
    if (discount > subtotal) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'The discount cannot exceed the subtotal.',
      );
    }
    var cumulative = BigInt.zero;
    var priorAllocated = BigInt.zero;
    var tax = BigInt.zero;
    final calculated = <CalculatedCartLine>[];
    for (final line in sorted) {
      final base =
          BigInt.from(line.product.priceMinor) * BigInt.from(line.quantity);
      cumulative += base;
      final allocated = subtotal == BigInt.zero
          ? BigInt.zero
          : discount * cumulative ~/ subtotal;
      final lineDiscount = allocated - priorAllocated;
      priorAllocated = allocated;
      final net = base - lineDiscount;
      final lineTax =
          (net * BigInt.from(taxBps) + BigInt.from(5000)) ~/ BigInt.from(10000);
      tax += lineTax;
      calculated.add(
        CalculatedCartLine(
          line: line,
          subtotalMinor: checkedAmount(base),
          discountMinor: checkedAmount(lineDiscount),
          taxMinor: checkedAmount(lineTax),
          totalMinor: checkedAmount(net + lineTax),
        ),
      );
    }
    final total = checkedAmount(subtotal - discount + tax);
    if (total == 0) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Zero-total checkout is not supported yet.',
      );
    }
    return CartTotals._(
      lines: calculated,
      subtotalMinor: subtotalMinor,
      discountMinor: discountMinor,
      taxMinor: checkedAmount(tax),
      totalMinor: total,
    );
  }
}

enum CheckoutPaymentMethod { cash, card, gcash, maya, other }

class CheckoutPayment {
  const CheckoutPayment({
    required this.method,
    required this.amountMinor,
    this.tenderedMinor,
    this.reference,
    this.manualConfirmed = false,
  });
  final CheckoutPaymentMethod method;
  final int amountMinor;
  final int? tenderedMinor;
  final String? reference;
  final bool manualConfirmed;
  Map<String, dynamic> validatedValues() {
    validateMinor(amountMinor);
    if (amountMinor == 0) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'A payment amount must be positive.',
      );
    }
    if (method == CheckoutPaymentMethod.cash) {
      if (tenderedMinor == null ||
          validateMinor(tenderedMinor!) < amountMinor) {
        throw const RepositoryFailure(
          RepositoryFailureType.validation,
          'Cash received must cover the cash payment.',
        );
      }
      return {
        'method': method.name,
        'amount_minor': amountMinor,
        'tendered_minor': tenderedMinor,
      };
    }
    if (!manualConfirmed || tenderedMinor != null) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Confirm the payment manually and enter its reference.',
      );
    }
    return {
      'method': method.name,
      'amount_minor': amountMinor,
      'reference': requiredText(
        reference ?? '',
        'Payment reference',
        120,
        minimum: 3,
      ),
      'manual_confirmed': true,
    };
  }
}

class CheckoutItem {
  const CheckoutItem({
    required this.productId,
    required this.quantity,
    required this.expectedRevision,
  });
  factory CheckoutItem.fromCart(CartLine line) => CheckoutItem(
    productId: line.product.id,
    quantity: line.quantity,
    expectedRevision: line.product.revision,
  );
  final String productId;
  final int quantity, expectedRevision;
  Map<String, dynamic> validatedValues() => {
    'product_id': validateId(productId).toLowerCase(),
    'quantity': wholeQuantity(quantity),
    'expected_revision': validateRevision(expectedRevision),
  };
}

/// Construct once when the operator confirms payment. Retain this object after
/// a timeout and reconcile/retry the same request; a new UUID can create a sale.
class CheckoutRequest {
  CheckoutRequest({
    required this.branchId,
    required this.shiftId,
    required this.expectedSettingsRevision,
    required List<CheckoutItem> items,
    required List<CheckoutPayment> payments,
    String? requestId,
    this.discountMinor = 0,
    this.reason,
    this.customerId,
  }) : requestId = requestId ?? const Uuid().v4(),
       items = List.unmodifiable(items),
       payments = List.unmodifiable(payments);
  final String requestId, branchId, shiftId;
  final int expectedSettingsRevision, discountMinor;
  final List<CheckoutItem> items;
  final List<CheckoutPayment> payments;
  final String? reason, customerId;
  Map<String, dynamic> validatedPayload() {
    validateId(requestId);
    validateId(branchId);
    validateId(shiftId);
    validateRevision(expectedSettingsRevision);
    validateMinor(discountMinor);
    if (items.isEmpty ||
        items.length > 100 ||
        payments.isEmpty ||
        payments.length > 5) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Choose 1 to 100 products and 1 to 5 payments.',
      );
    }
    final sorted = [...items]
      ..sort(
        (a, b) =>
            a.productId.toLowerCase().compareTo(b.productId.toLowerCase()),
      );
    if (sorted.map((i) => i.productId.toLowerCase()).toSet().length !=
        sorted.length) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Combine duplicate products into one cart line.',
      );
    }
    checkedAmount(
      payments.fold(BigInt.zero, (sum, p) => sum + BigInt.from(p.amountMinor)),
    );
    return {
      'shift_id': shiftId,
      'expected_settings_revision': expectedSettingsRevision,
      'items': sorted.map((i) => i.validatedValues()).toList(growable: false),
      'discount_minor': discountMinor,
      'payments': payments
          .map((p) => p.validatedValues())
          .toList(growable: false),
      'reason': discountMinor > 0
          ? requiredText(reason ?? '', 'Discount reason', 1000, minimum: 3)
          : optionalText(reason, 'Reason', 1000),
      'customer_id': validateOptionalId(customerId),
    };
  }
}

class Shift {
  const Shift({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.actorUserId,
    required this.openedAt,
    required this.openingCashMinor,
    required this.expectedCashMinor,
    required this.currency,
    this.closedAt,
    this.countedCashMinor,
    this.cashDifferenceMinor,
    this.closedBy,
  });
  final String id, organizationId, branchId, actorUserId, currency;
  final DateTime openedAt;
  final DateTime? closedAt;
  final int openingCashMinor, expectedCashMinor;
  final int? countedCashMinor, cashDifferenceMinor;
  final String? closedBy;
  bool get isOpen => closedAt == null;
}

class OpenShiftRequest {
  OpenShiftRequest({
    required this.branchId,
    required this.openingCashMinor,
    required this.expectedCurrency,
    String? requestId,
  }) : requestId = requestId ?? const Uuid().v4();
  final String requestId, branchId, expectedCurrency;
  final int openingCashMinor;
}

class CloseShiftRequest {
  CloseShiftRequest({
    required this.branchId,
    required this.shiftId,
    required this.countedCashMinor,
    required this.reason,
    String? requestId,
  }) : requestId = requestId ?? const Uuid().v4();
  final String requestId, branchId, shiftId, reason;
  final int countedCashMinor;
}

class SaleItem {
  const SaleItem({
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
  int get refundableQuantity => quantity - reversedQuantity;
}

class SalePayment {
  const SalePayment({
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
  int get refundableMinor => amountMinor - reversedMinor;
  int get changeMinor => method == CheckoutPaymentMethod.cash
      ? (tenderedMinor ?? amountMinor) - amountMinor
      : 0;
}

class SaleReceipt {
  SaleReceipt({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.shiftId,
    required this.actorUserId,
    required this.receiptNumber,
    required this.currency,
    required this.createdAt,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxBps,
    required this.taxMinor,
    required this.totalMinor,
    required List<SaleItem> items,
    required List<SalePayment> payments,
    this.businessName,
    this.branchName,
    this.address,
    this.contact,
    this.receiptFooter,
    this.requestId,
  }) : items = List.unmodifiable(items),
       payments = List.unmodifiable(payments);
  final String id,
      organizationId,
      branchId,
      shiftId,
      actorUserId,
      receiptNumber,
      currency;
  final String? requestId,
      businessName,
      branchName,
      address,
      contact,
      receiptFooter;
  final DateTime createdAt;
  final int subtotalMinor, discountMinor, taxBps, taxMinor, totalMinor;
  final List<SaleItem> items;
  final List<SalePayment> payments;
}

enum SaleReversalKind { refund, voidSale }

class ReversalItem {
  const ReversalItem({required this.saleItemId, required this.quantity});
  final String saleItemId;
  final int quantity;
}

class ReversalPayment {
  const ReversalPayment({
    required this.originalPaymentId,
    required this.amountMinor,
    required this.manualConfirmed,
    this.reference,
  });
  final String originalPaymentId;
  final int amountMinor;
  final bool manualConfirmed;
  final String? reference;
}

class ReversalRequest {
  ReversalRequest({
    required this.branchId,
    required this.saleId,
    required this.shiftId,
    required this.kind,
    required List<ReversalItem> items,
    required List<ReversalPayment> payments,
    required this.reason,
    required this.returnStock,
    String? requestId,
  }) : requestId = requestId ?? const Uuid().v4(),
       items = List.unmodifiable(items),
       payments = List.unmodifiable(payments);
  final String requestId, branchId, saleId, shiftId, reason;
  final SaleReversalKind kind;
  final bool returnStock;
  final List<ReversalItem> items;
  final List<ReversalPayment> payments;
}

class SaleReversal {
  const SaleReversal({
    required this.id,
    required this.saleId,
    required this.kind,
    required this.totalMinor,
    required this.createdAt,
    required this.reason,
    required this.returnStock,
    this.sale,
  });
  final String id, saleId, reason;
  final SaleReversalKind kind;
  final bool returnStock;
  final int totalMinor;
  final DateTime createdAt;
  final SaleReceipt? sale;
}
