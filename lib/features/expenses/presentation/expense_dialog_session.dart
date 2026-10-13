/// Cancels presentation immediately when its actor/business context changes.
/// No financial intent is deleted; the actor-scoped journal owns recovery.
class ExpenseDialogSession {
  bool active = true;
  final _listeners = <void Function()>{};
  void listen(void Function() callback) => _listeners.add(callback);
  void unlisten(void Function() callback) => _listeners.remove(callback);
  void invalidate() {
    if (!active) return;
    active = false;
    for (final callback in [..._listeners]) {
      callback();
    }
  }
}
