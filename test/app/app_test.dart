import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/app/app.dart';

void main() {
  testWidgets('unconfigured app opens only a labeled read-only preview', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const ProviderScope(child: NexaApp()));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Connect a Supabase project to sign in and access your business.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Open design preview'));
    await tester.pumpAndSettle();
    expect(find.text('DESIGN PREVIEW · Not Yet Connected'), findsOneWidget);
    expect(find.text('Design workspace · No active session'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
