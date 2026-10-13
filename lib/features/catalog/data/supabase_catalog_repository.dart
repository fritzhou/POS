import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_models.dart';
import '../domain/catalog_models.dart';
import '../domain/catalog_repository.dart';
import '../domain/repository_support.dart';
import 'supabase_repository_support.dart';

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository({
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
  Future<DataPage<Product>> searchProducts({
    ProductFilter filter = const ProductFilter(),
    PageRequest page = const PageRequest(),
  }) => _scope.safe(() async {
    page.validate();
    if (filter.query.trim().length > 120) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Use a shorter search phrase.',
      );
    }
    final result = await _scope.client.rpc(
      'list_products',
      params: {
        'p_organization_id': _scope.organizationId,
        'p_query': filter.query.trim(),
        'p_category_id': validateOptionalId(filter.categoryId),
        'p_active': filter.active,
        'p_offset': page.offset,
        'p_limit': page.limit + 1,
      },
    );
    return pageFrom(rowsFrom(result), page, productFromRow);
  });

  @override
  Future<DataPage<Category>> listCategories({
    bool? active,
    PageRequest page = const PageRequest(),
  }) => _scope.safe(() async {
    page.validate();
    var query = _scope.client
        .from('categories')
        .select('id,organization_id,name,active,revision')
        .eq('organization_id', _scope.organizationId);
    if (active != null) query = query.eq('active', active);
    final result = await query
        .order('name', ascending: true)
        .order('id', ascending: true)
        .range(page.offset, page.offset + page.limit);
    return pageFrom(rowsFrom(result), page, categoryFromRow);
  });

  Future<Product> _saveProduct({
    String? id,
    int? expectedRevision,
    required Map<String, dynamic> values,
  }) => _scope.safe(() async {
    if (values.containsKey('image_path')) {
      validateImageReference(
        values['image_path'] as String?,
        organizationId: _scope.organizationId,
      );
    }
    final result = await _scope.client.rpc(
      'save_product',
      params: _scope.saveParameters(
        id: id,
        expectedRevision: expectedRevision,
        values: values,
        reason: id == null ? 'Product created' : 'Product updated',
      ),
    );
    return productFromRow(rowFrom(result));
  });

  @override
  Future<Product> createProduct(ProductInput input) async {
    _scope.requireIdentity();
    return _saveProduct(values: input.validatedValues());
  }

  @override
  Future<Product> updateProduct({
    required String id,
    required int expectedRevision,
    required ProductInput input,
  }) async {
    _scope.requireIdentity();
    return _saveProduct(
      id: id,
      expectedRevision: expectedRevision,
      values: input.validatedValues(),
    );
  }

  @override
  Future<Product> setProductActive({
    required String id,
    required int expectedRevision,
    required bool active,
  }) => _saveProduct(
    id: id,
    expectedRevision: expectedRevision,
    values: {'active': active},
  );

  Future<Category> _saveCategory({
    String? id,
    int? expectedRevision,
    required Map<String, dynamic> values,
  }) => _scope.safe(() async {
    final result = await _scope.client.rpc(
      'save_category',
      params: _scope.saveParameters(
        id: id,
        expectedRevision: expectedRevision,
        values: values,
        reason: id == null ? 'Category created' : 'Category updated',
      ),
    );
    return categoryFromRow(rowFrom(result));
  });
  @override
  Future<Category> createCategory(String name) async {
    _scope.requireIdentity();
    return _saveCategory(
      values: {
        'name': requiredText(name, 'Category name', 120),
        'active': true,
      },
    );
  }

  @override
  Future<Category> updateCategory({
    required String id,
    required int expectedRevision,
    required String name,
    required bool active,
  }) async {
    _scope.requireIdentity();
    return _saveCategory(
      id: id,
      expectedRevision: expectedRevision,
      values: {
        'name': requiredText(name, 'Category name', 120),
        'active': active,
      },
    );
  }

  @override
  Future<void> uploadProductImage(String productId, List<int> bytes) async {
    _scope.requireIdentity();
    throw const RepositoryFailure(
      RepositoryFailureType.notConnected,
      'Product image uploads are Not Yet Connected.',
    );
  }
}

Product productFromRow(Map<String, dynamic> row) => Product(
  id: row['id'] as String,
  organizationId: row['organization_id'] as String,
  name: row['name'] as String,
  sku: row['sku'] as String,
  costMinor: row['cost_minor'] == null ? null : integerFrom(row['cost_minor']),
  priceMinor: integerFrom(row['price_minor']),
  currency: row['currency'] as String,
  // PostgreSQL serializes numeric(18,4) as text to preserve every digit.
  reorderLevel: row['reorder_level'] as String,
  unit: row['unit'] as String,
  active: row['active'] as bool,
  revision: integerFrom(row['revision']),
  barcode: row['barcode'] as String?,
  categoryId: row['category_id'] as String?,
  supplierId: row['supplier_id'] as String?,
  imagePath: row['image_path'] as String?,
);

Category categoryFromRow(Map<String, dynamic> row) => Category(
  id: row['id'] as String,
  organizationId: row['organization_id'] as String,
  name: row['name'] as String,
  active: row['active'] as bool,
  revision: integerFrom(row['revision']),
);
