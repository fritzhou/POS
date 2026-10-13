import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/app/config/backend_config.dart';
import 'package:nexapos/app/production_services.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/offline/offline_device_security.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_gate_test.dart' show FakeAuthRepository;
import '../auth/offline_failure_classification_test.dart' show Store;

void main() {
  test(
    'damaged offline locators lock device but preserve verified online identity',
    () async {
      const actorId = '10000000-0000-4000-8000-000000000001';
      const org = '10000000-0000-4000-8000-000000000002';
      const branch = '10000000-0000-4000-8000-000000000003';
      const identity = AuthIdentity(
        userId: actorId,
        email: 'actor@example.test',
        emailVerified: true,
      );
      final auth = FakeAuthRepository()..identity = identity;
      addTearDown(auth.controller.close);
      final client = SupabaseClient(
        'https://project.example.test',
        'public-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final store = Store();
      const namespace = 'nexapos.offline.project.example.test.$actorId';
      final security = OfflineDeviceSecurity(
        store: store,
        namespace: namespace,
      );
      await security.enable(
        organizationId: org,
        actorId: actorId,
        explicitConsent: true,
      );
      await store.write('$namespace.grant_index.$actorId', '{damaged');
      final production = ProductionServices(
        client: client,
        auth: auth,
        config: const BackendConfig(
          url: 'https://project.example.test',
          clientKey: 'public-test-key',
        ),
        store: store,
      );
      await production.reconcileMemberships(identity, [
        AuthenticatedUser(
          userId: actorId,
          email: identity.email,
          organizationId: org,
          membershipId: '10000000-0000-4000-8000-000000000004',
          role: AppRole.cashier,
          branchIds: {branch},
          allBranches: false,
          businessName: 'Test business',
        ),
      ]);
      expect(auth.currentIdentity, same(identity));
      expect(await store.read('$namespace.locked'), 'true');
      expect(
        await security.restore(organizationId: org, actorId: actorId),
        isNull,
      );
    },
  );
}
