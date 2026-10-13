import 'package:flutter/material.dart';

import '../domain/repository_support.dart';

String catalogError(Object error) {
  if (error is RepositoryFailure) {
    if (error.type == RepositoryFailureType.conflict) {
      return 'This record changed on another device. Reload the latest version before trying again.';
    }
    return error.message;
  }
  return 'The request could not be completed. Check your connection and try again.';
}

String? validateCatalogField(void Function() validate) {
  try {
    validate();
    return null;
  } on RepositoryFailure catch (error) {
    return error.message;
  }
}

class CatalogErrorNotice extends StatelessWidget {
  const CatalogErrorNotice({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: .4),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reload'),
          ),
        ],
      ],
    ),
  );
}

class CatalogStatus extends StatelessWidget {
  const CatalogStatus({required this.active, super.key});
  final bool active;

  @override
  Widget build(BuildContext context) => Text(
    active ? 'Active' : 'Inactive',
    style: TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 12,
      color: active ? const Color(0xff15803d) : const Color(0xff64748b),
    ),
  );
}
