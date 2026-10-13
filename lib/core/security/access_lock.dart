import 'package:flutter/foundation.dart';

/// A presentation/access lock, independent of logout and durable device keys.
/// It never deletes payment history or establishes a new identity.
class AccessLock extends ChangeNotifier {
  bool _locked = false;
  String? _actorId;
  int _generation = 0;
  int _idleMinutes = 5;

  bool get isLocked => _locked;
  String? get actorId => _actorId;
  int get generation => _generation;
  int get idleMinutes => _idleMinutes;

  void bind(String? actorId) {
    if (_actorId == actorId) return;
    _actorId = actorId;
    _locked = false;
    _idleMinutes = 5;
    _generation++;
    notifyListeners();
  }

  void setIdleMinutes(int minutes) {
    if (minutes < 1 || minutes > 60) {
      throw ArgumentError.value(minutes, 'minutes');
    }
    if (_idleMinutes == minutes) return;
    _idleMinutes = minutes;
    notifyListeners();
  }

  void lock() {
    if (_actorId == null || _locked) return;
    _locked = true;
    _generation++;
    notifyListeners();
  }

  bool unlockVerified({required String actorId, required int generation}) {
    if (!_locked || _actorId != actorId || _generation != generation) {
      return false;
    }
    _locked = false;
    _generation++;
    notifyListeners();
    return true;
  }
}
