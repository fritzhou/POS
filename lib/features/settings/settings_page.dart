import 'package:flutter/material.dart';

import '../../app/config/feature_status.dart';
import '../../core/widgets/status_widgets.dart';
import '../../core/security/app_role.dart';
import '../administration/domain/administration_repository.dart';
import '../administration/presentation/business_settings_editor.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    this.isPreview = true,
    this.repository,
    this.role,
    this.onBusinessNameSaved,
    this.onOpenSecurity,
    this.onOpenBranches,
    super.key,
  });

  final bool isPreview;
  final AdministrationRepository? repository;
  final AppRole? role;
  final ValueChanged<String>? onBusinessNameSaved;
  final VoidCallback? onOpenSecurity;
  final VoidCallback? onOpenBranches;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      PageHeading(
        title: 'Settings',
        subtitle: isPreview
            ? 'A read-only preview of your business configuration.'
            : 'Business identity, POS defaults and integration status.',
        trailing: isPreview || repository == null
            ? const StatusPill(status: FeatureStatus.notYetConnected)
            : null,
      ),
      const SizedBox(height: 24),
      if (isPreview ||
          (role?.allows(AppPermission.manageSettings) ?? false)) ...[
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Branches",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                "Create locations or edit scoped metadata. Deactivation preserves stock, shifts and unresolved paid evidence.",
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onOpenBranches,
                child: const Text("Manage branches"),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
      BusinessSettingsEditor(
        repository: repository,
        role: role,
        isPreview: isPreview,
        onBusinessNameSaved: onBusinessNameSaved,
      ),
      const SizedBox(height: 20),
      if (onOpenSecurity != null)
        SectionCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.security_outlined),
            title: const Text('Account and device security'),
            subtitle: const Text(
              'Idle locking, authenticator setup, PIN reset, devices and security notices.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenSecurity,
          ),
        )
      else
        const _SettingsSection(
          icon: Icons.security_outlined,
          title: 'Security',
          description: 'Only enforced capabilities are shown as active.',
          children: [
            _CapabilityRow(
              title: 'Session timeout',
              subtitle: 'Organization idle-lock policy is not enforced yet.',
              status: FeatureStatus.comingSoon,
            ),
            _CapabilityRow(
              title: 'Multi-factor authentication',
              subtitle: 'TOTP enrollment and privileged-account enforcement.',
              status: FeatureStatus.comingSoon,
            ),
            _CapabilityRow(
              title: 'Password rules',
              subtitle:
                  'Supabase project policy applies when authentication is connected.',
              status: FeatureStatus.notYetConnected,
            ),
            _CapabilityRow(
              title: 'Approved devices and sessions',
              subtitle: 'Enrollment, session inventory and revocation.',
              status: FeatureStatus.comingSoon,
            ),
            _CapabilityRow(
              title: 'Employee PIN and reset',
              subtitle:
                  'Server-side verifiers and audited manager authorization.',
              status: FeatureStatus.comingSoon,
            ),
          ],
        ),
      const SizedBox(height: 20),
      const _SettingsSection(
        icon: Icons.mail_outline,
        title: 'Email',
        description: 'Account actions use Supabase Auth when configured.',
        children: [
          _CapabilityRow(
            title: 'Supabase Auth Email',
            subtitle:
                'Current provider · Verification and password recovery. Actual delivery requires a configured Supabase project.',
            status: FeatureStatus.notYetConnected,
          ),
          _CapabilityRow(
            title: 'Custom SMTP / Resend / Postmark',
            subtitle:
                'Future server-side providers. No email credentials belong in the app.',
            status: FeatureStatus.comingSoon,
          ),
          _CapabilityRow(
            title: 'Branded email templates',
            subtitle:
                'Invitation, verification, recovery and security-notice design previews.',
            status: FeatureStatus.placeholder,
          ),
        ],
      ),
      const SizedBox(height: 20),
      const _SettingsSection(
        icon: Icons.payments_outlined,
        title: 'Payments',
        description: 'Clear verification status for every tender.',
        children: [
          _CapabilityRow(
            title: 'Cash',
            subtitle:
                'Operator-counted cash is recorded by online checkout after server confirmation. Requires the configured backend.',
            status: FeatureStatus.notYetConnected,
          ),
          _CapabilityRow(
            title: 'Card / GCash / Maya / Other',
            subtitle:
                'Manual Payment Verification. Online checkout records operator-confirmed amounts and references; provider authorization is not connected.',
            status: FeatureStatus.manualVerification,
          ),
          _CapabilityRow(
            title: 'Provider connections',
            subtitle: 'GCash API, Maya API and card terminal authorization.',
            status: FeatureStatus.notYetConnected,
          ),
        ],
      ),
      const SizedBox(height: 20),
      const _SettingsSection(
        icon: Icons.extension_outlined,
        title: 'Future services',
        description: 'Disabled until each service is implemented and tested.',
        children: [
          _CapabilityRow(
            title: 'SMS and push notifications',
            subtitle: 'Business and security alerts.',
            status: FeatureStatus.comingSoon,
          ),
          _CapabilityRow(
            title: 'Cloud backup and multi-branch sync',
            subtitle:
                'Recovery-tested backups and expanded branch replication.',
            status: FeatureStatus.comingSoon,
          ),
          _CapabilityRow(
            title: 'Accounting, loyalty and attendance',
            subtitle: 'Future operational integrations.',
            status: FeatureStatus.comingSoon,
          ),
          _CapabilityRow(
            title: 'Advanced analytics and AI insights',
            subtitle: 'Insights from authorized, verified business records.',
            status: FeatureStatus.comingSoon,
          ),
        ],
      ),
    ],
  );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          description,
          style: const TextStyle(color: Color(0xff64748b), height: 1.5),
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    ),
  );
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final String title;
  final String subtitle;
  final FeatureStatus status;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xff64748b),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        );
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              content,
              const SizedBox(height: 10),
              StatusPill(status: status),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: content),
            const SizedBox(width: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: StatusPill(status: status),
            ),
          ],
        );
      },
    ),
  );
}
