import 'dart:convert';

/// Public client configuration only; a service-role/secret key is rejected.
class BackendConfig {
  const BackendConfig({
    required this.url,
    required this.clientKey,
    this.authRedirectUrl = '',
    this.offlineTrustedKeysJson = '',
  });

  const BackendConfig.fromEnvironment()
    : url = const String.fromEnvironment('SUPABASE_URL'),
      clientKey = const String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
        defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
      ),
      authRedirectUrl = const String.fromEnvironment('AUTH_REDIRECT_URL'),
      offlineTrustedKeysJson = const String.fromEnvironment(
        'OFFLINE_TRUSTED_KEYS_JSON',
      );

  final String url;
  final String clientKey;
  final String authRedirectUrl;

  /// Public Ed25519 trust anchors keyed by server signing-key identifier.
  /// Empty configuration keeps the offline sales capability unavailable.
  final String offlineTrustedKeysJson;

  Map<String, String> get offlineTrustedKeys {
    if (offlineTrustedKeysJson.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(offlineTrustedKeysJson);
      if (decoded is! Map<String, dynamic> ||
          decoded.isEmpty ||
          decoded.length > 16) {
        throw const FormatException();
      }
      final result = <String, String>{};
      for (final entry in decoded.entries) {
        if (!RegExp(r'^[A-Za-z0-9_.-]{1,100}$').hasMatch(entry.key) ||
            entry.value is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(entry.value as String)) {
          throw const FormatException();
        }
        final value = entry.value as String;
        final bytes = base64Url.decode(base64Url.normalize(value));
        if (bytes.length != 32 ||
            base64Url.encode(bytes).replaceAll('=', '') != value) {
          throw const FormatException();
        }
        result[entry.key] = value;
      }
      return Map.unmodifiable(result);
    } on Object {
      throw const FormatException(
        'Offline trust anchors must contain public Ed25519 keys.',
      );
    }
  }

  String? get offlineValidationError {
    try {
      if (offlineTrustedKeys.isEmpty) {
        return 'Offline signing keys are Not Yet Connected.';
      }
      return null;
    } on FormatException {
      return 'Configure public Ed25519 offline signing keys before enabling offline sales.';
    }
  }

  bool get isConfigured => url.isNotEmpty && clientKey.isNotEmpty;

  String? get validationError {
    if (!isConfigured) {
      return 'Supabase is Not Yet Connected. Supply the public project URL '
          'and publishable or anon client key to connect.';
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return 'Use an HTTPS Supabase project URL without credentials.';
    }
    if (clientKey.startsWith('sb_secret_')) {
      return 'Private backend keys must never be used in this application.';
    }
    if (!clientKey.startsWith('sb_publishable_')) {
      try {
        final parts = clientKey.split('.');
        if (parts.length != 3) throw const FormatException();
        final claims =
            jsonDecode(
                  utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
                )
                as Map<String, dynamic>;
        if (claims['role'] != 'anon') {
          return 'Use a publishable or anon client key, never a privileged key.';
        }
      } on Object {
        return 'The public client key format is not recognized.';
      }
    }
    if (authRedirectUrl.isNotEmpty) {
      final redirect = Uri.tryParse(authRedirectUrl);
      if (redirect == null ||
          !redirect.hasScheme ||
          redirect.userInfo.isNotEmpty ||
          redirect.hasQuery ||
          redirect.hasFragment ||
          (redirect.scheme != 'https' &&
              redirect.scheme != 'com.nexapos.app')) {
        return 'Use an approved HTTPS or com.nexapos.app authentication callback.';
      }
    }
    return null;
  }
}
