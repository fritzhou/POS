import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../core/auth/auth_models.dart';
import '../../../core/operations/operation_journal.dart';
import '../../../core/security/app_role.dart';
import '../../catalog/data/supabase_repository_support.dart';
import '../../catalog/domain/repository_support.dart';
import '../../checkout/data/operation_executor.dart';
import '../domain/logistics_models.dart';

const logisticsFunctions = {
  'save_branch',
  'dispatch_stock_transfer',
  'complete_stock_transfer',
  'return_purchase_receipt',
};
const _proofKey = '_nexapos_logistics_proof';

class SupabaseLogisticsRepository {
  SupabaseLogisticsRepository({
    required SupabaseClient client,
    required AuthenticatedUser actor,
    required this.journal,
    bool Function()? isRecoverySession,
  }) : scope = SupabaseRepositoryScope(
         client: client,
         actor: actor,
         isRecoverySession: isRecoverySession,
       );
  final SupabaseRepositoryScope scope;
  final OperationJournal journal;
  late final _executor = OperationExecutor(
    scope,
    journal,
    allowHistoricalJournalBranch: true,
  );
  String get organizationId => scope.actor.organizationId;
  Set<String> get branchIds => scope.actor.branchIds;
  bool get canMaintainBranches =>
      scope.actor.role == AppRole.owner || scope.actor.role == AppRole.admin;
  Future<T> _read<T>(
    String rpc,
    Map<String, dynamic> params,
    T Function(Object?) decode,
  ) => scope.safe(
    () async => decode(
      await scope.client.rpc(
        rpc,
        params: {'p_organization_id': organizationId, ...params},
      ),
    ),
  );
  void _branch(String branch) {
    if (!scope.actor.role.allows(AppPermission.viewInventory)) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Current inventory access is required.',
      );
    }
    validateId(branch);
    if (!branchIds.contains(branch)) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Choose a verified active branch.',
      );
    }
  }

  Future<Map<String, dynamic>> branchContext() =>
      _read('get_branch_management_context', {}, (value) {
        final row = logisticsRow(value);
        logisticsCheck(
          row['organization_id'] == organizationId &&
              row['actor_id'] == scope.actor.userId &&
              row['can_create'] is bool &&
              row['can_set_active'] is bool &&
              row['maximum_active_branches'] == 100,
        );
        return row;
      });
  Future<DataPage<ManagedBranch>> branches({
    PageRequest page = const PageRequest(),
  }) {
    page.validate();
    return _read(
      'list_managed_branches',
      {'p_offset': page.offset, 'p_limit': page.limit + 1},
      (value) {
        final rows = logisticsRows(
          value,
          max: page.limit + 1,
        ).map(ManagedBranch.fromRow).toList();
        logisticsCheck(
          rows.every((b) => b.organizationId == organizationId) &&
              rows.map((b) => b.id).toSet().length == rows.length,
        );
        return DataPage(
          items: rows.take(page.limit).toList(),
          hasMore: rows.length > page.limit,
          offset: page.offset,
        );
      },
    );
  }

  Future<DataPage<StockTransfer>> transfers(
    String branch, {
    PageRequest page = const PageRequest(),
  }) {
    _branch(branch);
    page.validate();
    return _read(
      'list_stock_transfers',
      {
        'p_branch_id': branch,
        'p_offset': page.offset,
        'p_limit': page.limit + 1,
      },
      (value) {
        final rows = logisticsRows(
          value,
          max: page.limit + 1,
        ).map(StockTransfer.fromRow).toList();
        logisticsCheck(
          rows.every(
                (t) =>
                    t.organizationId == organizationId &&
                    (t.sourceBranchId == branch ||
                        t.destinationBranchId == branch),
              ) &&
              rows.map((t) => t.id).toSet().length == rows.length,
        );
        return DataPage(
          items: rows.take(page.limit).toList(),
          hasMore: rows.length > page.limit,
          offset: page.offset,
        );
      },
    );
  }

  Future<StockTransfer> transfer(String branch, String id) => _read(
    'get_stock_transfer',
    {'p_branch_id': validateId(branch), 'p_transfer_id': validateId(id)},
    (value) {
      final t = StockTransfer.fromRow(logisticsRow(value));
      logisticsCheck(
        t.id == id &&
            t.organizationId == organizationId &&
            (t.sourceBranchId == branch || t.destinationBranchId == branch),
      );
      return t;
    },
  );
  Future<DataPage<Map<String, dynamic>>> events(
    String branch,
    String id, {
    PageRequest page = const PageRequest(),
  }) {
    page.validate();
    return _read(
      'list_stock_transfer_events',
      {
        'p_branch_id': validateId(branch),
        'p_transfer_id': validateId(id),
        'p_offset': page.offset,
        'p_limit': page.limit + 1,
      },
      (value) {
        final rows = logisticsRows(value, max: page.limit + 1);
        for (final r in rows) {
          logisticsCheck(
            r['organization_id'] == organizationId &&
                r['transfer_id'] == id &&
                const {
                  'transfer.receive',
                  'transfer.return',
                }.contains(r['kind']),
          );
          logisticsId(r['id']);
          logisticsId(r['branch_id']);
          logisticsTime(r['created_at']);
          final lines = logisticsRows(r['items'], max: 100);
          logisticsCheck(lines.isNotEmpty);
          for (final l in lines) {
            logisticsId(l['item_id']);
            logisticsId(l['product_id']);
            logisticsInteger(l['quantity'], min: 1, max: 1000000);
            logisticsText(l['unit'], 32);
          }
        }
        return DataPage(
          items: rows.take(page.limit).toList(),
          hasMore: rows.length > page.limit,
          offset: page.offset,
        );
      },
    );
  }

  Future<PurchaseReturnContext> returnContext(String branch, String receipt) =>
      _read(
        'get_purchase_receipt_return_context',
        {
          'p_branch_id': validateId(branch),
          'p_receipt_id': validateId(receipt),
        },
        (value) {
          final c = PurchaseReturnContext.fromRow(logisticsRow(value));
          logisticsCheck(
            c.organizationId == organizationId &&
                c.branchId == branch &&
                c.receiptId == receipt,
          );
          return c;
        },
      );
  Future<DataPage<LogisticsAction>> returns(
    String branch, {
    PageRequest page = const PageRequest(),
  }) {
    _branch(branch);
    page.validate();
    return _read(
      'list_purchase_returns',
      {
        'p_branch_id': branch,
        'p_offset': page.offset,
        'p_limit': page.limit + 1,
      },
      (value) {
        final rows = logisticsRows(
          value,
          max: page.limit + 1,
        ).map(LogisticsAction.fromRow).toList();
        logisticsCheck(
          rows.every(
            (a) =>
                a.organizationId == organizationId &&
                a.branchId == branch &&
                a.kind == 'supplier.return',
          ),
        );
        logisticsCheck(
          rows.map((a) => a.requestId).toSet().length == rows.length,
        );
        for (final a in rows) {
          logisticsCheck(
            const {
              'PHP',
              'USD',
              'EUR',
              'GBP',
              'AUD',
              'CAD',
              'SGD',
            }.contains(a.document['currency']),
          );
          logisticsId(a.document['receipt_id']);
          logisticsId(a.document['operation_id']);
          final total = logisticsInteger(a.document['total_minor']);
          final lines = logisticsRows(a.document['items'], max: 100);
          logisticsCheck(
            lines.isNotEmpty &&
                lines.map((l) => l['item_id']).toSet().length == lines.length &&
                lines.map((l) => l['movement_id']).toSet().length ==
                    lines.length,
          );
          var sum = BigInt.zero;
          for (final l in lines) {
            final cost =
                BigInt.from(
                  logisticsInteger(l['quantity'], min: 1, max: 1000000),
                ) *
                BigInt.from(logisticsInteger(l['unit_cost_minor']));
            logisticsCheck(
              cost == BigInt.from(logisticsInteger(l['line_cost_minor'])),
            );
            sum += cost;
            logisticsId(l['item_id']);
            logisticsId(l['product_id']);
            logisticsText(l['unit'], 32);
            logisticsId(l['movement_id']);
          }
          logisticsCheck(sum == BigInt.from(total));
        }
        return DataPage(
          items: rows.take(page.limit).toList(),
          hasMore: rows.length > page.limit,
          offset: page.offset,
        );
      },
    );
  }

  Future<List<PendingOperation>> pending() => scope.safe(
    () async => (await _executor.pending())
        .where((p) => logisticsFunctions.contains(p.type))
        .toList(),
  );
  Future<Object> retry(PendingOperation op) => scope.safe(() async {
    logisticsCheck(
      op.organizationId == organizationId &&
          op.actorId == scope.actor.userId &&
          op.status == LocalOperationStatus.pending &&
          logisticsFunctions.contains(op.type) &&
          op.payload['p_organization_id'] == organizationId &&
          op.payload['p_request_id'] == op.requestId,
    );
    return _submit(op.type, op.branchId, Map.from(op.payload));
  });
  Future<Object> saveBranch({
    required String anchor,
    ManagedBranch? original,
    required String name,
    required String code,
    String? address,
    required bool active,
    required String reason,
    String? requestId,
  }) {
    if (!canMaintainBranches) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Branch administration required.',
      );
    }
    _branch(anchor);
    final rev = original?.revision;
    if (rev != null && rev >= logisticsMax) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Branch revision limit reached.',
      );
    }
    return _submit('save_branch', anchor, {
      'p_organization_id': organizationId,
      'p_request_id': requestId ?? const Uuid().v4(),
      'p_branch_id': original?.id,
      'p_expected_revision': rev,
      'p_name': requiredText(name, 'Branch name', 120),
      'p_code': requiredText(code, 'Branch code', 32),
      'p_address': optionalText(address, 'Address', 500),
      'p_active': active,
      'p_reason': requiredText(reason, 'Reason', 1000, minimum: 3),
    });
  }

  Future<Object> dispatch({
    required String source,
    required String destination,
    required List<Map<String, dynamic>> lines,
    required String reason,
    String? reference,
    required bool confirmed,
    String? requestId,
  }) {
    _branch(source);
    _branch(destination);
    logisticsCheck(source != destination && confirmed);
    final rpcLines =
        lines
            .map(
              (l) => {
                'product_id': logisticsId(l['product_id']),
                'quantity': logisticsInteger(
                  l['quantity'],
                  min: 1,
                  max: 1000000,
                ),
                'expected_revision': logisticsInteger(
                  l['expected_revision'],
                  min: 1,
                ),
              },
            )
            .toList()
          ..sort(
            (a, b) => (a['product_id'] as String).compareTo(
              b['product_id'] as String,
            ),
          );
    _uniqueLines(rpcLines, 'product_id');
    return _submit('dispatch_stock_transfer', source, {
      'p_organization_id': organizationId,
      'p_request_id': requestId ?? const Uuid().v4(),
      'p_source_branch_id': source,
      'p_destination_branch_id': destination,
      'p_items': rpcLines,
      'p_reference': optionalText(reference, 'Reference', 120),
      'p_reason': requiredText(reason, 'Reason', 1000, minimum: 3),
      'p_physical_confirmed': true,
      _proofKey: {
        'kind': 'transfer.dispatch',
        'lines': lines
            .map((l) => {'product_id': l['product_id'], 'unit': l['unit']})
            .toList(),
      },
    });
  }

  Future<Object> complete({
    required String branch,
    required StockTransfer original,
    required bool returning,
    required Map<String, int> quantities,
    required bool confirmed,
    required String reason,
    String? reference,
    String? requestId,
  }) {
    _branch(branch);
    logisticsCheck(
      confirmed &&
          branch ==
              (returning
                  ? original.sourceBranchId
                  : original.destinationBranchId) &&
          original.organizationId == organizationId,
    );
    return _physical(
      'complete_stock_transfer',
      branch,
      original.lines,
      quantities,
      reason,
      reference,
      requestId,
      {
        'p_transfer_id': original.id,
        'p_expected_revision': original.revision,
        'p_kind': returning ? 'transfer.return' : 'transfer.receive',
      },
      returning ? 'transfer.return' : 'transfer.receive',
    );
  }

  Future<Object> supplierReturn({
    required PurchaseReturnContext original,
    required Map<String, int> quantities,
    required bool confirmed,
    required String reason,
    String? reference,
    String? requestId,
  }) {
    _branch(original.branchId);
    logisticsCheck(confirmed && original.organizationId == organizationId);
    return _physical(
      'return_purchase_receipt',
      original.branchId,
      original.lines,
      quantities,
      reason,
      reference,
      requestId,
      {'p_receipt_id': original.receiptId},
      'supplier.return',
      currency: original.currency,
    );
  }

  Future<Object> _physical(
    String function,
    String branch,
    List<LogisticsLine> original,
    Map<String, int> quantities,
    String reason,
    String? reference,
    String? requestId,
    Map<String, dynamic> extra,
    String kind, {
    String? currency,
  }) {
    final chosen = original.where((l) => quantities.containsKey(l.id)).toList()
      ..sort((a, b) => a.productId.compareTo(b.productId));
    logisticsCheck(
      chosen.length == quantities.length &&
          chosen.every(
            (l) => quantities[l.id]! <= l.remaining && l.currentUnit == l.unit,
          ),
    );
    final lines = chosen
        .map(
          (l) => {
            'item_id': l.id,
            'quantity': logisticsInteger(
              quantities[l.id],
              min: 1,
              max: 1000000,
            ),
            'expected_revision': l.expectedRevision,
          },
        )
        .toList();
    _uniqueLines(lines, 'item_id');
    return _submit(function, branch, {
      'p_organization_id': organizationId,
      'p_branch_id': branch,
      'p_request_id': requestId ?? const Uuid().v4(),
      ...extra,
      'p_items': lines,
      'p_reference': optionalText(reference, 'Reference', 120),
      'p_reason': requiredText(reason, 'Reason', 1000, minimum: 3),
      'p_physical_confirmed': true,
      _proofKey: {
        'kind': kind,
        'lines': chosen.map((l) => l.proof()).toList(),
        'currency': ?currency,
      },
    });
  }

  void _uniqueLines(List<Map<String, dynamic>> lines, String key) {
    logisticsCheck(
      lines.isNotEmpty &&
          lines.length <= 100 &&
          lines.map((l) => l[key]).toSet().length == lines.length,
    );
  }

  Future<Object> _submit(
    String rpc,
    String anchor,
    Map<String, dynamic> saved,
  ) => scope.safe(() async {
    final params = Map<String, dynamic>.from(saved)..remove(_proofKey);
    final pending = await _executor.pending();
    if (pending.any(
      (p) =>
          logisticsFunctions.contains(p.type) &&
          p.requestId != params['p_request_id'],
    )) {
      throw const RepositoryFailure(
        RepositoryFailureType.conflict,
        'Resolve the saved branch or stock request before recording another action. Do not repeat physical goods movement.',
      );
    }
    return _executor.mutate<Object>(
      function: rpc,
      branchId: anchor,
      params: params,
      journalPayload: saved,
      decode: (row) {
        logisticsCheck(
          row['request_id'] == params['p_request_id'] &&
              row['organization_id'] == organizationId &&
              row['actor_id'] == scope.actor.userId,
        );
        if (rpc == 'save_branch') {
          final b = ManagedBranch.fromRow(logisticsRow(row['branch']));
          logisticsCheck(
            b.organizationId == organizationId &&
                b.name == params['p_name'] &&
                b.code == params['p_code'] &&
                b.address == params['p_address'] &&
                b.active == params['p_active'] &&
                b.revision ==
                    (params['p_expected_revision'] == null
                        ? 1
                        : (params['p_expected_revision'] as int) + 1) &&
                row['kind'] ==
                    (params['p_branch_id'] == null
                        ? 'branch.create'
                        : 'branch.update') &&
                (params['p_branch_id'] == null ||
                    b.id == params['p_branch_id']),
          );
          return b;
        }
        final action = LogisticsAction.fromRow(row);
        final proof = logisticsRow(saved[_proofKey]);
        final document = action.document;
        logisticsCheck(
          action.branchId == anchor && action.kind == proof['kind'],
        );
        logisticsId(document['operation_id']);
        if (rpc == 'dispatch_stock_transfer') {
          logisticsCheck(
            document['source_branch_id'] == params['p_source_branch_id'] &&
                document['destination_branch_id'] ==
                    params['p_destination_branch_id'] &&
                document['revision'] == 1 &&
                document['transfer_id'] == document['id'],
          );
        }
        if (rpc == 'complete_stock_transfer') {
          logisticsCheck(
            document['transfer_id'] == params['p_transfer_id'] &&
                document['revision'] ==
                    (params['p_expected_revision'] as int) + 1,
          );
        }
        if (rpc == 'return_purchase_receipt') {
          logisticsCheck(
            document['receipt_id'] == params['p_receipt_id'] &&
                document['currency'] == proof['currency'],
          );
        }
        final requested = logisticsRows(params['p_items'], max: 100),
            actual = logisticsRows(document['items'], max: 100),
            original = logisticsRows(proof['lines'], max: 100);
        logisticsCheck(
          requested.length == actual.length &&
              original.length == actual.length &&
              actual.map((l) => l['movement_id']).toSet().length ==
                  actual.length,
        );
        var cost = BigInt.zero;
        for (final input in requested) {
          final key = rpc == 'dispatch_stock_transfer'
              ? 'product_id'
              : 'item_id';
          final out = actual.singleWhere((l) => l[key] == input[key]);
          final from = original.singleWhere((l) => l[key] == input[key]);
          logisticsCheck(
            out['product_id'] == from['product_id'] &&
                out['unit'] == from['unit'] &&
                out['quantity'] == input['quantity'] &&
                out['expected_revision'] == input['expected_revision'],
          );
          logisticsId(out['item_id']);
          logisticsId(out['product_id']);
          logisticsId(out['movement_id']);
          logisticsInteger(out['stock_revision'], min: 1);
          logisticsInteger(
            out['balance_after'],
            min:
                const {
                  'transfer.dispatch',
                  'supplier.return',
                }.contains(action.kind)
                ? 0
                : -logisticsMax,
          );
          if (action.kind == 'supplier.return') {
            final line =
                BigInt.from(
                  logisticsInteger(out['quantity'], min: 1, max: 1000000),
                ) *
                BigInt.from(logisticsInteger(out['unit_cost_minor']));
            logisticsCheck(
              out['unit_cost_minor'] == from['unit_cost_minor'] &&
                  line == BigInt.from(logisticsInteger(out['line_cost_minor'])),
            );
            cost += line;
          }
        }
        if (action.kind == 'supplier.return') {
          logisticsCheck(
            cost == BigInt.from(logisticsInteger(document['total_minor'])),
          );
        }
        return action;
      },
    );
  });
}
