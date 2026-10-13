import 'package:flutter/material.dart';

import '../../app/config/feature_status.dart';
import '../../core/widgets/status_widgets.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({this.isPreview = true, super.key});

  final bool isPreview;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const PageHeading(
        title: 'Your business, at a glance',
        subtitle: 'A clear view of sales, stock and daily operations.',
        trailing: StatusPill(
          status: FeatureStatus.notYetConnected,
          icon: Icons.cloud_off_outlined,
        ),
      ),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1000
              ? 4
              : constraints.maxWidth >= 500
              ? 2
              : 1;
          const metrics = [
            (
              Icons.receipt_long_outlined,
              'Sales today',
              'Verified daily sales',
            ),
            (Icons.shopping_bag_outlined, 'Orders', 'Completed transactions'),
            (Icons.inventory_2_outlined, 'Low stock', 'Products to replenish'),
            (Icons.sync_outlined, 'Pending sync', 'Durable local event queue'),
          ];
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: metrics.map((metric) {
              return SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 16) / columns,
                child: SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        metric.$1,
                        color: Theme.of(context).colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        metric.$2,
                        style: const TextStyle(
                          color: Color(0xff64748b),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        '—',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: Color(0xff10223f),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        metric.$3,
                        style: const TextStyle(
                          color: Color(0xff94a3b8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
      const SizedBox(height: 24),
      SectionCard(
        child: FeatureEmptyState(
          icon: Icons.insights_outlined,
          title: isPreview
              ? 'Your dashboard starts here'
              : 'No business data yet',
          message: isPreview
              ? 'This read-only design preview contains no business records. Connect Supabase and sign in with an authorized business membership to begin.'
              : 'Reporting queries are Coming Soon. Verified sales and inventory summaries will appear here once those modules are connected.',
          status: FeatureStatus.notYetConnected,
        ),
      ),
      const SizedBox(height: 24),
      const SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent activity',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.history_outlined, color: Color(0xff94a3b8)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Activity will appear after real business operations are connected.',
                    style: TextStyle(color: Color(0xff64748b), height: 1.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}
