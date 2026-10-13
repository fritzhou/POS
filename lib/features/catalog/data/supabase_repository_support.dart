import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_models.dart';
import '../domain/repository_support.dart';

/// The selected actor originates from the verified membership loader. Client
/// policy is a preflight only: PostgreSQL checks the current membership again.
class SupabaseRepositoryScope {
  SupabaseRepositoryScope({
    required this.client,
    required this.actor,
    this.isRecoverySession,
  });
  final SupabaseClient client;
  final AuthenticatedUser actor;
  final bool Function()? isRecoverySession;
  String get organizationId => actor.organizationId;

  void requireIdentity() {
    final session = client.auth.currentSession;
    if (session == null ||
        session.user.id != actor.userId ||
        session.user.emailConfirmedAt == null ||
        actor.branchIds.isEmpty ||
        isRecoverySession?.call() == true) {
      throw const RepositoryFailure(
        RepositoryFailureType.unauthenticated,
        'Sign in with your verified business account to continue.',
      );
    }
  }

  Future<T> safe<T>(Future<T> Function() operation) async {
    requireIdentity();
    try {
      final result = await operation();
      // A response may arrive after sign-out, a tenant identity switch, or a
      // recovery event. Never expose it under the replacement identity.
      requireIdentity();
      return result;
    } on RepositoryFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw normalizeCode(error.code);
    } on FunctionException catch (error) {
      throw switch (error.status) {
        401 => const RepositoryFailure(
          RepositoryFailureType.unauthenticated,
          'Sign in again to continue.',
        ),
        403 => const RepositoryFailure(
          RepositoryFailureType.permissionDenied,
          'Your account cannot perform this action.',
        ),
        409 => const RepositoryFailure(
          RepositoryFailureType.conflict,
          'This record changed. Reload it before saving again.',
        ),
        400 || 422 => const RepositoryFailure(
          RepositoryFailureType.validation,
          'Check the supplied information and try again.',
        ),
        429 => const RepositoryFailure(
          RepositoryFailureType.unavailable,
          'Too many invitation requests. Wait before retrying the same request.',
        ),
        503 => const RepositoryFailure(
          RepositoryFailureType.unavailable,
          'Employee email delivery could not be confirmed. Retry the same invitation request shortly.',
        ),
        _ => const RepositoryFailure(
          RepositoryFailureType.unavailable,
          'The business service is temporarily unavailable. Try again shortly.',
        ),
      };
    } on AuthException {
      throw const RepositoryFailure(
        RepositoryFailureType.unauthenticated,
        'Sign in again to continue.',
      );
    } on Object {
      throw const RepositoryFailure(
        RepositoryFailureType.unavailable,
        'The business service is temporarily unavailable. Try again shortly.',
      );
    }
  }

  Map<String, dynamic> saveParameters({
    String? id,
    int? expectedRevision,
    required Map<String, dynamic> values,
    required String reason,
  }) {
    if (id != null) validateId(id);
    if (expectedRevision != null) validateRevision(expectedRevision);
    return {
      'p_organization_id': organizationId,
      'p_id': id,
      'p_expected_revision': expectedRevision,
      'p_values': values,
      'p_reason': reason,
    };
  }
}

RepositoryFailure normalizeCode(String? code) => switch (code) {
  '42501' => const RepositoryFailure(
    RepositoryFailureType.permissionDenied,
    'Your account cannot perform this action.',
  ),
  '40001' => const RepositoryFailure(
    RepositoryFailureType.conflict,
    'This record changed. Reload it before saving again.',
  ),
  'P0002' => const RepositoryFailure(
    RepositoryFailureType.notFound,
    'This record is no longer available.',
  ),
  '23505' => const RepositoryFailure(
    RepositoryFailureType.validation,
    'A record with these details already exists.',
  ),
  '22023' || '23514' || '23503' || '22P02' => const RepositoryFailure(
    RepositoryFailureType.validation,
    'Check the supplied information and try again.',
  ),
  'PGRST301' || 'PGRST302' => const RepositoryFailure(
    RepositoryFailureType.unauthenticated,
    'Sign in again to continue.',
  ),
  _ => const RepositoryFailure(
    RepositoryFailureType.unavailable,
    'The business service is temporarily unavailable. Try again shortly.',
  ),
};

List<Map<String, dynamic>> rowsFrom(Object? data) {
  if (data is! List) throw const FormatException('Expected record list');
  return data.map((row) => rowFrom(row)).toList(growable: false);
}

Map<String, dynamic> rowFrom(Object? data) {
  if (data is! Map<String, dynamic>) {
    throw const FormatException('Expected record');
  }
  return data;
}

int integerFrom(Object? value) {
  if (value is int) return value;
  if (value is String) return int.parse(value);
  throw const FormatException('Expected integral amount');
}

DataPage<T> pageFrom<T>(
  List<Map<String, dynamic>> rows,
  PageRequest page,
  T Function(Map<String, dynamic>) decode,
) => DataPage(
  items: rows.take(page.limit).map(decode).toList(growable: false),
  hasMore: rows.length > page.limit,
  offset: page.offset,
);

/// Values remain data in a parameterized filter; SQL wildcards are literal.
String literalSearch(String query) {
  if (query.trim().length > 120) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Use a shorter search phrase.',
    );
  }
  return query
      .trim()
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
