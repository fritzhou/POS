import 'package:flutter/material.dart';

import '../../app/config/feature_status.dart';

/// A visible capability label, never a substitute for enforcing a permission.
class StatusPill extends StatelessWidget {
  const StatusPill({
    this.label,
    this.status,
    this.color = const Color(0xff64748b),
    this.icon,
    super.key,
  }) : assert(label != null || status != null);

  final String? label;
  final FeatureStatus? status;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: .18)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            label ?? status!.label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class FeatureEmptyState extends StatelessWidget {
  const FeatureEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.status = FeatureStatus.comingSoon,
    this.compact = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final FeatureStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(compact ? 16 : 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 48 : 64,
          height: compact ? 48 : 64,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(
            icon,
            size: compact ? 24 : 30,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xff64748b),
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 18),
        StatusPill(status: status),
      ],
    ),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({required this.child, this.padding = 20, super.key});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xffe7edf5)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading({
    required this.title,
    required this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xff64748b),
              height: 1.4,
            ),
          ),
        ],
      );
      if (constraints.maxWidth < 540 || trailing == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            if (trailing != null) ...[const SizedBox(height: 14), trailing!],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: heading),
          const SizedBox(width: 16),
          trailing!,
        ],
      );
    },
  );
}
