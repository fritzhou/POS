enum RepositoryFailureType {
  unauthenticated,
  permissionDenied,
  unavailable,
  conflict,
  validation,
  notFound,
  notConnected,
}

/// Only deliberate, public messages cross the data boundary.
class RepositoryFailure implements Exception {
  const RepositoryFailure(this.type, this.message);
  final RepositoryFailureType type;
  final String message;
  @override
  String toString() => 'RepositoryFailure(${type.name})';
}

class PageRequest {
  const PageRequest({this.offset = 0, this.limit = 50});
  final int offset;
  final int limit;

  void validate() {
    if (offset < 0 || offset > 100000 || limit < 1 || limit > 100) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Choose a page size between 1 and 100.',
      );
    }
  }
}

class DataPage<T> {
  DataPage({
    required List<T> items,
    required this.hasMore,
    required this.offset,
  }) : items = List.unmodifiable(items);
  final List<T> items;
  final bool hasMore;
  final int offset;
  int get nextOffset => offset + items.length;
}

/// Decimal parsing avoids binary floating-point rounding in prices and costs.
abstract final class Money {
  static const currency = 'PHP';
  static final _maximum = BigInt.parse('9007199254740991');

  static int parseMinor(String amount) {
    final value = amount.trim();
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Enter a nonnegative amount with at most two decimal places.',
      );
    }
    final parts = value.split('.');
    final minor =
        BigInt.parse(parts.first) * BigInt.from(100) +
        BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
    if (minor > _maximum) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'The amount is too large.',
      );
    }
    return minor.toInt();
  }

  static String formatMinor(int minor) {
    final sign = minor < 0 ? '-' : '';
    final absolute = BigInt.from(minor).abs();
    return '$sign${absolute ~/ BigInt.from(100)}.${(absolute % BigInt.from(100)).toString().padLeft(2, '0')}';
  }
}

String requiredText(
  String value,
  String label,
  int maximum, {
  int minimum = 1,
}) {
  final normalized = value.trim();
  if (normalized.length < minimum || normalized.length > maximum) {
    throw RepositoryFailure(
      RepositoryFailureType.validation,
      '$label must contain $minimum to $maximum characters.',
    );
  }
  return normalized;
}

String? optionalText(String? value, String label, int maximum) {
  if (value == null || value.trim().isEmpty) return null;
  return requiredText(value, label, maximum);
}

String validateId(String value) {
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value)) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'This record identifier is invalid.',
    );
  }
  return value;
}

String? validateOptionalId(String? value) =>
    value == null ? null : validateId(value);

int validateRevision(int value) {
  if (value < 1) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Reload this record before saving.',
    );
  }
  return value;
}

String validateCurrency(String value) {
  final normalized = value.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalized)) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Use a three-letter currency code.',
    );
  }
  return normalized;
}

String validateQuantity(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^\d{1,14}(?:\.\d{1,4})?$').hasMatch(normalized)) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Enter a nonnegative quantity with at most four decimal places.',
    );
  }
  return normalized;
}

int validateMinor(int value) {
  if (value < 0 || value > 9007199254740991) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Enter a valid nonnegative amount.',
    );
  }
  return value;
}

/// References are stored only; upload and signed-URL hydration are future work.
String? validateImageReference(String? value, {String? organizationId}) {
  final normalized = optionalText(value, 'Image reference', 1024);
  if (normalized == null) return null;
  final parts = normalized.split('/');
  if (parts.length < 2 ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..') ||
      !RegExp(r'^[A-Za-z0-9._/-]+$').hasMatch(normalized)) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Use an organization-scoped Storage image reference.',
    );
  }
  validateId(parts.first);
  if (organizationId != null && parts.first != organizationId) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'The image reference must belong to this business.',
    );
  }
  return normalized;
}
