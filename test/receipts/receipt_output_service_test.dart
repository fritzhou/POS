import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/features/receipts/data/receipt_output_service.dart';
import 'package:nexapos/features/receipts/data/receipt_pdf_renderer.dart';
import 'package:nexapos/features/receipts/domain/receipt_document.dart';
import 'receipt_fixtures.dart';

class _Renderer extends ReceiptPdfRenderer {
  int calls = 0;
  final completer = Completer<Uint8List>();
  @override
  Future<Uint8List> render(
    ReceiptDocument document, {
    ReceiptPaperFormat format = ReceiptPaperFormat.thermal80,
  }) {
    calls++;
    return completer.future;
  }
}

class _Gateway implements ReceiptOutputGateway {
  int prints = 0, shares = 0;
  bool accepted = true;
  Object? error;
  String? filename;
  ReceiptPaperFormat? paper;
  @override
  Future<bool> printPdf({
    required Uint8List bytes,
    required String filename,
    required ReceiptPaperFormat paper,
    required bool Function() isCurrent,
  }) async {
    prints++;
    this.filename = filename;
    this.paper = paper;
    if (error != null) throw error!;
    return accepted;
  }

  @override
  Future<bool> sharePdf({
    required Uint8List bytes,
    required String filename,
  }) async {
    shares++;
    this.filename = filename;
    if (error != null) throw error!;
    return accepted;
  }
}

void main() {
  test(
    'unsupported font character is an explicit non-system failure with no native handoff',
    () async {
      final renderer = _Renderer(), gateway = _Gateway();
      final document = ReceiptDocument.fromSale(saleReceiptFixture());
      final pending =
          NativeReceiptOutputService(
            renderer: renderer,
            gateway: gateway,
          ).shareReceiptPdf(
            document,
            paper: ReceiptPaperFormat.a4,
            isCurrent: () => true,
          );
      renderer.completer.completeError(
        const UnsupportedReceiptCharacter(0x10ffff),
      );
      final result = await pending;
      expect(result.status, ReceiptOutputStatus.unsupportedCharacters);
      expect(result.message, contains('not supported'));
      expect(gateway.shares, 0);
    },
  );

  final pdf = Uint8List.fromList('%PDF-1.7\n test gateway document'.codeUnits);
  final document = ReceiptDocument.fromSale(saleReceiptFixture());
  test(
    'missing current authority refuses rendering and native handoff',
    () async {
      final renderer = _Renderer(), gateway = _Gateway();
      final service = NativeReceiptOutputService(
        renderer: renderer,
        gateway: gateway,
      );
      expect(
        (await service.printReceipt(
          document,
          paper: ReceiptPaperFormat.a4,
          isCurrent: () => false,
        )).status,
        ReceiptOutputStatus.scopeChanged,
      );
      expect(renderer.calls, 0);
      expect(gateway.prints, 0);
    },
  );
  for (final printing in [true, false]) {
    test(
      'scope revoked during PDF preparation refuses $printing output',
      () async {
        final renderer = _Renderer(), gateway = _Gateway();
        var current = true;
        final service = NativeReceiptOutputService(
          renderer: renderer,
          gateway: gateway,
        );
        final pending = printing
            ? service.printReceipt(
                document,
                paper: ReceiptPaperFormat.a4,
                isCurrent: () => current,
              )
            : service.shareReceiptPdf(
                document,
                paper: ReceiptPaperFormat.a4,
                isCurrent: () => current,
              );
        current = false;
        renderer.completer.complete(pdf);
        expect((await pending).status, ReceiptOutputStatus.scopeChanged);
        expect(gateway.prints + gateway.shares, 0);
      },
    );
  }
  for (final paper in ReceiptPaperFormat.values) {
    test(
      'print $paper submits one copy with a bounded safe filename',
      () async {
        final renderer = _Renderer(), gateway = _Gateway();
        renderer.completer.complete(pdf);
        final service = NativeReceiptOutputService(
          renderer: renderer,
          gateway: gateway,
        );
        final result = await service.printReceipt(
          document,
          paper: paper,
          isCurrent: () => true,
        );
        expect(result.status, ReceiptOutputStatus.submitted);
        expect(result.message, contains('Check the printer'));
        expect(gateway.prints, 1);
        expect(gateway.shares, 0);
        expect(gateway.paper, paper);
        expect(gateway.filename, endsWith('_COPY.pdf'));
        expect(gateway.filename!.length, lessThan(128));
        expect(gateway.filename, matches(RegExp(r'^[A-Za-z0-9_.]+$')));
      },
    );
  }
  test(
    'share uses explicit OS handler with a copy, not physical delivery evidence',
    () async {
      final renderer = _Renderer(), gateway = _Gateway();
      renderer.completer.complete(pdf);
      final result =
          await NativeReceiptOutputService(
            renderer: renderer,
            gateway: gateway,
          ).shareReceiptPdf(
            document,
            paper: ReceiptPaperFormat.thermal58,
            isCurrent: () => true,
          );
      expect(result.status, ReceiptOutputStatus.submitted);
      expect(result.message, contains('system PDF handler'));
      expect(gateway.shares, 1);
      expect(gateway.prints, 0);
    },
  );
  for (final error in [
    null,
    MissingPluginException('private-path'),
    StateError('private-path'),
  ]) {
    test(
      'cancelled or failed native handoff does not claim successful printing: $error',
      () async {
        final renderer = _Renderer(), gateway = _Gateway();
        renderer.completer.complete(pdf);
        gateway.accepted = false;
        gateway.error = error;
        final result =
            await NativeReceiptOutputService(
              renderer: renderer,
              gateway: gateway,
            ).printReceipt(
              document,
              paper: ReceiptPaperFormat.a4,
              isCurrent: () => true,
            );
        expect(
          result.status,
          error == null
              ? ReceiptOutputStatus.cancelled
              : error is MissingPluginException
              ? ReceiptOutputStatus.unavailable
              : ReceiptOutputStatus.failed,
        );
        expect(result.message, isNot(contains('private-path')));
      },
    );
  }
  test('malformed renderer bytes never reach native output', () async {
    final renderer = _Renderer(), gateway = _Gateway();
    renderer.completer.complete(Uint8List.fromList('not a receipt'.codeUnits));
    expect(
      (await NativeReceiptOutputService(
            renderer: renderer,
            gateway: gateway,
          ).shareReceiptPdf(
            document,
            paper: ReceiptPaperFormat.a4,
            isCurrent: () => true,
          ))
          .status,
      ReceiptOutputStatus.failed,
    );
    expect(gateway.shares, 0);
  });
}
