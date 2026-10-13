import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/sync/outbox_state.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';
import 'package:nexapos/features/checkout/data/checkout_decoders.dart';
import 'package:nexapos/features/receipts/data/receipt_pdf_renderer.dart';
import 'package:nexapos/features/receipts/domain/receipt_document.dart';
import 'package:pdf/pdf.dart';

import 'receipt_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ReceiptPdfFonts fonts;
  late ReceiptPdfRenderer renderer;
  setUpAll(() async {
    ByteData data(String file) =>
        ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync());
    fonts = ReceiptPdfFonts(
      regular: data('NotoSans-Regular.ttf'),
      bold: data('NotoSans-Bold.ttf'),
      fallbacks: [data('NexaPOS-CJK-Regular.ttf')],
    );
    renderer = ReceiptPdfRenderer(fonts: fonts);
  });

  test(
    'actual PDF encodes original totals, reversals separately and manual payment evidence',
    () async {
      final pdf = _PdfRead(
        await renderer.render(
          ReceiptDocument.fromSale(
            saleReceiptFixture(reversedQuantity: 1, reversedMinor: 126),
          ),
        ),
      );
      expect(pdf.pages, isNotEmpty);
      final text = pdf.text;
      expect(text, contains('SALE RECEIPT'));
      expect(text, contains('Receipt copy'));
      expect(text, contains('Original total PHP 2.52'));
      expect(text, contains('Recorded reversals PHP 1.26'));
      expect(text, contains('Recorded reversed units: 1'));
      expect(text, contains('Card PHP 2.52'));
      expect(text, contains('Operator verified - no provider authorization'));
      expect(text, contains('Manual reference: MANUAL-REFERENCE'));
      expect(
        text,
        contains(
          'Server recorded 2026-10-12 11:04:05.000 Asia/Manila (UTC+08:00)',
        ),
      );
      expect(text, isNot(contains('PHP 1.26 Original total')));
      expect(text, isNot(contains('Cash received')));
      expect(pdf.fontCount, greaterThan(1));
      pdf.expectTextInsidePages();
    },
  );

  test(
    'cash PDF renders original tender/change and no provider verification claim',
    () async {
      final pdf = _PdfRead(
        await renderer.render(
          ReceiptDocument.fromSale(
            saleReceiptFixture(method: CheckoutPaymentMethod.cash),
          ),
        ),
      );
      expect(pdf.text, contains('Cash received PHP 3.52'));
      expect(pdf.text, contains('Change PHP 1.00'));
      expect(pdf.text, isNot(contains('provider authorization')));
    },
  );

  test(
    'historical missing cash tender and linked acceptance time are omitted',
    () async {
      final cash = _PdfRead(
        await renderer.render(
          ReceiptDocument.fromSale(
            saleReceiptFixture(
              method: CheckoutPaymentMethod.cash,
              omitCashTender: true,
            ),
          ),
        ),
      );
      expect(cash.text, contains('Cash PHP 2.52'));
      expect(cash.text, isNot(contains('Cash received')));
      expect(cash.text, isNot(contains('Change')));
      final offline = _PdfRead(
        await renderer.render(
          ReceiptDocument.fromOffline(
            offlineReceiptFixture(
              status: OutboxStatus.synced,
              serverReceiptId: receiptFixtureLinked,
            ),
          ),
        ),
      );
      expect(offline.text, contains('PROVISIONAL OFFLINE RECEIPT'));
      expect(
        offline.text,
        contains('Linked server receipt $receiptFixtureLinked'),
      );
      expect(offline.text, isNot(contains('Server accepted')));
      expect(offline.text, isNot(contains('Cash received')));
    },
  );

  test(
    'linked offline PDF stays provisional and keeps both clocks and identifiers',
    () async {
      final pdf = _PdfRead(
        await renderer.render(
          ReceiptDocument.fromOffline(
            offlineReceiptFixture(
              status: OutboxStatus.synced,
              serverReceiptId: receiptFixtureLinked,
              acceptedAt: DateTime.utc(2026, 10, 12, 2),
              reconciliationCode: 'stock_review',
              method: CheckoutPaymentMethod.gcash,
            ),
          ),
        ),
      );
      final text = pdf.text;
      expect(text, contains('PROVISIONAL OFFLINE RECEIPT'));
      expect(text, contains('Original event $receiptFixtureEvent'));
      expect(text, contains('Original local sale $receiptFixtureId'));
      expect(text, contains('Linked server receipt $receiptFixtureLinked'));
      expect(
        text,
        contains(
          'Device observed 2026-10-12 11:04:05.000 Asia/Manila (UTC+08:00)',
        ),
      );
      expect(
        text,
        contains(
          'Server accepted 2026-10-12 10:00:00.000 Asia/Manila (UTC+08:00)',
        ),
      );
      expect(text, contains('Do not collect another payment.'));
      expect(text, contains('GCash PHP 2.52'));
      expect(text, isNot(contains('Cash received')));
      expect(text, isNot(contains('Tax (')));
      expect(text, isNot(contains('Server recorded')));
      pdf.expectTextInsidePages();
    },
  );

  for (final format in ReceiptPaperFormat.values) {
    test(
      '$format preserves the largest exact original total without clipping',
      () async {
        final document = ReceiptDocument.fromSale(
          saleReceiptFixture(
            quantity: 1,
            unitPriceMinor: maximumExactInteger,
            discountMinor: 0,
            taxMinor: 0,
            taxBps: 0,
          ),
        );
        final pdf = _PdfRead(await renderer.render(document, format: format));
        expect(
          pdf.text.replaceAll(RegExp(r'\s'), ''),
          contains('OriginaltotalPHP90071992547409.91'),
        );
        expect(
          pdf.text.replaceAll(RegExp(r'\s'), ''),
          contains('CardPHP90071992547409.91'),
        );
        pdf.expectTextInsidePages();
      },
    );
    test(
      '$format has correct finite width and paginates all 100 long original items',
      () async {
        final document = ReceiptDocument.fromSale(
          saleReceiptFixture(
            count: 100,
            name: 'Original long name ${'abcdefghijklmnopqrst ' * 10}',
            footer: 'End of original receipt - final footer',
          ),
        );
        final pdf = _PdfRead(await renderer.render(document, format: format));
        expect(pdf.pages.length, greaterThan(1));
        final expectedWidth = switch (format) {
          ReceiptPaperFormat.a4 => PdfPageFormat.a4.width,
          ReceiptPaperFormat.thermal80 => 80 * PdfPageFormat.mm,
          ReceiptPaperFormat.thermal58 => 58 * PdfPageFormat.mm,
        };
        for (final page in pdf.pages) {
          expect(page.width, closeTo(expectedWidth, .02));
          expect(page.height, lessThanOrEqualTo(PdfPageFormat.a4.height + .02));
          expect(page.height, greaterThan(100));
        }
        final text = pdf.text;
        for (var index = 0; index < 100; index++) {
          expect(text, contains('SKU ORIGINAL-SKU-$index'));
        }
        expect(text, contains('Original total PHP 252.00'));
        expect(text, contains('End of original receipt - final footer'));
        expect(
          RegExp('Receipt copy - Page ').allMatches(text).length,
          pdf.pages.length,
        );
        pdf.expectTextInsidePages();
      },
    );
  }

  test(
    'actual PostgreSQL sale wire snapshot decodes and renders original exact amounts',
    () async {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/phase3_rpc_contract.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final sale = receiptFromRow(fixture['sale'] as Map<String, dynamic>);
      final document = ReceiptDocument.fromSale(sale);
      final pdf = _PdfRead(
        await renderer.render(document, format: ReceiptPaperFormat.thermal58),
      );
      final compact = pdf.text.replaceAll(RegExp(r'\s'), '');
      expect(compact, contains('SubtotalPHP90071992547409.91'));
      expect(compact, contains('DiscountPHP90071992547409.89'));
      expect(compact, contains('OriginaltotalPHP0.03'));
      expect(compact, contains('CashreceivedPHP0.05'));
      expect(compact, contains('ChangePHP0.02'));
      expect(
        compact,
        contains(
          'Serverrecorded2026-10-0920:22:04.351343Asia/Manila(UTC+08:00)',
        ),
      );
      expect(document.id, sale.id);
      expect(document.sourceAtUtc, sale.createdAt.toUtc());
      pdf.expectTextInsidePages();
    },
  );

  test(
    'single oversized text field spans pages without truncating its final word',
    () async {
      final document = ReceiptDocument.fromSale(
        saleReceiptFixture(
          businessName:
              '${'Long original business line ' * 130} FINALBUSINESSWORD',
          footer: '${'Long original footer line ' * 130} FINALFOOTERWORD',
        ),
      );
      final pdf = _PdfRead(
        await renderer.render(document, format: ReceiptPaperFormat.thermal58),
      );
      expect(pdf.pages.length, greaterThan(3));
      expect(pdf.text, contains('FINALBUSINESSWORD'));
      expect(pdf.text, contains('FINALFOOTERWORD'));
      expect(pdf.text, contains('Original total PHP 2.52'));
      pdf.expectTextInsidePages();
    },
  );

  test(
    'Latin, CJK, Hangul and escaping survive real PDF Unicode extraction',
    () async {
      const name = 'Café naïve 茶 中文 日本語 한국어 (\\) < & >';
      final pdf = _PdfRead(
        await renderer.render(
          ReceiptDocument.fromSale(saleReceiptFixture(name: name)),
        ),
      );
      final compact = pdf.text.replaceAll(RegExp(r'\s'), '');
      expect(compact, contains(name.replaceAll(RegExp(r'\s'), '')));
      expect(pdf.fontCount, greaterThanOrEqualTo(3));
      pdf.expectTextInsidePages();
    },
  );

  test(
    'unsupported Unicode fails before output instead of silently replacing it',
    () async {
      final document = ReceiptDocument.fromSale(
        saleReceiptFixture(name: 'Original product 🦄'),
      );
      await expectLater(
        renderer.render(document),
        throwsA(
          isA<UnsupportedReceiptCharacter>().having(
            (error) => error.rune,
            'original rune',
            0x1f984,
          ),
        ),
      );
      expect(document.lines.single.name, 'Original product 🦄');
    },
  );

  test(
    'non-BMP glyph coverage cannot bypass PDF Unicode fidelity checks',
    () async {
      final rune = TtfParser(fonts.fallbacks.single).charToGlyphIndexMap.entries
          .firstWhere((entry) => entry.key > 0xffff && entry.value != 0)
          .key;
      final document = ReceiptDocument.fromSale(
        saleReceiptFixture(name: String.fromCharCode(rune)),
      );
      await expectLater(
        renderer.render(document),
        throwsA(
          isA<UnsupportedReceiptCharacter>().having(
            (error) => error.rune,
            'font-covered original rune',
            rune,
          ),
        ),
      );
    },
  );

  test(
    'bundled default font loader works without a remote font service',
    () async {
      final pdf = _PdfRead(
        await ReceiptPdfRenderer().render(
          ReceiptDocument.fromOffline(offlineReceiptFixture(name: 'Café 茶')),
        ),
      );
      expect(pdf.text.replaceAll(RegExp(r'\s'), ''), contains('Café茶'));
      expect(pdf.text, contains('PROVISIONAL OFFLINE RECEIPT'));
    },
  );
}

/// Small independent reader for PDFs generated by this renderer. It reads the
/// actual page objects, deflated content streams and embedded ToUnicode maps.
/// It needs no external PDF binary or package, and never reads renderer state.
class _PdfRead {
  _PdfRead(Uint8List bytes) {
    final source = latin1.decode(bytes);
    expect(source, startsWith('%PDF-'));
    expect(source.trimRight(), endsWith('%%EOF'));
    for (final match in RegExp(
      r'(\d+)\s+0\s+obj\s*([\s\S]*?)endobj',
    ).allMatches(source)) {
      final body = match.group(2)!;
      final stream = RegExp(r'\bstream\r?\n').firstMatch(body);
      final header = stream == null ? body : body.substring(0, stream.start);
      Uint8List? content;
      if (stream != null) {
        final length = int.parse(
          RegExp(r'/Length\s+(\d+)').firstMatch(header)!.group(1)!,
        );
        final raw = latin1.encode(
          body.substring(stream.end, stream.end + length),
        );
        content = Uint8List.fromList(
          header.contains('/FlateDecode') ? ZLibDecoder().convert(raw) : raw,
        );
      }
      _objects[int.parse(match.group(1)!)] = _PdfObject(header, content);
    }
    for (final entry in _objects.entries) {
      final unicode = RegExp(
        r'/ToUnicode\s+(\d+)\s+0\s+R',
      ).firstMatch(entry.value.header);
      if (unicode == null) continue;
      final mapBytes = _objects[int.parse(unicode.group(1)!)]!.stream!;
      final body = latin1.decode(mapBytes);
      final section = RegExp(
        r'beginbfchar([\s\S]*?)endbfchar',
      ).firstMatch(body)!.group(1)!;
      _fonts['F${entry.key}'] = {
        for (final pair in RegExp(
          r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
        ).allMatches(section))
          int.parse(pair.group(1)!, radix: 16): int.parse(
            pair.group(2)!,
            radix: 16,
          ),
      };
      final widthsRef = RegExp(
        r'/W\s*\[\s*0\s+(\d+)\s+0\s+R\s*\]',
      ).firstMatch(entry.value.header)!;
      _widths['F${entry.key}'] = RegExp(r'-?\d+(?:\.\d+)?')
          .allMatches(_objects[int.parse(widthsRef.group(1)!)]!.header)
          .map((number) => double.parse(number.group(0)!))
          .toList();
    }
    for (final object in _objects.values) {
      if (!RegExp(r'/Type\s*/Page\b').hasMatch(object.header)) continue;
      final media = RegExp(
        r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]',
      ).firstMatch(object.header)!;
      final contents = RegExp(
        r'/Contents\s+(\d+)\s+0\s+R',
      ).firstMatch(object.header)!;
      final content = latin1.decode(
        _objects[int.parse(contents.group(1)!)]!.stream!,
      );
      pages.add(
        _PdfPage(
          double.parse(media.group(1)!),
          double.parse(media.group(2)!),
          content,
        ),
      );
    }
    expect(pages, isNotEmpty);
  }

  final _objects = <int, _PdfObject>{};
  final _fonts = <String, Map<int, int>>{};
  final _widths = <String, List<double>>{};
  final pages = <_PdfPage>[];
  int get fontCount => _fonts.length;

  String get text {
    final all = StringBuffer();
    final tokens = RegExp(r'/(F\d+)\s+[\d.]+\s+Tf|<([0-9A-Fa-f]+)>|\bET\b');
    for (final page in pages) {
      String? font;
      for (final token in tokens.allMatches(page.content)) {
        if (token.group(1) != null) {
          font = token.group(1);
        } else if (token.group(2) != null) {
          final encoded = token.group(2)!;
          final map = _fonts[font]!;
          for (var offset = 0; offset < encoded.length; offset += 4) {
            final code = int.parse(
              encoded.substring(offset, offset + 4),
              radix: 16,
            );
            final rune = map[code];
            expect(
              rune,
              isNotNull,
              reason: 'Encoded glyph must have an actual Unicode mapping.',
            );
            all.writeCharCode(rune!);
          }
        } else {
          all.write(' ');
        }
      }
      all.write(' ');
    }
    return all.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void expectTextInsidePages() {
    final positions = RegExp(r'(-?[\d.]+)\s+(-?[\d.]+)\s+Td');
    for (final page in pages) {
      expect(positions.allMatches(page.content), isNotEmpty);
      for (final position in positions.allMatches(page.content)) {
        final x = double.parse(position.group(1)!);
        final y = double.parse(position.group(2)!);
        expect(
          x,
          inInclusiveRange(0, page.width),
          reason: 'Text baseline must be inside the page horizontally.',
        );
        expect(
          y,
          inInclusiveRange(0, page.height),
          reason: 'Text baseline must be inside the page vertically.',
        );
      }
      final runs = RegExp(
        r'/(F\d+)\s+([\d.]+)\s+Tf|(-?[\d.]+)\s+(-?[\d.]+)\s+Td|<([0-9A-Fa-f]+)>',
      );
      String? font;
      var fontSize = 0.0;
      var x = 0.0;
      for (final run in runs.allMatches(page.content)) {
        if (run.group(1) != null) {
          font = run.group(1);
          fontSize = double.parse(run.group(2)!);
        } else if (run.group(3) != null) {
          x = double.parse(run.group(3)!);
        } else {
          final hex = run.group(5)!;
          var width = 0.0;
          for (var offset = 0; offset < hex.length; offset += 4) {
            width +=
                _widths[font]![int.parse(
                  hex.substring(offset, offset + 4),
                  radix: 16,
                )] *
                fontSize /
                1000;
          }
          expect(
            x + width,
            lessThanOrEqualTo(page.width + .1),
            reason: 'Actual embedded glyph widths must fit inside the page.',
          );
        }
      }
    }
  }
}

class _PdfObject {
  const _PdfObject(this.header, this.stream);
  final String header;
  final Uint8List? stream;
}

class _PdfPage {
  const _PdfPage(this.width, this.height, this.content);
  final double width, height;
  final String content;
}
