import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/auth/invitation_inbox.dart';
import 'package:nexapos/core/auth/supabase_invitation_inbox.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gate_test.dart' show FakeAuthRepository;

const _userId = '00000000-0000-4000-8000-000000000001';
const _invitationId = '00000000-0000-4000-8000-000000000002';
const _identity = AuthIdentity(
  userId: _userId,
  email: 'employee@example.test',
  emailVerified: true,
);

class _RecordedRequest {
  _RecordedRequest(this.method, this.path, this.body);
  final String method;
  final String path;
  final Map<String, dynamic> body;
}

/// Exercises Supabase's actual HTTP serialization and Auth update endpoint.
/// Every request is intercepted: no live project or secret is used.
class _EndpointClient extends http.BaseClient {
  final requests = <_RecordedRequest>[];
  bool requiresPassword = false;
  bool failAcceptance = false;
  void Function()? onPasswordUpdate;

  Map<String, dynamic> get user => {
    'id': _userId,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': _identity.email,
    'email_confirmed_at': '2026-01-01T00:00:00Z',
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
    'app_metadata': {'provider': 'email'},
    'user_metadata': <String, dynamic>{},
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final rawBody = await request.finalize().bytesToString();
    final decoded = rawBody.isEmpty ? null : jsonDecode(rawBody);
    final body = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    final path = request.url.path;
    requests.add(_RecordedRequest(request.method, path, body));
    Object payload;
    var status = 200;
    if (path == '/auth/v1/token') {
      final expiry =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
      String segment(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      payload = {
        'access_token':
            '${segment({'alg': 'HS256', 'typ': 'JWT'})}.${segment({'sub': _userId, 'exp': expiry, 'role': 'authenticated'})}.test-signature',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': expiry,
        'user': user,
      };
    } else if (path == '/auth/v1/user') {
      if (request.method == 'PUT') onPasswordUpdate?.call();
      payload = user;
    } else if (path == '/rest/v1/rpc/list_pending_invitations') {
      payload = [
        {
          'invitation_id': _invitationId,
          'organization_id': '00000000-0000-4000-8000-000000000003',
          'business_name': 'Real response business',
          'full_name': 'Employee',
          'requested_role': 'cashier',
          'branch_ids': ['00000000-0000-4000-8000-000000000004'],
          'branch_names': ['Main Branch'],
          'all_branches': false,
          'requires_password': requiresPassword,
          'expires_at': '2030-01-01T00:00:00Z',
        },
      ];
    } else if (path == '/rest/v1/rpc/accept_employee_invitation') {
      if (failAcceptance) {
        status = 400;
        payload = {
          'code': '22023',
          'message': 'private token=SECRET',
          'details': null,
          'hint': null,
        };
      } else {
        payload = {
          'organization_id': 'server-business',
          'membership_id': 'server-membership',
          'role': 'cashier',
        };
      }
    } else {
      throw StateError('Unexpected intercepted endpoint: $path');
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(payload))),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

void main() {
  late _EndpointClient transport;
  late SupabaseClient client;
  late FakeAuthRepository auth;
  late SupabaseInvitationInbox inbox;

  setUp(() async {
    transport = _EndpointClient();
    client = SupabaseClient(
      'https://project.example.test',
      'public-test-key',
      httpClient: transport,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.pkce),
    );
    await client.auth.signInWithPassword(
      email: _identity.email,
      password: 'test-login-password',
    );
    auth = FakeAuthRepository()..identity = _identity;
    inbox = SupabaseInvitationInbox(client: client, authRepository: auth);
    transport.requests.clear();
  });

  tearDown(() async => client.dispose());

  test(
    'real RPC response maps server scope and acceptance sends only invitation ID',
    () async {
      final pending = await inbox.listPending();
      expect(pending.single.businessName, 'Real response business');
      expect(pending.single.role.name, 'cashier');
      expect(pending.single.branchNames, ['Main Branch']);
      await inbox.accept(pending.single);
      expect(
        transport.requests.last.path,
        '/rest/v1/rpc/accept_employee_invitation',
      );
      expect(transport.requests.last.body, {'p_invitation_id': _invitationId});
      expect(
        transport.requests.where((item) => item.path == '/auth/v1/user'),
        isEmpty,
      );
      expect(
        auth.memberships,
        isEmpty,
      ); // adapter never manufactures membership
    },
  );

  test(
    'new account needs password and updates real Auth before acceptance RPC',
    () async {
      transport.requiresPassword = true;
      final invitation = (await inbox.listPending()).single;
      await expectLater(
        inbox.accept(invitation),
        throwsA(isA<InvitationFailure>()),
      );
      expect(
        transport.requests.where(
          (item) => item.path.endsWith('accept_employee_invitation'),
        ),
        isEmpty,
      );
      await inbox.accept(invitation, newPassword: 'LongSafePassword123!');
      final update = transport.requests.indexWhere(
        (item) => item.path == '/auth/v1/user',
      );
      final accept = transport.requests.indexWhere(
        (item) => item.path.endsWith('accept_employee_invitation'),
      );
      expect(update, greaterThanOrEqualTo(0));
      expect(accept, greaterThan(update));
      expect(
        transport.requests[update].body['password'],
        'LongSafePassword123!',
      );
    },
  );

  test('unverified identity cannot invoke list or accept endpoints', () async {
    final invitation = (await inbox.listPending()).single;
    auth.identity = const AuthIdentity(
      userId: _userId,
      email: 'employee@example.test',
      emailVerified: false,
    );
    transport.requests.clear();
    await expectLater(inbox.listPending(), throwsA(isA<InvitationFailure>()));
    await expectLater(
      inbox.accept(invitation),
      throwsA(isA<InvitationFailure>()),
    );
    expect(transport.requests, isEmpty);
  });

  test('recovery session cannot invoke invitation endpoints', () async {
    final invitation = (await inbox.listPending()).single;
    auth.recoveryPolicy.beginVerifiedRecovery(_userId);
    transport.requests.clear();
    await expectLater(inbox.listPending(), throwsA(isA<InvitationFailure>()));
    await expectLater(
      inbox.accept(invitation),
      throwsA(isA<InvitationFailure>()),
    );
    expect(transport.requests, isEmpty);
  });

  test(
    'recovery starting during password update prevents acceptance RPC',
    () async {
      transport.requiresPassword = true;
      final invitation = (await inbox.listPending()).single;
      transport.onPasswordUpdate = () =>
          auth.recoveryPolicy.beginVerifiedRecovery(_userId);
      await expectLater(
        inbox.accept(invitation, newPassword: 'LongSafePassword123!'),
        throwsA(isA<InvitationFailure>()),
      );
      expect(
        transport.requests.where(
          (item) => item.path.endsWith('accept_employee_invitation'),
        ),
        isEmpty,
      );
    },
  );

  test('expired or revoked invitation errors are sanitized', () async {
    final invitation = (await inbox.listPending()).single;
    transport.failAcceptance = true;
    await expectLater(
      inbox.accept(invitation),
      throwsA(
        isA<InvitationFailure>()
            .having(
              (error) => error.message,
              'message',
              contains('no longer available'),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('SECRET')),
            ),
      ),
    );
  });

  test(
    'PKCE configured SDK validates server invite callback through Auth user endpoint',
    () async {
      final accessToken = client.auth.currentSession!.accessToken;
      final result = await client.auth.getSessionFromUrl(
        Uri(
          scheme: 'com.nexapos.app',
          host: 'auth-callback',
          fragment:
              'access_token=$accessToken&expires_in=3600&refresh_token=test-callback-refresh&token_type=bearer&type=invite',
        ),
      );
      expect(result.session.user.id, _userId);
      expect(result.session.user.emailConfirmedAt, isNotNull);
      expect(transport.requests.single.path, '/auth/v1/user');
      expect(transport.requests.single.method, 'GET');
    },
  );
}
