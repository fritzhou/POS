import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_models.dart';
import '../../administration/domain/administration_models.dart';
import '../../catalog/data/supabase_repository_support.dart';
import '../../catalog/domain/repository_support.dart';
import '../domain/people_models.dart';
import '../domain/people_repository.dart';

class SupabasePeopleRepository implements PeopleRepository {
  SupabasePeopleRepository({
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
  Future<List<BranchOption>> listBranches() => _scope.safe(() async {
    final result = await _scope.client
        .from('branches')
        .select('id,name,code')
        .eq('organization_id', _scope.organizationId)
        .eq('active', true)
        .order('name', ascending: true)
        .limit(100);
    return rowsFrom(result)
        .map(
          (row) => BranchOption(
            id: row['id'] as String,
            name: row['name'] as String,
            code: row['code'] as String,
          ),
        )
        .toList(growable: false);
  });

  Future<List<Map<String, dynamic>>> _list(
    String table, {
    required String query,
    bool? active,
    String? branchId,
    required PageRequest page,
  }) async {
    page.validate();
    var request = _scope.client
        .from(table)
        .select()
        .eq('organization_id', _scope.organizationId);
    if (active != null) request = request.eq('active', active);
    if (branchId != null) {
      request = request.eq('branch_id', validateId(branchId));
    }
    final term = literalSearch(query);
    if (term.isNotEmpty) request = request.ilike('name', '%$term%');
    final result = await request
        .order('name', ascending: true)
        .order('id', ascending: true)
        .range(page.offset, page.offset + page.limit);
    return rowsFrom(result);
  }

  @override
  Future<DataPage<Supplier>> listSuppliers({
    String query = '',
    bool? active,
    String? branchId,
    PageRequest page = const PageRequest(),
  }) => _scope.safe(
    () async => pageFrom(
      await _list(
        'suppliers',
        query: query,
        active: active,
        branchId: branchId,
        page: page,
      ),
      page,
      supplierFromRow,
    ),
  );
  @override
  Future<DataPage<Customer>> listCustomers({
    String query = '',
    bool? active,
    String? branchId,
    PageRequest page = const PageRequest(),
  }) => _scope.safe(
    () async => pageFrom(
      await _list(
        'customers',
        query: query,
        active: active,
        branchId: branchId,
        page: page,
      ),
      page,
      customerFromRow,
    ),
  );

  Future<T> _save<T>(
    String rpc, {
    String? id,
    int? expectedRevision,
    required Map<String, dynamic> values,
    required T Function(Map<String, dynamic>) decode,
  }) => _scope.safe(
    () async => decode(
      rowFrom(
        await _scope.client.rpc(
          rpc,
          params: _scope.saveParameters(
            id: id,
            expectedRevision: expectedRevision,
            values: values,
            reason: id == null ? 'Contact created' : 'Contact updated',
          ),
        ),
      ),
    ),
  );

  @override
  Future<Supplier> createSupplier(SupplierInput input) async {
    _scope.requireIdentity();
    return _save(
      'save_supplier',
      values: input.validatedValues(),
      decode: supplierFromRow,
    );
  }

  @override
  Future<Customer> createCustomer(CustomerInput input) async {
    _scope.requireIdentity();
    return _save(
      'save_customer',
      values: input.validatedValues(),
      decode: customerFromRow,
    );
  }

  @override
  Future<Supplier> updateSupplier({
    required String id,
    required int expectedRevision,
    required SupplierInput input,
  }) async {
    _scope.requireIdentity();
    return _save(
      'save_supplier',
      id: id,
      expectedRevision: expectedRevision,
      values: input.validatedValues(),
      decode: supplierFromRow,
    );
  }

  @override
  Future<Customer> updateCustomer({
    required String id,
    required int expectedRevision,
    required CustomerInput input,
  }) async {
    _scope.requireIdentity();
    return _save(
      'save_customer',
      id: id,
      expectedRevision: expectedRevision,
      values: input.validatedValues(),
      decode: customerFromRow,
    );
  }

  @override
  Future<Supplier> setSupplierActive({
    required String id,
    required int expectedRevision,
    required bool active,
  }) => _save(
    'save_supplier',
    id: id,
    expectedRevision: expectedRevision,
    values: {'active': active},
    decode: supplierFromRow,
  );
  @override
  Future<Customer> setCustomerActive({
    required String id,
    required int expectedRevision,
    required bool active,
  }) => _save(
    'save_customer',
    id: id,
    expectedRevision: expectedRevision,
    values: {'active': active},
    decode: customerFromRow,
  );
}

Supplier supplierFromRow(Map<String, dynamic> row) => Supplier(
  id: row['id'] as String,
  organizationId: row['organization_id'] as String,
  name: row['name'] as String,
  active: row['active'] as bool,
  revision: integerFrom(row['revision']),
  branchId: row['branch_id'] as String?,
  contactName: row['contact_name'] as String?,
  email: row['email'] as String?,
  phone: row['phone'] as String?,
  address: row['address'] as String?,
  notes: row['notes'] as String?,
);
Customer customerFromRow(Map<String, dynamic> row) => Customer(
  id: row['id'] as String,
  organizationId: row['organization_id'] as String,
  name: row['name'] as String,
  active: row['active'] as bool,
  revision: integerFrom(row['revision']),
  branchId: row['branch_id'] as String?,
  email: row['email'] as String?,
  phone: row['phone'] as String?,
  address: row['address'] as String?,
  notes: row['notes'] as String?,
);
