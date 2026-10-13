import '../../catalog/domain/repository_support.dart';
import 'report_models.dart';

abstract interface class ReportsRepository {
  String get organizationId;
  Set<String> get branchIds;
  Future<SalesReport> sales({
    required String branchId,
    required ReportWindow window,
    String? shiftId,
  });
  Future<InventoryReport> inventory({
    required String branchId,
    String query = '',
    PageRequest page = const PageRequest(),
  });
  Future<ExpenseReport> expenses({
    required String branchId,
    required ReportWindow window,
  });
}
