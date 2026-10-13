import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/features/scanning/domain/hid_scan_decoder.dart';

HidScanResult burst(
  HidScanDecoder decoder,
  String barcode, {
  int gap = 5,
  bool prefix = true,
}) {
  var elapsed = Duration.zero;
  if (prefix) decoder.feed(timestamp: elapsed, prefix: true);
  for (final character in barcode.split('')) {
    elapsed += Duration(milliseconds: gap);
    decoder.feed(timestamp: elapsed, character: character);
  }
  return decoder.feed(
    timestamp: elapsed + Duration(milliseconds: gap),
    terminator: true,
  );
}

void main() {
  test('default prefix distinguishes an exact case-preserved barcode', () {
    final decoder = HidScanDecoder(const HidScannerConfiguration());
    expect(burst(decoder, 'abCD-0123', prefix: false).barcode, isNull);
    expect(burst(decoder, 'abCD-0123').barcode, 'abCD-0123');
  });

  test('never emits an incomplete or too-short barcode', () {
    final decoder = HidScanDecoder(const HidScannerConfiguration());
    decoder.feed(timestamp: Duration.zero, prefix: true);
    expect(
      decoder.feed(timestamp: Duration.zero, character: 'a').barcode,
      isNull,
    );
    expect(burst(decoder, '123').barcode, isNull);
    expect(burst(decoder, '1234').barcode, '1234');
  });

  test(
    'slow or reversed timestamps reject the entire burst including suffix',
    () {
      final decoder = HidScanDecoder(
        const HidScannerConfiguration(prefix: ScannerPrefix.none),
      );
      decoder.feed(timestamp: const Duration(milliseconds: 50), character: '1');
      decoder.feed(timestamp: const Duration(milliseconds: 40), character: '2');
      for (final character in '34567890'.split('')) {
        decoder.feed(
          timestamp: const Duration(milliseconds: 60),
          character: character,
        );
      }
      expect(
        decoder
            .feed(timestamp: const Duration(milliseconds: 65), terminator: true)
            .barcode,
        isNull,
      );
      expect(
        burst(decoder, '12345678', gap: 41, prefix: false).barcode,
        isNull,
      );
      expect(
        burst(decoder, '12345678', gap: 5, prefix: false).barcode,
        '12345678',
      );
    },
  );

  test(
    'maximum duration bounds even a stream with individually timely keys',
    () {
      final decoder = HidScanDecoder(const HidScannerConfiguration());
      expect(burst(decoder, '1' * 100, gap: 25).barcode, isNull);
    },
  );

  test('overflow rejects suffix and fresh prefix permits next scan', () {
    final decoder = HidScanDecoder(const HidScannerConfiguration());
    expect(burst(decoder, 'a' * 129, gap: 1).barcode, isNull);
    expect(burst(decoder, 'a' * 128, gap: 1).barcode, 'a' * 128);
  });

  test(
    'control, whitespace, unicode and malformed character events fail closed',
    () {
      for (final character in ['\n', ' ', 'é', 'ab', '\u007f']) {
        final decoder = HidScanDecoder(const HidScannerConfiguration());
        decoder.feed(timestamp: Duration.zero, prefix: true);
        decoder.feed(timestamp: Duration.zero, character: character);
        for (final tail in '12345678'.split('')) {
          decoder.feed(timestamp: Duration.zero, character: tail);
        }
        expect(
          decoder.feed(timestamp: Duration.zero, terminator: true).barcode,
          isNull,
        );
      }
    },
  );

  test(
    'modifier and repeat rejection cannot be repaired by later characters',
    () {
      final decoder = HidScanDecoder(const HidScannerConfiguration());
      decoder.feed(timestamp: Duration.zero, prefix: true);
      decoder.feed(timestamp: Duration.zero, character: '1', invalid: true);
      for (final tail in '23456789'.split('')) {
        decoder.feed(timestamp: Duration.zero, character: tail);
      }
      expect(
        decoder.feed(timestamp: Duration.zero, terminator: true).barcode,
        isNull,
      );
    },
  );

  test(
    'terminator consumes rejected burst so it cannot trigger a focused button',
    () {
      final decoder = HidScanDecoder(const HidScannerConfiguration());
      expect(burst(decoder, '12', gap: 100).consumed, isTrue);
      expect(
        decoder.feed(timestamp: Duration.zero, terminator: true).consumed,
        isFalse,
      );
    },
  );

  test('reset on route, focus or scope change discards partial proof', () {
    final decoder = HidScanDecoder(const HidScannerConfiguration());
    decoder.feed(timestamp: Duration.zero, prefix: true);
    for (final character in '1234'.split('')) {
      decoder.feed(timestamp: Duration.zero, character: character);
    }
    decoder.reset();
    expect(
      decoder.feed(timestamp: Duration.zero, terminator: true).barcode,
      isNull,
    );
  });

  test('unsupported timing configuration captures nothing', () {
    for (final gap in [0, 9, 101, 1000]) {
      final decoder = HidScanDecoder(
        HidScannerConfiguration(maximumGap: Duration(milliseconds: gap)),
      );
      expect(burst(decoder, '12345678').barcode, isNull);
    }
  });
}
