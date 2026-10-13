import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/security/app_role.dart';
import '../../catalog/data/supabase_repository_support.dart';
import '../../catalog/domain/repository_support.dart';
import '../domain/report_models.dart';
import '../domain/reports_repository.dart';
import 'report_decoders.dart';

class SupabaseReportsRepository implements ReportsRepository {
  SupabaseReportsRepository({
    required SupabaseClient client,
    required AuthenticatedUser actor,
    bool Function()? isRecoverySession,
  }) : _scope = SupabaseRepositoryScope(
         client: client,
         actor: actor,
         isRecoverySession: isRecoverySession,
       );
  final SupabaseRepositoryScope _scope;
  @override
  String get organizationId => _scope.organizationId.toLowerCase();
  @override
  Set<String> get branchIds =>
      Set.unmodifiable(_scope.actor.branchIds.map((id) => id.toLowerCase()));

  void _branch(String id) {
    validateId(id);
    if (!branchIds.contains(id.toLowerCase())) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Choose a currently authorized branch.',
      );
    }
  }

  Future<T> _read<T>(
    String function,
    Map<String, dynamic> params,
    T Function(Map<String, dynamic>) decode,
  ) => _scope.safe(() async {
    try {
      return decode(
        reportRow(await _scope.client.rpc(function, params: params)),
      );
    } on PostgrestException catch (error) {
      if (error.code == 'NX003') {
        throw const RepositoryFailure(
          RepositoryFailureType.validation,
          'This report exceeds the exact supported amount. Choose a narrower activity window or product filter.',
        );
      }
      rethrow;
    }
  });

  @override
  Future<SalesReport> sales({
    required String branchId,
    required ReportWindow window,
    String? shiftId,
  }) => _scope.safe(() async {
    _branch(branchId);
    final role = _scope.actor.role;
    if (role == AppRole.inventoryStaff ||
        (role == AppRole.cashier && shiftId == null)) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Cashier sales reports require an explicitly selected own shift.',
      );
    }
    validateOptionalId(shiftId);
    return _read(
      'get_sales_report',
      {
        'p_organization_id': organizationId,
        'p_branch_id': branchId.toLowerCase(),
        'p_from': window.from.toIso8601String(),
        'p_to': window.to.toIso8601String(),
        'p_shift_id': shiftId?.toLowerCase(),
      },
      (row) => salesReportFromRow(
        row,
        organizationId: organizationId,
        branchId: branchId,
        window: window,
        shiftId: shiftId,
      ),
    );
  });

  @override
  Future<InventoryReport> inventory({
    required String branchId,
    String query = '',
    PageRequest page = const PageRequest(),
  }) => _scope.safe(() async {
    _branch(branchId);
    page.validate();
    if (_scope.actor.role == AppRole.cashier) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Operational inventory reports require stock access.',
      );
    }
    final normalized = query.trim();
    if (normalized.length > 120) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Use a product filter of at most 120 characters.',
      );
    }
    return _read(
      'get_inventory_report',
      {
        'p_organization_id': organizationId,
        'p_branch_id': branchId.toLowerCase(),
        'p_query': normalized,
        'p_offset': page.offset,
        'p_limit': page.limit + 1,
      },
      (row) => inventoryReportFromRow(
        row,
        organizationId: organizationId,
        branchId: branchId,
        query: normalized,
        page: page,
      ),
    );
  });

  @override
  Future<ExpenseReport> expenses({
    required String branchId,
    required ReportWindow window,
  }) => _scope.safe(() async {
    _branch(branchId);
    if (!{
      AppRole.owner,
      AppRole.admin,
      AppRole.manager,
    }.contains(_scope.actor.role)) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Business expense reports require owner, admin or manager access.',
      );
    }
    return _read(
      'get_expense_report',
      {
        'p_organization_id': organizationId,
        'p_branch_id': branchId.toLowerCase(),
        'p_from': window.from.toIso8601String(),
        'p_to': window.to.toIso8601String(),
      },
      (row) => expenseReportFromRow(
        row,
        organizationId: organizationId,
        branchId: branchId,
        window: window,
      ),
    );
  });
}
