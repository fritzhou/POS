import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/app/shell/nexa_shell.dart';
import 'package:nexapos/app/theme/app_theme.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/settings/settings_page.dart';

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  AppRole? role,
  bool isPreview = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: NexaShell(role: role, isPreview: isPreview),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final sample in [
    (const Size(1440, 900), 'desktop-navigation'),
    (const Size(1024, 768), 'tablet-navigation'),
    (const Size(400, 800), 'mobile-navigation'),
    (const Size(320, 640), 'mobile-navigation'),
  ]) {
    testWidgets('adapts without overflow at ${sample.$1}', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpShell(tester, size: sample.$1);

      expect(find.byKey(Key(sample.$2)), findsOneWidget);
      expect(find.text('DESIGN PREVIEW · Not Yet Connected'), findsOneWidget);
      expect(find.text('Design workspace · No active session'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(4));
      expect(tester.takeException(), isNull);

      if (sample.$2 == 'mobile-navigation') {
        await tester.tap(find.text('POS'));
      } else {
        await tester.tap(find.byKey(const Key('navigate-pos')));
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manual-barcode')), findsOneWidget);
      expect(tester.takeException(), isNull);

      if (sample.$2 == 'mobile-navigation') {
        await tester.tap(find.text('Cart'));
        await tester.pumpAndSettle();
      }
      final cartScroll = find.descendant(
        of: find.byKey(const Key('order-cart-scroll')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Your cart is empty'),
        150,
        scrollable: cartScroll,
      );
      expect(find.text('Your cart is empty'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('checkout-button')),
        200,
        scrollable: cartScroll,
      );
      await tester.pumpAndSettle();
      final checkout = tester.widget<FilledButton>(
        find.byKey(const Key('checkout-button')),
      );
      expect(checkout.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('live cashier navigation denies management modules', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpShell(tester, role: AppRole.cashier, isPreview: false);

    expect(find.byKey(const Key('design-preview-banner')), findsNothing);
    expect(find.byKey(const Key('navigate-pos')), findsOneWidget);
    expect(find.byKey(const Key('navigate-sales')), findsOneWidget);
    expect(find.byKey(const Key('navigate-employees')), findsNothing);
    expect(find.byKey(const Key('navigate-settings')), findsNothing);
    expect(find.byKey(const Key('navigate-inventory')), findsNothing);
    expect(find.byKey(const Key('navigate-auditLogs')), findsNothing);
  });

  testWidgets('missing verified role has no live business navigation', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpShell(tester, isPreview: false);

    expect(find.text('Verified membership required'), findsOneWidget);
    expect(find.byKey(const Key('navigate-pos')), findsNothing);
    expect(find.text('Your business, at a glance'), findsNothing);
  });

  testWidgets('mobile inventory role keeps unauthorized modules out of More', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpShell(
      tester,
      size: const Size(400, 800),
      role: AppRole.inventoryStaff,
      isPreview: false,
    );

    expect(find.text('POS'), findsNothing);
    expect(find.text('Sales'), findsNothing);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigate-products')), findsOneWidget);
    expect(find.byKey(const Key('navigate-suppliers')), findsOneWidget);
    expect(find.byKey(const Key('navigate-employees')), findsNothing);
    expect(find.byKey(const Key('navigate-settings')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings has explicit disabled connection and payment states', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpShell(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('navigate-settings')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('desktop-navigation')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const Key('navigate-settings')));
    await tester.pumpAndSettle();

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields, isNotEmpty);
    expect(fields.every((field) => field.enabled == false), isTrue);
    final settingsScroll = find
        .descendant(
          of: find.byType(SettingsPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Supabase Auth Email'),
      450,
      scrollable: settingsScroll,
    );
    expect(find.text('Custom SMTP / Resend / Postmark'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Manual Payment Verification'),
      450,
      scrollable: settingsScroll,
    );
    expect(find.text('Manual Payment Verification'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard shortcut opens POS and focuses product search', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpShell(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Point of sale'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('product-search')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
  });

  testWidgets('settings stays readable and disabled on a 320px phone', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: SafeArea(child: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .every((field) => field.enabled == false),
      isTrue,
    );

    final scroll = find.byType(Scrollable).first;
    for (final capability in [
      'Supabase Auth Email',
      'Manual Payment Verification',
      'Advanced analytics and AI insights',
    ]) {
      await tester.scrollUntilVisible(
        find.text(capability),
        300,
        scrollable: scroll,
        maxScrolls: 60,
      );
      await tester.pumpAndSettle();
      expect(find.text(capability), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('desktop resize keeps total and checkout visible at 600px high', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpShell(tester, size: const Size(1440, 600));
    await tester.tap(find.byKey(const Key('navigate-pos')));
    await tester.pumpAndSettle();

    expect(find.text('Total').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const Key('checkout-button')).hitTestable(),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('checkout-button')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
