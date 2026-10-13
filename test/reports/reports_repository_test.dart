import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/reports/data/supabase_reports_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'report_fixtures.dart';

class _Harness {
  _Harness() {
    client = SupabaseClient(
      'https://project.example.test',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final result = await handler(request);
        return http.Response.bytes(
          result.bodyBytes,
          result.statusCode,
          headers: result.headers,
          request: request,
        );
      }),
    );
  }
  late final SupabaseClient client;
  final requests = <http.Request>[];
  late Future<http.Response> Function(http.Request) handler = (request) async {
    final payload = switch (request.url.path.split('/').last) {
      'get_sales_report' => salesReportWire(),
      'get_inventory_report' => inventoryReportWire(),
      'get_expense_report' => expenseReportWire(),
      _ => <String, dynamic>{},
    };
    return response(payload);
  };
  static http.Response response(Object value, {int status = 200}) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json'},
      );
  SupabaseReportsRepository repository({
    AppRole role = AppRole.owner,
    bool Function()? recovery,
  }) => SupabaseReportsRepository(
    client: client,
    actor: reportMembership(role: role),
    isRecoverySession: recovery,
  );
  Future<void> signIn({
    String actor = reportActor,
    bool verified = true,
  }) async {
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token':
            '${encode({'alg': 'HS256'})}.${encode({'sub': actor, 'exp': 4102444800})}.test',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'user': {
          'id': actor,
          'aud': 'authenticated',
          'email': 'reports@example.test',
          'email_confirmed_at': verified ? '2026-10-12T00:00:00Z' : null,
          'created_at': '2026-10-12T00:00:00Z',
          'app_metadata': {},
          'user_metadata': {},
        },
      }),
    );
  }
}

TypeMatcher<RepositoryFailure> _failure(RepositoryFailureType type) =>
    isA<RepositoryFailure>().having(
      (value) => value.type,
      'failure type',
      type,
    );

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.client.dispose());

  test(
    'reports require current verified actor session and reject recovery before HTTP',
    () async {
      await expectLater(
        h.repository().sales(branchId: reportBranch, window: reportWindow),
        throwsA(_failure(RepositoryFailureType.unauthenticated)),
      );
      await h.signIn(verified: false);
      await expectLater(
        h.repository().inventory(branchId: reportBranch),
        throwsA(_failure(RepositoryFailureType.unauthenticated)),
      );
      await h.signIn(actor: reportOtherBranch);
      await expectLater(
        h.repository().expenses(branchId: reportBranch, window: reportWindow),
        throwsA(_failure(RepositoryFailureType.unauthenticated)),
      );
      await h.signIn();
      await expectLater(
        h
            .repository(recovery: () => true)
            .sales(branchId: reportBranch, window: reportWindow),
        throwsA(_failure(RepositoryFailureType.unauthenticated)),
      );
      expect(h.requests, isEmpty);
    },
  );

  test(
    'role preflights prevent cashier unscoped sales, stock and expenses, and staff financial reports',
    () async {
      await h.signIn();
      final cashier = h.repository(role: AppRole.cashier);
      await expectLater(
        cashier.sales(branchId: reportBranch, window: reportWindow),
        throwsA(_failure(RepositoryFailureType.permissionDenied)),
      );
      await expectLater(
        cashier.inventory(branchId: reportBranch),
        throwsA(_failure(RepositoryFailureType.permissionDenied)),
      );
      await expectLater(
        cashier.expenses(branchId: reportBranch, window: reportWindow),
        throwsA(_failure(RepositoryFailureType.permissionDenied)),
      );
      final staff = h.repository(role: AppRole.inventoryStaff);
      await expectLater(
        staff.sales(
          branchId: reportBranch,
          window: reportWindow,
          shiftId: reportShift,
        ),
        throwsA(_failure(RepositoryFailureType.permissionDenied)),
      );
      await expectLater(
        staff.expenses(branchId: reportBranch, window: reportWindow),
        throwsA(_failure(RepositoryFailureType.permissionDenied)),
      );
      expect(h.requests, isEmpty);
    },
  );

  test(
    'foreign branches malformed shifts paging and too long filters fail before HTTP',
    () async {
      await h.signIn();
      final repository = h.repository();
      await expectLater(
        repository.sales(branchId: reportOtherBranch, window: reportWindow),
        throwsA(_failure(RepositoryFailureType.permissionDenied)),
      );
      await expectLater(
        repository.sales(
          branchId: reportBranch,
          window: reportWindow,
          shiftId: 'invalid',
        ),
        throwsA(_failure(RepositoryFailureType.validation)),
      );
      await expectLater(
        repository.inventory(
          branchId: reportBranch,
          page: const PageRequest(limit: 101),
        ),
        throwsA(_failure(RepositoryFailureType.validation)),
      );
      await expectLater(
        repository.inventory(branchId: reportBranch, query: 'x' * 121),
        throwsA(_failure(RepositoryFailureType.validation)),
      );
      expect(h.requests, isEmpty);
    },
  );

  test(
    'sales sends explicit UTC branch window and operation shift, accepts cashier scoped result',
    () async {
      await h.signIn();
      h.handler = (request) async =>
          _Harness.response(salesReportWire(shift: reportShift));
      final report = await h
          .repository(role: AppRole.cashier)
          .sales(
            branchId: reportBranch.toUpperCase(),
            window: reportWindow,
            shiftId: reportShift.toUpperCase(),
          );
      expect(report.shiftId, reportShift);
      expect(h.requests.single.url.path, '/rest/v1/rpc/get_sales_report');
      expect(jsonDecode(h.requests.single.body), {
        'p_organization_id': reportOrg,
        'p_branch_id': reportBranch,
        'p_from': reportWindow.from.toIso8601String(),
        'p_to': reportWindow.to.toIso8601String(),
        'p_shift_id': reportShift,
      });
    },
  );

  test(
    'inventory uses exact normalized literal query and lookahead page contract',
    () async {
      await h.signIn();
      h.handler = (request) async => _Harness.response(
        inventoryReportWire(
          query: '%_\\ exact',
          offset: 20,
          limit: 21,
          empty: true,
        ),
      );
      final report = await h
          .repository(role: AppRole.inventoryStaff)
          .inventory(
            branchId: reportBranch,
            query: '  %_\\ exact  ',
            page: const PageRequest(offset: 20, limit: 20),
          );
      expect(report.items.offset, 20);
      expect(jsonDecode(h.requests.single.body), {
        'p_organization_id': reportOrg,
        'p_branch_id': reportBranch,
        'p_query': '%_\\ exact',
        'p_offset': 20,
        'p_limit': 21,
      });
    },
  );

  for (final role in [AppRole.owner, AppRole.admin, AppRole.manager]) {
    test(
      '${role.name} can read all three report kinds without an org aggregate',
      () async {
        await h.signIn();
        final repository = h.repository(role: role);
        expect(
          (await repository.sales(
            branchId: reportBranch,
            window: reportWindow,
          )).currencies.single.currency,
          'PHP',
        );
        expect(
          (await repository.inventory(
            branchId: reportBranch,
          )).items.items.single.quantity,
          -2,
        );
        expect(
          (await repository.expenses(
            branchId: reportBranch,
            window: reportWindow,
          )).currencies.single.totals.netExpenseMinor,
          -100,
        );
        expect(h.requests.length, 3);
        expect(
          h.requests.every(
            (request) =>
                (jsonDecode(request.body) as Map)['p_branch_id'] ==
                reportBranch,
          ),
          isTrue,
        );
        expect(repository.branchIds, {reportBranch});
        expect(() => repository.branchIds.clear(), throwsUnsupportedError);
      },
    );
  }

  test(
    'malformed foreign and nonposted server responses never render as valid snapshots',
    () async {
      await h.signIn();
      for (final payload in [
        <Object>[],
        {...salesReportWire(), 'branch_id': reportOtherBranch},
        {...salesReportWire(), 'source': 'offline_provisional'},
      ]) {
        h.handler = (request) async => _Harness.response(payload);
        await expectLater(
          h.repository().sales(branchId: reportBranch, window: reportWindow),
          throwsA(_failure(RepositoryFailureType.unavailable)),
        );
      }
    },
  );

  test(
    'server exact overflow gives actionable narrower range without exposing SQL detail',
    () async {
      await h.signIn();
      h.handler = (request) async => _Harness.response({
        'code': 'NX003',
        'message': 'PRIVATE SQL',
        'details': 'PRIVATE',
      }, status: 400);
      await expectLater(
        h.repository().sales(branchId: reportBranch, window: reportWindow),
        throwsA(
          _failure(RepositoryFailureType.validation).having(
            (value) => value.message,
            'message',
            allOf(contains('narrower'), isNot(contains('PRIVATE'))),
          ),
        ),
      );
    },
  );

  test(
    'server remains authoritative for foreign cashier shift ownership',
    () async {
      await h.signIn();
      h.handler = (request) async => _Harness.response({
        'code': '42501',
        'message': 'PRIVATE ownership',
      }, status: 403);
      await expectLater(
        h
            .repository(role: AppRole.cashier)
            .sales(
              branchId: reportBranch,
              window: reportWindow,
              shiftId: reportShift,
            ),
        throwsA(_failure(RepositoryFailureType.permissionDenied)),
      );
      expect(h.requests.length, 1);
    },
  );

  test(
    'response arriving after account change fails current identity check',
    () async {
      await h.signIn();
      final ready = Completer<void>();
      final response = Completer<http.Response>();
      h.handler = (request) {
        ready.complete();
        return response.future;
      };
      final result = h.repository().sales(
        branchId: reportBranch,
        window: reportWindow,
      );
      final assertion = expectLater(
        result,
        throwsA(_failure(RepositoryFailureType.unauthenticated)),
      );
      await ready.future;
      await h.signIn(actor: reportOtherBranch);
      response.complete(_Harness.response(salesReportWire()));
      await assertion;
    },
  );

  test(
    'response arriving after recovery activation fails current identity check',
    () async {
      await h.signIn();
      var recovery = false;
      final ready = Completer<void>();
      final response = Completer<http.Response>();
      h.handler = (request) {
        ready.complete();
        return response.future;
      };
      final result = h
          .repository(recovery: () => recovery)
          .expenses(branchId: reportBranch, window: reportWindow);
      final assertion = expectLater(
        result,
        throwsA(_failure(RepositoryFailureType.unauthenticated)),
      );
      await ready.future;
      recovery = true;
      response.complete(_Harness.response(expenseReportWire()));
      await assertion;
    },
  );
}
