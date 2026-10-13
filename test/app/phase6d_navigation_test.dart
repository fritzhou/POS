import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/app/shell/nexa_shell.dart';
import 'package:nexapos/app/theme/app_theme.dart';
import 'package:nexapos/features/invitations/presentation/invitations_page.dart';

void main() {
  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'employee invitation history opens as an empty preview at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.light, home: const NexaShell()),
        );
        await tester.pumpAndSettle();
        if (width < 720) {
          await tester.tap(find.text('More'));
          await tester.pumpAndSettle();
        }
        final employees = find.byKey(const Key('navigate-employees'));
        await tester.ensureVisible(employees);
        await tester.pumpAndSettle();
        await tester.tap(employees);
        await tester.pumpAndSettle();
        final button = find.byKey(const Key('employee-invitations'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(InvitationsPage), findsOneWidget);
        expect(find.text('No connected invitations'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.text('Revoke invitation'), findsNothing);
        expect(find.text('Retry original request'), findsNothing);
      },
    );
  }
}
