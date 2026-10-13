import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/app/theme/app_theme.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/catalog/domain/catalog_models.dart';
import 'package:nexapos/features/catalog/domain/catalog_repository.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/catalog/presentation/products_page.dart';

const _org = '11111111-1111-4111-8111-111111111111';
const _categoryId = '22222222-2222-4222-8222-222222222222';
const _productId = '33333333-3333-4333-8333-333333333333';
const _category = Category(
  id: _categoryId,
  organizationId: _org,
  name: 'Beverages',
  active: true,
  revision: 5,
);

Product _product({
  String id = _productId,
  String name = 'Coffee beans',
  String sku = 'COFFEE-001',
  bool active = true,
  int? cost = 1234,
}) => Product(
  id: id,
  organizationId: _org,
  name: name,
  sku: sku,
  barcode: '0123456789',
  costMinor: cost,
  priceMinor: 4567,
  currency: 'PHP',
  reorderLevel: '2.5000',
  unit: 'bag',
  active: active,
  revision: 7,
  categoryId: _categoryId,
);

class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository({List<Product>? products})
    : products = products ?? [_product()];
  final List<Product> products;
  final List<Category> categories = [_category];
  final List<(ProductFilter, PageRequest)> searches = [];
  final List<PageRequest> categoryRequests = [];
  ProductInput? created;
  ProductInput? updated;
  int? expectedRevision;
  int createCalls = 0;
  int updateCalls = 0;
  int activeCalls = 0;
  String? createdCategory;
  String? updatedCategory;
  bool? categoryActive;
  Object? readError;
  Object? writeError;
  Completer<Product>? pendingCreate;
  Completer<Product>? pendingToggle;
  Completer<DataPage<Product>>? pendingRead;

  @override
  Future<DataPage<Product>> searchProducts({
    ProductFilter filter = const ProductFilter(),
    PageRequest page = const PageRequest(),
  }) async {
    searches.add((filter, page));
    if (readError != null) throw readError!;
    if (pendingRead != null) return pendingRead!.future;
    final items = products
        .where(
          (product) =>
              (filter.active == null || product.active == filter.active) &&
              (filter.categoryId == null ||
                  product.categoryId == filter.categoryId) &&
              (filter.query.isEmpty ||
                  '${product.name} ${product.sku} ${product.barcode}'
                      .toLowerCase()
                      .contains(filter.query.toLowerCase())),
        )
        .toList();
    return DataPage(
      items: items.skip(page.offset).take(page.limit).toList(),
      hasMore: page.offset + page.limit < items.length,
      offset: page.offset,
    );
  }

  @override
  Future<DataPage<Category>> listCategories({
    bool? active,
    PageRequest page = const PageRequest(),
  }) async {
    categoryRequests.add(page);
    final items = categories
        .where((category) => active == null || category.active == active)
        .toList();
    return DataPage(
      items: items.skip(page.offset).take(page.limit).toList(),
      hasMore: page.offset + page.limit < items.length,
      offset: page.offset,
    );
  }

  @override
  Future<Product> createProduct(ProductInput input) async {
    createCalls++;
    created = input;
    if (writeError != null) throw writeError!;
    if (pendingCreate != null) return pendingCreate!.future;
    return _product(name: input.name, sku: input.sku);
  }

  @override
  Future<Product> updateProduct({
    required String id,
    required int expectedRevision,
    required ProductInput input,
  }) async {
    updateCalls++;
    updated = input;
    this.expectedRevision = expectedRevision;
    if (writeError != null) throw writeError!;
    return _product(name: input.name, sku: input.sku);
  }

  @override
  Future<Product> setProductActive({
    required String id,
    required int expectedRevision,
    required bool active,
  }) async {
    activeCalls++;
    this.expectedRevision = expectedRevision;
    if (writeError != null) throw writeError!;
    if (pendingToggle != null) return pendingToggle!.future;
    return _product(active: active);
  }

  @override
  Future<Category> createCategory(String name) async {
    createdCategory = name;
    if (writeError != null) throw writeError!;
    return _category;
  }

  @override
  Future<Category> updateCategory({
    required String id,
    required int expectedRevision,
    required String name,
    required bool active,
  }) async {
    updatedCategory = name;
    this.expectedRevision = expectedRevision;
    categoryActive = active;
    if (writeError != null) throw writeError!;
    return _category;
  }

  @override
  Future<void> uploadProductImage(String productId, List<int> bytes) =>
      throw StateError('Unexpected image upload');
}

Future<void> _pump(
  WidgetTester tester, {
  FakeCatalogRepository? repository,
  AppRole? role = AppRole.owner,
  Size size = const Size(1440, 1000),
  bool preview = false,
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ProductsPage(
          repository: repository,
          role: role,
          isPreview: preview,
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  if (find.byKey(Key(key)).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.byKey(Key(key)),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('catalog-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(Key(key)), value);
  await tester.pump();
}

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(400, 800),
    const Size(768, 900),
    const Size(1440, 1000),
  ]) {
    testWidgets('connected catalog and form fit $size', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeCatalogRepository(
        products: [
          _product(
            name:
                'A very long product name that should wrap gracefully on small phones',
          ),
        ],
      );
      await _pump(tester, repository: repository, size: size);
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('products-table')),
        size.width >= 900 ? findsOneWidget : findsNothing,
      );
      await _tapKey(tester, 'add-catalog-record');
      await _enter(tester, 'product-name', 'Tea');
      await _enter(tester, 'product-sku', 'TEA-001');
      await _enter(tester, 'product-reorder', '1.2500');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('catalog-tabs')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      expect(find.text('Beverages'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'preview, missing repository and missing verified role do not request records or enable writes',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeCatalogRepository();
      for (final state in [
        (true, AppRole.owner, repository),
        (false, null, repository),
        (false, AppRole.owner, null),
      ]) {
        await _pump(
          tester,
          repository: state.$3,
          role: state.$2,
          preview: state.$1,
        );
        expect(find.text('Not Yet Connected'), findsWidgets);
        expect(find.text('Coffee beans'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('add-catalog-record')))
              .onPressed,
          isNull,
        );
        expect(repository.searches, isEmpty);
        expect(repository.categoryRequests, isEmpty);
      }
    },
  );

  testWidgets(
    'cashier and manager are read-only and cashier never displays returned cost',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final role in [AppRole.cashier, AppRole.manager]) {
        await _pump(tester, repository: FakeCatalogRepository(), role: role);
        expect(find.text('Coffee beans'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('add-catalog-record')))
              .onPressed,
          isNull,
        );
        expect(find.byKey(const Key('edit-product-$_productId')), findsNothing);
        if (role == AppRole.cashier) {
          expect(find.text('Cost'), findsNothing);
          expect(find.text('PHP 12.34'), findsNothing);
        }
      }
    },
  );

  for (final role in [AppRole.owner, AppRole.admin, AppRole.inventoryStaff]) {
    testWidgets('${role.name} can manage products', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(tester, repository: FakeCatalogRepository(), role: role);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('add-catalog-record')))
            .onPressed,
        isNotNull,
      );
      expect(find.byKey(const Key('edit-product-$_productId')), findsOneWidget);
    });
  }

  testWidgets('search, category, status and bounded paging reach repository', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeCatalogRepository(
      products: List.generate(
        25,
        (index) => _product(
          id: 'product-$index',
          name: 'Coffee $index',
          sku: 'SKU-$index',
        ),
      ),
    );
    await _pump(tester, repository: repository);
    expect(repository.searches.last.$2.limit, 20);
    await _tapKey(tester, 'catalog-next');
    expect(repository.searches.last.$2.offset, 20);
    expect(find.text('Showing 21–25'), findsOneWidget);
    await _tapKey(tester, 'catalog-previous');
    expect(repository.searches.last.$2.offset, 0);
    await _enter(tester, 'catalog-search', 'SKU-24');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repository.searches.last.$1.query, 'SKU-24');
    expect(repository.searches.last.$2.offset, 0);
    expect(find.text('Coffee 24'), findsOneWidget);
    await _tapKey(tester, 'catalog-category-filter');
    await tester.tap(find.text('Beverages').last);
    await tester.pumpAndSettle();
    expect(repository.searches.last.$1.categoryId, _categoryId);
    await _tapKey(tester, 'catalog-active-filter');
    await tester.tap(find.text('Inactive').last);
    await tester.pumpAndSettle();
    expect(repository.searches.last.$1.active, false);
    expect(find.text('No products found'), findsOneWidget);
  });

  testWidgets(
    'product validates text, exact decimals and storage paths before server save',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeCatalogRepository();
      await _pump(tester, repository: repository);
      await _tapKey(tester, 'add-catalog-record');
      await _tapKey(tester, 'save-product');
      expect(repository.createCalls, 0);
      expect(
        find.text('Product name must contain 1 to 160 characters.'),
        findsOneWidget,
      );
      await _enter(tester, 'product-name', ' Tea ');
      await _enter(tester, 'product-sku', ' TEA-001 ');
      await _enter(tester, 'product-cost', '0.001');
      await _tapKey(tester, 'save-product');
      expect(repository.createCalls, 0);
      expect(
        find.text(
          'Enter a nonnegative amount with at most two decimal places.',
        ),
        findsOneWidget,
      );
      await _enter(tester, 'product-cost', '0.29');
      await _enter(tester, 'product-price', '123.45');
      await _enter(tester, 'product-reorder', '2.5000');
      await _enter(
        tester,
        'product-image',
        'https://untrusted.example/image.png',
      );
      await _tapKey(tester, 'save-product');
      expect(repository.createCalls, 0);
      await _enter(tester, 'product-image', '$_org/products/tea.png');
      await _tapKey(tester, 'save-product');
      expect(repository.createCalls, 1);
      expect(repository.created!.name, 'Tea');
      expect(repository.created!.sku, 'TEA-001');
      expect(repository.created!.costMinor, 29);
      expect(repository.created!.priceMinor, 12345);
      expect(repository.created!.reorderLevel, '2.5000');
      expect(repository.created!.imagePath, '$_org/products/tea.png');
      expect(find.byKey(const Key('save-product')), findsNothing);
    },
  );

  testWidgets(
    'save remains pending until server responds and errors stay sanitized',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeCatalogRepository()
        ..pendingCreate = Completer<Product>();
      await _pump(tester, repository: repository);
      await _tapKey(tester, 'add-catalog-record');
      await _enter(tester, 'product-name', 'Tea');
      await _enter(tester, 'product-sku', 'TEA');
      await _tapKey(tester, 'save-product');
      expect(find.text('Saving…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-product')))
            .onPressed,
        isNull,
      );
      expect(repository.createCalls, 1);
      repository.pendingCreate!.completeError(
        StateError('private database URL and secret token'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The request could not be completed. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('secret token'), findsNothing);
      expect(find.byKey(const Key('save-product')), findsOneWidget);
    },
  );

  testWidgets(
    'revision conflict requires closing and reloading instead of claiming success',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeCatalogRepository()
        ..writeError = const RepositoryFailure(
          RepositoryFailureType.conflict,
          'conflict',
        );
      await _pump(tester, repository: repository);
      await _tapKey(tester, 'edit-product-$_productId');
      await _tapKey(tester, 'save-product');
      expect(repository.expectedRevision, 7);
      expect(
        find.text(
          'This record changed on another device. Reload the latest version before trying again.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-product')))
            .onPressed,
        isNull,
      );
      final queryCount = repository.searches.length;
      await tester.tap(find.text('Close and reload'));
      await tester.pumpAndSettle();
      expect(repository.searches.length, queryCount + 1);
      expect(find.textContaining('Saved'), findsNothing);
    },
  );

  testWidgets(
    'deactivate uses revision and reports conflict without successful snackbar',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeCatalogRepository()
        ..writeError = const RepositoryFailure(
          RepositoryFailureType.conflict,
          'conflict',
        );
      await _pump(tester, repository: repository);
      await _tapKey(tester, 'toggle-product-$_productId');
      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();
      expect(repository.activeCalls, 1);
      expect(repository.expectedRevision, 7);
      expect(find.text('Product deactivated.'), findsNothing);
      expect(
        find.text(
          'This record changed on another device. Reload the latest version before trying again.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Reload'));
      await tester.pumpAndSettle();
      expect(find.text('Coffee beans'), findsOneWidget);
    },
  );

  testWidgets('read failure has retry and category edit uses actual revision', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeCatalogRepository()
      ..readError = StateError('secret connection string');
    await _pump(tester, repository: repository);
    expect(find.textContaining('secret connection'), findsNothing);
    repository.readError = null;
    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();
    expect(find.text('Coffee beans'), findsOneWidget);
    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'edit-category-$_categoryId');
    await _enter(tester, 'category-name', ' Drinks ');
    await _tapKey(tester, 'save-category');
    expect(repository.updatedCategory, 'Drinks');
    expect(repository.expectedRevision, 5);
    expect(repository.categoryActive, true);
  });

  testWidgets('stale loading response cannot replace a new membership scope', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<DataPage<Product>>();
    final oldRepository = FakeCatalogRepository()..pendingRead = pending;
    await _pump(tester, repository: oldRepository, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final newRepository = FakeCatalogRepository(
      products: [_product(name: 'New business product')],
    );
    await _pump(tester, repository: newRepository);
    pending.complete(
      DataPage(
        items: [_product(name: 'Old business product')],
        hasMore: false,
        offset: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('New business product'), findsOneWidget);
    expect(find.text('Old business product'), findsNothing);
  });

  testWidgets('pending mutation cannot show success in a replacement session', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<Product>();
    final repository = FakeCatalogRepository()..pendingToggle = pending;
    await _pump(tester, repository: repository);
    await _tapKey(tester, 'toggle-product-$_productId');
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();
    expect(repository.activeCalls, 1);
    await _pump(tester, repository: repository, role: null);
    pending.complete(_product(active: false));
    await tester.pumpAndSettle();
    expect(find.text('Product deactivated.'), findsNothing);
    expect(find.text('Coffee beans'), findsNothing);
  });

  testWidgets(
    'category create validates and category conflict blocks stale saves',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeCatalogRepository();
      await _pump(tester, repository: repository);
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'add-catalog-record');
      await _tapKey(tester, 'save-category');
      expect(repository.createdCategory, isNull);
      await _enter(tester, 'category-name', ' Bakery ');
      await _tapKey(tester, 'save-category');
      expect(repository.createdCategory, 'Bakery');
      repository.writeError = const RepositoryFailure(
        RepositoryFailureType.conflict,
        'conflict',
      );
      await _tapKey(tester, 'edit-category-$_categoryId');
      await _tapKey(tester, 'save-category');
      expect(repository.expectedRevision, 5);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-category')))
            .onPressed,
        isNull,
      );
      expect(find.text('Close and reload'), findsOneWidget);
    },
  );
}
