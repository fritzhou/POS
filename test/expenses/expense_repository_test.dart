import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexapos/core/auth/secure_session_storage.dart';
import 'package:nexapos/core/operations/native_operation_journal.dart';
import 'package:nexapos/core/operations/operation_journal.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/core/security/local_database_security.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';
import 'package:nexapos/features/expenses/data/expense_decoders.dart';
import 'package:nexapos/features/expenses/data/supabase_expense_repository.dart';
import 'package:nexapos/features/expenses/domain/expense_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'expense_fixtures.dart';

class _Store implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _Harness {
  _Harness({NativeOperationJournal? journal}) {
    this.journal =
        journal ??
        NativeOperationJournal(
          executor: NativeDatabase.memory(),
          organizationId: expenseOrg,
          actorId: expenseActor,
        );
    client = SupabaseClient(
      'https://project.example.test',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final reply = await handler(request);
        return http.Response.bytes(
          reply.bodyBytes,
          reply.statusCode,
          headers: reply.headers,
          request: request,
        );
      }),
    );
  }
  late final NativeOperationJournal journal;
  late final SupabaseClient client;
  final requests = <http.Request>[];
  Map<String, dynamic> result = expenseRecordAction();
  late Future<http.Response> Function(http.Request) handler = (_) async =>
      response(result);
  static http.Response response(Object value, {int status = 200}) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json'},
      );
  SupabaseExpenseRepository repository({
    AppRole role = AppRole.owner,
    bool recovery = false,
  }) => SupabaseExpenseRepository(
    client: client,
    actor: expenseMembership(role: role),
    journal: journal,
    isRecoverySession: () => recovery,
  );
  Future<void> signIn({String actor = expenseActor}) async {
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
          'email': 'owner@example.test',
          'email_confirmed_at': '2026-10-11T00:00:00Z',
          'created_at': '2026-10-11T00:00:00Z',
          'app_metadata': {},
          'user_metadata': {},
        },
      }),
    );
  }

  Future<void> close() async {
    await client.dispose();
    await journal.close();
  }
}

Matcher failure(RepositoryFailureType type) =>
    isA<RepositoryFailure>().having((e) => e.type, 'failure type', type);
void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.close());
  test(
    'verified role branch and recovery checks happen before preparing intent',
    () async {
      await expectLater(
        h.repository().recordExpense(expenseRequest()),
        throwsA(failure(RepositoryFailureType.unauthenticated)),
      );
      await h.signIn();
      for (final role in [AppRole.cashier, AppRole.inventoryStaff]) {
        await expectLater(
          h.repository(role: role).recordExpense(expenseRequest()),
          throwsA(failure(RepositoryFailureType.permissionDenied)),
        );
      }
      await expectLater(
        h.repository(recovery: true).recordExpense(expenseRequest()),
        throwsA(failure(RepositoryFailureType.unauthenticated)),
      );
      await expectLater(
        h.repository().loadContext(otherExpenseActor),
        throwsA(failure(RepositoryFailureType.permissionDenied)),
      );
      expect(h.requests, isEmpty);
      expect(await h.journal.pending(), isEmpty);
    },
  );
  test(
    'original UUID and attempt are durable before payment record RPC',
    () async {
      await h.signIn();
      h.handler = (request) async {
        final pending = (await h.journal.pending()).single;
        expect(pending.requestId, expenseRequestId);
        expect(pending.attemptCount, 1);
        expect(pending.payload, jsonDecode(request.body));
        expect(pending.payload['p_source'], 'external');
        expect(pending.payload['p_shift_id'], isNull);
        return _Harness.response(expenseRecordAction());
      };
      final record = await h
          .repository(role: AppRole.manager)
          .recordExpense(expenseRequest());
      expect(record.amountMinor, 12345);
      expect(await h.journal.pending(), isEmpty);
      expect(h.requests.single.url.path, '/rest/v1/rpc/record_expense');
    },
  );
  test(
    'uppercase input UUIDs normalize before dispatch and scope comparison',
    () async {
      await h.signIn();
      final base = expenseRequest();
      await h.repository().recordExpense(
        RecordExpenseRequest(
          requestId: expenseRequestId.toUpperCase(),
          branchId: expenseBranch.toUpperCase(),
          expectedSettingsRevision: 1,
          currency: 'PHP',
          amountMinor: base.amountMinor,
          category: base.category,
          paymentMethod: base.paymentMethod,
          source: base.source,
          manualConfirmed: true,
          payee: base.payee,
          reason: base.reason,
        ),
      );
      final params = jsonDecode(h.requests.single.body);
      expect(params['p_branch_id'], expenseBranch);
      expect(params['p_request_id'], expenseRequestId);
      h.result = expenseWire();
      expect(
        (await h.repository().getExpense(
          branchId: expenseBranch.toUpperCase(),
          expenseId: expenseId.toUpperCase(),
        )).id,
        expenseId,
      );
    },
  );
  test(
    'server context validates own actor and read pages validate scope and filters',
    () async {
      await h.signIn();
      h.result = expenseContextWire();
      expect(
        (await h.repository().loadContext(
          expenseBranch,
        )).ownOpenShift?.expectedCashMinor,
        -300,
      );
      h.result['own_open_shift']['actor_user_id'] = otherExpenseActor;
      await expectLater(
        h.repository().loadContext(expenseBranch),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      h.handler = (_) async => _Harness.response([expenseWire()]);
      final page = await h.repository().listExpenses(
        branchId: expenseBranch,
        page: const PageRequest(limit: 1),
      );
      expect(page.items.single.id, expenseId);
      expect(page.hasMore, isFalse);
      expect(jsonDecode(h.requests.last.body)['p_limit'], 2);
      h.handler = (_) async =>
          _Harness.response([expenseWire(), expenseWire()]);
      await expectLater(
        h.repository().listExpenses(branchId: expenseBranch),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      h.handler = (_) async =>
          _Harness.response([expenseWire()..['branch_id'] = otherExpenseActor]);
      await expectLater(
        h.repository().listExpenses(branchId: expenseBranch),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      h.handler = (_) async => _Harness.response([expenseWire()]);
      await expectLater(
        h.repository().listExpenses(
          branchId: expenseBranch,
          filter: const ExpenseFilter(category: ExpenseCategory.rent),
        ),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
    },
  );
  final corruptions = <String, void Function(Map<String, dynamic>)>{
    'foreign scope': (r) => r['expense']['organization_id'] = otherExpenseActor,
    'wrong actor': (r) => r['expense']['actor_user_id'] = otherExpenseActor,
    'wrong UUID': (r) => r['request_id'] = otherExpenseActor,
    'wrong amount': (r) => r['expense']['amount_minor'] = 1,
    'float amount': (r) => r['expense']['amount_minor'] = 12345.0,
    'unsafe amount': (r) =>
        r['expense']['amount_minor'] = maximumExactInteger + 1,
    'wrong currency': (r) => r['expense']['currency'] = 'USD',
    'different payee': (r) => r['expense']['payee'] = 'Other payee',
    'different source': (r) {
      r['expense']['source'] = 'cash_drawer';
      r['expense']['shift_id'] = expenseShift;
    },
    'wrong category': (r) => r['expense']['category'] = 'rent',
    'missing manual evidence': (r) => r['expense']['manual_confirmed'] = false,
    'later reversed detail in action': (r) =>
        r['expense'] = expenseWire(reversed: true),
    'unsupported action field': (r) => r['provider_success'] = true,
  };
  for (final entry in corruptions.entries) {
    test('${entry.key} cannot confirm a mutation', () async {
      await h.signIn();
      entry.value(h.result);
      await expectLater(
        h.repository().recordExpense(expenseRequest()),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      expect((await h.journal.pending()).single.requestId, expenseRequestId);
    });
  }
  test(
    'lost record response preserves same UUID and blocks replacement',
    () async {
      await h.signIn();
      h.handler = (_) async =>
          throw const SocketException('test lost response');
      await expectLater(
        h.repository().recordExpense(expenseRequest()),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      final pending = (await h.repository().pendingOperations()).single;
      await expectLater(
        h.repository().recordExpense(
          expenseRequest(requestId: otherExpenseActor),
        ),
        throwsA(failure(RepositoryFailureType.conflict)),
      );
      expect(h.requests, hasLength(1));
      h.handler = (_) async => _Harness.response(expenseRecordAction());
      final recovered = await h.repository().retryPending(pending);
      expect(recovered, isA<Expense>());
      expect(jsonDecode(h.requests[0].body), jsonDecode(h.requests[1].body));
      expect(await h.journal.pending(), isEmpty);
    },
  );
  test('same UUID cannot change an uncertain payment payload', () async {
    await h.signIn();
    h.handler = (_) async => throw const SocketException('test lost');
    await expectLater(
      h.repository().recordExpense(expenseRequest()),
      throwsA(failure(RepositoryFailureType.unavailable)),
    );
    final changed = RecordExpenseRequest(
      requestId: expenseRequestId,
      branchId: expenseBranch,
      expectedSettingsRevision: 1,
      currency: 'PHP',
      amountMinor: 1,
      category: ExpenseCategory.other,
      paymentMethod: CheckoutPaymentMethod.cash,
      source: ExpenseSource.external,
      manualConfirmed: true,
      reason: 'Changed payment',
    );
    await expectLater(
      h.repository().recordExpense(changed),
      throwsA(failure(RepositoryFailureType.unavailable)),
    );
    expect(h.requests, hasLength(1));
    expect((await h.journal.pending()).single.payload['p_amount_minor'], 12345);
  });
  test(
    'later denial after unknown success retains uncertain payment and attempt count',
    () async {
      await h.signIn();
      h.handler = (_) async => throw const SocketException('test lost');
      await expectLater(
        h.repository().recordExpense(expenseRequest()),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      final pending = (await h.journal.pending()).single;
      h.handler = (_) async => _Harness.response({
        'code': '42501',
        'message': 'PRIVATE denial detail',
      }, status: 403);
      await expectLater(
        h.repository().retryPending(pending),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      expect((await h.journal.pending()).single.attemptCount, 2);
    },
  );
  test(
    'definitive first rollback rejects while preserving immutable history',
    () async {
      await h.signIn();
      h.handler = (_) async => _Harness.response({
        'code': '40001',
        'message': 'PRIVATE settings revision',
      }, status: 409);
      await expectLater(
        h.repository().recordExpense(expenseRequest()),
        throwsA(failure(RepositoryFailureType.conflict)),
      );
      expect(await h.journal.pending(), isEmpty);
      final archived = await h.journal.prepare(
        requestId: expenseRequestId,
        type: 'record_expense',
        branchId: expenseBranch,
        payload: expenseRequest().parameters(expenseOrg),
      );
      expect(archived.status, LocalOperationStatus.rejected);
    },
  );
  test(
    'same branch uncertain checkout and close block drawer but external cash remains possible',
    () async {
      await h.signIn();
      for (final type in ['checkout_sale', 'close_shift']) {
        await h.journal.prepare(
          requestId: type == 'checkout_sale'
              ? otherExpenseActor
              : expenseReverseRequestId,
          type: type,
          branchId: expenseBranch,
          payload: {
            'p_request_id': type == 'checkout_sale'
                ? otherExpenseActor
                : expenseReverseRequestId,
          },
        );
      }
      expect(await h.repository().drawerBlockers(expenseBranch), hasLength(2));
      await expectLater(
        h.repository().recordExpense(expenseRequest(drawer: true)),
        throwsA(failure(RepositoryFailureType.conflict)),
      );
      expect(h.requests, isEmpty);
      await h.repository().recordExpense(expenseRequest());
      expect(h.requests, hasLength(1));
    },
  );
  test(
    'different branch uncertain checkout does not block own drawer record',
    () async {
      await h.signIn();
      await h.journal.prepare(
        requestId: otherExpenseActor,
        type: 'checkout_sale',
        branchId: otherExpenseActor,
        payload: {'p_request_id': otherExpenseActor},
      );
      h.result = expenseRecordAction(drawer: true);
      expect(
        (await h.repository().recordExpense(
          expenseRequest(drawer: true),
        )).shiftId,
        expenseShift,
      );
    },
  );
  test(
    'reversal keeps frozen original proof private and strips it from every RPC',
    () async {
      await h.signIn();
      h.handler = (request) async {
        final pending = (await h.journal.pending()).single;
        final proof = pending.payload['_nexapos_expense_original'] as Map;
        expect(proof['amount_minor'], 12345);
        expect(proof['reversal'], isNull);
        expect(() => proof['amount_minor'] = 1, throwsUnsupportedError);
        expect(
          jsonDecode(request.body).containsKey('_nexapos_expense_original'),
          isFalse,
        );
        throw const SocketException('test lost reversal');
      };
      await expectLater(
        h.repository().reverseExpense(expenseReverseRequest()),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      final pending = (await h.journal.pending()).single;
      h.handler = (_) async => _Harness.response(expenseReverseAction());
      final reversal =
          await h.repository().retryPending(pending) as ExpenseReversal;
      expect(reversal.amountMinor, 12345);
      expect(jsonDecode(h.requests[0].body), jsonDecode(h.requests[1].body));
      expect(await h.journal.pending(), isEmpty);
    },
  );
  test(
    'same UUID reversal cannot replace frozen original amount evidence',
    () async {
      await h.signIn();
      h.handler = (_) async => throw const SocketException('test lost');
      await expectLater(
        h.repository().reverseExpense(expenseReverseRequest()),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      final altered = expenseFromRow(expenseWire()..['amount_minor'] = 1);
      await expectLater(
        h.repository().reverseExpense(
          ReverseExpenseRequest(
            original: altered,
            requestId: expenseReverseRequestId,
            reason: 'Verified full correction',
            manualConfirmed: true,
          ),
        ),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      expect(h.requests, hasLength(1));
    },
  );
  for (final field in [
    'amount_minor',
    'currency',
    'source',
    'shift_id',
    'expense_id',
    'actor_user_id',
  ]) {
    test(
      'contradictory reversal $field keeps original payment pending',
      () async {
        await h.signIn();
        h.result = expenseReverseAction(drawer: true);
        h.result['reversal'][field] = switch (field) {
          'amount_minor' => 1,
          'currency' => 'USD',
          'source' => 'external',
          _ => otherExpenseActor,
        };
        await expectLater(
          h.repository().reverseExpense(expenseReverseRequest(drawer: true)),
          throwsA(failure(RepositoryFailureType.unavailable)),
        );
        expect((await h.journal.pending()).single.type, 'reverse_expense');
      },
    );
  }
  test('foreign original drawer actor cannot create new reversal', () async {
    await h.signIn();
    final original = expenseFromRow(
      expenseWire(drawer: true)..['actor_user_id'] = otherExpenseActor,
    );
    await expectLater(
      h.repository().reverseExpense(
        ReverseExpenseRequest(
          original: original,
          reason: 'Return confirmed',
          manualConfirmed: true,
        ),
      ),
      throwsA(failure(RepositoryFailureType.permissionDenied)),
    );
    expect(h.requests, isEmpty);
    expect(await h.journal.pending(), isEmpty);
  });
  test(
    'late success after actor change remains pending and exposes no original record',
    () async {
      await h.signIn();
      final dispatched = Completer<void>();
      final reply = Completer<http.Response>();
      h.handler = (_) async {
        dispatched.complete();
        return reply.future;
      };
      final assertion = expectLater(
        h.repository().recordExpense(expenseRequest()),
        throwsA(failure(RepositoryFailureType.unauthenticated)),
      );
      await dispatched.future;
      await h.signIn(actor: otherExpenseActor);
      reply.complete(_Harness.response(expenseRecordAction()));
      await assertion;
      expect(await h.journal.pending(), hasLength(1));
    },
  );
  test(
    'physical encrypted journal close reopen retries original reversal exactly',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nexapos-expense-journal-',
      );
      final file = File('${directory.path}/operations.sqlite');
      final factory = EncryptedDatabaseFactory(store: _Store());
      final first = _Harness(
        journal: NativeOperationJournal(
          executor: await factory.open(file),
          organizationId: expenseOrg,
          actorId: expenseActor,
        ),
      );
      await first.signIn();
      first.handler = (_) async =>
          throw const SocketException('test process lost');
      await expectLater(
        first.repository().reverseExpense(expenseReverseRequest(drawer: true)),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      final saved = (await first.journal.pending()).single;
      final originalBody = first.requests.single.body;
      await first.close();
      expect(
        latin1
            .decode(await file.readAsBytes())
            .contains('Verified full correction'),
        isFalse,
      );
      expect(
        latin1.decode(await file.readAsBytes()).startsWith('SQLite format 3'),
        isFalse,
      );
      final second = _Harness(
        journal: NativeOperationJournal(
          executor: await factory.open(file),
          organizationId: expenseOrg,
          actorId: expenseActor,
        ),
      );
      try {
        await second.signIn();
        second.result = expenseReverseAction(drawer: true);
        final reopened = (await second.repository().pendingOperations()).single;
        expect(reopened.payload, saved.payload);
        expect(reopened.attemptCount, 1);
        final reversal =
            await second.repository().retryPending(reopened) as ExpenseReversal;
        expect(reversal.shiftId, expenseShift);
        expect(
          jsonDecode(second.requests.single.body),
          jsonDecode(originalBody),
        );
        expect(await second.journal.pending(), isEmpty);
      } finally {
        await second.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
