import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_models.dart';
import '../../catalog/domain/repository_support.dart';

/// The server retained an append-only outcome proving that this particular
/// expired reservation never acquired a signature or authorized paid events.
class OfflinePreparationExpired implements Exception {
  const OfflinePreparationExpired();
}

/// The Edge endpoint validates the bearer JWT again using Supabase Auth. Public
/// client checks prevent responses from being applied after a local identity
/// switch; they do not replace server authorization.
class OfflineEdgeAdapter {
  OfflineEdgeAdapter({
    required this.client,
    required this.actor,
    this.isRecoverySession,
    this.isExplicitlySignedOut,
    this.onAuthorizationDenied,
  });
  final SupabaseClient client;
  final AuthenticatedUser actor;
  final bool Function()? isRecoverySession, isExplicitlySignedOut;
  final Future<void> Function()? onAuthorizationDenied;

  void requireOnlineIdentity() {
    final session = client.auth.currentSession;
    if (isExplicitlySignedOut?.call() == true ||
        isRecoverySession?.call() == true ||
        session == null ||
        session.user.id.toLowerCase() != actor.userId.toLowerCase() ||
        session.user.emailConfirmedAt == null) {
      throw const RepositoryFailure(
        RepositoryFailureType.unauthenticated,
        'Sign in with your verified account to prepare or synchronize offline sales.',
      );
    }
  }

  Future<Map<String, Object?>> call({
    required String action,
    required String branchId,
    required String deviceId,
    Map<String, Object?> values = const {},
  }) async {
    requireOnlineIdentity();
    if (!actor.branchIds.contains(branchId) ||
        !{
          'enroll_challenge',
          'enroll',
          'prepare',
          'ingest',
          'pull',
          'release',
        }.contains(action) ||
        values.keys.any(
          (key) => {
            'action',
            'actor_id',
            'organization_id',
            'branch_id',
            'device_id',
          }.contains(key),
        )) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Choose an authorized offline workspace.',
      );
    }
    try {
      final response = await client.functions.invoke(
        'offline-sync',
        body: {
          ...values,
          'action': action,
          'organization_id': actor.organizationId,
          'branch_id': branchId,
          'device_id': deviceId,
        },
      );
      requireOnlineIdentity();
      if (response.status != 200 || response.data is! Map) {
        throw const FormatException('Invalid offline response');
      }
      return Map<String, Object?>.from(response.data as Map);
    } on RepositoryFailure {
      rethrow;
    } on FunctionException catch (error) {
      requireOnlineIdentity();
      if (error.status == 401 || error.status == 403) {
        await onAuthorizationDenied?.call();
      }
      if (error.status == 409 &&
          error.details is Map &&
          (error.details as Map)['error'] == 'offline_preparation_expired') {
        throw const OfflinePreparationExpired();
      }
      throw switch (error.status) {
        401 => const RepositoryFailure(
          RepositoryFailureType.unauthenticated,
          'Sign in again before synchronizing offline sales.',
        ),
        403 => const RepositoryFailure(
          RepositoryFailureType.permissionDenied,
          'Offline authorization was denied. Preserved sales require review.',
        ),
        409 => const RepositoryFailure(
          RepositoryFailureType.conflict,
          'The offline record requires review. Its original payment is preserved.',
        ),
        400 || 422 => const RepositoryFailure(
          RepositoryFailureType.validation,
          'Offline preparation or the preserved event could not be validated.',
        ),
        _ => const RepositoryFailure(
          RepositoryFailureType.unavailable,
          'The offline service could not be confirmed. Retry the same preserved request.',
        ),
      };
    } on Object {
      requireOnlineIdentity();
      throw const RepositoryFailure(
        RepositoryFailureType.unavailable,
        'The offline service could not be confirmed. Retry the same preserved request.',
      );
    }
  }
}
