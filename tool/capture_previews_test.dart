// Capture actual, read-only Flutter previews with no connected business data.
// Run from the repository root in the prepared cloud environment:
//   source tool/dev_env.sh
//   flutter test --no-pub tool/capture_previews_test.dart --reporter expanded
// Output: build/preview/*.png. This capture is excluded from ordinary test/.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/app/shell/nexa_shell.dart';
import 'package:nexapos/app/theme/app_theme.dart';
import 'package:nexapos/features/logistics/presentation/logistics_page.dart';
import 'package:nexapos/features/invitations/presentation/invitations_page.dart';

void main() {
  testWidgets('capture actual operations design preview renders', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    await tester.runAsync(() async {
      final toolchain =
          Platform.environment['NEXAPOS_TOOLCHAIN_ROOT'] ??
          '/workspace/.toolchains';
      final flutterRoot =
          Platform.environment['FLUTTER_ROOT'] ?? '$toolchain/flutter';
      final roboto = FontLoader('Roboto');
      for (final weight in ['Regular', 'Medium', 'Bold']) {
        final file = File(
          '$flutterRoot/engine/src/flutter/txt/third_party/fonts/Roboto-$weight.ttf',
        );
        if (file.existsSync()) {
          roboto.addFont(
            Future.value(ByteData.sublistView(file.readAsBytesSync())),
          );
        }
      }
      await roboto.load();
      final icons = FontLoader('MaterialIcons');
      final file = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      icons.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await icons.load();
    });

    Future<void> capture(String name, GlobalKey key) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final bitmap = await boundary.toImage(pixelRatio: 1);
        final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/preview/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        bitmap.dispose();
        debugPrint('Captured ${file.path}');
      });
    }

    for (final sample in [
      (const Size(1440, 1000), 'pos', 'desktop-pos'),
      (const Size(390, 844), 'pos', 'mobile-pos'),
      (const Size(390, 844), 'pos', 'mobile-cart'),
      (const Size(1440, 1000), 'inventory', 'desktop-inventory'),
      (const Size(390, 844), 'inventory', 'mobile-inventory'),
      (const Size(1440, 1000), 'sales', 'desktop-sales'),
      (const Size(390, 844), 'sales', 'mobile-sales'),
      (const Size(1440, 1000), 'shifts', 'desktop-shifts'),
      (const Size(390, 844), 'shifts', 'mobile-shifts'),
      (const Size(1440, 1000), 'products', 'desktop-products'),
      (const Size(390, 844), 'products', 'mobile-products'),
      (const Size(1440, 1000), 'employees', 'desktop-employees'),
      (const Size(390, 844), 'settings', 'mobile-settings'),
      (const Size(1440, 1000), 'purchases', 'desktop-purchases'),
      (const Size(390, 844), 'purchases', 'mobile-purchases'),
      (const Size(1440, 1000), 'expenses', 'desktop-expenses'),
      (const Size(390, 844), 'expenses', 'mobile-expenses'),
      (const Size(1440, 1000), 'reports', 'desktop-reports'),
      (const Size(390, 844), 'reports', 'mobile-reports'),
    ]) {
      // Each capture starts with a fresh shell, so retained page state cannot
      // turn a catalog capture into the previous sample's mobile cart view.
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.physicalSize = sample.$1;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: AppTheme.light,
            debugShowCheckedModeBanner: false,
            home: const NexaShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      const primaryMobile = {
        'pos': 'POS',
        'sales': 'Sales',
        'inventory': 'Inventory',
      };
      if (sample.$1.width < 720 && primaryMobile.containsKey(sample.$2)) {
        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('mobile-navigation')),
            matching: find.text(primaryMobile[sample.$2]!),
          ),
        );
      } else {
        if (sample.$1.width < 720) {
          await tester.tap(find.text('More'));
          await tester.pumpAndSettle();
        }
        final destination = find.byKey(Key('navigate-${sample.$2}'));
        if (destination.evaluate().isEmpty) {
          final scroll = find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(destination, 200, scrollable: scroll);
        } else {
          await tester.ensureVisible(destination);
        }
        await tester.pumpAndSettle();
        await tester.tap(destination);
      }
      await tester.pumpAndSettle();
      if (sample.$3 == 'mobile-cart') {
        await tester.tap(
          find.descendant(
            of: find.byType(SegmentedButton<bool>),
            matching: find.text('Cart'),
          ),
        );
      }
      await tester.pumpAndSettle();
      if (sample.$2 == 'inventory') {
        expect(find.text('No connected inventory'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('stock-receive')))
              .onPressed,
          isNull,
        );
      }
      if (sample.$2 == 'sales') {
        expect(find.text('No connected sales'), findsOneWidget);
      }
      if (sample.$2 == 'shifts') {
        expect(find.text('No connected shifts'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('shift-open')))
              .onPressed,
          isNull,
        );
      }
      if (sample.$2 == 'purchases') {
        expect(find.text('No connected purchase orders'), findsOneWidget);
        expect(find.byKey(const Key('purchase-create')), findsNothing);
      }
      if (sample.$2 == 'expenses') {
        expect(find.text('No connected expense history'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('expense-record')))
              .onPressed,
          isNull,
        );
      }
      if (sample.$2 == 'reports') {
        expect(find.byKey(const Key('copy-report-csv')), findsNothing);
        expect(find.text('0.00'), findsNothing);
      }
      if (sample.$2 == 'pos' && sample.$1.width >= 720) {
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('checkout-button')))
              .onPressed,
          isNull,
        );
      }
      expect(find.text('DESIGN PREVIEW · Not Yet Connected'), findsOneWidget);
      expect(find.text('Design workspace · No active session'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(sample.$3, boundary);

      if (sample.$3 == 'mobile-cart') {
        final scroll = find
            .descendant(
              of: find.byKey(const Key('order-cart-scroll')),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.byKey(const Key('checkout-button')),
          160,
          scrollable: scroll,
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('checkout-button')))
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
        await capture('mobile-cart-checkout', boundary);
      }

      if (sample.$3 == 'mobile-products') {
        final scroll = find
            .descendant(
              of: find.byKey(const Key('catalog-scroll')),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text('Your product catalog belongs here'),
          160,
          scrollable: scroll,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture('mobile-products-empty', boundary);
      }
    }
    for (final size in [const Size(320, 740), const Size(1440, 1000)]) {
      for (final branches in [false, true]) {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.physicalSize = size;
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: AppTheme.light,
              debugShowCheckedModeBanner: false,
              home: Scaffold(body: LogisticsPage(branchesOnly: branches)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(
          '${size.width < 720 ? 'mobile' : 'desktop'}-${branches ? 'branches' : 'logistics'}',
          boundary,
        );
      }
    }
    for (final size in [const Size(320, 740), const Size(1440, 1000)]) {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.physicalSize = size;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: AppTheme.light,
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: const InvitationsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(
        '${size.width < 720 ? 'mobile' : 'desktop'}-invitations',
        boundary,
      );
    }
  });
}
