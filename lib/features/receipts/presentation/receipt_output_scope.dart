import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../../core/security/access_lock.dart';

/// Covers the Navigator so a dialog retains the original access generation.
class ReceiptOutputScope extends StatefulWidget {
  const ReceiptOutputScope({
    required this.identity,
    required this.isAllowed,
    required this.child,
    this.access,
    this.currentIdentity,
    super.key,
  });
  final Object? identity;
  final bool Function() isAllowed;
  final AccessLock? access;
  final Object? Function()? currentIdentity;
  final Widget child;
  static ReceiptOutputScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ReceiptScope>()?.state.widget;
  static bool Function() capture(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_ReceiptScope>()?.state;
    if (scope == null) return () => false;
    final epoch = scope.epoch;
    final access = scope.widget.access;
    final lockGeneration = access?.generation;
    final authorization = scope.widget.currentIdentity?.call();
    final initiallyAllowed =
        scope.widget.isAllowed() && !(access?.isLocked ?? false);
    return () =>
        initiallyAllowed &&
        context.mounted &&
        scope.mounted &&
        epoch == scope.epoch &&
        access == scope.widget.access &&
        lockGeneration == access?.generation &&
        !(access?.isLocked ?? false) &&
        scope.widget.isAllowed() &&
        authorization == scope.widget.currentIdentity?.call();
  }

  @override
  State<ReceiptOutputScope> createState() => _ReceiptOutputScopeState();
}

class _ReceiptOutputScopeState extends State<ReceiptOutputScope> {
  int epoch = 0;
  @override
  void initState() {
    super.initState();
    widget.access?.addListener(_accessChanged);
  }

  void _accessChanged() {
    if (!mounted) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(ReceiptOutputScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.access != widget.access) {
      oldWidget.access?.removeListener(_accessChanged);
      widget.access?.addListener(_accessChanged);
    }
    if (oldWidget.identity != widget.identity ||
        oldWidget.access != widget.access) {
      epoch++;
    }
  }

  @override
  void dispose() {
    epoch++;
    widget.access?.removeListener(_accessChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ReceiptScope(state: this, child: widget.child);
}

class _ReceiptScope extends InheritedWidget {
  const _ReceiptScope({required this.state, required super.child});
  final _ReceiptOutputScopeState state;
  @override
  bool updateShouldNotify(_ReceiptScope oldWidget) => true;
}
