import 'package:flutter/material.dart';

import '../../../core/operations/operation_journal.dart';
import '../../catalog/domain/repository_support.dart';

String operationError(Object error) => error is RepositoryFailure
    ? error.message
    : 'The server result could not be confirmed. Check your connection and retry the same request.';

bool operationMayBeUnconfirmed(Object error) =>
    error is! RepositoryFailure ||
    error.type == RepositoryFailureType.unavailable;

String manilaTime(DateTime value) {
  final time = value.toUtc().add(const Duration(hours: 8));
  String pad(int number) => number.toString().padLeft(2, '0');
  return '${time.year}-${pad(time.month)}-${pad(time.day)} ${pad(time.hour)}:${pad(time.minute)}';
}

String amountLabel(int amount, String currency) =>
    '$currency ${Money.formatMinor(amount)}';

int wholeUnits(String value, {bool signed = false}) {
  final text = value.trim();
  if (!(signed ? RegExp(r'^-?[1-9]\d{0,8}$') : RegExp(r'^[1-9]\d{0,8}$'))
      .hasMatch(text)) {
    throw RepositoryFailure(
      RepositoryFailureType.validation,
      signed
          ? 'Enter a nonzero whole-unit change, with a minus sign to remove stock.'
          : 'Enter a positive whole-unit quantity.',
    );
  }
  final quantity = int.parse(text);
  if (quantity.abs() > 1000000) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'A stock operation supports at most 1,000,000 units.',
    );
  }
  return quantity;
}

String? operationValidation(void Function() action) {
  try {
    action();
    return null;
  } on RepositoryFailure catch (error) {
    return error.message;
  }
}

class OperationNotice extends StatelessWidget {
  const OperationNotice({
    required this.message,
    this.requestId,
    this.isError = false,
    super.key,
  });
  final String message;
  final String? requestId;
  final bool isError;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color:
          (isError
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.primaryContainer)
              .withValues(alpha: .4),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        if (requestId != null) ...[
          const SizedBox(height: 8),
          SelectableText(
            'Request: $requestId',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ],
    ),
  );
}

class OperationPager extends StatelessWidget {
  const OperationPager({
    required this.offset,
    required this.hasMore,
    required this.busy,
    required this.onPage,
    this.pageSize = 20,
    this.prefix = 'operations',
    super.key,
  });
  final int offset, pageSize;
  final bool hasMore, busy;
  final String prefix;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      OutlinedButton(
        key: Key('$prefix-previous'),
        onPressed: !busy && offset > 0
            ? () => onPage((offset - pageSize).clamp(0, 100000))
            : null,
        child: const Text('Previous'),
      ),
      Text('Page ${offset ~/ pageSize + 1}'),
      OutlinedButton(
        key: Key('$prefix-next'),
        onPressed: !busy && hasMore ? () => onPage(offset + pageSize) : null,
        child: const Text('Next'),
      ),
    ],
  );
}

/// Pending entries come from the durable actor-scoped journal. Retrying uses
/// its frozen payload; this card never constructs a replacement transaction.
class PendingOperationsPanel extends StatefulWidget {
  const PendingOperationsPanel({
    required this.operations,
    required this.retry,
    required this.onSettled,
    this.busy = false,
    super.key,
  });
  final List<PendingOperation> operations;
  final Future<Object> Function(PendingOperation) retry;
  final void Function(Object? result) onSettled;
  final bool busy;
  @override
  State<PendingOperationsPanel> createState() => _PendingOperationsPanelState();
}

class _PendingOperationsPanelState extends State<PendingOperationsPanel> {
  String? _retrying, _error;
  Future<void> _retry(PendingOperation operation) async {
    if (_retrying != null || widget.busy) return;
    setState(() {
      _retrying = operation.requestId;
      _error = null;
    });
    try {
      final result = await widget.retry(operation);
      if (mounted) widget.onSettled(result);
    } catch (error) {
      if (mounted) {
        setState(() => _error = operationError(error));
        if (!operationMayBeUnconfirmed(error)) widget.onSettled(null);
      }
    } finally {
      if (mounted) setState(() => _retrying = null);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ...widget.operations.map(
        (operation) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OperationNotice(
            message:
                'Unconfirmed ${operation.type.replaceAll('_', ' ')} request from ${manilaTime(operation.createdAt)} (Asia/Manila). Retry the saved server request. Do not repeat the physical payment, cash count or stock movement.',
            requestId: operation.requestId,
          ),
        ),
      ),
      ...widget.operations.map(
        (operation) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: Key('pending-retry-${operation.requestId}'),
              onPressed: _retrying == null && !widget.busy
                  ? () => _retry(operation)
                  : null,
              child: Text(
                _retrying == operation.requestId
                    ? 'Confirming saved request…'
                    : 'Retry saved request',
              ),
            ),
          ),
        ),
      ),
      if (_error != null) ...[
        OperationNotice(message: _error!, isError: true),
        const SizedBox(height: 12),
      ],
    ],
  );
}
