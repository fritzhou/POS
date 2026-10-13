import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/features/administration/domain/administration_models.dart';
import 'package:nexapos/features/catalog/domain/catalog_models.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/people/domain/people_models.dart';

void main() {
  test('PHP decimals parse exactly without binary floating point', () {
    expect(Money.parseMinor('0.29'), 29);
    expect(Money.parseMinor(' 123456789012.34 '), 12345678901234);
    expect(Money.parseMinor('1.2'), 120);
    expect(Money.parseMinor('0001'), 100);
    expect(Money.formatMinor(29), '0.29');
    expect(Money.formatMinor(12345678901234), '123456789012.34');
    expect(Money.formatMinor(-29), '-0.29');
  });
  test('money rejects precision loss, exponents, negatives and overflow', () {
    for (final invalid in [
      '-1',
      '0.001',
      '1e3',
      'NaN',
      '1,000.00',
      '90071992547409.92',
      '.29',
      '1.',
    ]) {
      expect(
        () => Money.parseMinor(invalid),
        throwsA(isA<RepositoryFailure>()),
        reason: invalid,
      );
    }
  });
  test('quantities preserve four decimals and reject imprecise formats', () {
    expect(validateQuantity('1.2300'), '1.2300');
    for (final invalid in ['-1', '1.23456', '1e2', '123456789012345']) {
      expect(
        () => validateQuantity(invalid),
        throwsA(isA<RepositoryFailure>()),
      );
    }
  });
  test('product input validates relationships and exact integral prices', () {
    expect(
      () => const ProductInput(
        name: 'A',
        sku: 'A',
        costMinor: 0,
        priceMinor: 1,
        categoryId: 'fake',
      ).validatedValues(),
      throwsA(isA<RepositoryFailure>()),
    );
    expect(
      () => const ProductInput(
        name: 'A',
        sku: 'A',
        costMinor: -1,
        priceMinor: 1,
      ).validatedValues(),
      throwsA(isA<RepositoryFailure>()),
    );
  });
  test('contact input cannot accept malformed email or UUID scopes', () {
    expect(
      () => const SupplierInput(
        name: 'Supplier',
        email: 'bad email',
      ).validatedValues(),
      throwsA(isA<RepositoryFailure>()),
    );
    expect(
      () => const CustomerInput(
        name: 'Customer',
        branchId: 'fake',
      ).validatedValues(),
      throwsA(isA<RepositoryFailure>()),
    );
    expect(
      const CustomerInput(
        name: ' Customer ',
        email: ' USER@example.test ',
      ).validatedValues()['email'],
      'user@example.test',
    );
  });
  test('business settings use basis points with useful input boundaries', () {
    expect(
      const BusinessSettingsInput(
        businessName: 'Business',
        taxBps: 1200,
      ).validatedValues()['tax_bps'],
      1200,
    );
    expect(
      () => const BusinessSettingsInput(
        businessName: 'Business',
        taxBps: 10001,
      ).validatedValues(),
      throwsA(isA<RepositoryFailure>()),
    );
  });
}
