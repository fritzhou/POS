import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/database/app_database.dart';
import 'package:nexapos/core/offline/offline_device_security.dart';
import 'package:nexapos/core/offline/offline_protocol.dart';
import 'package:nexapos/core/operations/native_operation_journal.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/checkout/data/checkout_decoders.dart';
import 'package:nexapos/features/offline/data/supabase_offline_workspace.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_workspace_test.dart' show MemorySecrets;

Map<String, Object?> object(Object? value) =>
    Map<String, Object?>.from(value as Map);

void main() {
  test(
    'actual PostgreSQL accepted receipt and multi-change deficit feed preserve frozen paid math',
    () async {
      final fixture = object(
        jsonDecode(
          File(
            'test/fixtures/offline_sql_signed_contract.json',
          ).readAsStringSync(),
        ),
      );
      final preparation = object(fixture['prepare']);
      final snapshot = object(preparation['snapshot']);
      final wire = object(preparation['grant']);
      final parsed = OfflineGrant.fromWire(wire);
      final scope = parsed.scope;
      final now = offlineUtc(preparation['server_time']);
      final verifier = OfflineGrantVerifier(
        issuer: parsed.claims['issuer'] as String,
        trustedKeys: {'test-key': fixture['public_test_key'] as String},
      );
      final grant = await verifier.verify(
        wire: wire,
        snapshot: snapshot,
        scope: scope,
        serverTime: now,
      );
      final store = MemorySecrets();
      final security = OfflineDeviceSecurity(store: store, clock: () => now);
      const seed =
          '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
      final seedBytes = [
        for (var i = 0; i < seed.length; i += 2)
          int.parse(seed.substring(i, i + 2), radix: 16),
      ];
      await store.write(
        'nexapos.offline.v1.identity.${scope.organizationId}.${scope.actorId}',
        strictCanonicalJson({
          'device_id': scope.deviceId,
          'organization_id': scope.organizationId,
          'actor_id': scope.actorId,
          'public_key': fixture['public_test_key'],
          'seed': encodeOfflineBytes(seedBytes),
        }),
      );
      await store.write(
        'nexapos.offline.v1.identity_index',
        strictCanonicalJson({'${scope.organizationId}.${scope.actorId}': true}),
      );
      await store.write('nexapos.offline.v1.active_actor', scope.actorId);
      await security.anchor(grant: grant, serverTime: now);
      await security.retainGrant(grant);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final databaseScope = DatabaseScope(
        organizationId: scope.organizationId,
        branchId: scope.branchId,
      );
      final cursor = snapshot['cursor'] as int;
      final changes = <OfflineCacheChange>[
        OfflineCacheChange(
          kind: 'context',
          id: scope.branchId,
          revision: cursor,
          deleted: false,
          value: object(snapshot['context']),
        ),
        OfflineCacheChange(
          kind: 'shift',
          id: scope.shiftId,
          revision: cursor,
          deleted: false,
          value: object(snapshot['shift']),
        ),
        for (final product in snapshot['products'] as List)
          OfflineCacheChange(
            kind: 'product',
            id: product['id'] as String,
            revision: cursor,
            deleted: false,
            value: object(product),
          ),
        for (final stock in snapshot['stock'] as List)
          OfflineCacheChange(
            kind: 'stock',
            id: stock['product_id'] as String,
            revision: cursor,
            deleted: false,
            value: object(stock),
          ),
      ];
      await db.persistOfflinePreparation(
        scope: databaseScope,
        actorId: scope.actorId,
        deviceId: scope.deviceId,
        grantId: grant.grantId,
        grantWire: wire,
        snapshot: snapshot,
        batch: OfflineCacheBatch(
          cursor: '$cursor',
          serverTime: now,
          changes: changes,
          completeSnapshot: true,
          grantId: grant.grantId,
        ),
        now: now,
      );
      final event = object(fixture['event']);
      final payload = object(event['payload']);
      final draft = SaleDraft(
        id: payload['id'] as String,
        eventId: event['event_id'] as String,
        scope: databaseScope,
        deviceId: scope.deviceId,
        shiftId: scope.shiftId,
        cashierId: scope.actorId,
        receiptNumber: payload['receipt_number'] as String,
        currency: payload['currency'] as String,
        createdAt: offlineUtc(event['occurred_at']),
        items: (payload['items'] as List)
            .map(
              (item) => SaleLineDraft(
                id: item['id'] as String,
                productId: item['product_id'] as String,
                sku: item['sku_snapshot'] as String,
                name: item['name_snapshot'] as String,
                quantity: item['quantity'] as int,
                unitPriceMinor: item['unit_price_minor'] as int,
                discountMinor: item['discount_minor'] as int,
                taxMinor: item['tax_minor'] as int,
              ),
            )
            .toList(),
        payments: (payload['payments'] as List)
            .map(
              (payment) => SalePaymentDraft(
                id: payment['id'] as String,
                method: payment['method'] as String,
                amountMinor: payment['amount_minor'] as int,
                reference: payment['reference'] as String?,
              ),
            )
            .toList(),
      );
      expect(draft.toEvent().digest, fixture['digest']);
      final authorization = object(fixture['authorization']);
      final shift = shiftFromRow(
        Map<String, dynamic>.from(object(snapshot['shift'])),
      );
      await db.persistAuthorizedSale(
        draft: draft,
        authorization: OfflineAuthorization(
          organizationId: scope.organizationId,
          branchId: scope.branchId,
          actorId: scope.actorId,
          deviceId: scope.deviceId,
          eventId: draft.eventId,
          grantId: grant.grantId,
          sequence: authorization['sequence'] as int,
          paymentEvidence: object(authorization['payment_evidence']),
          signature: fixture['signature'] as String,
        ),
        shift: OfflineShiftSnapshot(
          scope: databaseScope,
          id: shift.id,
          actorId: scope.actorId,
          deviceId: scope.deviceId,
          currency: shift.currency,
          openedAt: shift.openedAt,
          openingCashMinor: shift.openingCashMinor,
        ),
      );
      final client = SupabaseClient(
        parsed.claims['issuer'] as String,
        'public-unit-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final body = object(jsonDecode(request.body));
          final value = body['action'] == 'ingest'
              ? fixture['accepted']
              : fixture['pull'];
          return http.Response(
            jsonEncode(value),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      String encode(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      await client.auth.recoverSession(
        jsonEncode({
          'access_token':
              '${encode({'alg': 'HS256'})}.${encode({'sub': scope.actorId, 'exp': 4102444800})}.test',
          'refresh_token': 'unit-refresh',
          'token_type': 'bearer',
          'user': {
            'id': scope.actorId,
            'aud': 'authenticated',
            'email': 'actor@example.test',
            'email_confirmed_at': '2026-10-09T00:00:00Z',
            'created_at': '2026-10-09T00:00:00Z',
            'app_metadata': <String, Object?>{},
            'user_metadata': <String, Object?>{},
          },
        }),
      );
      final journal = NativeOperationJournal(
        executor: NativeDatabase.memory(),
        organizationId: scope.organizationId,
        actorId: scope.actorId,
      );
      addTearDown(journal.close);
      final workspace = SupabaseOfflineWorkspace(
        client: client,
        actor: AuthenticatedUser(
          userId: scope.actorId,
          email: 'actor@example.test',
          organizationId: scope.organizationId,
          membershipId: scope.membershipId,
          role: AppRole.fromDatabase(scope.role),
          branchIds: {scope.branchId},
          allBranches: false,
          businessName: grant.businessName,
        ),
        database: (_) async => db,
        security: security,
        verifier: verifier,
        journal: journal,
        clock: () => now,
      );
      await workspace.status(branchId: scope.branchId);
      final result = await workspace.synchronize(scope.branchId);
      expect(result.accepted, 1);
      expect(result.pulled, 4);
      expect(result.stoppedReason, isNull);
      final receipt = (await workspace.listReceipts(
        branchId: scope.branchId,
      )).single;
      expect(receipt.draft.totalMinor, 113);
      expect(receipt.reconciliationCode, 'STOCK_DEFICIT');
      final product = (await workspace.searchProducts()).items.single;
      expect(product.availableQuantity, -1);
      expect(product.priceMinor, 100);
      expect((await workspace.context()).taxBps, 1250);
      expect(
        object(
          jsonDecode(await workspace.exportReceipt(draft.eventId)),
        )['grant'],
        wire,
      );
    },
  );
}
