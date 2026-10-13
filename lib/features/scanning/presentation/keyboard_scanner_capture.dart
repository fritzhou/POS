import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/hid_scan_decoder.dart';

typedef ScannerLookup =
    Future<void> Function(String barcode, bool Function() stillCurrent);

/// Opt-in keyboard capture confined to this active POS route. Its callback must
/// check stillCurrent after asynchronous lookup, before changing the cart.
class KeyboardScannerCapture extends StatefulWidget {
  const KeyboardScannerCapture({
    required this.available,
    required this.scopeToken,
    required this.onBarcode,
    required this.builder,
    super.key,
  });

  final bool available;
  final Object scopeToken;
  final ScannerLookup onBarcode;
  final Widget Function(BuildContext context, Widget controls) builder;

  @override
  State<KeyboardScannerCapture> createState() => _KeyboardScannerCaptureState();
}

class _KeyboardScannerCaptureState extends State<KeyboardScannerCapture>
    with WidgetsBindingObserver {
  final _focus = FocusNode(debugLabel: 'POS keyboard scanner');
  HidScannerConfiguration _configuration = const HidScannerConfiguration();
  late HidScanDecoder _decoder;
  bool _enabled = false, _processing = false, _foreground = true;
  int _epoch = 0, _lookupSerial = 0;
  String? _lastBarcode;
  Duration? _lastScan;

  @override
  void initState() {
    super.initState();
    _decoder = HidScanDecoder(_configuration);
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant KeyboardScannerCapture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeToken != widget.scopeToken) {
      _invalidate();
      _enabled = false;
      _processing = false;
      _lookupSerial++;
      _lastBarcode = null;
      _lastScan = null;
    } else if (oldWidget.available && !widget.available) {
      _invalidate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _invalidate();
      if (mounted) setState(() => _enabled = false);
    }
  }

  void _invalidate() {
    _epoch++;
    _decoder.reset();
  }

  void _focusChanged() {
    if (!_focus.hasFocus ||
        _editing ||
        (mounted && ModalRoute.of(context)?.isCurrent != true)) {
      _invalidate();
    }
  }

  bool get _editing {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused?.widget is EditableText ||
        focused?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool get _eligible =>
      mounted &&
      _enabled &&
      widget.available &&
      _foreground &&
      _focus.hasFocus &&
      _focus.canRequestFocus &&
      ModalRoute.of(context)?.isCurrent == true &&
      !_editing;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_eligible) {
      _decoder.reset();
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // HID scanners send physical Shift transitions for uppercase characters.
    // They are modifiers of a character, rather than part of the barcode.
    if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight) {
      return KeyEventResult.ignored;
    }
    if (_processing) {
      _decoder.reset();
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    final invalid =
        event is KeyRepeatEvent ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed;
    final result = _decoder.feed(
      timestamp: event.timeStamp,
      character: event.character,
      prefix: event.logicalKey == LogicalKeyboardKey.f9 && !invalid,
      terminator: _configuration.terminator == ScannerTerminator.enter
          ? event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter
          : event.logicalKey == LogicalKeyboardKey.tab,
      invalid: invalid,
    );
    final barcode = result.barcode;
    if (barcode != null) {
      final duplicate =
          barcode == _lastBarcode &&
          _lastScan != null &&
          event.timeStamp >= _lastScan! &&
          event.timeStamp - _lastScan! < const Duration(milliseconds: 750);
      if (!duplicate) {
        _lastBarcode = barcode;
        _lastScan = event.timeStamp;
        unawaited(_lookup(barcode));
      }
    }
    return result.consumed ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  Future<void> _lookup(String barcode) async {
    final epoch = _epoch;
    final serial = ++_lookupSerial;
    setState(() => _processing = true);
    try {
      await widget.onBarcode(barcode, () => _eligible && epoch == _epoch);
    } finally {
      if (mounted && serial == _lookupSerial) {
        setState(() => _processing = false);
      }
    }
  }

  void _toggle(bool value) {
    _invalidate();
    setState(() => _enabled = value);
    if (value) _focus.requestFocus();
  }

  Future<void> _settings() async {
    _invalidate();
    final configuration = await showDialog<HidScannerConfiguration>(
      context: context,
      builder: (context) => _ScannerSettings(configuration: _configuration),
    );
    if (!mounted || configuration == null) return;
    _invalidate();
    setState(() {
      _configuration = configuration;
      _decoder = HidScanDecoder(configuration);
    });
    if (_enabled) _focus.requestFocus();
  }

  @override
  void dispose() {
    _invalidate();
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_focusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefix = _configuration.prefix == ScannerPrefix.f9
        ? 'F9 → barcode'
        : 'Rapid barcode burst';
    final terminator = _configuration.terminator == ScannerTerminator.enter
        ? 'Enter'
        : 'Tab';
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: widget.builder(
        context,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SwitchListTile(
                key: const Key('keyboard-scanner-enabled'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Keyboard scanner'),
                subtitle: Text(
                  !_enabled
                      ? 'Off · USB / Bluetooth HID'
                      : !widget.available
                      ? 'Enabled · paused'
                      : _processing
                      ? 'Enabled · looking up barcode'
                      : 'Enabled · $prefix → $terminator. Typing fields pause capture.',
                ),
                value: _enabled,
                onChanged: widget.available || _enabled ? _toggle : null,
              ),
            ),
            IconButton(
              key: const Key('keyboard-scanner-settings'),
              tooltip: 'Configure keyboard scanner',
              onPressed: widget.available && !_processing ? _settings : null,
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerSettings extends StatefulWidget {
  const _ScannerSettings({required this.configuration});
  final HidScannerConfiguration configuration;

  @override
  State<_ScannerSettings> createState() => _ScannerSettingsState();
}

class _ScannerSettingsState extends State<_ScannerSettings> {
  late ScannerPrefix _prefix = widget.configuration.prefix;
  late ScannerTerminator _terminator = widget.configuration.terminator;
  late int _gap = widget.configuration.maximumGap.inMilliseconds;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Keyboard scanner settings'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configure the same prefix and terminator on your HID scanner. Scans use exact barcode lookup in the selected branch.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ScannerPrefix>(
              key: const Key('scanner-prefix'),
              initialValue: _prefix,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Prefix'),
              items: const [
                DropdownMenuItem(
                  value: ScannerPrefix.f9,
                  child: Text('F9 (recommended)'),
                ),
                DropdownMenuItem(
                  value: ScannerPrefix.none,
                  child: Text('None · rapid bursts only'),
                ),
              ],
              onChanged: (value) => setState(() => _prefix = value!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ScannerTerminator>(
              key: const Key('scanner-terminator'),
              initialValue: _terminator,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Terminator'),
              items: const [
                DropdownMenuItem(
                  value: ScannerTerminator.enter,
                  child: Text('Enter'),
                ),
                DropdownMenuItem(
                  value: ScannerTerminator.tab,
                  child: Text('Tab'),
                ),
              ],
              onChanged: (value) => setState(() => _terminator = value!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: const Key('scanner-timing'),
              initialValue: _gap,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Maximum key gap'),
              items: const [
                DropdownMenuItem(value: 25, child: Text('25 milliseconds')),
                DropdownMenuItem(value: 40, child: Text('40 milliseconds')),
                DropdownMenuItem(value: 70, child: Text('70 milliseconds')),
              ],
              onChanged: (value) => setState(() => _gap = value!),
            ),
            const SizedBox(height: 12),
            const Text(
              'Accepts 4–128 printable ASCII characters. Rapid mode can resemble fast typing; use an F9 prefix to distinguish scans. No capture occurs in typing fields or dialogs. Duplicate scans within 750 ms are ignored.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('save-scanner-settings'),
        onPressed: () => Navigator.pop(
          context,
          HidScannerConfiguration(
            prefix: _prefix,
            terminator: _terminator,
            maximumGap: Duration(milliseconds: _gap),
          ),
        ),
        child: const Text('Apply'),
      ),
    ],
  );
}
