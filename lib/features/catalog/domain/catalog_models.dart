import 'repository_support.dart';

class Category {
  const Category({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.active,
    required this.revision,
  });
  final String id;
  final String organizationId;
  final String name;
  final bool active;
  final int revision;
}

class Product {
  const Product({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.sku,
    required this.priceMinor,
    required this.currency,
    required this.reorderLevel,
    required this.unit,
    required this.active,
    required this.revision,
    this.costMinor,
    this.barcode,
    this.categoryId,
    this.supplierId,
    this.imagePath,
  });
  final String id;
  final String organizationId;
  final String name;
  final String sku;

  /// Cashier catalog responses omit sensitive cost information.
  final int? costMinor;
  final int priceMinor;
  final String currency;
  final String reorderLevel;
  final String unit;
  final bool active;
  final int revision;
  final String? barcode;
  final String? categoryId;
  final String? supplierId;
  final String? imagePath;
}

class ProductInput {
  const ProductInput({
    required this.name,
    required this.sku,
    required this.costMinor,
    required this.priceMinor,
    this.currency = Money.currency,
    this.reorderLevel = '0',
    this.unit = 'each',
    this.active = true,
    this.barcode,
    this.categoryId,
    this.supplierId,
    this.imagePath,
  });
  final String name;
  final String sku;
  final int costMinor;
  final int priceMinor;
  final String currency;
  final String reorderLevel;
  final String unit;
  final bool active;
  final String? barcode;
  final String? categoryId;
  final String? supplierId;
  final String? imagePath;

  Map<String, dynamic> validatedValues() => {
    'name': requiredText(name, 'Product name', 160),
    'sku': requiredText(sku, 'SKU', 64),
    'barcode': optionalText(barcode, 'Barcode', 128),
    'cost_minor': validateMinor(costMinor),
    'price_minor': validateMinor(priceMinor),
    'currency': validateCurrency(currency),
    'reorder_level': validateQuantity(reorderLevel),
    'unit': requiredText(unit, 'Unit', 32),
    'active': active,
    'category_id': validateOptionalId(categoryId),
    'supplier_id': validateOptionalId(supplierId),
    'image_path': validateImageReference(imagePath),
  };
}

class ProductFilter {
  const ProductFilter({this.query = '', this.categoryId, this.active});
  final String query;
  final String? categoryId;
  final bool? active;
}
