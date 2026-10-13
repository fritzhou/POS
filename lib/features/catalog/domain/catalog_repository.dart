import 'catalog_models.dart';
import 'repository_support.dart';

abstract interface class CatalogRepository {
  Future<DataPage<Product>> searchProducts({
    ProductFilter filter = const ProductFilter(),
    PageRequest page = const PageRequest(),
  });
  Future<DataPage<Category>> listCategories({
    bool? active,
    PageRequest page = const PageRequest(),
  });
  Future<Product> createProduct(ProductInput input);
  Future<Product> updateProduct({
    required String id,
    required int expectedRevision,
    required ProductInput input,
  });
  Future<Product> setProductActive({
    required String id,
    required int expectedRevision,
    required bool active,
  });
  Future<Category> createCategory(String name);
  Future<Category> updateCategory({
    required String id,
    required int expectedRevision,
    required String name,
    required bool active,
  });
  Future<void> uploadProductImage(String productId, List<int> bytes);
}
