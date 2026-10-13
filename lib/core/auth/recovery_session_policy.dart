/// Restricts a validated recovery identity until password update, explicit
/// sign-out or a new ordinary sign-in. A transport error is not any of those.
class RecoverySessionPolicy {
  String? _recoveryUserId;

  void beginVerifiedRecovery(String userId) => _recoveryUserId = userId;

  bool isActiveFor(String? liveUserId) =>
      liveUserId != null && liveUserId == _recoveryUserId;

  /// A retained live session stays recovery-only through refresh failures and
  /// later refresh success. A missing/different identity cannot inherit it.
  void retainForSession(String? liveUserId) {
    if (!isActiveFor(liveUserId)) clear();
  }

  void clear() => _recoveryUserId = null;
}
