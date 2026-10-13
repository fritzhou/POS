import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/config/feature_status.dart';
import '../../../core/security/app_role.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../people/domain/people_models.dart';
import '../../people/domain/people_repository.dart';
import '../domain/catalog_models.dart';
import '../domain/catalog_repository.dart';
import '../domain/repository_support.dart';
import 'catalog_ui_support.dart';
import 'category_editor.dart';
import 'product_editor.dart';

/// The role is supplied by verified membership, never selected in this page.
/// Repository scope and PostgreSQL authorize every query and mutation again.
class ProductsPage extends StatefulWidget {
  const ProductsPage({
    this.repository,
    this.peopleRepository,
    this.role,
    this.isPreview = true,
    super.key,
  });

  final CatalogRepository? repository;
  final PeopleRepository? peopleRepository;
  final AppRole? role;
  final bool isPreview;

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  static const _pageSize = 20;
  final _search = TextEditingController();
  Timer? _debounce;
  bool _categoriesTab = false;
  bool? _active = true;
  String? _categoryId;
  int _offset = 0;
  final _previousOffsets = <int>[];
  int _loadGeneration = 0;
  int _choicesGeneration = 0;
  int _scopeGeneration = 0;
  bool _loading = false;
  bool _choicesLoading = false;
  bool _mutating = false;
  String? _error;
  String? _choicesError;
  DataPage<Product>? _products;
  DataPage<Category>? _categories;
  List<Category> _categoryChoices = [];
  List<Supplier> _supplierChoices = [];
  bool _choicesHaveMore = false;
  bool _suppliersConnected = false;

  bool get _connected =>
      !widget.isPreview &&
      widget.repository != null &&
      (widget.role?.allows(AppPermission.viewProducts) ?? false);
  bool get _canManage =>
      _connected &&
      (widget.role?.allows(AppPermission.manageProducts) ?? false);
  bool get _showCost => _connected && widget.role != AppRole.cashier;

  @override
  void initState() {
    super.initState();
    if (_connected) {
      unawaited(_loadChoices());
      unawaited(_loadRows());
    }
  }

  @override
  void didUpdateWidget(covariant ProductsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.peopleRepository != widget.peopleRepository ||
        oldWidget.role != widget.role ||
        oldWidget.isPreview != widget.isPreview) {
      _debounce?.cancel();
      _scopeGeneration++;
      _loadGeneration++;
      _choicesGeneration++;
      _search.clear();
      _offset = 0;
      _previousOffsets.clear();
      _products = null;
      _categories = null;
      _categoryChoices = [];
      _supplierChoices = [];
      _categoryId = null;
      _active = true;
      _error = null;
      _choicesError = null;
      _loading = false;
      _choicesLoading = false;
      _suppliersConnected = false;
      _choicesHaveMore = false;
      _mutating = false;
      if (_connected) {
        unawaited(_loadChoices());
        unawaited(_loadRows());
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadChoices() async {
    if (!_connected) return;
    final generation = ++_choicesGeneration;
    final repository = widget.repository!;
    final people = widget.peopleRepository;
    final canReadSuppliers =
        people != null &&
        (widget.role?.allows(AppPermission.viewSuppliers) ?? false);
    setState(() {
      _choicesLoading = true;
      _choicesError = null;
    });
    try {
      final categories = await repository.listCategories(
        page: const PageRequest(limit: 100),
      );
      DataPage<Supplier>? suppliers;
      if (canReadSuppliers) {
        suppliers = await people.listSuppliers(
          active: true,
          page: const PageRequest(limit: 100),
        );
      }
      if (!mounted || generation != _choicesGeneration) return;
      setState(() {
        _categoryChoices = categories.items;
        _supplierChoices = suppliers?.items ?? [];
        _suppliersConnected = canReadSuppliers;
        _choicesHaveMore = categories.hasMore || (suppliers?.hasMore ?? false);
        _choicesLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _choicesGeneration) return;
      setState(() {
        _choicesLoading = false;
        _choicesError = catalogError(error);
      });
    }
  }

  Future<void> _loadRows() async {
    if (!_connected) return;
    final generation = ++_loadGeneration;
    final repository = widget.repository!;
    final categoriesTab = _categoriesTab;
    final page = PageRequest(offset: _offset, limit: _pageSize);
    final filter = ProductFilter(
      query: _search.text.trim(),
      categoryId: _categoryId,
      active: _active,
    );
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (categoriesTab) {
        final result = await repository.listCategories(
          active: _active,
          page: page,
        );
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _categories = result;
          _loading = false;
        });
      } else {
        final result = await repository.searchProducts(
          filter: filter,
          page: page,
        );
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _products = result;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = catalogError(error);
        _loading = false;
      });
    }
  }

  void _resetAndLoad() {
    _offset = 0;
    _previousOffsets.clear();
    unawaited(_loadRows());
  }

  Future<void> _editProduct([Product? product]) async {
    if (!_canManage || _choicesLoading || _choicesError != null || _mutating) {
      return;
    }
    if (product != null && product.costMinor == null) return;
    final refresh = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProductEditor(
        repository: widget.repository!,
        product: product,
        categories: _categoryChoices,
        suppliers: _supplierChoices,
        suppliersConnected: _suppliersConnected,
        choicesHaveMore: _choicesHaveMore,
      ),
    );
    if (refresh == true && mounted) await _loadRows();
  }

  Future<void> _editCategory([Category? category]) async {
    if (!_canManage || _mutating) return;
    final refresh = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          CategoryEditor(repository: widget.repository!, category: category),
    );
    if (refresh == true && mounted) {
      await _loadRows();
      unawaited(_loadChoices());
    }
  }

  Future<void> _setActive(Product product) async {
    if (!_canManage || _mutating) return;
    final scope = _scopeGeneration;
    final repository = widget.repository!;
    final action = product.active ? 'Deactivate' : 'Reactivate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action product?'),
        content: Text(
          '${product.name} will ${product.active ? 'be hidden from the active catalog' : 'return to the active catalog'}. Its history will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        !_canManage ||
        scope != _scopeGeneration) {
      return;
    }
    setState(() {
      _mutating = true;
      _error = null;
    });
    try {
      await repository.setProductActive(
        id: product.id,
        expectedRevision: product.revision,
        active: !product.active,
      );
      if (!mounted || scope != _scopeGeneration) return;
      setState(() => _mutating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Product ${product.active ? 'deactivated' : 'reactivated'}.',
          ),
        ),
      );
      await _loadRows();
    } catch (error) {
      if (mounted && scope == _scopeGeneration) {
        setState(() {
          _mutating = false;
          _error = catalogError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 900;
      return ListView(
        key: const Key('catalog-scroll'),
        padding: EdgeInsets.all(constraints.maxWidth < 500 ? 16 : 24),
        children: [
          PageHeading(
            title: 'Products',
            subtitle: 'Organize your catalog, prices and product details.',
            trailing: _connected
                ? StatusPill(
                    label: _canManage
                        ? 'Catalog management'
                        : 'Read-only catalog',
                    icon: _canManage
                        ? Icons.inventory_2_outlined
                        : Icons.lock_outline,
                  )
                : const StatusPill(status: FeatureStatus.notYetConnected),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            children: [
              SegmentedButton<bool>(
                key: const Key('catalog-tabs'),
                segments: const [
                  ButtonSegment(value: false, label: Text('Products')),
                  ButtonSegment(value: true, label: Text('Categories')),
                ],
                selected: {_categoriesTab},
                onSelectionChanged: _mutating
                    ? null
                    : (selection) {
                        _debounce?.cancel();
                        setState(() => _categoriesTab = selection.single);
                        _resetAndLoad();
                      },
              ),
              FilledButton.icon(
                key: const Key('add-catalog-record'),
                onPressed:
                    _canManage &&
                        !_mutating &&
                        (_categoriesTab ||
                            (!_choicesLoading && _choicesError == null))
                    ? () => _categoriesTab ? _editCategory() : _editProduct()
                    : null,
                icon: const Icon(Icons.add, size: 20),
                label: Text(_categoriesTab ? 'Add category' : 'Add product'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SectionCard(child: _filters()),
          const SizedBox(height: 16),
          if (!_categoriesTab) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(
                  label: _connected
                      ? 'Stock quantities · Inventory'
                      : 'Stock ledger · Not Yet Connected',
                  icon: Icons.layers_outlined,
                ),
                StatusPill(
                  label: _connected
                      ? 'Stock movements · Inventory'
                      : 'Inventory movements · Not Yet Connected',
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (_choicesError != null && _connected) ...[
            CatalogErrorNotice(
              message:
                  'Category or supplier choices could not be loaded. ${_choicesError!}',
              onRetry: () => unawaited(_loadChoices()),
            ),
            const SizedBox(height: 16),
          ],
          SectionCard(
            padding: desktop ? 20 : 16,
            child: !_connected
                ? FeatureEmptyState(
                    icon: _categoriesTab
                        ? Icons.category_outlined
                        : Icons.inventory_2_outlined,
                    title: _categoriesTab
                        ? 'Your categories belong here'
                        : 'Your product catalog belongs here',
                    message: widget.isPreview
                        ? 'This design preview is read-only. No product or category records are connected.'
                        : 'A connected catalog and verified business membership are required to load records.',
                    status: FeatureStatus.notYetConnected,
                  )
                : _loading
                ? const Padding(
                    padding: EdgeInsets.all(36),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _error != null
                ? CatalogErrorNotice(
                    message: _error!,
                    onRetry: () => unawaited(_loadRows()),
                  )
                : _categoriesTab
                ? _categoryList(desktop)
                : _productList(desktop),
          ),
          if (_connected && !_loading && _error == null) ...[
            const SizedBox(height: 14),
            _paging(),
          ],
        ],
      );
    },
  );

  Widget _filters() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!_categoriesTab) ...[
        TextField(
          key: const Key('catalog-search'),
          controller: _search,
          enabled: _connected && !_mutating,
          decoration: const InputDecoration(
            hintText: 'Search name, SKU or barcode',
            prefixIcon: Icon(Icons.search),
            labelText: 'Search products',
          ),
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 300), _resetAndLoad);
          },
          onSubmitted: (_) {
            _debounce?.cancel();
            _resetAndLoad();
          },
        ),
        const SizedBox(height: 14),
      ],
      LayoutBuilder(
        builder: (context, constraints) {
          final status = DropdownButtonFormField<bool>(
            key: const Key('catalog-active-filter'),
            initialValue: _active,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status'),
            items: const [
              DropdownMenuItem(value: true, child: Text('Active')),
              DropdownMenuItem(value: false, child: Text('Inactive')),
              DropdownMenuItem(value: null, child: Text('All statuses')),
            ],
            onChanged: _connected && !_mutating
                ? (value) {
                    setState(() => _active = value);
                    _resetAndLoad();
                  }
                : null,
          );
          if (_categoriesTab) return status;
          final category = DropdownButtonFormField<String>(
            key: const Key('catalog-category-filter'),
            initialValue: _categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('All categories'),
              ),
              ..._categoryChoices.map(
                (item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(item.name, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: _connected && !_mutating && !_choicesLoading
                ? (value) {
                    setState(() => _categoryId = value);
                    _resetAndLoad();
                  }
                : null,
          );
          return constraints.maxWidth >= 500
              ? Row(
                  children: [
                    Expanded(child: category),
                    const SizedBox(width: 14),
                    Expanded(child: status),
                  ],
                )
              : Column(
                  children: [category, const SizedBox(height: 14), status],
                );
        },
      ),
      if (_choicesHaveMore && !_categoriesTab) ...[
        const SizedBox(height: 8),
        const Text(
          'Category filter shows the first 100 categories.',
          style: TextStyle(fontSize: 12, color: Color(0xff64748b)),
        ),
      ],
    ],
  );

  String _categoryName(String? id) {
    if (id == null) return 'Uncategorized';
    for (final category in _categoryChoices) {
      if (category.id == id) return category.name;
    }
    return 'Category outside this page';
  }

  Widget _productList(bool desktop) {
    final products = _products?.items ?? [];
    if (products.isEmpty) {
      return _empty(
        'No products found',
        'Add your first product or change the search and filters.',
      );
    }
    if (desktop) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const Key('products-table'),
          columnSpacing: 24,
          columns: [
            const DataColumn(label: Text('Product')),
            const DataColumn(label: Text('SKU / Barcode')),
            const DataColumn(label: Text('Category')),
            const DataColumn(label: Text('Price'), numeric: true),
            if (_showCost) const DataColumn(label: Text('Cost'), numeric: true),
            const DataColumn(label: Text('Status')),
            if (_canManage) const DataColumn(label: Text('Actions')),
          ],
          rows: products
              .map(
                (product) => DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 180,
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 140,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.sku,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (product.barcode != null)
                              Text(
                                product.barcode!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xff64748b),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 130,
                        child: Text(
                          _categoryName(product.categoryId),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${product.currency} ${Money.formatMinor(product.priceMinor)}',
                      ),
                    ),
                    if (_showCost)
                      DataCell(
                        Text(
                          product.costMinor == null
                              ? 'Restricted'
                              : '${product.currency} ${Money.formatMinor(product.costMinor!)}',
                        ),
                      ),
                    DataCell(CatalogStatus(active: product.active)),
                    if (_canManage) DataCell(_productActions(product)),
                  ],
                ),
              )
              .toList(),
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < products.length; index++) ...[
          if (index > 0) const Divider(height: 32),
          _productCard(products[index]),
        ],
      ],
    );
  }

  Widget _productCard(Product product) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xffeff6ff),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 21,
              color: Color(0xff2563eb),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  product.sku,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xff64748b),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          Text(
            '${product.currency} ${Money.formatMinor(product.priceMinor)}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          CatalogStatus(active: product.active),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        _categoryName(product.categoryId),
        style: const TextStyle(fontSize: 12, color: Color(0xff64748b)),
      ),
      if (product.barcode != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Barcode: ${product.barcode!}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      if (_showCost && product.costMinor != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Cost: ${product.currency} ${Money.formatMinor(product.costMinor!)}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      if (_canManage)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _productActions(product),
        ),
    ],
  );

  Widget _productActions(Product product) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: Key('edit-product-${product.id}'),
        tooltip: 'Edit ${product.name}',
        onPressed:
            _mutating ||
                _choicesLoading ||
                _choicesError != null ||
                product.costMinor == null
            ? null
            : () => _editProduct(product),
        icon: const Icon(Icons.edit_outlined, size: 20),
      ),
      const SizedBox(width: 4),
      IconButton(
        key: Key('toggle-product-${product.id}'),
        tooltip: product.active
            ? 'Deactivate ${product.name}'
            : 'Reactivate ${product.name}',
        onPressed: _mutating ? null : () => _setActive(product),
        icon: Icon(
          product.active
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 20,
        ),
      ),
    ],
  );

  Widget _categoryList(bool desktop) {
    final categories = _categories?.items ?? [];
    if (categories.isEmpty) {
      return _empty(
        'No categories found',
        'Create a category or change the status filter.',
      );
    }
    if (desktop) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const Key('categories-table'),
          columns: [
            const DataColumn(label: Text('Category')),
            const DataColumn(label: Text('Status')),
            if (_canManage) const DataColumn(label: Text('Actions')),
          ],
          rows: categories
              .map(
                (category) => DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 280,
                        child: Text(
                          category.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(CatalogStatus(active: category.active)),
                    if (_canManage)
                      DataCell(
                        IconButton(
                          key: Key('edit-category-${category.id}'),
                          tooltip: 'Edit ${category.name}',
                          onPressed: _mutating
                              ? null
                              : () => _editCategory(category),
                          icon: const Icon(Icons.edit_outlined, size: 20),
                        ),
                      ),
                  ],
                ),
              )
              .toList(),
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < categories.length; index++) ...[
          if (index > 0) const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      categories[index].name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    CatalogStatus(active: categories[index].active),
                  ],
                ),
              ),
              if (_canManage)
                IconButton(
                  key: Key('edit-category-${categories[index].id}'),
                  tooltip: 'Edit ${categories[index].name}',
                  onPressed: _mutating
                      ? null
                      : () => _editCategory(categories[index]),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _empty(String title, String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      children: [
        const Icon(
          Icons.search_off_outlined,
          size: 36,
          color: Color(0xff94a3b8),
        ),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          _canManage
              ? message
              : 'Change the search or filters to find authorized records.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xff64748b)),
        ),
      ],
    ),
  );

  Widget _paging() {
    final page = _categoriesTab ? _categories : _products;
    final count = page?.items.length ?? 0;
    final hasMore = page?.hasMore ?? false;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Text(
          count == 0
              ? 'No records on this page'
              : 'Showing ${_offset + 1}–${_offset + count}',
          style: const TextStyle(fontSize: 12, color: Color(0xff64748b)),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('catalog-previous'),
              tooltip: 'Previous page',
              onPressed: _previousOffsets.isEmpty || _mutating
                  ? null
                  : () {
                      _offset = _previousOffsets.removeLast();
                      unawaited(_loadRows());
                    },
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              key: const Key('catalog-next'),
              tooltip: 'Next page',
              onPressed: !hasMore || _mutating
                  ? null
                  : () {
                      _previousOffsets.add(_offset);
                      _offset += count;
                      unawaited(_loadRows());
                    },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}
