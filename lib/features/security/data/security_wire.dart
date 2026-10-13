import '../../catalog/domain/repository_support.dart';

/// Server security state must retain its tenant and branch provenance. A
/// malformed response is transport uncertainty, never permission to continue.
Map<String, dynamic> securityRow(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid security record');
  }
  return value;
}

List<Map<String, dynamic>> securityRows(Object? value, {int maximum = 101}) {
  if (value is! List || value.length > maximum) {
    throw const FormatException('Invalid security page');
  }
  return value.map(securityRow).toList(growable: false);
}

String securityId(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String) throw const FormatException('Invalid security ID');
  try {
    return validateId(value).toLowerCase();
  } on RepositoryFailure {
    throw const FormatException('Invalid security ID');
  }
}

String? securityOptionalId(Map<String, dynamic> row, String key) =>
    row[key] == null ? null : securityId(row, key);

String securityText(
  Map<String, dynamic> row,
  String key, {
  int maximum = 120,
  int minimum = 1,
}) {
  final value = row[key];
  if (value is! String ||
      value.length < minimum ||
      value.length > maximum ||
      value.trim() != value ||
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]').hasMatch(value)) {
    throw const FormatException('Invalid security text');
  }
  return value;
}

String? securityOptionalText(
  Map<String, dynamic> row,
  String key, {
  int maximum = 120,
}) => row[key] == null ? null : securityText(row, key, maximum: maximum);

int securityInteger(
  Map<String, dynamic> row,
  String key, {
  int minimum = 0,
  int maximum = 9007199254740991,
}) {
  final value = row[key];
  if (value is! int || value < minimum || value > maximum) {
    throw const FormatException('Invalid security integer');
  }
  return value;
}

bool securityBoolean(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! bool) throw const FormatException('Invalid security boolean');
  return value;
}

DateTime securityTime(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$',
      ).hasMatch(value)) {
    throw const FormatException('Invalid security time');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      parsed.toUtc().year < 2000 ||
      parsed.toUtc().year > 9999) {
    throw const FormatException('Invalid security time');
  }
  if (!value.endsWith('Z')) {
    final offset = value.substring(value.length - 6);
    if (int.parse(offset.substring(1, 3)) > 23 ||
        int.parse(offset.substring(4, 6)) > 59) {
      throw const FormatException('Invalid security time offset');
    }
  }
  // Dart normalizes invalid calendar fields. Check the source date/time in
  // its original offset before accepting a server observation.
  final wall = DateTime.utc(
    int.parse(value.substring(0, 4)),
    int.parse(value.substring(5, 7)),
    int.parse(value.substring(8, 10)),
    int.parse(value.substring(11, 13)),
    int.parse(value.substring(14, 16)),
    int.parse(value.substring(17, 19)),
  );
  final normalized =
      '${wall.year.toString().padLeft(4, '0')}-'
      '${wall.month.toString().padLeft(2, '0')}-'
      '${wall.day.toString().padLeft(2, '0')}T'
      '${wall.hour.toString().padLeft(2, '0')}:'
      '${wall.minute.toString().padLeft(2, '0')}:'
      '${wall.second.toString().padLeft(2, '0')}';
  if (normalized != value.substring(0, 19)) {
    throw const FormatException('Invalid security calendar');
  }
  return parsed.toUtc();
}

DateTime? securityOptionalTime(Map<String, dynamic> row, String key) =>
    row[key] == null ? null : securityTime(row, key);
