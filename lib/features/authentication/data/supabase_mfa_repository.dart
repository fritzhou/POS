// Public constructor parameter names describe the integration boundary.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/mfa_repository.dart';

/// Uses the installed Supabase Auth MFA API in an isolated, nonpersistent
/// client. Its verify method writes its own session before returning; isolating
/// that write prevents a delayed response restoring an actor after logout.
class SupabaseMfaRepository implements MfaRepository {
  SupabaseMfaRepository({
    required SupabaseClient client,
    required String authUrl,
    required String publicApiKey,
    bool Function()? isRecoverySession,
    DateTime Function()? clock,
    GoTrueClient Function()? isolatedClientFactory,
  }) : _client = client,
       _authUrl = authUrl,
       _publicApiKey = publicApiKey,
       _isRecoverySession = isRecoverySession ?? (() => false),
       _clock = clock ?? DateTime.now,
       _isolatedClientFactory = isolatedClientFactory {
    _observedActor = client.auth.currentSession?.user.id;
    _subscription = client.auth.onAuthStateChange.listen((state) {
      final nextActor = state.session?.user.id;
      if (nextActor != _observedActor ||
          state.event == AuthChangeEvent.signedOut ||
          state.event == AuthChangeEvent.passwordRecovery) {
        _generation++;
      }
      _observedActor = nextActor;
    }, onError: (Object _, StackTrace _) {});
  }

  final SupabaseClient _client;
  final String _authUrl;
  final String _publicApiKey;
  final bool Function() _isRecoverySession;
  final DateTime Function() _clock;
  final GoTrueClient Function()? _isolatedClientFactory;
  late final StreamSubscription<AuthState> _subscription;
  String? _observedActor;
  int _generation = 0;
  bool _disposed = false;

  @override
  String? get actorId => _client.auth.currentSession?.user.id;

  static const _signInAgain = MfaFailure(
    'Sign in again before managing two-step verification.',
    kind: MfaFailureKind.authorization,
  );

  void _guard(Session session, int generation) {
    if (_disposed ||
        _generation != generation ||
        _client.auth.currentSession?.user.id != session.user.id ||
        _isRecoverySession()) {
      throw _signInAgain;
    }
  }

  Future<T> _run<T>(
    Future<T> Function(GoTrueClient isolated, Session original, int generation)
    action,
  ) async {
    final session = _client.auth.currentSession;
    final generation = _generation;
    if (session == null || session.isExpired) throw _signInAgain;
    _guard(session, generation);
    final isolated =
        _isolatedClientFactory?.call() ??
        GoTrueClient(
          url: _authUrl,
          headers: {'apikey': _publicApiKey},
          autoRefreshToken: false,
        );
    try {
      // A nonexpired SDK session is installed synchronously without a network
      // refresh. Neither PKCE nor local session storage is configured here.
      await isolated.recoverSession(jsonEncode(session.toJson()));
      _guard(session, generation);
      final result = await action(isolated, session, generation);
      _guard(session, generation);
      return result;
    } on MfaFailure {
      rethrow;
    } catch (error) {
      throw _failure(error);
    } finally {
      isolated.dispose();
    }
  }

  MfaStatus _status(GoTrueClient isolated, User user) {
    final assurance = isolated.mfa.getAuthenticatorAssuranceLevel();
    final factors = user.factors ?? const <Factor>[];
    final verified = factors.any(
      (factor) => factor.status == FactorStatus.verified,
    );
    final current = _level(assurance.currentLevel);
    return MfaStatus(
      actorId: user.id,
      currentLevel: current,
      nextLevel: verified ? MfaAssuranceLevel.aal2 : current,
      factors: factors
          .map(
            (factor) => MfaFactor(
              id: factor.id,
              name: factor.friendlyName?.trim().isNotEmpty == true
                  ? factor.friendlyName!
                  : 'Authenticator app',
              isVerified: factor.status == FactorStatus.verified,
              isTotp: factor.factorType == FactorType.totp,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<User> _freshUser(
    GoTrueClient isolated,
    Session original,
    int generation,
  ) async {
    // listFactors refreshes a token. Reading the actual Auth user instead keeps
    // factor discovery from racing the shared client's refresh-token rotation.
    final user = (await isolated.getUser()).user;
    _guard(original, generation);
    if (user == null || user.id != original.user.id) throw _signInAgain;
    return user;
  }

  @override
  Future<MfaStatus> status() => _run((isolated, original, generation) async {
    return _status(isolated, await _freshUser(isolated, original, generation));
  });

  @override
  Future<MfaEnrollment> enrollTotp({required String name}) {
    final label = name.trim();
    if (label.isEmpty || label.length > 64) {
      throw const MfaFailure(
        'Use an authenticator name of 1 to 64 characters.',
      );
    }
    return _run((isolated, original, generation) async {
      final response = await isolated.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'NexaPOS',
        friendlyName: label,
      );
      _guard(original, generation);
      final enrollment = response.totp;
      if (response.type != FactorType.totp ||
          response.id.isEmpty ||
          enrollment == null ||
          !RegExp(r'^[A-Z2-7]{16,128}$').hasMatch(enrollment.secret)) {
        throw const MfaFailure('The authenticator setup could not be loaded.');
      }
      return MfaEnrollment(factorId: response.id, secret: enrollment.secret);
    });
  }

  @override
  Future<MfaChallenge> challenge(String factorId) {
    if (factorId.isEmpty) {
      throw const MfaFailure('Choose an authenticator app.');
    }
    return _run((isolated, original, generation) async {
      final user = await _freshUser(isolated, original, generation);
      _requireFactor(user, factorId);
      final response = await isolated.mfa.challenge(factorId: factorId);
      _guard(original, generation);
      if (response.id.isEmpty || !response.expiresAt.isAfter(_clock())) {
        throw const MfaFailure(
          'This verification challenge expired. Enter a new code.',
          kind: MfaFailureKind.expired,
        );
      }
      return MfaChallenge(
        factorId: factorId,
        id: response.id,
        expiresAt: response.expiresAt.toUtc(),
      );
    });
  }

  @override
  Future<MfaStatus> verify(MfaChallenge challenge, String code) {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const MfaFailure(
        'Enter the six-digit code from your authenticator app.',
        kind: MfaFailureKind.invalidCode,
      );
    }
    if (!challenge.expiresAt.isAfter(_clock())) {
      throw const MfaFailure(
        'This verification challenge expired. Enter a new code.',
        kind: MfaFailureKind.expired,
      );
    }
    return _run((isolated, original, generation) async {
      final user = await _freshUser(isolated, original, generation);
      _requireFactor(user, challenge.factorId);
      if (!challenge.expiresAt.isAfter(_clock())) {
        throw const MfaFailure(
          'This verification challenge expired. Enter a new code.',
          kind: MfaFailureKind.expired,
        );
      }
      final response = await isolated.mfa.verify(
        factorId: challenge.factorId,
        challengeId: challenge.id,
        code: code,
      );
      _guard(original, generation);
      final upgraded = isolated.currentSession;
      if (response.user.id != original.user.id ||
          upgraded == null ||
          upgraded.isExpired ||
          _status(isolated, response.user).currentLevel !=
              MfaAssuranceLevel.aal2) {
        throw const MfaFailure('Two-step verification was not confirmed.');
      }
      // There is no await between the actor guard and setInitialSession's
      // synchronous, nonexpired session installation.
      await _client.auth.setInitialSession(jsonEncode(upgraded.toJson()));
      _guard(original, generation);
      return _status(isolated, response.user);
    });
  }

  @override
  Future<void> cancelEnrollment(String factorId) => _run((
    isolated,
    original,
    generation,
  ) async {
    final user = await _freshUser(isolated, original, generation);
    final factor = _findFactor(user, factorId);
    if (factor == null) return;
    if (factor.status != FactorStatus.unverified) {
      throw const MfaFailure('A verified authenticator cannot be canceled.');
    }
    await isolated.mfa.unenroll(factorId);
  });

  @override
  Future<void> unenroll(String factorId) =>
      _run((isolated, original, generation) async {
        final user = await _freshUser(isolated, original, generation);
        _requireFactor(user, factorId);
        if (_status(isolated, user).currentLevel != MfaAssuranceLevel.aal2) {
          throw const MfaFailure(
            'Verify an authenticator code before removing an authenticator.',
            kind: MfaFailureKind.authorization,
          );
        }
        await isolated.mfa.unenroll(factorId);
      });

  Factor? _findFactor(User user, String id) {
    for (final factor in user.factors ?? const <Factor>[]) {
      if (factor.id == id) return factor;
    }
    return null;
  }

  void _requireFactor(User user, String id) {
    final factor = _findFactor(user, id);
    if (factor == null || factor.factorType != FactorType.totp) {
      throw const MfaFailure('This authenticator is no longer available.');
    }
  }

  MfaFailure _failure(Object error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is AuthRetryableFetchException) {
      return const MfaFailure(
        'The authentication service is unavailable. Try again when connected.',
        kind: MfaFailureKind.unavailable,
      );
    }
    if (error is AuthException) {
      if (error.code == 'mfa_verification_failed') {
        return const MfaFailure(
          'The code was not accepted. Enter the current authenticator code.',
          kind: MfaFailureKind.invalidCode,
        );
      }
      if (error.code == 'mfa_challenge_expired') {
        return const MfaFailure(
          'This verification challenge expired. Enter a new code.',
          kind: MfaFailureKind.expired,
        );
      }
      if (const {
        'session_not_found',
        'bad_jwt',
        'user_banned',
        'insufficient_aal',
      }.contains(error.code)) {
        return _signInAgain;
      }
    }
    return const MfaFailure('Two-step verification could not be completed.');
  }

  MfaAssuranceLevel _level(AuthenticatorAssuranceLevels? level) =>
      switch (level) {
        AuthenticatorAssuranceLevels.aal1 => MfaAssuranceLevel.aal1,
        AuthenticatorAssuranceLevels.aal2 => MfaAssuranceLevel.aal2,
        null => MfaAssuranceLevel.none,
      };

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await _subscription.cancel();
  }
}
