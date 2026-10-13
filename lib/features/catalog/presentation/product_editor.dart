import 'package:flutter/material.dart';

import '../../people/domain/people_models.dart';
import '../domain/catalog_models.dart';
import '../domain/catalog_repository.dart';
import '../domain/repository_support.dart';
import 'catalog_ui_support.dart';

class ProductEditor extends StatefulWidget {
  const ProductEditor({
    required this.repository,
    required this.categories,
    this.suppliers = const [],
    this.suppliersConnected = false,
    this.choicesHaveMore = false,
    this.product,
    super.key,
  });

  final CatalogRepository repository;
  final List<Category> categories;
  final List<Supplier> suppliers;
  final bool suppliersConnected;
  final bool choicesHaveMore;
  final Product? product;

  @override
  State<ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<ProductEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late final TextEditingController _cost;
  late final TextEditingController _price;
  late final TextEditingController _reorder;
  late final TextEditingController _unit;
  late final TextEditingController _image;
  String? _categoryId;
  String? _supplierId;
  bool _active = true;
  bool _saving = false;
  bool _conflict = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _sku = TextEditingController(text: product?.sku ?? '');
    _barcode = TextEditingController(text: product?.barcode ?? '');
    _cost = TextEditingController(
      text: Money.formatMinor(product?.costMinor ?? 0),
    );
    _price = TextEditingController(
      text: Money.formatMinor(product?.priceMinor ?? 0),
    );
    _reorder = TextEditingController(text: product?.reorderLevel ?? '0');
    _unit = TextEditingController(text: product?.unit ?? 'each');
    _image = TextEditingController(text: product?.imagePath ?? '');
    _categoryId = product?.categoryId;
    _supplierId = product?.supplierId;
    _active = product?.active ?? true;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _sku,
      _barcode,
      _cost,
      _price,
      _reorder,
      _unit,
      _image,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _conflict || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final input = ProductInput(
        name: _name.text.trim(),
        sku: _sku.text.trim(),
        barcode: optionalText(_barcode.text, 'Barcode', 128),
        costMinor: Money.parseMinor(_cost.text),
        priceMinor: Money.parseMinor(_price.text),
        currency: widget.product?.currency ?? Money.currency,
        reorderLevel: validateQuantity(_reorder.text),
        unit: _unit.text.trim(),
        categoryId: _categoryId,
        supplierId: _supplierId,
        imagePath: validateImageReference(
          _image.text,
          organizationId: widget.product?.organizationId,
        ),
        active: _active,
      );
      input.validatedValues();
      final product = widget.product;
      if (product == null) {
        await widget.repository.createProduct(input);
      } else {
        await widget.repository.updateProduct(
          id: product.id,
          expectedRevision: product.revision,
          input: input,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = catalogError(error);
          _conflict =
              error is RepositoryFailure &&
              error.type == RepositoryFailureType.conflict;
        });
      }
    }
  }

  Widget _textField({
    required String keyName,
    required String label,
    required TextEditingController controller,
    String? helper,
    String? Function(String?)? validator,
    bool number = false,
  }) => TextFormField(
    key: Key(keyName),
    controller: controller,
    enabled: !_saving && !_conflict,
    keyboardType: number
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 3,
    ),
    validator: validator,
    textInputAction: TextInputAction.next,
  );

  Widget _pair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= 500
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 16),
              Expanded(child: second),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 16), second],
          ),
  );

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories
        .where((category) => category.active || category.id == _categoryId)
        .toList();
    final suppliers = widget.suppliers
        .where((supplier) => supplier.active || supplier.id == _supplierId)
        .toList();
    final currency = widget.product?.currency ?? Money.currency;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(widget.product == null ? 'Add product' : 'Edit product'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _textField(
                    keyName: 'product-name',
                    label: 'Product name',
                    controller: _name,
                    validator: (value) => validateCatalogField(
                      () => requiredText(value ?? '', 'Product name', 160),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _pair(
                    _textField(
                      keyName: 'product-sku',
                      label: 'SKU',
                      controller: _sku,
                      validator: (value) => validateCatalogField(
                        () => requiredText(value ?? '', 'SKU', 64),
                      ),
                    ),
                    _textField(
                      keyName: 'product-barcode',
                      label: 'Barcode (optional)',
                      controller: _barcode,
                      validator: (value) => validateCatalogField(
                        () => optionalText(value, 'Barcode', 128),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const Key('product-category'),
                    initialValue: _categoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category (optional)',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Uncategorized'),
                      ),
                      if (_categoryId != null &&
                          !categories.any(
                            (category) => category.id == _categoryId,
                          ))
                        DropdownMenuItem(
                          value: _categoryId,
                          child: const Text(
                            'Current category · outside this list',
                          ),
                        ),
                      ...categories.map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Text(
                            category.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: _saving || _conflict
                        ? null
                        : (value) => setState(() => _categoryId = value),
                  ),
                  const SizedBox(height: 16),
                  _pair(
                    _textField(
                      keyName: 'product-cost',
                      label: 'Cost ($currency)',
                      controller: _cost,
                      number: true,
                      validator: (value) => validateCatalogField(
                        () => Money.parseMinor(value ?? ''),
                      ),
                    ),
                    _textField(
                      keyName: 'product-price',
                      label: 'Selling price ($currency)',
                      controller: _price,
                      number: true,
                      validator: (value) => validateCatalogField(
                        () => Money.parseMinor(value ?? ''),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _pair(
                    _textField(
                      keyName: 'product-reorder',
                      label: 'Reorder level',
                      controller: _reorder,
                      number: true,
                      helper:
                          'A planning threshold; this does not change stock.',
                      validator: (value) => validateCatalogField(
                        () => validateQuantity(value ?? ''),
                      ),
                    ),
                    _textField(
                      keyName: 'product-unit',
                      label: 'Unit',
                      controller: _unit,
                      validator: (value) => validateCatalogField(
                        () => requiredText(value ?? '', 'Unit', 32),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const Key('product-supplier'),
                    initialValue: _supplierId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Supplier (optional)',
                      helperText: widget.suppliersConnected
                          ? null
                          : 'Supplier directory · Not Yet Connected',
                      helperMaxLines: 2,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('No supplier'),
                      ),
                      if (_supplierId != null &&
                          !suppliers.any(
                            (supplier) => supplier.id == _supplierId,
                          ))
                        DropdownMenuItem(
                          value: _supplierId,
                          child: const Text(
                            'Current supplier · outside this list',
                          ),
                        ),
                      ...suppliers.map(
                        (supplier) => DropdownMenuItem(
                          value: supplier.id,
                          child: Text(
                            supplier.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged:
                        _saving || _conflict || !widget.suppliersConnected
                        ? null
                        : (value) => setState(() => _supplierId = value),
                  ),
                  if (widget.choicesHaveMore) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'The first 100 category and supplier choices are shown. Existing links are preserved.',
                      style: TextStyle(fontSize: 12, color: Color(0xff64748b)),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _textField(
                    keyName: 'product-image',
                    label: 'Image reference · Upload Coming Soon',
                    controller: _image,
                    helper:
                        'Optional organization-scoped Storage path. No image is uploaded or downloaded here.',
                    validator: (value) => validateCatalogField(
                      () => validateImageReference(
                        value,
                        organizationId: widget.product?.organizationId,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    key: const Key('product-active'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active product'),
                    subtitle: const Text(
                      'Inactive products stay in catalog history.',
                    ),
                    value: _active,
                    onChanged: _saving || _conflict
                        ? null
                        : (value) => setState(() => _active = value),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    CatalogErrorNotice(message: _error!),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () => Navigator.of(context).pop(_conflict ? true : false),
            child: Text(_conflict ? 'Close and reload' : 'Cancel'),
          ),
          FilledButton(
            key: const Key('save-product'),
            onPressed: _saving || _conflict ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save product'),
          ),
        ],
      ),
    );
  }
}
