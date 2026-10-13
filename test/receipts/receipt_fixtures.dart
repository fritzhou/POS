import 'package:nexapos/core/database/database_scope.dart';
import 'package:nexapos/core/database/sale_draft.dart';
import 'package:nexapos/core/sync/outbox_state.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';
import 'package:nexapos/features/offline/domain/offline_workspace.dart';

const receiptFixtureId = 'c1000000-0000-4000-8000-000000000001';
const receiptFixtureOrg = 'c1000000-0000-4000-8000-000000000002';
const receiptFixtureBranch = 'c1000000-0000-4000-8000-000000000003';
const receiptFixtureEvent = 'c1000000-0000-4000-8000-000000000004';
const receiptFixtureLinked = 'c1000000-0000-4000-8000-000000000005';

SaleReceipt saleReceiptFixture({
  String name = 'Original product',
  String businessName = 'Original business',
  String? footer = 'Original footer',
  String? reference = 'MANUAL-REFERENCE',
  int count = 1,
  int quantity = 2,
  int unitPriceMinor = 125,
  int discountMinor = 10,
  int taxMinor = 12,
  int taxBps = 500,
  int? totalMinor,
  int reversedQuantity = 0,
  int reversedMinor = 0,
  CheckoutPaymentMethod method = CheckoutPaymentMethod.card,
  int? tenderedMinor,
  bool omitCashTender = false,
  DateTime? createdAt,
}) {
  final subtotal = count * quantity * unitPriceMinor;
  final total = subtotal - count * discountMinor + count * taxMinor;
  return SaleReceipt(
    id: receiptFixtureId,
    requestId: receiptFixtureId,
    organizationId: receiptFixtureOrg,
    branchId: receiptFixtureBranch,
    shiftId: 'c1000000-0000-4000-8000-000000000006',
    actorUserId: 'c1000000-0000-4000-8000-000000000007',
    receiptNumber: 'ORIGINAL-0001',
    currency: 'PHP',
    createdAt: createdAt ?? DateTime.utc(2026, 10, 12, 3, 4, 5),
    businessName: businessName,
    branchName: 'Original branch',
    address: 'Original address',
    contact: 'Original contact',
    receiptFooter: footer,
    subtotalMinor: subtotal,
    discountMinor: count * discountMinor,
    taxBps: taxBps,
    taxMinor: count * taxMinor,
    totalMinor: totalMinor ?? total,
    items: [
      for (var index = 0; index < count; index++)
        SaleItem(
          id: 'original-line-$index',
          productId: 'original-product-$index',
          name: '$name${count == 1 ? '' : ' ${index + 1}'}',
          sku: 'ORIGINAL-SKU-$index',
          quantity: quantity,
          unitPriceMinor: unitPriceMinor,
          subtotalMinor: quantity * unitPriceMinor,
          discountMinor: discountMinor,
          taxMinor: taxMinor,
          totalMinor: quantity * unitPriceMinor - discountMinor + taxMinor,
          reversedQuantity: reversedQuantity,
        ),
    ],
    payments: [
      SalePayment(
        id: 'original-payment',
        method: method,
        amountMinor: total,
        tenderedMinor: method == CheckoutPaymentMethod.cash
            ? (omitCashTender ? null : (tenderedMinor ?? total + 100))
            : tenderedMinor,
        reference: method == CheckoutPaymentMethod.cash ? null : reference,
        reversedMinor: reversedMinor,
      ),
    ],
  );
}

LocalOfflineReceipt offlineReceiptFixture({
  OutboxStatus status = OutboxStatus.pending,
  String? serverReceiptId,
  DateTime? acceptedAt,
  String? reconciliationCode,
  String? failureCode,
  String name = 'Original offline product',
  CheckoutPaymentMethod method = CheckoutPaymentMethod.cash,
  int quantity = 2,
  int unitPriceMinor = 125,
  int? paymentMinor,
}) => LocalOfflineReceipt(
  draft: SaleDraft(
    id: receiptFixtureId,
    eventId: receiptFixtureEvent,
    scope: DatabaseScope(
      organizationId: receiptFixtureOrg,
      branchId: receiptFixtureBranch,
    ),
    deviceId: 'original-device',
    shiftId: 'original-shift',
    cashierId: 'original-cashier',
    receiptNumber: 'OFFLINE-ORIGINAL-0001',
    currency: 'PHP',
    createdAt: DateTime.utc(2026, 10, 12, 3, 4, 5),
    items: [
      SaleLineDraft(
        id: 'original-offline-line',
        productId: 'original-product',
        sku: 'ORIGINAL-OFFLINE-SKU',
        name: name,
        quantity: quantity,
        unitPriceMinor: unitPriceMinor,
        discountMinor: 10,
        taxMinor: 12,
      ),
    ],
    payments: [
      SalePaymentDraft(
        id: 'original-offline-payment',
        method: method.name,
        amountMinor: paymentMinor ?? quantity * unitPriceMinor + 2,
        reference: method == CheckoutPaymentMethod.cash
            ? null
            : 'ORIGINAL-MANUAL-REFERENCE',
      ),
    ],
  ),
  status: status,
  sequence: 3,
  grantId: 'original-grant',
  businessName: 'Original offline business',
  branchName: 'Original offline branch',
  serverReceiptId: serverReceiptId,
  acceptedAt: acceptedAt,
  reconciliationCode: reconciliationCode,
  failureCode: failureCode,
);
