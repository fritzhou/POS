String? validateEmail(String? input) {
  final value = (input ?? '').trim();
  if (value.isEmpty) return 'Enter your email address.';
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? validateLoginIdentifier(String? input) {
  final value = (input ?? '').trim();
  if (value.isEmpty) return 'Enter your email address.';
  if (!value.contains('@')) {
    return 'Employee ID sign-in is Coming Soon. Use your email.';
  }
  return validateEmail(value);
}

String? validateNewPassword(String? input) {
  final value = input ?? '';
  if (value.length < 12 ||
      !RegExp(r'[A-Z]').hasMatch(value) ||
      !RegExp(r'[a-z]').hasMatch(value) ||
      !RegExp(r'[0-9]').hasMatch(value) ||
      !RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
    return 'Use at least 12 characters with uppercase, lowercase, a number and a symbol.';
  }
  return null;
}

String? validateRequiredName(String? input, String label) {
  final value = (input ?? '').trim();
  if (value.length < 2) return 'Enter your $label.';
  if (value.length > 120) return 'Keep your $label within 120 characters.';
  return null;
}
