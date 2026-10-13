enum ScannerPrefix { f9, none }

enum ScannerTerminator { enter, tab }

/// The prefix is deliberate: ordinary keyboard input is not a scan by default.
class HidScannerConfiguration {
  const HidScannerConfiguration({
    this.prefix = ScannerPrefix.f9,
    this.terminator = ScannerTerminator.enter,
    this.maximumGap = const Duration(milliseconds: 40),
  });

  final ScannerPrefix prefix;
  final ScannerTerminator terminator;
  final Duration maximumGap;

  bool get valid =>
      maximumGap >= const Duration(milliseconds: 10) &&
      maximumGap <= const Duration(milliseconds: 100);
}

class HidScanResult {
  const HidScanResult({this.barcode, this.consumed = false});
  final String? barcode;
  final bool consumed;
}

/// Decodes complete, bounded HID bursts; never normalizes barcode case or space.
/// A malformed burst stays rejected until its terminator or a fresh prefix,
/// preventing a valid-looking suffix from being accepted as another barcode.
class HidScanDecoder {
  HidScanDecoder(this.configuration);

  final HidScannerConfiguration configuration;
  static const minimumLength = 4;
  static const maximumLength = 128;
  static const maximumDuration = Duration(seconds: 2);
  final StringBuffer _buffer = StringBuffer();
  Duration? _started, _previous;
  bool _armed = false, _rejected = false;

  void reset() {
    _buffer.clear();
    _started = null;
    _previous = null;
    _armed = false;
    _rejected = false;
  }

  HidScanResult feed({
    required Duration timestamp,
    String? character,
    bool prefix = false,
    bool terminator = false,
    bool invalid = false,
  }) {
    if (!configuration.valid) {
      reset();
      return const HidScanResult();
    }
    if (prefix && configuration.prefix == ScannerPrefix.f9) {
      reset();
      _armed = true;
      _started = _previous = timestamp;
      return const HidScanResult(consumed: true);
    }
    if (!_armed && configuration.prefix == ScannerPrefix.f9) {
      return const HidScanResult();
    }
    if (terminator) {
      final consumed = _armed;
      final valid =
          _armed &&
          !_rejected &&
          !invalid &&
          _timely(timestamp) &&
          _buffer.length >= minimumLength &&
          _buffer.length <= maximumLength;
      final barcode = valid ? _buffer.toString() : null;
      reset();
      return HidScanResult(barcode: barcode, consumed: consumed);
    }
    if (invalid || character == null || character.runes.length != 1) {
      if (_armed) _rejected = true;
      return HidScanResult(consumed: _armed);
    }
    final rune = character.runes.single;
    if (rune < 33 || rune == 127 || rune > 126) {
      if (_armed) _rejected = true;
      return HidScanResult(consumed: _armed);
    }
    if (!_armed) {
      _armed = true;
      _started = timestamp;
    } else if (!_timely(timestamp)) {
      _rejected = true;
    }
    _previous = timestamp;
    if (_buffer.length >= maximumLength) _rejected = true;
    if (!_rejected) _buffer.write(character);
    return const HidScanResult(consumed: true);
  }

  bool _timely(Duration timestamp) =>
      _previous != null &&
      _started != null &&
      timestamp >= _previous! &&
      timestamp - _previous! <= configuration.maximumGap &&
      timestamp - _started! <= maximumDuration;
}
