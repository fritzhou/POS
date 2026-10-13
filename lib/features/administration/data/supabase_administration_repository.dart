import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_models.dart';
import '../../catalog/data/supabase_repository_support.dart';
import '../../catalog/domain/repository_support.dart';
import '../domain/administration_models.dart';
import '../domain/administration_repository.dart';

class SupabaseAdministrationRepository implements AdministrationRepository {
  SupabaseAdministrationRepository({
    required SupabaseClient client,
    required AuthenticatedUser actor,
    bool Function()? isRecoverySession,
  }) : _scope = SupabaseRepositoryScope(
         client: client,
         actor: actor,
         isRecoverySession: isRecoverySession,
       );
  final SupabaseRepositoryScope _scope;

  @override
  Future<BusinessSettings> loadSettings() => _scope.safe(
    () async => settingsFromRow(
      rowFrom(
        await _scope.client.rpc(
          'get_business_settings',
          params: {'p_organization_id': _scope.organizationId},
        ),
      ),
    ),
  );
  @override
  Future<BusinessSettings> updateSettings({
    required int expectedRevision,
    required BusinessSettingsInput input,
  }) => _scope.safe(() async {
    final values = input.validatedValues();
    validateImageReference(
      input.logoPath,
      organizationId: _scope.organizationId,
    );
    final result = await _scope.client.rpc(
      'save_business_settings',
      params: {
        'p_organization_id': _scope.organizationId,
        'p_expected_revision': validateRevision(expectedRevision),
        'p_values': values,
        'p_reason': 'Business settings updated',
      },
    );
    return settingsFromRow(rowFrom(result));
  });
  @override
  Future<DataPage<AuditEntry>> listAudit({
    AuditFilter filter = const AuditFilter(),
    PageRequest page = const PageRequest(),
  }) => _scope.safe(() async {
    page.validate();
    final result = await _scope.client.rpc(
      'list_audit_logs',
      params: {
        'p_organization_id': _scope.organizationId,
        'p_entity': optionalText(filter.entity, 'Entity filter', 80),
        'p_action': optionalText(filter.action, 'Action filter', 80),
        'p_branch_id': validateOptionalId(filter.branchId),
        'p_offset': page.offset,
        'p_limit': page.limit + 1,
      },
    );
    return pageFrom(rowsFrom(result), page, auditFromRow);
  });
}

BusinessSettings settingsFromRow(Map<String, dynamic> row) => BusinessSettings(
  organizationId: row['id'] as String,
  businessName: row['business_name'] as String,
  currency: row['currency'] as String,
  taxBps: integerFrom(row['tax_bps']),
  revision: integerFrom(row['revision']),
  address: row['address'] as String?,
  contact: row['contact'] as String?,
  logoPath: row['logo_path'] as String?,
  receiptFooter: row['receipt_footer'] as String?,
);
AuditEntry auditFromRow(Map<String, dynamic> row) => AuditEntry(
  id: row['id'] as String,
  organizationId: row['organization_id'] as String,
  role: row['role'] as String,
  action: row['action'] as String,
  entity: row['entity'] as String,
  occurredAt: DateTime.parse(row['occurred_at'] as String),
  metadata: rowFrom(row['metadata']),
  userId: row['user_id'] as String?,
  entityId: row['entity_id'] as String?,
  branchId: row['branch_id'] as String?,
  reason: row['reason'] as String?,
);
