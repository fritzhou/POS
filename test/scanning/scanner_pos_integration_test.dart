import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';

import '../offline_widgets/offline_workspace_page_test.dart' as offline;
import '../pos_widgets/pos_page_test.dart' as online;
import 'keyboard_scanner_capture_test.dart' as hid;

class _DelayedOnline extends online.FakeCheckout {
  final response = Completer<PosProduct?>();
  @override
  Future<PosProduct?> lookupProductByBarcode({
    required String branchId,
    required String barcode,
  }) {
    barcodeRequests.add(barcode);
    return response.future;
  }
}

class _DelayedOffline extends offline.FixtureWorkspace {
  final response = Completer<PosProduct?>();
  @override
  Future<PosProduct?> lookupProductByBarcode(String barcode) {
    barcodes.add(barcode);
    return response.future;
  }
}

void main() {
  testWidgets(
    'online scanner adds one exact product and an unknown scan adds nothing',
    (tester) async {
      final repository = online.FakeCheckout();
      await online.pumpPos(tester, repository);
      await hid.enable(tester);
      hid.scan('AbCd1234');
      await tester.pumpAndSettle();
      expect(repository.barcodeRequests, ['AbCd1234']);
      expect(
        find.byKey(const Key('quantity-${online.productId}')),
        findsNothing,
      );
      hid.scan(online.product.barcode!);
      await tester.pumpAndSettle();
      expect(repository.barcodeRequests, ['AbCd1234', online.product.barcode]);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('quantity-${online.productId}')))
            .data,
        '1',
      );
      hid.scan(online.product.barcode!);
      await tester.pumpAndSettle();
      expect(repository.barcodeRequests, hasLength(2));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('quantity-${online.productId}')))
            .data,
        '1',
      );
    },
  );

  testWidgets(
    'online lookup cannot apply after repository or membership scope replacement',
    (tester) async {
      final first = _DelayedOnline();
      await online.pumpPos(tester, first);
      await hid.enable(tester);
      hid.scan(online.product.barcode!);
      await tester.pump();
      expect(first.barcodeRequests, [online.product.barcode]);
      final second = online.FakeCheckout();
      await online.pumpPos(tester, second);
      first.response.complete(online.product);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('quantity-${online.productId}')),
        findsNothing,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('keyboard-scanner-enabled')),
            )
            .value,
        isFalse,
      );
    },
  );

  testWidgets('preview and a role without POS access cannot enable capture', (
    tester,
  ) async {
    final repository = online.FakeCheckout();
    await online.pumpPos(tester, repository, preview: true);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('keyboard-scanner-enabled')),
          )
          .onChanged,
      isNull,
    );
    hid.scan(online.product.barcode!);
    await tester.pump();
    expect(repository.barcodeRequests, isEmpty);
    await online.pumpPos(tester, repository, role: AppRole.inventoryStaff);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('keyboard-scanner-enabled')),
          )
          .onChanged,
      isNull,
    );
    hid.scan(online.product.barcode!);
    await tester.pump();
    expect(repository.barcodeRequests, isEmpty);
  });

  testWidgets('phone online scanner controls preserve 320 px layout', (
    tester,
  ) async {
    final repository = online.FakeCheckout();
    await online.pumpPos(tester, repository, size: const Size(320, 640));
    await hid.enable(tester);
    hid.scan(online.product.barcode!);
    await tester.pumpAndSettle();
    expect(repository.barcodeRequests, [online.product.barcode]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'explicit offline scanner uses only signed snapshot exact lookup',
    (tester) async {
      final workspace = offline.FixtureWorkspace();
      await offline.mount(tester, workspace);
      await hid.enable(tester);
      hid.scan('Unknown1234');
      await tester.pumpAndSettle();
      expect(workspace.barcodes, ['Unknown1234']);
      expect(find.text('Add cached products to begin.'), findsOneWidget);
      hid.scan(offline.product.barcode!);
      await tester.pumpAndSettle();
      expect(workspace.barcodes, ['Unknown1234', offline.product.barcode]);
      expect(find.text('Add cached products to begin.'), findsNothing);
      expect(workspace.calls, isEmpty);
      expect(workspace.syncCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offline stale lookup cannot add to a replacement workspace', (
    tester,
  ) async {
    final first = _DelayedOffline();
    await offline.mount(tester, first);
    await hid.enable(tester);
    hid.scan(offline.product.barcode!);
    await tester.pump();
    expect(first.barcodes, [offline.product.barcode]);
    await offline.mount(tester, offline.FixtureWorkspace());
    first.response.complete(offline.product);
    await tester.pumpAndSettle();
    expect(find.text('Add cached products to begin.'), findsOneWidget);
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
    'offline expired or blocked grant cannot enable scanner capture',
    (tester) async {
      final workspace = offline.FixtureWorkspace()..expired = true;
      await offline.mount(tester, workspace);
      await tester.ensureVisible(
        find.byKey(const Key('keyboard-scanner-enabled')),
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('keyboard-scanner-enabled')),
            )
            .onChanged,
        isNull,
      );
      hid.scan(offline.product.barcode!);
      await tester.pump();
      expect(workspace.barcodes, isEmpty);
      final blocked = offline.FixtureWorkspace()..blocked = true;
      await offline.mount(tester, blocked);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('keyboard-scanner-enabled')),
            )
            .onChanged,
        isNull,
      );
      hid.scan(offline.product.barcode!);
      await tester.pump();
      expect(blocked.barcodes, isEmpty);
    },
  );

  testWidgets('phone offline scanner controls fit 320 px', (tester) async {
    final workspace = offline.FixtureWorkspace();
    await offline.mount(tester, workspace, width: 320);
    await hid.enable(tester);
    hid.scan(offline.product.barcode!);
    await tester.pumpAndSettle();
    expect(workspace.barcodes, [offline.product.barcode]);
    expect(find.text('Add cached products to begin.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
