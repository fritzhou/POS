import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth/auth_models.dart';
import '../core/auth/auth_repository.dart';
import '../core/auth/secure_session_storage.dart';
import '../core/database/app_database.dart';
import '../core/offline/offline_device_security.dart';
import '../core/offline/offline_protocol.dart';
import '../core/operations/native_operation_journal.dart';
import '../features/administration/data/supabase_administration_repository.dart';
import '../features/administration/data/supabase_employee_repository.dart';
import '../features/catalog/data/supabase_catalog_repository.dart';
import '../features/checkout/data/supabase_checkout_repository.dart';
import '../features/inventory/data/supabase_inventory_repository.dart';
import '../features/offline/data/supabase_offline_workspace.dart';
import '../features/people/data/supabase_people_repository.dart';
import '../features/security/data/supabase_security_repository.dart';
import '../features/security/pin_security.dart';
import '../features/authentication/data/supabase_mfa_repository.dart';
import '../features/purchases/data/supabase_purchase_repository.dart';
import '../features/expenses/data/supabase_expense_repository.dart';
import '../features/reports/data/supabase_reports_repository.dart';
import '../features/logistics/data/supabase_logistics_repository.dart';
import '../features/invitations/data/supabase_invitation_administration_repository.dart';
import 'business_services.dart';
import 'config/backend_config.dart';
import 'offline_services.dart';

/// Centralizes resource ownership for online memberships and grant-only resume.
class ProductionServices {
  ProductionServices({
    required this.client,
    required this.auth,
    required this.config,
    SecretStore? store,
    this.isAppLocked,
  }) : store = store ?? PlatformSecretStore();

  final SupabaseClient client;
  final AuthRepository auth;
  final BackendConfig config;
  final SecretStore store;
  final bool Function()? isAppLocked;
  final _deviceSecurity = <String, OfflineDeviceSecurity>{};

  OfflineDeviceSecurity _security(String actorId) =>
      _deviceSecurity.putIfAbsent(
        actorId,
        () => OfflineDeviceSecurity(
          store: store,
          namespace: 'nexapos.offline.${Uri.parse(config.url).host}.$actorId',
        ),
      );

  OfflineGrantVerifier get _verifier => OfflineGrantVerifier(
    issuer: config.url,
    trustedKeys: config.offlineTrustedKeys,
  );

  Future<void> lockIdentity(String actorId) => _security(actorId).lock();

  Future<void> reconcileMemberships(
    AuthIdentity identity,
    List<AuthenticatedUser> memberships,
  ) async {
    final security = _security(identity.userId);
    try {
      await _reconcileStoredGrants(security, identity, memberships);
    } on Object {
      // Damaged offline locators cannot grant offline authority or prevent a
      // freshly verified server membership from using ordinary online services.
      // lock() sets a shared volatile denial before attempting durable cleanup.
      try {
        await security.lock();
      } on Object {
        // The workspace remains locked in-process if secure cleanup fails.
      }
    }
  }

  Future<void> _reconcileStoredGrants(
    OfflineDeviceSecurity security,
    AuthIdentity identity,
    List<AuthenticatedUser> memberships,
  ) async {
    final grants = await security.retainedScopes(actorId: identity.userId);
    for (final grant in grants) {
      final device = await security.restore(
        organizationId: grant.scope.organizationId,
        actorId: identity.userId,
      );
      if (device == null ||
          device.deviceId != grant.scope.deviceId ||
          await security.isReleased(grant.grantId)) {
        continue;
      }
      final current = memberships.where(
        (member) =>
            member.userId == identity.userId &&
            member.organizationId == grant.scope.organizationId &&
            member.membershipId == grant.scope.membershipId &&
            member.role.name == grant.scope.role &&
            member.branchIds.contains(grant.scope.branchId),
      );
      if (current.isEmpty) {
        await security.lock();
        return;
      }
    }
  }

  BusinessServices create(AuthenticatedUser actor) {
    final journal = NativeOperationJournal.openNative(
      organizationId: actor.organizationId,
      actorId: actor.userId,
      store: store,
    );
    final databases = <String, AppDatabase>{};
    bool disposed = false;
    Future<void>? disposal;
    Future<AppDatabase> database(DatabaseScope scope) async {
      if (disposed) throw StateError('Workspace resources are closed.');
      return databases.putIfAbsent(
        '${scope.organizationId}:${scope.branchId}',
        () => AppDatabase.openNative(scope: scope, store: store),
      );
    }

    bool recovery() =>
        auth.hasVerifiedRecoverySession || isAppLocked?.call() == true;
    bool locked() =>
        auth.currentIdentity?.userId != actor.userId ||
        auth.currentIdentity?.emailVerified != true ||
        isAppLocked?.call() == true;
    final mfa = SupabaseMfaRepository(
      client: client,
      authUrl: '${config.url}/auth/v1',
      publicApiKey: config.clientKey,
      isRecoverySession: recovery,
    );
    final offline = config.offlineValidationError == null
        ? SupabaseOfflineWorkspace(
            client: client,
            actor: actor,
            database: database,
            security: _security(actor.userId),
            verifier: _verifier,
            journal: journal,
            isRecoverySession: recovery,
            isExplicitlySignedOut: locked,
          )
        : null;
    return BusinessServices(
      logistics: SupabaseLogisticsRepository(
        client: client,
        actor: actor,
        journal: journal,
        isRecoverySession: recovery,
      ),
      purchases: SupabasePurchaseRepository(
        client: client,
        actor: actor,
        journal: journal,
        isRecoverySession: recovery,
      ),
      expenses: SupabaseExpenseRepository(
        client: client,
        actor: actor,
        journal: journal,
        isRecoverySession: recovery,
      ),
      reports: SupabaseReportsRepository(
        client: client,
        actor: actor,
        isRecoverySession: recovery,
      ),
      offline: offline,
      security: SupabaseSecurityRepository(
        client: client,
        actor: actor,
        journal: journal,
        isRecoverySession: recovery,
      ),
      mfa: mfa,
      pin: SupabaseEmployeePinRepository(
        client: client,
        actor: actor,
        isRecoverySession: recovery,
      ),
      onDispose: () => disposal ??= () async {
        disposed = true;
        Object? failure;
        Future<void> close(Future<void> Function() operation) async {
          try {
            await operation();
          } on Object catch (error) {
            failure ??= error;
          }
        }

        await close(mfa.dispose);
        for (final db in databases.values) {
          await close(db.close);
        }
        await close(journal.close);
        if (failure != null) throw failure!;
      }(),
      checkout: SupabaseCheckoutRepository(
        client: client,
        actor: actor,
        journal: journal,
        isRecoverySession: recovery,
      ),
      inventory: SupabaseInventoryRepository(
        client: client,
        actor: actor,
        journal: journal,
        isRecoverySession: recovery,
      ),
      catalog: SupabaseCatalogRepository(
        client: client,
        actor: actor,
        isRecoverySession: recovery,
      ),
      people: SupabasePeopleRepository(
        client: client,
        actor: actor,
        isRecoverySession: recovery,
      ),
      administration: SupabaseAdministrationRepository(
        client: client,
        actor: actor,
        isRecoverySession: recovery,
      ),
      invitationAdministration: SupabaseInvitationAdministrationRepository(
        client: client,
        actor: actor,
        journal: journal,
        isRecoverySession: recovery,
      ),
      employees: SupabaseEmployeeRepository(
        client: client,
        actor: actor,
        isRecoverySession: recovery,
      ),
    );
  }

  Future<List<OfflineResumeCandidate>> resume(AuthIdentity identity) async {
    if (config.offlineValidationError != null ||
        auth.currentIdentity?.userId != identity.userId ||
        !identity.emailVerified ||
        auth.hasVerifiedRecoverySession) {
      return const [];
    }
    final databases = <String, AppDatabase>{};
    Future<AppDatabase> database(DatabaseScope scope) async =>
        databases.putIfAbsent(
          '${scope.organizationId}:${scope.branchId}',
          () => AppDatabase.openNative(scope: scope, store: store),
        );
    try {
      final descriptors = await SupabaseOfflineWorkspace.resumeDescriptors(
        identity: identity,
        security: _security(identity.userId),
        verifier: _verifier,
        database: database,
      );
      if (auth.currentIdentity?.userId != identity.userId ||
          auth.hasVerifiedRecoverySession) {
        return const [];
      }
      return descriptors
          .map((descriptor) {
            final services = create(descriptor.actor);
            return OfflineResumeCandidate(
              workspace: services.offline!,
              branchId: descriptor.branchId,
              label: descriptor.label,
              dispose: services.dispose,
              actor: descriptor.actor,
            );
          })
          .toList(growable: false);
    } finally {
      for (final db in databases.values) {
        await db.close();
      }
    }
  }
}
