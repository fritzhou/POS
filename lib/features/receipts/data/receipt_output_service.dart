import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../domain/receipt_document.dart';
import 'receipt_pdf_renderer.dart';

enum ReceiptOutputStatus {
  submitted,
  cancelled,
  unavailable,
  scopeChanged,
  failed,
  unsupportedCharacters,
}

class ReceiptOutputResult {
  const ReceiptOutputResult(this.status, this.message);
  final ReceiptOutputStatus status;
  final String message;
}

abstract interface class ReceiptOutputService {
  Future<ReceiptOutputResult> printReceipt(
    ReceiptDocument document, {
    required ReceiptPaperFormat paper,
    required bool Function() isCurrent,
  });
  Future<ReceiptOutputResult> shareReceiptPdf(
    ReceiptDocument document, {
    required ReceiptPaperFormat paper,
    required bool Function() isCurrent,
  });
}

/// A user-requested OS handoff; it never acknowledges a physical print or sale.
abstract interface class ReceiptOutputGateway {
  Future<bool> printPdf({
    required Uint8List bytes,
    required String filename,
    required ReceiptPaperFormat paper,
    required bool Function() isCurrent,
  });
  Future<bool> sharePdf({required Uint8List bytes, required String filename});
}

class SystemReceiptOutputGateway implements ReceiptOutputGateway {
  const SystemReceiptOutputGateway();
  @override
  Future<bool> printPdf({
    required Uint8List bytes,
    required String filename,
    required ReceiptPaperFormat paper,
    required bool Function() isCurrent,
  }) {
    if (!isCurrent()) throw const _ChangedScope();
    // The explicit OS handoff is the boundary. Android may pause/lock Flutter
    // before it asks for layout. Return only the already authorized snapshot;
    // never read a replacement account or render a new document in callbacks.
    final frozen = Uint8List.fromList(bytes);
    return Printing.layoutPdf(
      name: filename,
      dynamicLayout: false,
      format: switch (paper) {
        ReceiptPaperFormat.a4 => PdfPageFormat.a4,
        ReceiptPaperFormat.thermal80 => PdfPageFormat(
          80 * PdfPageFormat.mm,
          200 * PdfPageFormat.mm,
        ),
        ReceiptPaperFormat.thermal58 => PdfPageFormat(
          58 * PdfPageFormat.mm,
          200 * PdfPageFormat.mm,
        ),
      },
      onLayout: (_) async => Uint8List.fromList(frozen),
    );
  }

  @override
  Future<bool> sharePdf({required Uint8List bytes, required String filename}) =>
      Printing.sharePdf(bytes: bytes, filename: filename);
}

class NativeReceiptOutputService implements ReceiptOutputService {
  NativeReceiptOutputService({
    ReceiptPdfRenderer? renderer,
    ReceiptOutputGateway? gateway,
  }) : renderer = renderer ?? ReceiptPdfRenderer(),
       gateway = gateway ?? const SystemReceiptOutputGateway();
  final ReceiptPdfRenderer renderer;
  final ReceiptOutputGateway gateway;
  @override
  Future<ReceiptOutputResult> printReceipt(
    ReceiptDocument document, {
    required ReceiptPaperFormat paper,
    required bool Function() isCurrent,
  }) => _output(document, paper, isCurrent, printing: true);
  @override
  Future<ReceiptOutputResult> shareReceiptPdf(
    ReceiptDocument document, {
    required ReceiptPaperFormat paper,
    required bool Function() isCurrent,
  }) => _output(document, paper, isCurrent, printing: false);

  Future<ReceiptOutputResult> _output(
    ReceiptDocument document,
    ReceiptPaperFormat paper,
    bool Function() isCurrent, {
    required bool printing,
  }) async {
    const changed = ReceiptOutputResult(
      ReceiptOutputStatus.scopeChanged,
      'Business access changed. Open the receipt again before exporting.',
    );
    if (!isCurrent()) return changed;
    try {
      final bytes = await renderer.render(document, format: paper);
      if (!isCurrent()) return changed;
      if (bytes.length < 8 ||
          bytes.length > 128 * 1024 * 1024 ||
          String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        throw const FormatException('Invalid PDF document');
      }
      final scopeId = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                document.organizationId,
                document.branchId,
                document.id,
              ]),
            ),
          )
          .toString()
          .substring(0, 32);
      final filename = 'NexaPOS_${document.origin.name}_${scopeId}_COPY.pdf';
      final submitted = printing
          ? await gateway.printPdf(
              bytes: bytes,
              filename: filename,
              paper: paper,
              isCurrent: isCurrent,
            )
          : await gateway.sharePdf(bytes: bytes, filename: filename);
      return ReceiptOutputResult(
        submitted
            ? ReceiptOutputStatus.submitted
            : ReceiptOutputStatus.cancelled,
        submitted
            ? printing
                  ? 'Receipt copy submitted to the system print service. Check the printer for completion.'
                  : 'PDF handed to the system PDF handler. Use its save or share controls.'
            : 'Receipt output was cancelled or was not submitted. The original record is unchanged.',
      );
    } on UnsupportedReceiptCharacter {
      return const ReceiptOutputResult(
        ReceiptOutputStatus.unsupportedCharacters,
        'A character in this receipt is not supported for PDF output. The original record remains readable.',
      );
    } on _ChangedScope {
      return changed;
    } on MissingPluginException {
      return const ReceiptOutputResult(
        ReceiptOutputStatus.unavailable,
        'Receipt output is unavailable on this platform.',
      );
    } on UnimplementedError {
      return const ReceiptOutputResult(
        ReceiptOutputStatus.unavailable,
        'Receipt output is unavailable on this platform.',
      );
    } on Object {
      return const ReceiptOutputResult(
        ReceiptOutputStatus.failed,
        'Receipt output could not be completed. Unsupported characters or a system error may prevent export. The original record is unchanged.',
      );
    }
  }
}

class _ChangedScope implements Exception {
  const _ChangedScope();
}
