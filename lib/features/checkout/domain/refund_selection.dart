import '../../catalog/domain/repository_support.dart';
import 'checkout_models.dart';

class RefundPaymentAllocation {
  const RefundPaymentAllocation({
    required this.originalPayment,
    required this.amountMinor,
  });
  final SalePayment originalPayment;
  final int amountMinor;
}

/// Cumulative integer proportions of each original tax-inclusive line total.
/// Neither today's prices nor today's tax settings affect the amount.
class RefundSelection {
  RefundSelection._({
    required List<ReversalItem> items,
    required List<RefundPaymentAllocation> allocations,
    required this.totalMinor,
  }) : items = List.unmodifiable(items),
       allocations = List.unmodifiable(allocations);

  final List<ReversalItem> items;
  final List<RefundPaymentAllocation> allocations;
  final int totalMinor;

  factory RefundSelection.calculate({
    required SaleReceipt receipt,
    required Map<String, int> quantities,
  }) {
    if (receipt.totalMinor <= 0) {
      _invalid('The original receipt total could not be confirmed.');
    }
    checkedAmount(BigInt.from(receipt.totalMinor));
    final originalItems = [...receipt.items]
      ..sort((a, b) => a.id.toLowerCase().compareTo(b.id.toLowerCase()));
    final originalPayments = [...receipt.payments]
      ..sort((a, b) => a.id.toLowerCase().compareTo(b.id.toLowerCase()));
    final itemIds = <String>{};
    final selected = <String, int>{};
    for (final entry in quantities.entries) {
      final id = validateId(entry.key).toLowerCase();
      if (selected.containsKey(id)) _invalid('Choose each receipt item once.');
      selected[id] = entry.value;
    }
    var total = BigInt.zero;
    var originalTotal = BigInt.zero;
    final items = <ReversalItem>[];
    for (final item in originalItems) {
      final id = validateId(item.id).toLowerCase();
      if (!itemIds.add(id) ||
          item.quantity < 1 ||
          item.quantity > 1000000 ||
          item.reversedQuantity < 0 ||
          item.reversedQuantity > item.quantity ||
          item.unitPriceMinor < 0 ||
          BigInt.from(item.subtotalMinor) !=
              BigInt.from(item.unitPriceMinor) * BigInt.from(item.quantity) ||
          item.subtotalMinor < 0 ||
          item.discountMinor < 0 ||
          item.discountMinor > item.subtotalMinor ||
          item.taxMinor < 0 ||
          item.totalMinor !=
              item.subtotalMinor - item.discountMinor + item.taxMinor) {
        _invalid('The receipt item amounts could not be confirmed.');
      }
      final lineTotal = BigInt.from(item.totalMinor);
      checkedAmount(lineTotal);
      originalTotal += lineTotal;
      final quantity = selected[id] ?? 0;
      if (quantity < 0 || quantity > item.refundableQuantity) {
        _invalid('Choose whole units within the remaining receipt quantity.');
      }
      if (quantity == 0) continue;
      final originalQuantity = BigInt.from(item.quantity);
      final used = BigInt.from(item.reversedQuantity);
      total +=
          lineTotal * (used + BigInt.from(quantity)) ~/ originalQuantity -
          lineTotal * used ~/ originalQuantity;
      items.add(ReversalItem(saleItemId: item.id, quantity: quantity));
    }
    if (selected.keys.any((id) => !itemIds.contains(id))) {
      _invalid('Choose items from this original receipt.');
    }
    if (items.isEmpty || items.length > 100) {
      _invalid('Choose at least one remaining unit to refund.');
    }
    if (originalTotal != BigInt.from(receipt.totalMinor)) {
      _invalid('The original receipt total could not be confirmed.');
    }
    final totalMinor = checkedAmount(total);
    var remaining = total;
    var paid = BigInt.zero;
    final paymentIds = <String>{};
    final allocations = <RefundPaymentAllocation>[];
    for (final payment in originalPayments) {
      final id = validateId(payment.id).toLowerCase();
      if (!paymentIds.add(id) ||
          payment.amountMinor <= 0 ||
          payment.reversedMinor < 0 ||
          payment.reversedMinor > payment.amountMinor) {
        _invalid('The original payment amounts could not be confirmed.');
      }
      checkedAmount(BigInt.from(payment.amountMinor));
      paid += BigInt.from(payment.amountMinor);
      final cap = BigInt.from(payment.refundableMinor);
      final allocated = remaining < cap ? remaining : cap;
      if (allocated > BigInt.zero) {
        allocations.add(
          RefundPaymentAllocation(
            originalPayment: payment,
            amountMinor: checkedAmount(allocated),
          ),
        );
        remaining -= allocated;
      }
    }
    if (remaining != BigInt.zero ||
        paid != originalTotal ||
        originalPayments.length > 5) {
      _invalid('The payout exceeds the remaining original payments.');
    }
    return RefundSelection._(
      items: items,
      allocations: allocations,
      totalMinor: totalMinor,
    );
  }
}

Never _invalid(String message) =>
    throw RepositoryFailure(RepositoryFailureType.validation, message);
