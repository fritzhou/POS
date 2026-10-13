import '../../catalog/domain/repository_support.dart';

const logisticsMax = 9007199254740991;
int logisticsInteger(Object? value, {int min = 0, int max = logisticsMax}) {
  if (value is! int || value < min || value > max) {
    throw const FormatException('Invalid exact logistics integer');
  }
  return value;
}

String logisticsId(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid logistics identifier');
  }
  return validateId(value).toLowerCase();
}

String logisticsText(Object? value, int max, {int min = 1}) {
  if (value is! String ||
      value != value.trim() ||
      value.length < min ||
      value.length > max) {
    throw const FormatException('Invalid logistics text');
  }
  return value;
}

DateTime logisticsTime(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$',
      ).hasMatch(value)) {
    throw const FormatException('Expected UTC logistics time');
  }
  final time = DateTime.parse(value);
  if (!time.isUtc ||
      time.toIso8601String().substring(0, 19) != value.substring(0, 19)) {
    throw const FormatException('Invalid UTC calendar');
  }
  return time;
}

Map<String, dynamic> logisticsRow(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected logistics record');
  }
  return value;
}

List<Map<String, dynamic>> logisticsRows(Object? value, {int max = 101}) {
  if (value is! List || value.length > max) {
    throw const FormatException('Invalid bounded logistics list');
  }
  return value.map(logisticsRow).toList(growable: false);
}

void logisticsCheck(bool condition) {
  if (!condition) {
    throw const FormatException('Logistics evidence is inconsistent');
  }
}

class ManagedBranch {
  ManagedBranch.fromRow(Map<String, dynamic> row)
    : id = logisticsId(row['id']),
      organizationId = logisticsId(row['organization_id']),
      name = logisticsText(row['name'], 120),
      code = logisticsText(row['code'], 32),
      address = row['address'] == null
          ? null
          : logisticsText(row['address'], 65536),
      active = row['active'] as bool,
      revision = logisticsInteger(row['revision'], min: 1),
      createdAt = logisticsTime(row['created_at']);
  final String id, organizationId, name, code;
  final String? address;
  final bool active;
  final int revision;
  final DateTime createdAt;
}

class LogisticsLine {
  const LogisticsLine({
    required this.id,
    required this.productId,
    required this.name,
    required this.sku,
    required this.unit,
    required this.expectedRevision,
    required this.quantity,
    this.received = 0,
    this.returned = 0,
    this.unitCostMinor,
    this.onHand,
    this.currentUnit,
  });
  final String id, productId, name, sku, unit;
  final String? currentUnit;
  final int expectedRevision, quantity, received, returned;
  final int? unitCostMinor, onHand;
  int get remaining => quantity - received - returned;
  Map<String, dynamic> proof() => {
    'item_id': id,
    'product_id': productId,
    'unit': unit,
    if (unitCostMinor != null) 'unit_cost_minor': unitCostMinor,
  };
  factory LogisticsLine.fromRow(
    Map<String, dynamic> row, {
    bool purchase = false,
  }) {
    final quantity = logisticsInteger(row['quantity'], min: 1, max: 1000000);
    final received = purchase ? 0 : logisticsInteger(row['received']);
    final returned = logisticsInteger(row['returned']);
    logisticsCheck(received + returned <= quantity);
    if (!purchase) {
      logisticsCheck(
        logisticsInteger(row['remaining']) == quantity - received - returned,
      );
    }
    final cost = purchase ? logisticsInteger(row['unit_cost_minor']) : null;
    if (cost != null) {
      logisticsCheck(
        BigInt.from(cost) * BigInt.from(quantity) <= BigInt.from(logisticsMax),
      );
    }
    return LogisticsLine(
      id: logisticsId(row[purchase ? 'item_id' : 'id']),
      productId: logisticsId(row['product_id']),
      name: logisticsText(row['product_name'], 160),
      sku: logisticsText(row['sku'], 64),
      unit: logisticsText(row['unit'], 32),
      currentUnit: logisticsText(row['current_unit'], 32),
      expectedRevision: logisticsInteger(row['expected_revision'], min: 1),
      quantity: quantity,
      received: received,
      returned: returned,
      unitCostMinor: cost,
      onHand: purchase
          ? logisticsInteger(row['on_hand'], min: -logisticsMax)
          : null,
    );
  }
}

class StockTransfer {
  StockTransfer.fromRow(Map<String, dynamic> row)
    : id = logisticsId(row['id']),
      organizationId = logisticsId(row['organization_id']),
      sourceBranchId = logisticsId(row['source_branch_id']),
      destinationBranchId = logisticsId(row['destination_branch_id']),
      sourceName = logisticsText(row['source_name'], 120),
      destinationName = logisticsText(row['destination_name'], 120),
      status = logisticsText(row['status'], 32),
      revision = logisticsInteger(row['revision'], min: 1),
      createdAt = logisticsTime(row['created_at']),
      lines = row['items'] == null
          ? const []
          : List.unmodifiable(
              logisticsRows(
                row['items'],
                max: 100,
              ).map((r) => LogisticsLine.fromRow(r)),
            ) {
    logisticsCheck(
      sourceBranchId != destinationBranchId &&
          {
            'in_transit',
            'partially_completed',
            'received',
            'returned',
            'completed',
          }.contains(status),
    );
    logisticsCheck(
      logisticsInteger(row['line_count'], min: 1, max: 100) ==
          (row['items'] == null ? row['line_count'] : lines.length),
    );
    logisticsCheck(
      lines.map((l) => l.id).toSet().length == lines.length &&
          lines.map((l) => l.productId).toSet().length == lines.length,
    );
    if (lines.isNotEmpty) {
      final expected = lines.any((l) => l.remaining > 0)
          ? (lines.any((l) => l.received + l.returned > 0)
                ? 'partially_completed'
                : 'in_transit')
          : lines.every((l) => l.returned == 0)
          ? 'received'
          : lines.every((l) => l.received == 0)
          ? 'returned'
          : 'completed';
      logisticsCheck(status == expected);
    }
  }
  final String id,
      organizationId,
      sourceBranchId,
      destinationBranchId,
      sourceName,
      destinationName,
      status;
  final int revision;
  final DateTime createdAt;
  final List<LogisticsLine> lines;
}

class PurchaseReturnContext {
  PurchaseReturnContext.fromRow(Map<String, dynamic> row)
    : organizationId = logisticsId(row['organization_id']),
      branchId = logisticsId(row['branch_id']),
      receiptId = logisticsId(row['receipt_id']),
      currency = logisticsText(row['currency'], 3),
      lines = List.unmodifiable(
        logisticsRows(
          row['items'],
          max: 100,
        ).map((r) => LogisticsLine.fromRow(r, purchase: true)),
      ) {
    logisticsCheck(
      {'PHP', 'USD', 'EUR', 'GBP', 'AUD', 'CAD', 'SGD'}.contains(currency) &&
          lines.isNotEmpty &&
          lines.map((l) => l.id).toSet().length == lines.length,
    );
  }
  final String organizationId, branchId, receiptId, currency;
  final List<LogisticsLine> lines;
}

class LogisticsAction {
  LogisticsAction.fromRow(Map<String, dynamic> row)
    : requestId = logisticsId(row['request_id']),
      organizationId = logisticsId(row['organization_id']),
      branchId = logisticsId(row['branch_id']),
      actorId = logisticsId(row['actor_id']),
      kind = logisticsText(row['kind'], 32),
      document = Map.unmodifiable(logisticsRow(row['document'])) {
    logisticsId(document['id']);
    logisticsTime(document['created_at']);
  }
  final String requestId, organizationId, branchId, actorId, kind;
  final Map<String, dynamic> document;
}
