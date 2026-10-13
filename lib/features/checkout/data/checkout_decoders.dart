import '../../catalog/data/supabase_repository_support.dart';
import '../../catalog/domain/repository_support.dart';
import '../domain/checkout_models.dart';

int amountFrom(Object? value) => validateMinor(integerFrom(value));

PosContext contextFromRow(Map<String, dynamic> row) => PosContext(
  branchId: validateId(row['branch_id'] as String),
  branchName: row['branch_name'] as String,
  businessName: row['business_name'] as String,
  currency: validatePosCurrency(row['currency'] as String),
  taxBps: amountFrom(row['tax_bps']),
  settingsRevision: validateRevision(integerFrom(row['settings_revision'])),
  address: row['address'] as String?,
  contact: row['contact'] as String?,
  receiptFooter: row['receipt_footer'] as String?,
);

PosProduct posProductFromRow(Map<String, dynamic> row) => PosProduct(
  id: validateId(row['id'] as String),
  organizationId: validateId(row['organization_id'] as String),
  name: row['name'] as String,
  sku: row['sku'] as String,
  priceMinor: amountFrom(row['price_minor']),
  currency: validateCurrency(row['currency'] as String),
  unit: row['unit'] as String,
  revision: validateRevision(integerFrom(row['revision'])),
  availableQuantity: amountFrom(row['available_quantity']),
  costMinor: row['cost_minor'] == null ? null : amountFrom(row['cost_minor']),
  barcode: row['barcode'] as String?,
  categoryId: row['category_id'] as String?,
  imagePath: row['image_path'] as String?,
  active: row['active'] as bool? ?? true,
);

Shift shiftFromRow(Map<String, dynamic> row) {
  final closure = row['closure'] == null ? null : rowFrom(row['closure']);
  return Shift(
    id: validateId(row['id'] as String),
    organizationId: validateId(row['organization_id'] as String),
    branchId: validateId(row['branch_id'] as String),
    actorUserId: validateId(row['actor_user_id'] as String),
    currency: validatePosCurrency(row['currency'] as String),
    openedAt: DateTime.parse(row['opened_at'] as String),
    openingCashMinor: amountFrom(row['opening_cash_minor']),
    expectedCashMinor: signedExactInteger(
      integerFrom(
        row['expected_cash_minor'] ?? closure?['expected_cash_minor'],
      ),
    ),
    closedAt: closure == null
        ? null
        : DateTime.parse(closure['closed_at'] as String),
    countedCashMinor: closure == null
        ? null
        : amountFrom(closure['counted_cash_minor']),
    cashDifferenceMinor: closure == null
        ? null
        : signedExactInteger(integerFrom(closure['difference_minor'])),
    closedBy: closure?['closed_by'] as String?,
  );
}

CheckoutPaymentMethod paymentMethodFrom(Object? value) =>
    CheckoutPaymentMethod.values.firstWhere((method) => method.name == value);

SaleReceipt _receiptFromRow(Map<String, dynamic> row) => SaleReceipt(
  id: validateId(row['id'] as String),
  organizationId: validateId(row['organization_id'] as String),
  branchId: validateId(row['branch_id'] as String),
  shiftId: validateId(row['shift_id'] as String),
  actorUserId: validateId(row['actor_user_id'] as String),
  receiptNumber: row['receipt_number'] as String,
  requestId: row['request_id'] == null
      ? null
      : validateId(row['request_id'] as String),
  currency: validatePosCurrency(row['currency'] as String),
  createdAt: DateTime.parse(row['created_at'] as String),
  subtotalMinor: amountFrom(row['subtotal_minor']),
  discountMinor: amountFrom(row['discount_minor']),
  taxBps: amountFrom(row['tax_bps']),
  taxMinor: amountFrom(row['tax_minor']),
  totalMinor: amountFrom(row['total_minor']),
  businessName: row['business_name'] as String?,
  branchName: row['branch_name'] as String?,
  address: row['address'] as String?,
  contact: row['contact'] as String?,
  receiptFooter: row['receipt_footer'] as String?,
  items: rowsFrom(row['items'])
      .map(
        (item) => SaleItem(
          id: validateId(item['id'] as String),
          productId: validateId(item['product_id'] as String),
          name: item['product_name'] as String,
          sku: item['sku'] as String,
          quantity: wholeQuantity(integerFrom(item['quantity'])),
          unitPriceMinor: amountFrom(item['unit_price_minor']),
          subtotalMinor: amountFrom(item['line_subtotal_minor']),
          discountMinor: amountFrom(item['discount_minor']),
          taxMinor: amountFrom(item['tax_minor']),
          totalMinor: amountFrom(item['line_total_minor']),
          reversedQuantity: amountFrom(item['reversed_quantity'] ?? 0),
        ),
      )
      .toList(growable: false),
  payments: rowsFrom(row['payments'])
      .map(
        (payment) => SalePayment(
          id: validateId(payment['id'] as String),
          method: paymentMethodFrom(payment['method']),
          amountMinor: amountFrom(payment['amount_minor']),
          tenderedMinor: payment['tendered_minor'] == null
              ? null
              : amountFrom(payment['tendered_minor']),
          reference: payment['reference'] as String?,
          reversedMinor: amountFrom(payment['reversed_minor'] ?? 0),
        ),
      )
      .toList(growable: false),
);

SaleReceipt receiptFromRow(Map<String, dynamic> row) {
  final receipt = _receiptFromRow(row);
  if (receipt.requestId == null ||
      receipt.items.isEmpty ||
      receipt.items.length > 100 ||
      receipt.payments.isEmpty ||
      receipt.payments.length > 5 ||
      receipt.totalMinor <= 0 ||
      receipt.taxBps > 10000) {
    throw const FormatException('Invalid financial receipt');
  }
  final calculated = CartTotals.calculate(
    lines: receipt.items
        .map(
          (item) => CartLine(
            product: PosProduct(
              id: item.productId,
              organizationId: receipt.organizationId,
              name: item.name,
              sku: item.sku,
              priceMinor: item.unitPriceMinor,
              currency: receipt.currency,
              unit: 'each',
              revision: 1,
              availableQuantity: 0,
            ),
            quantity: item.quantity,
          ),
        )
        .toList(growable: false),
    taxBps: receipt.taxBps,
    discountMinor: receipt.discountMinor,
  );
  if (calculated.subtotalMinor != receipt.subtotalMinor ||
      calculated.taxMinor != receipt.taxMinor ||
      calculated.totalMinor != receipt.totalMinor) {
    throw const FormatException('Inconsistent receipt totals');
  }
  final linesByProduct = {
    for (final line in calculated.lines) line.line.product.id: line,
  };
  for (final item in receipt.items) {
    final line = linesByProduct[item.productId]!;
    if (item.subtotalMinor != line.subtotalMinor ||
        item.discountMinor != line.discountMinor ||
        item.taxMinor != line.taxMinor ||
        item.totalMinor != line.totalMinor ||
        item.reversedQuantity > item.quantity) {
      throw const FormatException('Inconsistent receipt line');
    }
  }
  final seen = <String>{};
  var paid = BigInt.zero;
  final rawPayments = rowsFrom(row['payments']);
  for (var index = 0; index < receipt.payments.length; index++) {
    final payment = receipt.payments[index];
    if (!seen.add(payment.id) ||
        payment.amountMinor <= 0 ||
        payment.reversedMinor > payment.amountMinor) {
      throw const FormatException('Invalid receipt payment');
    }
    paid += BigInt.from(payment.amountMinor);
    if (payment.method == CheckoutPaymentMethod.cash) {
      if (payment.tenderedMinor == null ||
          payment.tenderedMinor! < payment.amountMinor ||
          payment.reference != null ||
          rawPayments[index]['manual_confirmed'] == true) {
        throw const FormatException('Invalid cash payment');
      }
    } else if (payment.tenderedMinor != null ||
        rawPayments[index]['manual_confirmed'] != true ||
        (payment.reference?.trim().length ?? 0) < 3 ||
        payment.reference!.trim().length > 120) {
      throw const FormatException('Unconfirmed manual payment');
    }
  }
  if (paid != BigInt.from(receipt.totalMinor)) {
    throw const FormatException('Inconsistent payment total');
  }
  return receipt;
}

SaleReversal reversalFromRow(Map<String, dynamic> row) => SaleReversal(
  id: validateId(row['id'] as String),
  saleId: validateId(row['sale_id'] as String),
  kind: switch (row['kind']) {
    'refund' => SaleReversalKind.refund,
    'void' => SaleReversalKind.voidSale,
    _ => throw const FormatException('Unknown reversal'),
  },
  totalMinor: amountFrom(row['total_minor']),
  createdAt: DateTime.parse(row['created_at'] as String),
  reason: row['reason'] as String,
  returnStock: row['return_stock'] as bool,
  sale: row['sale'] == null ? null : receiptFromRow(rowFrom(row['sale'])),
);
