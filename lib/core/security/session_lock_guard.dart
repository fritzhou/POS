import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/auth_models.dart';
import 'access_lock.dart';

/// Covers the entire Navigator, including payment dialogs, during a lock.
class SessionLockGuard extends StatefulWidget {
  const SessionLockGuard({
    required this.access,
    required this.actorId,
    required this.child,
    required this.onVerifyPassword,
    required this.onSignOut,
    this.activityClock,
    super.key,
  });
  final AccessLock access;
  final String? actorId;
  final Widget child;
  final Future<void> Function(String)? onVerifyPassword;
  final VoidCallback onSignOut;
  final Stopwatch? activityClock;

  @override
  State<SessionLockGuard> createState() => _SessionLockGuardState();
}

class _SessionLockGuardState extends State<SessionLockGuard>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  final _clock = Stopwatch();
  Stopwatch get _elapsed => widget.activityClock ?? _clock;
  bool _wasLocked = false;
  Timer? _timer;
  bool _busy = false;
  String? _error;
  int _failures = 0;
  DateTime? _retryAfter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_key);
    widget.access.bind(widget.actorId);
    widget.access.addListener(_changed);
    _activity();
  }

  @override
  void didUpdateWidget(covariant SessionLockGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.access != widget.access) {
      oldWidget.access.removeListener(_changed);
      widget.access.addListener(_changed);
    }
    if (oldWidget.actorId != widget.actorId) {
      _password.clear();
      _busy = false;
      _failures = 0;
      _error = null;
      widget.access.bind(widget.actorId);
      _activity();
    }
  }

  bool _key(KeyEvent event) {
    if (event is KeyDownEvent) _activity();
    return false;
  }

  void _activity() {
    if (widget.actorId == null || widget.access.isLocked) return;
    _elapsed
      ..reset()
      ..start();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (widget.actorId == null || widget.access.isLocked) return;
    final remaining =
        Duration(minutes: widget.access.idleMinutes) - _elapsed.elapsed;
    _timer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      widget.access.lock,
    );
  }

  void _changed() {
    if (!mounted) return;
    final wasLocked = _wasLocked;
    _wasLocked = widget.access.isLocked;
    if (widget.access.isLocked) {
      _timer?.cancel();
      _password.clear();
      FocusManager.instance.primaryFocus?.unfocus();
    } else if (wasLocked) {
      _activity();
    } else {
      _schedule();
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.access.lock();
    } else if (state == AppLifecycleState.resumed &&
        _elapsed.elapsed >= Duration(minutes: widget.access.idleMinutes)) {
      widget.access.lock();
    }
  }

  Future<void> _unlock() async {
    final verify = widget.onVerifyPassword;
    final actor = widget.actorId;
    if (_busy || verify == null || actor == null) return;
    if (_retryAfter != null && DateTime.now().isBefore(_retryAfter!)) {
      setState(() => _error = 'Wait 30 seconds before trying again.');
      return;
    }
    final generation = widget.access.generation;
    final password = _password.text;
    _password.clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await verify(password);
      if (!mounted || widget.actorId != actor) return;
      if (widget.access.unlockVerified(
        actorId: actor,
        generation: generation,
      )) {
        _failures = 0;
        _retryAfter = null;
      }
    } on Object catch (error) {
      if (!mounted || widget.actorId != actor) return;
      _failures++;
      if (_failures % 5 == 0) {
        _retryAfter = DateTime.now().add(const Duration(seconds: 30));
      }
      setState(
        () => _error = error is AuthFailure
            ? error.message
            : 'Unlock could not be verified. Connect and try again.',
      );
    } finally {
      if (mounted && widget.actorId == actor) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _password.dispose();
    HardwareKeyboard.instance.removeHandler(_key);
    WidgetsBinding.instance.removeObserver(this);
    widget.access.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _activity(),
    onPointerSignal: (_) => _activity(),
    onPointerMove: (_) => _activity(),
    child: Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: widget.access.isLocked,
          child: ExcludeSemantics(
            excluding: widget.access.isLocked,
            child: Offstage(
              offstage: widget.access.isLocked,
              child: widget.child,
            ),
          ),
        ),
        if (widget.access.isLocked)
          Positioned.fill(
            child: _LockOverlay(
              child: Scaffold(
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_outline, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              'Workspace locked',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Enter your account password online to continue. Recorded payments are preserved.',
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _password,
                              obscureText: true,
                              enabled:
                                  !_busy && widget.onVerifyPassword != null,
                              autofillHints: const [AutofillHints.password],
                              decoration: const InputDecoration(
                                labelText: 'Account password',
                              ),
                              onSubmitted: (_) => _unlock(),
                            ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed:
                                  _busy || widget.onVerifyPassword == null
                                  ? null
                                  : _unlock,
                              child: Text(
                                _busy ? 'Verifying…' : 'Unlock online',
                              ),
                            ),
                            TextButton(
                              onPressed: widget.onSignOut,
                              child: const Text('Sign out'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// The protected Navigator is hidden, so editable selection needs its own
/// overlay while locked. This entry updates with busy/error form state.
class _LockOverlay extends StatefulWidget {
  const _LockOverlay({required this.child});
  final Widget child;
  @override
  State<_LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends State<_LockOverlay> {
  late final OverlayEntry _entry = OverlayEntry(builder: (_) => widget.child);
  @override
  void didUpdateWidget(covariant _LockOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
