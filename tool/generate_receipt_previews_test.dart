// Isolated test documents, excluded from the application and ordinary tests.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/features/receipts/data/receipt_pdf_renderer.dart';
import 'package:nexapos/features/receipts/domain/receipt_document.dart';
import '../test/receipts/receipt_fixtures.dart';

void main() {
  testWidgets('create clearly labelled typography test PDF artifacts', (
    tester,
  ) async {
    final renderer = ReceiptPdfRenderer();
    final document = ReceiptDocument.fromSale(
      saleReceiptFixture(
        name: 'Coffee 咖啡 コーヒー 커피 – Café',
        businessName: 'ISOLATED TEST FIXTURE',
        footer: 'Test document only. No actual sale or payment.',
        count: 12,
        reversedQuantity: 1,
        reversedMinor: 125,
      ),
    );
    await tester.runAsync(() async {
      for (final paper in ReceiptPaperFormat.values) {
        final bytes = await renderer.render(document, format: paper);
        final file = File('build/validation/receipt-test-${paper.name}.pdf');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      }
    });
  });
}
