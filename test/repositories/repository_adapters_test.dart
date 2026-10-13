import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// The HTTP transport is already supplied by Supabase; no new package is needed.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/administration/data/supabase_administration_repository.dart';
import 'package:nexapos/features/administration/data/supabase_employee_repository.dart';
import 'package:nexapos/features/administration/domain/administration_models.dart';
import 'package:nexapos/features/catalog/data/supabase_catalog_repository.dart';
import 'package:nexapos/features/catalog/domain/catalog_models.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/people/data/supabase_people_repository.dart';
import 'package:nexapos/features/people/domain/people_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _org = '11111111-1111-1111-1111-111111111111';
const _user = '22222222-2222-2222-2222-222222222222';
const _member = '33333333-3333-3333-3333-333333333333';
const _branch = '44444444-4444-4444-4444-444444444444';
const _record = '55555555-5555-5555-5555-555555555555';
const _requestId = '66666666-6666-6666-6666-666666666666';
const _productInput = ProductInput(
  name: 'Coffee',
  sku: 'COF-1',
  costMinor: 3000,
  priceMinor: 6500,
);

AuthenticatedUser _actor({
  AppRole role = AppRole.owner,
  String userId = _user,
}) => AuthenticatedUser(
  userId: userId,
  email: 'owner@example.test',
  organizationId: _org,
  membershipId: _member,
  role: role,
  branchIds: {_branch},
  allBranches: role == AppRole.owner,
  businessName: 'Test business',
);

Map<String, dynamic> _product({int? costMinor = 3000, int revision = 2}) => {
  'id': _record,
  'organization_id': _org,
  'name': 'Coffee',
  'sku': 'COF-1',
  'cost_minor': costMinor,
  'price_minor': 6500,
  'currency': 'PHP',
  'reorder_level': '1.2500',
  'unit': 'each',
  'active': true,
  'revision': revision,
};
Map<String, dynamic> _supplier({int revision = 2}) => {
  'id': _record,
  'organization_id': _org,
  'name': 'Coffee Supplier',
  'branch_id': _branch,
  'active': true,
  'revision': revision,
};
Map<String, dynamic> _settings() => {
  'id': _org,
  'business_name': 'Test business',
  'currency': 'PHP',
  'tax_bps': 1200,
  'revision': 5,
};
Map<String, dynamic> _employee() => {
  'id': _record,
  'user_id': _requestId,
  'full_name': 'Employee',
  'role': 'cashier',
  'status': 'active',
  'all_branches': false,
  'branch_ids': [_branch],
  'revision': 3,
};

TypeMatcher<RepositoryFailure> _failure(RepositoryFailureType type) =>
    isA<RepositoryFailure>()
        .having((error) => error.type, 'type', type)
        .having(
          (error) => error.message,
          'public message',
          isNot(contains('PRIVATE')),
        );

class _Harness {
  _Harness() {
    client = SupabaseClient(
      'https://project.example.test',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (handler != null) return handler!(request);
        return response(payload, status, request);
      }),
    );
  }
  late final SupabaseClient client;
  final requests = <http.Request>[];
  Object? payload = <Object>[];
  int status = 200;
  Future<http.Response> Function(http.Request)? handler;

  Future<void> signIn({String userId = _user, bool verified = true}) async {
    final header = base64Url
        .encode(utf8.encode('{"alg":"HS256"}'))
        .replaceAll('=', '');
    final body = base64Url
        .encode(utf8.encode(jsonEncode({'sub': userId, 'exp': 4102444800})))
        .replaceAll('=', '');
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': '$header.$body.test-signature',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'user': {
          'id': userId,
          'aud': 'authenticated',
          'email': 'owner@example.test',
          'email_confirmed_at': verified ? '2026-10-09T00:00:00Z' : null,
          'created_at': '2026-10-09T00:00:00Z',
          'app_metadata': {},
          'user_metadata': {},
        },
      }),
    );
  }

  static http.Response response(
    Object? body,
    int status,
    http.Request request,
  ) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
    request: request,
  );
  Map<String, dynamic> get lastBody =>
      jsonDecode(requests.last.body) as Map<String, dynamic>;
  Future<void> dispose() => client.dispose();
}

void main() {
  late _Harness transport;
  setUp(() => transport = _Harness());
  tearDown(() => transport.dispose());

  test('all actual adapters reject absent sessions without HTTP', () async {
    final actor = _actor();
    await expectLater(
      SupabaseCatalogRepository(
        client: transport.client,
        actor: actor,
      ).searchProducts(),
      throwsA(_failure(RepositoryFailureType.unauthenticated)),
    );
    await expectLater(
      SupabasePeopleRepository(
        client: transport.client,
        actor: actor,
      ).listCustomers(),
      throwsA(_failure(RepositoryFailureType.unauthenticated)),
    );
    await expectLater(
      SupabaseAdministrationRepository(
        client: transport.client,
        actor: actor,
      ).loadSettings(),
      throwsA(_failure(RepositoryFailureType.unauthenticated)),
    );
    await expectLater(
      SupabaseEmployeeRepository(
        client: transport.client,
        actor: actor,
      ).listEmployees(),
      throwsA(_failure(RepositoryFailureType.unauthenticated)),
    );
    expect(transport.requests, isEmpty);
  });

  test('wrong actor and unverified identity cannot query a tenant', () async {
    await transport.signIn(verified: false);
    await expectLater(
      SupabaseCatalogRepository(
        client: transport.client,
        actor: _actor(),
      ).searchProducts(),
      throwsA(_failure(RepositoryFailureType.unauthenticated)),
    );
    await transport.signIn(userId: _requestId);
    await expectLater(
      SupabaseCatalogRepository(
        client: transport.client,
        actor: _actor(),
      ).searchProducts(),
      throwsA(_failure(RepositoryFailureType.unauthenticated)),
    );
    expect(transport.requests, isEmpty);
  });

  test('a recovery session cannot enter repositories', () async {
    await transport.signIn();
    final repository = SupabaseCatalogRepository(
      client: transport.client,
      actor: _actor(),
      isRecoverySession: () => true,
    );
    await expectLater(
      repository.createProduct(_productInput),
      throwsA(_failure(RepositoryFailureType.unauthenticated)),
    );
    expect(transport.requests, isEmpty);
  });

  test(
    'catalog RPC scopes search and overfetches a bounded stable page',
    () async {
      await transport.signIn();
      transport.payload = [_product(costMinor: null), _product()];
      final repository = SupabaseCatalogRepository(
        client: transport.client,
        actor: _actor(role: AppRole.cashier),
      );
      final page = await repository.searchProducts(
        filter: const ProductFilter(
          query: ' COF-1 ',
          categoryId: _record,
          active: true,
        ),
        page: const PageRequest(offset: 10, limit: 1),
      );
      expect(page.items.single.costMinor, isNull);
      expect(page.items.single.priceMinor, 6500);
      expect(page.items.single.reorderLevel, '1.2500');
      expect(page.hasMore, isTrue);
      expect(page.nextOffset, 11);
      expect(transport.requests.single.url.path, '/rest/v1/rpc/list_products');
      expect(transport.lastBody, {
        'p_organization_id': _org,
        'p_query': 'COF-1',
        'p_category_id': _record,
        'p_active': true,
        'p_offset': 10,
        'p_limit': 2,
      });
    },
  );

  test(
    'category query carries tenant filter and inclusive bounded range',
    () async {
      await transport.signIn();
      transport.payload = [
        {
          'id': _record,
          'organization_id': _org,
          'name': 'Cafe',
          'active': true,
          'revision': 1,
        },
      ];
      final page =
          await SupabaseCatalogRepository(
            client: transport.client,
            actor: _actor(),
          ).listCategories(
            active: true,
            page: const PageRequest(offset: 5, limit: 2),
          );
      expect(page.items.single.name, 'Cafe');
      final query = transport.requests.single.url.queryParameters;
      expect(query['organization_id'], 'eq.$_org');
      expect(query['active'], 'eq.true');
      expect(query['offset'], '5');
      expect(query['limit'], '3');
      expect(query['order'], 'name.asc.nullslast,id.asc.nullslast');
    },
  );

  test(
    'product edit sends expected revision; CAS conflict cannot silently save',
    () async {
      await transport.signIn();
      transport.status = 409;
      transport.payload = {
        'code': '40001',
        'message': 'PRIVATE concurrent version',
      };
      await expectLater(
        SupabaseCatalogRepository(
          client: transport.client,
          actor: _actor(),
        ).updateProduct(id: _record, expectedRevision: 7, input: _productInput),
        throwsA(_failure(RepositoryFailureType.conflict)),
      );
      expect(transport.requests.single.method, 'POST');
      expect(transport.requests.single.url.path, '/rest/v1/rpc/save_product');
      expect(transport.lastBody['p_expected_revision'], 7);
      expect(transport.lastBody['p_id'], _record);
      final values = transport.lastBody['p_values'] as Map<String, dynamic>;
      expect(values['price_minor'], 6500);
      expect(values.containsKey('revision'), isFalse);
      expect(values.containsKey('organization_id'), isFalse);
      expect(values.containsKey('role'), isFalse);
    },
  );

  test('create accepts a server-generated identifier and revision', () async {
    await transport.signIn();
    transport.payload = _product(revision: 1);
    final saved = await SupabaseCatalogRepository(
      client: transport.client,
      actor: _actor(),
    ).createProduct(_productInput);
    expect(saved.id, _record);
    expect(saved.revision, 1);
    expect(transport.lastBody['p_id'], isNull);
    expect(transport.lastBody['p_expected_revision'], isNull);
  });

  test('product deactivation is a partial CAS without forged prices', () async {
    await transport.signIn();
    transport.payload = {..._product(), 'active': false};
    final saved = await SupabaseCatalogRepository(
      client: transport.client,
      actor: _actor(),
    ).setProductActive(id: _record, expectedRevision: 1, active: false);
    expect(saved.active, isFalse);
    expect(transport.lastBody['p_values'], {'active': false});
    expect(transport.lastBody['p_expected_revision'], 1);
  });

  test('permission and duplicate errors expose only public messages', () async {
    await transport.signIn();
    final repository = SupabaseCatalogRepository(
      client: transport.client,
      actor: _actor(),
    );
    for (final entry in {
      '42501': RepositoryFailureType.permissionDenied,
      '23505': RepositoryFailureType.validation,
    }.entries) {
      transport.status = 403;
      transport.payload = {
        'code': entry.key,
        'message': 'PRIVATE internal table and credentials',
      };
      await expectLater(
        repository.createProduct(_productInput),
        throwsA(_failure(entry.value)),
      );
    }
  });

  test('invalid pages and inputs are stopped before transport', () async {
    await transport.signIn();
    final repository = SupabaseCatalogRepository(
      client: transport.client,
      actor: _actor(),
    );
    await expectLater(
      repository.searchProducts(page: const PageRequest(limit: 101)),
      throwsA(_failure(RepositoryFailureType.validation)),
    );
    await expectLater(
      repository.createProduct(
        const ProductInput(name: ' ', sku: 'A', costMinor: 0, priceMinor: -1),
      ),
      throwsA(_failure(RepositoryFailureType.validation)),
    );
    expect(transport.requests, isEmpty);
  });

  test(
    'Storage references cannot target another organization or arbitrary URL',
    () async {
      await transport.signIn();
      final repository = SupabaseCatalogRepository(
        client: transport.client,
        actor: _actor(),
      );
      for (final reference in [
        '$_branch/photo.png',
        'https://private.example.test/photo.png',
        '$_org/../photo.png',
      ]) {
        await expectLater(
          repository.createProduct(
            ProductInput(
              name: 'Coffee',
              sku: 'COF-1',
              costMinor: 0,
              priceMinor: 1,
              imagePath: reference,
            ),
          ),
          throwsA(_failure(RepositoryFailureType.validation)),
        );
      }
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'image upload is explicitly disconnected and never invokes Storage',
    () async {
      await transport.signIn();
      await expectLater(
        SupabaseCatalogRepository(
          client: transport.client,
          actor: _actor(),
        ).uploadProductImage(_record, [1, 2]),
        throwsA(_failure(RepositoryFailureType.notConnected)),
      );
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'contacts queries remain tenant and branch scoped with literal search',
    () async {
      await transport.signIn();
      transport.payload = [_supplier()];
      final page =
          await SupabasePeopleRepository(
            client: transport.client,
            actor: _actor(),
          ).listSuppliers(
            query: ' 50%_ ',
            branchId: _branch,
            active: true,
            page: const PageRequest(limit: 5),
          );
      expect(page.items.single.branchId, _branch);
      final query = transport.requests.single.url.queryParameters;
      expect(query['organization_id'], 'eq.$_org');
      expect(query['branch_id'], 'eq.$_branch');
      expect(query['name'], r'ilike.%50\%\_%');
      expect(query['limit'], '6');
    },
  );

  test('contact CAS normalizes email without sending actor claims', () async {
    await transport.signIn();
    transport.payload = _supplier(revision: 4);
    final saved =
        await SupabasePeopleRepository(
          client: transport.client,
          actor: _actor(),
        ).updateSupplier(
          id: _record,
          expectedRevision: 3,
          input: const SupplierInput(
            name: ' Coffee Supplier ',
            email: ' PERSON@example.test ',
            branchId: _branch,
          ),
        );
    expect(saved.revision, 4);
    expect(transport.lastBody['p_expected_revision'], 3);
    expect(
      (transport.lastBody['p_values'] as Map)['email'],
      'person@example.test',
    );
    expect((transport.lastBody['p_values'] as Map)['branch_id'], _branch);
  });

  test('settings CAS uses integer basis points and server revision', () async {
    await transport.signIn();
    transport.payload = _settings();
    final saved =
        await SupabaseAdministrationRepository(
          client: transport.client,
          actor: _actor(),
        ).updateSettings(
          expectedRevision: 4,
          input: const BusinessSettingsInput(
            businessName: 'Test business',
            taxBps: 1200,
          ),
        );
    expect(saved.taxBps, 1200);
    expect(saved.revision, 5);
    expect(transport.lastBody['p_expected_revision'], 4);
    expect((transport.lastBody['p_values'] as Map)['tax_bps'], 1200);
  });

  test('audit RPC sends tenant filters and a bounded page', () async {
    await transport.signIn();
    await SupabaseAdministrationRepository(
      client: transport.client,
      actor: _actor(),
    ).listAudit(
      filter: const AuditFilter(
        entity: 'products',
        action: 'products.update',
        branchId: _branch,
      ),
      page: const PageRequest(offset: 20, limit: 10),
    );
    expect(transport.requests.single.url.path, '/rest/v1/rpc/list_audit_logs');
    expect(transport.lastBody, {
      'p_organization_id': _org,
      'p_entity': 'products',
      'p_action': 'products.update',
      'p_branch_id': _branch,
      'p_offset': 20,
      'p_limit': 11,
    });
  });

  test('roster reads server roles and preserves page bounds', () async {
    await transport.signIn();
    transport.payload = [_employee()];
    final result = await SupabaseEmployeeRepository(
      client: transport.client,
      actor: _actor(),
    ).listEmployees(status: EmployeeStatus.active);
    expect(result.items.single.role, AppRole.cashier);
    expect(result.items.single.membershipId, _record);
    expect(transport.lastBody['p_status'], 'active');
    expect(transport.lastBody['p_limit'], 51);
  });

  test(
    'employee changes require CAS reason and cannot mutate own access',
    () async {
      await transport.signIn();
      final repository = SupabaseEmployeeRepository(
        client: transport.client,
        actor: _actor(),
      );
      final input = EmployeeAccessInput(
        role: AppRole.cashier,
        status: EmployeeStatus.disabled,
        allBranches: false,
        branchIds: [_branch],
        reason: 'Employment ended',
      );
      await expectLater(
        repository.updateEmployee(
          membershipId: _member,
          expectedRevision: 2,
          input: input,
        ),
        throwsA(_failure(RepositoryFailureType.permissionDenied)),
      );
      expect(transport.requests, isEmpty);
      transport.payload = _employee();
      await repository.updateEmployee(
        membershipId: _record,
        expectedRevision: 2,
        input: input,
      );
      expect(transport.lastBody['p_expected_revision'], 2);
      expect(transport.lastBody['p_status'], 'disabled');
      expect(transport.lastBody['p_reason'], 'Employment ended');
    },
  );

  test(
    'invitation uses bearer transport and distinguishes sent from sending',
    () async {
      await transport.signIn();
      final repository = SupabaseEmployeeRepository(
        client: transport.client,
        actor: _actor(),
      );
      final input = EmployeeInvitationInput(
        requestId: _requestId,
        email: ' STAFF@example.test ',
        fullName: 'New staff',
        role: AppRole.inventoryStaff,
        branchIds: [_branch],
      );
      for (final status in [200, 202]) {
        transport.status = status;
        transport.payload = {
          'invitation_id': _record,
          'expires_at': '2026-10-16T00:00:00Z',
          'delivery_state': status == 200 ? 'sent' : 'sending',
        };
        final delivery = await repository.createInvitation(input);
        expect(
          delivery.state,
          status == 200
              ? InvitationDeliveryState.sent
              : InvitationDeliveryState.sending,
        );
        expect(
          transport.requests.last.url.path,
          '/functions/v1/employee-invitations',
        );
        expect(transport.lastBody['request_id'], _requestId);
        expect(transport.lastBody['email'], 'staff@example.test');
        expect(transport.lastBody['role'], 'inventory_staff');
        expect(transport.lastBody['organization_id'], _org);
        expect(
          transport.requests.last.headers['authorization'],
          startsWith('Bearer '),
        );
      }
    },
  );

  test('failed email never returns fake sent acknowledgement', () async {
    await transport.signIn();
    transport.status = 503;
    transport.payload = {
      'error': 'email_delivery_not_confirmed',
      'delivery_state': 'failed',
      'message': 'PRIVATE provider secret',
    };
    await expectLater(
      SupabaseEmployeeRepository(
        client: transport.client,
        actor: _actor(),
      ).createInvitation(
        EmployeeInvitationInput(
          requestId: _requestId,
          email: 'staff@example.test',
          fullName: 'New staff',
          role: AppRole.cashier,
          branchIds: [_branch],
        ),
      ),
      throwsA(_failure(RepositoryFailureType.unavailable)),
    );
  });

  test('rate-limited invitations expose a sanitized retry message', () async {
    await transport.signIn();
    transport.status = 429;
    transport.payload = {
      'error': 'invitation_rate_limited',
      'message': 'PRIVATE internal limiter metadata',
    };
    await expectLater(
      SupabaseEmployeeRepository(
        client: transport.client,
        actor: _actor(),
      ).createInvitation(
        EmployeeInvitationInput(
          requestId: _requestId,
          email: 'staff@example.test',
          fullName: 'New staff',
          role: AppRole.cashier,
          branchIds: [_branch],
        ),
      ),
      throwsA(
        _failure(RepositoryFailureType.unavailable).having(
          (RepositoryFailure error) => error.message,
          'retry message',
          contains('Wait before retrying the same request'),
        ),
      ),
    );
    expect(
      transport.requests.single.url.path,
      '/functions/v1/employee-invitations',
    );
  });

  test(
    'all-branch invitations use canonical empty branch assignments',
    () async {
      await transport.signIn();
      final repository = SupabaseEmployeeRepository(
        client: transport.client,
        actor: _actor(),
      );
      await expectLater(
        repository.createInvitation(
          EmployeeInvitationInput(
            requestId: _requestId,
            email: 'admin@example.test',
            fullName: 'New admin',
            role: AppRole.admin,
            allBranches: true,
            branchIds: [_branch],
          ),
        ),
        throwsA(_failure(RepositoryFailureType.validation)),
      );
      expect(transport.requests, isEmpty);
      transport.payload = {
        'invitation_id': _record,
        'expires_at': '2026-10-16T00:00:00Z',
        'delivery_state': 'sent',
      };
      await repository.createInvitation(
        EmployeeInvitationInput(
          requestId: _requestId,
          email: 'admin@example.test',
          fullName: 'New admin',
          role: AppRole.admin,
          allBranches: true,
          branchIds: const [],
        ),
      );
      expect(transport.lastBody['all_branches'], isTrue);
      expect(transport.lastBody['branch_ids'], isEmpty);
    },
  );

  test('transport and malformed data failures are sanitized', () async {
    await transport.signIn();
    final repository = SupabaseCatalogRepository(
      client: transport.client,
      actor: _actor(),
    );
    transport.handler = (_) async =>
        throw const SocketException('PRIVATE connection details');
    await expectLater(
      repository.searchProducts(),
      throwsA(_failure(RepositoryFailureType.unavailable)),
    );
    transport.handler = null;
    transport.payload = {'unexpected': 'PRIVATE'};
    await expectLater(
      repository.searchProducts(),
      throwsA(_failure(RepositoryFailureType.unavailable)),
    );
  });

  test(
    'malformed saved contact is normalized inside the data boundary',
    () async {
      await transport.signIn();
      transport.payload = {'name': 'PRIVATE unexpected saved row'};
      await expectLater(
        SupabasePeopleRepository(
          client: transport.client,
          actor: _actor(),
        ).createSupplier(const SupplierInput(name: 'Supplier')),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
    },
  );

  test('a delayed business response is discarded after sign-out', () async {
    await transport.signIn();
    final response = Completer<http.Response>();
    final started = Completer<http.Request>();
    transport.handler = (request) async {
      if (request.url.path.endsWith('/list_products')) {
        started.complete(request);
        return response.future;
      }
      return _Harness.response({}, 200, request);
    };
    final pending = SupabaseCatalogRepository(
      client: transport.client,
      actor: _actor(),
    ).searchProducts();
    final request = await started.future;
    await transport.client.auth.signOut(scope: SignOutScope.local);
    final expectation = expectLater(
      pending,
      throwsA(_failure(RepositoryFailureType.unauthenticated)),
    );
    response.complete(_Harness.response([_product()], 200, request));
    await expectation;
  });

  test(
    'large reorder quantities keep all digits and reject numeric JSON',
    () async {
      await transport.signIn();
      final repository = SupabaseCatalogRepository(
        client: transport.client,
        actor: _actor(),
      );
      transport.payload = [
        {..._product(), 'reorder_level': '99999999999999.9999'},
      ];
      expect(
        (await repository.searchProducts()).items.single.reorderLevel,
        '99999999999999.9999',
      );
      transport.payload = [
        {..._product(), 'reorder_level': 99999999999999.9999},
      ];
      await expectLater(
        repository.searchProducts(),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
    },
  );

  test(
    'recovery beginning during a write suppresses its success response',
    () async {
      await transport.signIn();
      var recovery = false;
      final response = Completer<http.Response>();
      final started = Completer<http.Request>();
      transport.handler = (request) async {
        started.complete(request);
        return response.future;
      };
      final pending = SupabaseCatalogRepository(
        client: transport.client,
        actor: _actor(),
        isRecoverySession: () => recovery,
      ).createProduct(_productInput);
      final request = await started.future;
      recovery = true;
      final expectation = expectLater(
        pending,
        throwsA(_failure(RepositoryFailureType.unauthenticated)),
      );
      response.complete(_Harness.response(_product(revision: 1), 200, request));
      await expectation;
      expect(transport.requests.single.url.path, '/rest/v1/rpc/save_product');
    },
  );
}
