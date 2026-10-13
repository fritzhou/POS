import '../../catalog/domain/repository_support.dart';
import '../../administration/domain/administration_models.dart';
import 'people_models.dart';

abstract interface class PeopleRepository {
  Future<List<BranchOption>> listBranches();
  Future<DataPage<Supplier>> listSuppliers({
    String query = '',
    bool? active,
    String? branchId,
    PageRequest page = const PageRequest(),
  });
  Future<DataPage<Customer>> listCustomers({
    String query = '',
    bool? active,
    String? branchId,
    PageRequest page = const PageRequest(),
  });
  Future<Supplier> createSupplier(SupplierInput input);
  Future<Customer> createCustomer(CustomerInput input);
  Future<Supplier> updateSupplier({
    required String id,
    required int expectedRevision,
    required SupplierInput input,
  });
  Future<Customer> updateCustomer({
    required String id,
    required int expectedRevision,
    required CustomerInput input,
  });
  Future<Supplier> setSupplierActive({
    required String id,
    required int expectedRevision,
    required bool active,
  });
  Future<Customer> setCustomerActive({
    required String id,
    required int expectedRevision,
    required bool active,
  });
}
