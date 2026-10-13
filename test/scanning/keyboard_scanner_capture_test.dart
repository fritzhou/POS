import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/features/scanning/presentation/keyboard_scanner_capture.dart';

int _time = 0;

void _dispatch(KeyEvent event) {
  HardwareKeyboard.instance.handleKeyEvent(event);
  // Flutter 3.44 still dispatches Focus key events through this message bridge.
  // Inject timestamps here because tester.sendKeyEvent always uses zero.
  // ignore: deprecated_member_use
  ServicesBinding.instance.keyEventManager.keyMessageHandler!(
    // ignore: deprecated_member_use
    KeyMessage([event], null),
  );
}

void key(LogicalKeyboardKey logical, {String? character}) {
  final physical = logical == LogicalKeyboardKey.f9
      ? PhysicalKeyboardKey.f9
      : logical == LogicalKeyboardKey.enter
      ? PhysicalKeyboardKey.enter
      : logical == LogicalKeyboardKey.tab
      ? PhysicalKeyboardKey.tab
      : PhysicalKeyboardKey.keyA;
  final down = KeyDownEvent(
    physicalKey: physical,
    logicalKey: logical,
    timeStamp: Duration(milliseconds: _time += 5),
    character: character,
  );
  final up = KeyUpEvent(
    physicalKey: physical,
    logicalKey: logical,
    timeStamp: Duration(milliseconds: _time),
  );
  for (final event in [down, up]) {
    _dispatch(event);
  }
}

void scan(String barcode, {bool prefix = true, bool tab = false}) {
  if (prefix) key(LogicalKeyboardKey.f9);
  for (final character in barcode.split('')) {
    key(LogicalKeyboardKey.keyA, character: character);
  }
  key(tab ? LogicalKeyboardKey.tab : LogicalKeyboardKey.enter);
}

Future<void> enable(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('keyboard-scanner-enabled')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('keyboard-scanner-enabled')));
  await tester.pump();
}

Future<void> mount(
  WidgetTester tester, {
  required ScannerLookup lookup,
  Object scope = 'actor-branch-1',
  bool available = true,
  bool excluded = false,
  double width = 800,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ExcludeFocus(
          excluding: excluded,
          child: KeyboardScannerCapture(
            available: available,
            scopeToken: scope,
            onBarcode: lookup,
            builder: (context, controls) => ListView(
              children: [
                controls,
                const TextField(key: Key('typing-field')),
                TextButton(
                  key: const Key('open-dialog'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Other form'),
                      content: const TextField(
                        key: Key('dialog-password'),
                        obscureText: true,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Open form'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _time = 10000);

  testWidgets(
    'capture is opt-in and Windows HID events require default F9 prefix',
    (tester) async {
      final barcodes = <String>[];
      await mount(
        tester,
        lookup: (barcode, current) async {
          if (current()) barcodes.add(barcode);
        },
      );
      scan('abCD0123');
      await tester.pump();
      expect(barcodes, isEmpty);
      await enable(tester);
      scan('abCD0123', prefix: false);
      await tester.pump();
      expect(barcodes, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.f9, platform: 'windows');
      for (final character in 'abCD0123'.split('')) {
        await tester.sendKeyEvent(
          LogicalKeyboardKey.keyA,
          character: character,
          platform: 'windows',
        );
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter, platform: 'windows');
      await tester.pump();
      expect(barcodes, ['abCD0123']);
    },
  );

  testWidgets(
    'physical Shift modifiers preserve uppercase scanner characters',
    (tester) async {
      final barcodes = <String>[];
      await mount(
        tester,
        lookup: (barcode, current) async {
          barcodes.add(barcode);
        },
      );
      await enable(tester);
      key(LogicalKeyboardKey.f9);
      _dispatch(
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.shiftLeft,
          logicalKey: LogicalKeyboardKey.shiftLeft,
          timeStamp: Duration(milliseconds: _time += 5),
        ),
      );
      for (final character in 'ABCD'.split('')) {
        key(LogicalKeyboardKey.keyA, character: character);
      }
      _dispatch(
        KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.shiftLeft,
          logicalKey: LogicalKeyboardKey.shiftLeft,
          timeStamp: Duration(milliseconds: _time += 5),
        ),
      );
      for (final character in '0123'.split('')) {
        key(LogicalKeyboardKey.keyA, character: character);
      }
      key(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(barcodes, ['ABCD0123']);
    },
  );

  testWidgets(
    'held-key repeats cannot become a barcode or leave a valid suffix',
    (tester) async {
      final barcodes = <String>[];
      await mount(
        tester,
        lookup: (barcode, current) async {
          barcodes.add(barcode);
        },
      );
      await enable(tester);
      key(LogicalKeyboardKey.f9);
      _dispatch(
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          character: 'a',
          timeStamp: Duration(milliseconds: _time += 5),
        ),
      );
      _dispatch(
        KeyRepeatEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          character: 'a',
          timeStamp: Duration(milliseconds: _time += 5),
        ),
      );
      _dispatch(
        KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          timeStamp: Duration(milliseconds: _time += 5),
        ),
      );
      for (final character in 'bcde1234'.split('')) {
        key(LogicalKeyboardKey.keyA, character: character);
      }
      key(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(barcodes, isEmpty);
      scan('real1234');
      await tester.pumpAndSettle();
      expect(barcodes, ['real1234']);
    },
  );

  testWidgets(
    'duplicate bursts and simultaneous asynchronous lookups are not queued',
    (tester) async {
      final pending = Completer<void>();
      final barcodes = <String>[];
      await mount(
        tester,
        lookup: (barcode, current) async {
          barcodes.add(barcode);
          await pending.future;
        },
      );
      await enable(tester);
      scan('12345678');
      scan('87654321');
      await tester.pump();
      expect(barcodes, ['12345678']);
      pending.complete();
      await tester.pump();
      scan('12345678');
      await tester.pump();
      expect(barcodes, ['12345678']);
      _time += 800;
      scan('12345678');
      await tester.pump();
      expect(barcodes, ['12345678', '12345678']);
    },
  );

  testWidgets('typing focus including password dialogs is never decoded', (
    tester,
  ) async {
    final barcodes = <String>[];
    await mount(
      tester,
      lookup: (barcode, current) async {
        barcodes.add(barcode);
      },
    );
    await enable(tester);
    await tester.tap(find.byKey(const Key('typing-field')));
    await tester.pump();
    scan('12345678');
    await tester.pump();
    expect(barcodes, isEmpty);
    await tester.tap(find.byKey(const Key('open-dialog')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dialog-password')));
    await tester.pump();
    scan('12345678');
    await tester.pump();
    expect(barcodes, isEmpty);
  });

  testWidgets('opening and closing a modal invalidates an outstanding lookup', (
    tester,
  ) async {
    final pending = Completer<void>();
    final applied = <String>[];
    await mount(
      tester,
      lookup: (barcode, current) async {
        await pending.future;
        if (current()) applied.add(barcode);
      },
    );
    await enable(tester);
    scan('12345678');
    await tester.pump();
    await tester.tap(find.byKey(const Key('open-dialog')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    expect(applied, isEmpty);
    expect(find.textContaining('looking up'), findsNothing);
  });

  testWidgets('scope changes disable scanner and invalidate async results', (
    tester,
  ) async {
    final pending = Completer<void>();
    final applied = <String>[];
    Future<void> lookup(String barcode, bool Function() current) async {
      await pending.future;
      if (current()) applied.add(barcode);
    }

    await mount(tester, lookup: lookup);
    await enable(tester);
    scan('12345678');
    await tester.pump();
    await mount(tester, lookup: lookup, scope: 'other-actor-branch');
    pending.complete();
    await tester.pump();
    expect(applied, isEmpty);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('keyboard-scanner-enabled')),
          )
          .value,
      isFalse,
    );
    scan('87654321');
    await tester.pump();
    expect(applied, isEmpty);
  });

  testWidgets(
    'locking with ExcludeFocus invalidates lookup through a later unlock',
    (tester) async {
      final pending = Completer<void>();
      final received = <String>[];
      final applied = <String>[];
      Future<void> lookup(String barcode, bool Function() current) async {
        received.add(barcode);
        await pending.future;
        if (current()) applied.add(barcode);
      }

      await mount(tester, lookup: lookup);
      await enable(tester);
      scan('12345678');
      await tester.pump();
      expect(received, ['12345678']);
      await mount(tester, lookup: lookup, excluded: true);
      scan('87654321');
      await tester.pump();
      expect(received, ['12345678']);
      await mount(tester, lookup: lookup);
      pending.complete();
      await tester.pumpAndSettle();
      expect(applied, isEmpty);
      expect(find.textContaining('looking up'), findsNothing);
    },
  );

  testWidgets('unavailable or background POS captures nothing', (tester) async {
    final barcodes = <String>[];
    Future<void> lookup(String barcode, bool Function() current) async {
      barcodes.add(barcode);
    }

    await mount(tester, lookup: lookup, available: false);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('keyboard-scanner-enabled')),
          )
          .onChanged,
      isNull,
    );
    scan('12345678');
    await tester.pump();
    expect(barcodes, isEmpty);
    await mount(tester, lookup: lookup);
    await enable(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    scan('12345678');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(barcodes, isEmpty);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('keyboard-scanner-enabled')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets(
    'configuration fits 320 px and supports explicit no-prefix Tab scans',
    (tester) async {
      final barcodes = <String>[];
      await mount(
        tester,
        width: 320,
        lookup: (barcode, current) async {
          barcodes.add(barcode);
        },
      );
      await tester.tap(find.byKey(const Key('keyboard-scanner-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scanner-prefix')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('None · rapid bursts only').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scanner-terminator')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tab').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-scanner-settings')));
      await tester.pumpAndSettle();
      await enable(tester);
      scan('abCD0123', prefix: false, tab: true);
      await tester.pump();
      expect(barcodes, ['abCD0123']);
      expect(tester.takeException(), isNull);
    },
  );
}
