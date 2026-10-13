import 'package:flutter/material.dart';

import '../domain/catalog_models.dart';
import '../domain/catalog_repository.dart';
import '../domain/repository_support.dart';
import 'catalog_ui_support.dart';

class CategoryEditor extends StatefulWidget {
  const CategoryEditor({required this.repository, this.category, super.key});
  final CatalogRepository repository;
  final Category? category;

  @override
  State<CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<CategoryEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late bool _active;
  bool _saving = false;
  bool _conflict = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.category?.name ?? '');
    _active = widget.category?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _conflict || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final category = widget.category;
      if (category == null) {
        await widget.repository.createCategory(_name.text.trim());
      } else {
        await widget.repository.updateCategory(
          id: category.id,
          expectedRevision: category.revision,
          name: _name.text.trim(),
          active: _active,
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(widget.category == null ? 'Add category' : 'Edit category'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('category-name'),
                  controller: _name,
                  enabled: !_saving && !_conflict,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Category name'),
                  validator: (value) => validateCatalogField(
                    () => requiredText(value ?? '', 'Category name', 120),
                  ),
                ),
                if (widget.category != null) ...[
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active category'),
                    subtitle: const Text(
                      'Existing products keep their category when it is inactive.',
                    ),
                    value: _active,
                    onChanged: _saving || _conflict
                        ? null
                        : (value) => setState(() => _active = value),
                  ),
                ],
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
          key: const Key('save-category'),
          onPressed: _saving || _conflict ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save category'),
        ),
      ],
    ),
  );
}
