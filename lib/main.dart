import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/business_services.dart';
import 'app/offline_services.dart';
import 'app/production_services.dart';
import 'app/config/backend_config.dart';
import 'core/auth/auth_repository.dart';
import 'core/auth/invitation_inbox.dart';
import 'core/auth/secure_session_storage.dart';
import 'core/auth/supabase_auth_repository.dart';
import 'core/auth/supabase_invitation_inbox.dart';
import 'core/security/access_lock.dart';
import 'core/security/session_security_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = BackendConfig.fromEnvironment();
  AuthRepository repository = const NotConfiguredAuthRepository();
  InvitationInbox? invitations;
  BusinessServicesFactory? servicesFactory;
  OfflineResumeFactory? offlineResume;
  OfflineIdentityLock? offlineLock;
  OfflineMembershipReconciler? offlineMembershipReconciler;
  String? notice;
  final accessLock = AccessLock();
  SessionSecurityRepository? sessionSecurity;
  if (config.isConfigured) {
    notice = config.validationError;
    if (notice == null) {
      try {
        final storage = SecureSessionStorage(
          namespace: 'nexapos.auth.${Uri.parse(config.url).host}',
        );
        await Supabase.initialize(
          url: config.url,
          publishableKey: config.clientKey,
          debug: false,
          authOptions: FlutterAuthClientOptions(
            localStorage: storage,
            pkceAsyncStorage: storage,
            authFlowType: AuthFlowType.pkce,
            autoRefreshToken: true,
          ),
        );
        final redirect = config.authRedirectUrl.isEmpty
            ? null
            : config.authRedirectUrl;
        repository = SupabaseAuthRepository(
          client: Supabase.instance.client,
          sessionStorage: storage,
          recoveryRedirectTo: redirect,
          ownerRedirectTo: redirect,
        );
        final client = Supabase.instance.client;
        invitations = SupabaseInvitationInbox(
          client: client,
          authRepository: repository,
        );
        final services = ProductionServices(
          client: client,
          auth: repository,
          config: config,
          isAppLocked: () => accessLock.isLocked,
        );
        sessionSecurity = SupabaseSessionSecurityRepository(
          client: client,
          auth: repository,
          sessionStorage: storage,
          authUrl: '${config.url}/auth/v1',
          publicApiKey: config.clientKey,
        );
        servicesFactory = services.create;
        if (config.offlineValidationError == null) {
          offlineResume = services.resume;
          offlineLock = services.lockIdentity;
          offlineMembershipReconciler = services.reconcileMemberships;
        }
      } on Object {
        notice =
            'Authentication could not be initialized. Check public project '
            'configuration and platform secure storage. Not Yet Connected.';
      }
    }
  }
  runApp(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        accessLockProvider.overrideWithValue(accessLock),
        sessionSecurityProvider.overrideWithValue(sessionSecurity),
        invitationInboxProvider.overrideWithValue(invitations),
        businessServicesFactoryProvider.overrideWithValue(servicesFactory),
        offlineResumeFactoryProvider.overrideWithValue(offlineResume),
        offlineIdentityLockProvider.overrideWithValue(offlineLock),
        offlineMembershipReconcilerProvider.overrideWithValue(
          offlineMembershipReconciler,
        ),
      ],
      child: NexaApp(startupNotice: notice),
    ),
  );
}
