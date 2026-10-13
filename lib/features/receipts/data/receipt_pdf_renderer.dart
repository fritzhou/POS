import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../catalog/domain/repository_support.dart';
import '../domain/receipt_document.dart';

/// Font bytes are bundled with the application or explicitly injected. This
/// renderer never fetches fonts or business information from a network.
class ReceiptPdfFonts {
  ReceiptPdfFonts({
    required ByteData regular,
    required ByteData bold,
    List<ByteData> fallbacks = const [],
  }) : regular = _copy(regular),
       bold = _copy(bold),
       fallbacks = List.unmodifiable(fallbacks.map(_copy));

  final ByteData regular, bold;
  final List<ByteData> fallbacks;

  static ByteData _copy(ByteData source) => ByteData.sublistView(
    Uint8List.fromList(
      source.buffer.asUint8List(source.offsetInBytes, source.lengthInBytes),
    ),
  );

  static Future<ReceiptPdfFonts> loadBundled() async {
    final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final fallback = await rootBundle.load(
      'assets/fonts/NexaPOS-CJK-Regular.ttf',
    );
    return ReceiptPdfFonts(regular: regular, bold: bold, fallbacks: [fallback]);
  }
}

class UnsupportedReceiptCharacter implements Exception {
  const UnsupportedReceiptCharacter(this.rune);
  final int rune;

  @override
  String toString() =>
      'PDF export does not support character U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}. The original receipt remains unchanged.';
}

class ReceiptPdfRenderer {
  ReceiptPdfRenderer({this.fonts});
  final ReceiptPdfFonts? fonts;
  Future<ReceiptPdfFonts>? _bundledFonts;

  Future<Uint8List> render(
    ReceiptDocument document, {
    ReceiptPaperFormat format = ReceiptPaperFormat.thermal80,
  }) async {
    final fontBytes =
        fonts ?? await (_bundledFonts ??= ReceiptPdfFonts.loadBundled());
    _verifyCoverage(document, fontBytes);
    final regular = pw.Font.ttf(fontBytes.regular);
    final bold = pw.Font.ttf(fontBytes.bold);
    final fallbacks = [regular, bold, ...fontBytes.fallbacks.map(pw.Font.ttf)];
    final thermal = format != ReceiptPaperFormat.a4;
    final fontSize = format == ReceiptPaperFormat.thermal58 ? 8.0 : 9.0;
    final pageFormat = switch (format) {
      ReceiptPaperFormat.a4 => PdfPageFormat.a4,
      // Finite pages allow the PDF engine to paginate every item instead of
      // clipping a long sale into a single thermal bitmap/page.
      ReceiptPaperFormat.thermal80 => PdfPageFormat(
        80 * PdfPageFormat.mm,
        200 * PdfPageFormat.mm,
      ),
      ReceiptPaperFormat.thermal58 => PdfPageFormat(
        58 * PdfPageFormat.mm,
        200 * PdfPageFormat.mm,
      ),
    };
    final pdf = pw.Document(
      title: '${document.title} ${document.receiptNumber}',
      creator: 'NexaPOS',
      subject: document.isProvisional
          ? 'Copy of the original provisional local receipt; server links are separate.'
          : 'Copy of the original accepted sale snapshot.',
      theme:
          pw.ThemeData.withFont(
            base: regular,
            bold: bold,
            fontFallback: fallbacks,
          ).copyWith(
            defaultTextStyle: pw.TextStyle(
              font: regular,
              fontBold: bold,
              fontFallback: fallbacks,
              fontSize: fontSize,
              lineSpacing: 2,
            ),
          ),
    );
    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.all(
          thermal ? 3 * PdfPageFormat.mm : 15 * PdfPageFormat.mm,
        ),
        maxPages: 1000,
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              document.title,
              style: pw.TextStyle(font: bold, fontSize: fontSize + 1),
            ),
            pw.Text('Receipt copy'),
            pw.Text(
              'Receipt ${document.receiptNumber}',
              style: pw.TextStyle(fontSize: fontSize - 1),
            ),
            pw.Divider(thickness: .4),
          ],
        ),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 5),
          child: pw.Text(
            'Receipt copy - Page ${context.pageNumber} of ${context.pagesCount}',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: fontSize - 1),
          ),
        ),
        build: (_) => _content(document, bold),
      ),
    );
    return pdf.save();
  }

  List<pw.Widget> _content(ReceiptDocument document, pw.Font bold) {
    String money(int amount) =>
        '${document.currency} ${Money.formatMinor(amount)}';
    pw.Widget text(String value, {bool strong = false}) => pw.Text(
      value.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
      overflow: pw.TextOverflow.span,
      style: strong ? pw.TextStyle(font: bold) : null,
    );
    pw.Widget amount(String label, int value, {bool strong = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  label,
                  style: strong ? pw.TextStyle(font: bold) : null,
                ),
              ),
              pw.SizedBox(width: 5),
              pw.Flexible(
                child: pw.Text(
                  money(value),
                  textAlign: pw.TextAlign.right,
                  style: strong ? pw.TextStyle(font: bold) : null,
                ),
              ),
            ],
          ),
        );
    return [
      text(document.businessName ?? 'Business receipt', strong: true),
      if (document.branchName != null) text(document.branchName!),
      if (document.address != null) text(document.address!),
      if (document.contact != null) text(document.contact!),
      pw.SizedBox(height: 8),
      text(
        '${document.isProvisional ? 'Device observed' : 'Server recorded'} ${_manilaTime(document.sourceAtUtc)}',
      ),
      if (document.isProvisional) ...[
        text(document.offlineStatusLabel!, strong: true),
        text(
          'Original local receipt. Synchronization records a server link separately; this copy remains provisional.',
        ),
        text('Original event ${document.eventId}'),
        text('Original local sale ${document.id}'),
        text('Offline sequence ${document.offlineSequence}'),
        if (document.serverReceiptId != null) ...[
          text('Linked server receipt ${document.serverReceiptId}'),
          if (document.serverAcceptedAtUtc != null)
            text(
              'Server accepted ${_manilaTime(document.serverAcceptedAtUtc!)}',
            ),
        ],
        if (document.failureCode != null || document.reconciliationCode != null)
          text(
            'Review required. Original paid evidence is preserved. Do not collect another payment.',
            strong: true,
          ),
      ] else
        text('Sale ${document.id}'),
      pw.Divider(),
      text('Original items', strong: true),
      for (var index = 0; index < document.lines.length; index++) ...[
        pw.SizedBox(height: 6),
        text('${index + 1}. ${document.lines[index].name}', strong: true),
        text('SKU ${document.lines[index].sku}'),
        text(
          '${document.lines[index].quantity} x ${money(document.lines[index].unitPriceMinor)}',
        ),
        amount('Line total', document.lines[index].totalMinor),
        if (document.lines[index].discountMinor != 0)
          amount('Line discount', document.lines[index].discountMinor),
        if (document.lines[index].reversedQuantity != 0)
          text(
            'Recorded reversed units: ${document.lines[index].reversedQuantity}',
          ),
      ],
      pw.Divider(),
      amount('Subtotal', document.subtotalMinor),
      amount('Discount', document.discountMinor),
      amount(
        document.taxBps == null
            ? 'Tax'
            : 'Tax (${Money.formatMinor(document.taxBps!)}%)',
        document.taxMinor,
      ),
      amount('Original total', document.totalMinor, strong: true),
      if (document.recordedReversalMinor != 0) ...[
        pw.SizedBox(height: 6),
        amount('Recorded reversals', document.recordedReversalMinor),
        text(
          'Reversals are separate records. Original totals and payment allocations above remain unchanged.',
        ),
      ],
      pw.Divider(),
      text('Original payments', strong: true),
      for (final payment in document.payments) ...[
        pw.SizedBox(height: 5),
        amount(payment.label, payment.amountMinor),
        if (payment.operatorVerified) ...[
          text('Operator verified - no provider authorization'),
          text('Manual reference: ${payment.reference}'),
        ] else if (payment.tenderedMinor != null) ...[
          amount('Cash received', payment.tenderedMinor!),
          amount('Change', payment.changeMinor!),
        ],
        if (payment.reversedMinor != 0)
          amount('Recorded reversed amount', payment.reversedMinor),
      ],
      if (document.footer != null) ...[
        pw.SizedBox(height: 10),
        text(document.footer!),
      ],
    ];
  }

  void _verifyCoverage(ReceiptDocument document, ReceiptPdfFonts fonts) {
    final parsers = [
      fonts.regular,
      fonts.bold,
      ...fonts.fallbacks,
    ].map(TtfParser.new).toList();
    final texts = [
      document.receiptNumber,
      document.id,
      document.businessName,
      document.branchName,
      document.address,
      document.contact,
      document.footer,
      document.eventId,
      document.serverReceiptId,
      for (final line in document.lines) ...[line.name, line.sku],
      for (final payment in document.payments) payment.reference,
    ];
    for (final value in texts.whereType<String>()) {
      for (final rune in value.runes) {
        if (rune == 9 || rune == 10 || rune == 13) continue;
        // pdf 3.13.1 writes non-BMP ToUnicode values as a single scalar rather
        // than UTF-16 surrogate pairs. Refuse those characters rather than
        // create a visually plausible PDF with corrupted extractable text.
        if (rune > 0xffff) throw UnsupportedReceiptCharacter(rune);
        if (!parsers.any(
          (parser) => (parser.charToGlyphIndexMap[rune] ?? 0) != 0,
        )) {
          throw UnsupportedReceiptCharacter(rune);
        }
      }
    }
  }

  String _manilaTime(DateTime utc) {
    final local = utc.add(const Duration(hours: 8)).toIso8601String();
    return '${local.replaceFirst('T', ' ').replaceFirst(RegExp(r'Z$'), '')} Asia/Manila (UTC+08:00)';
  }
}
