import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/security/access_lock.dart';
import 'package:nexapos/features/receipts/presentation/receipt_output_scope.dart';

void main() {
  testWidgets('missing business output scope fails closed', (tester) async {
    late bool Function() current;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            current = ReceiptOutputScope.capture(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(current(), false);
  });
  testWidgets(
    'captured scope follows live authorization and survives no replacement identity',
    (tester) async {
      var allowed = true;
      Object identity = 'actor-org-one';
      late bool Function() current;
      await tester.pumpWidget(
        MaterialApp(
          home: ReceiptOutputScope(
            identity: 1,
            currentIdentity: () => identity,
            isAllowed: () => allowed,
            child: Builder(
              builder: (context) {
                current = ReceiptOutputScope.capture(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(current(), true);
      allowed = false;
      expect(current(), false);
      allowed = true;
      identity = 'actor-org-two';
      expect(current(), false);
      identity = 'actor-org-one';
      await tester.pumpWidget(const SizedBox());
      expect(current(), false);
    },
  );
  testWidgets(
    'lock and verified unlock invalidate the captured original generation',
    (tester) async {
      final access = AccessLock()..bind('actor');
      addTearDown(access.dispose);
      late bool Function() current;
      await tester.pumpWidget(
        MaterialApp(
          home: ReceiptOutputScope(
            identity: 'same-actor',
            access: access,
            isAllowed: () => true,
            child: Builder(
              builder: (context) {
                current = ReceiptOutputScope.capture(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(current(), true);
      access.lock();
      expect(current(), false);
      expect(
        access.unlockVerified(actorId: 'actor', generation: access.generation),
        true,
      );
      expect(current(), false);
    },
  );
  testWidgets('scope replacement invalidates a retained dialog context', (
    tester,
  ) async {
    late bool Function() current;
    final child = Builder(
      builder: (context) {
        current = ReceiptOutputScope.capture(context);
        return const Text('Receipt snapshot');
      },
    );
    Widget page(Object scope) => MaterialApp(
      home: ReceiptOutputScope(
        identity: scope,
        isAllowed: () => true,
        child: child,
      ),
    );
    await tester.pumpWidget(page(1));
    final original = current;
    expect(original(), true);
    await tester.pumpWidget(page(2));
    expect(original(), false);
  });
}
