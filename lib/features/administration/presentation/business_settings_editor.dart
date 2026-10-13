import 'package:flutter/material.dart';

import '../../../app/config/feature_status.dart';
import '../../../core/security/app_role.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../catalog/domain/repository_support.dart';
import '../domain/administration_models.dart';
import '../domain/administration_repository.dart';

class BusinessSettingsEditor extends StatefulWidget {
  const BusinessSettingsEditor({
    this.repository,
    this.role,
    this.isPreview = true,
    this.onBusinessNameSaved,
    super.key,
  });
  final AdministrationRepository? repository;
  final AppRole? role;
  final bool isPreview;
  final ValueChanged<String>? onBusinessNameSaved;

  @override
  State<BusinessSettingsEditor> createState() => _BusinessSettingsEditorState();
}

class _BusinessSettingsEditorState extends State<BusinessSettingsEditor> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _contact = TextEditingController();
  final _currency = TextEditingController();
  final _tax = TextEditingController();
  final _footer = TextEditingController();
  BusinessSettings? _saved;
  bool _busy = false;
  bool _dirty = false;
  bool _conflict = false;
  String? _error;
  int _loadId = 0;

  bool get _authorized =>
      !widget.isPreview &&
      widget.repository != null &&
      (widget.role?.allows(AppPermission.manageSettings) ?? false);
  bool get _editable => _authorized && !_busy && _saved != null;

  @override
  void initState() {
    super.initState();
    if (_authorized) _load();
  }

  @override
  void didUpdateWidget(covariant BusinessSettingsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.role != widget.role ||
        oldWidget.isPreview != widget.isPreview) {
      _loadId++;
      _saved = null;
      _dirty = false;
      _busy = false;
      _error = null;
      for (final controller in [
        _name,
        _address,
        _contact,
        _currency,
        _tax,
        _footer,
      ]) {
        controller.clear();
      }
      if (_authorized) _load();
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _address,
      _contact,
      _currency,
      _tax,
      _footer,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _apply(BusinessSettings value) {
    _saved = value;
    _name.text = value.businessName;
    _address.text = value.address ?? '';
    _contact.text = value.contact ?? '';
    _currency.text = value.currency;
    _tax.text = Money.formatMinor(value.taxBps);
    _footer.text = value.receiptFooter ?? '';
    _dirty = false;
    _conflict = false;
    _error = null;
  }

  Future<void> _load() async {
    if (!_authorized || _busy) return;
    final request = ++_loadId;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await widget.repository!.loadSettings();
      if (!mounted || request != _loadId) return;
      setState(() => _apply(value));
    } on RepositoryFailure catch (error) {
      if (!mounted || request != _loadId) return;
      setState(() {
        _saved = null;
        _error = error.message;
      });
    } on Object {
      if (!mounted || request != _loadId) return;
      setState(() {
        _saved = null;
        _error = 'Business settings could not be loaded. Try again.';
      });
    } finally {
      if (mounted && request == _loadId) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reload saved settings?'),
          content: const Text('Your unsaved edits will be discarded.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reload'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    await _load();
  }

  BusinessSettingsInput _input() => BusinessSettingsInput(
    businessName: _name.text,
    address: _address.text,
    contact: _contact.text,
    currency: _currency.text,
    taxBps: Money.parseMinor(_tax.text),
    receiptFooter: _footer.text,
    logoPath: _saved?.logoPath,
  );

  Future<void> _save() async {
    if (!_editable ||
        !_dirty ||
        _conflict ||
        !_formKey.currentState!.validate()) {
      return;
    }
    final request = _loadId;
    final expectedRevision = _saved!.revision;
    BusinessSettingsInput input;
    try {
      input = _input();
      input.validatedValues();
    } on RepositoryFailure catch (error) {
      setState(() => _error = error.message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await widget.repository!.updateSettings(
        expectedRevision: expectedRevision,
        input: input,
      );
      if (!mounted || request != _loadId) return;
      setState(() => _apply(value));
      widget.onBusinessNameSaved?.call(value.businessName);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Business settings saved.')));
    } on RepositoryFailure catch (error) {
      if (!mounted || request != _loadId) return;
      setState(() {
        _error = error.message;
        _conflict = error.type == RepositoryFailureType.conflict;
      });
    } on Object {
      if (!mounted || request != _loadId) return;
      setState(
        () => _error =
            'Settings could not be saved. Reload to check the saved version before retrying.',
      );
    } finally {
      if (mounted && request == _loadId) setState(() => _busy = false);
    }
  }

  String? _validate(
    String? value,
    String label,
    int maximum, {
    int minimum = 0,
  }) {
    try {
      if (minimum == 0) {
        optionalText(value, label, maximum);
      } else {
        requiredText(value ?? '', label, maximum, minimum: minimum);
      }
      return null;
    } on RepositoryFailure catch (error) {
      return error.message;
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 1,
    String? helper,
    FormFieldValidator<String>? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: Key('settings-$label'),
      controller: controller,
      enabled: _editable,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
      ),
      validator: validator,
      onChanged: (_) => setState(() => _dirty = true),
    ),
  );

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Business & POS',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _authorized
                ? 'Changes are saved to this business with revision checks and an audit event.'
                : 'Connect an authorized Owner or Admin session to edit saved business settings.',
          ),
          const SizedBox(height: 20),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _error!,
                key: const Key('settings-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          _field(
            _name,
            'Business name',
            validator: (v) => _validate(v, 'Business name', 120, minimum: 2),
          ),
          _field(
            _address,
            'Business address',
            lines: 2,
            validator: (v) => _validate(v, 'Address', 1000),
          ),
          _field(
            _contact,
            'Contact details',
            validator: (v) => _validate(v, 'Contact', 1000),
          ),
          _field(
            _currency,
            'Currency',
            helper:
                'Checkout supports PHP, USD, EUR, GBP, AUD, CAD and SGD. Checkout is unavailable for other currencies.',
            validator: (v) {
              try {
                validateCurrency(v ?? '');
                return null;
              } on RepositoryFailure catch (error) {
                return error.message;
              }
            },
          ),
          _field(
            _tax,
            'Tax rate (%)',
            helper: '0–100, with at most two decimal places.',
            validator: (v) {
              try {
                if (Money.parseMinor(v ?? '') > 10000) {
                  return 'Tax must be between 0% and 100%.';
                }
                return null;
              } on RepositoryFailure catch (error) {
                return error.message;
              }
            },
          ),
          _field(
            _footer,
            'Receipt footer',
            lines: 3,
            validator: (v) => _validate(v, 'Receipt footer', 1000),
          ),
          const Text(
            'Currency changes do not convert product prices or an existing shift. Products and shifts must match the checkout currency.',
          ),
          const SizedBox(height: 16),
          const Text('Business logo upload · Coming Soon'),
          if (_saved?.logoPath != null)
            Text(
              'Saved reference: ${_saved!.logoPath}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                key: const Key('save-business-settings'),
                onPressed: _editable && _dirty && !_conflict ? _save : null,
                icon: const Icon(Icons.save_outlined),
                label: Text(_busy ? 'Working…' : 'Save settings'),
              ),
              OutlinedButton.icon(
                key: const Key('reload-business-settings'),
                onPressed: _authorized && !_busy ? _reload : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Reload saved'),
              ),
              if (!_authorized)
                const StatusPill(status: FeatureStatus.notYetConnected),
              if (_saved != null) Text('Saved revision ${_saved!.revision}'),
            ],
          ),
        ],
      ),
    ),
  );
}
