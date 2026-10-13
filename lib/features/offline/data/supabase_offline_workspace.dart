import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/database/app_database.dart';
import '../../../core/offline/offline_device_security.dart';
import '../../../core/offline/offline_protocol.dart';
import '../../../core/operations/operation_journal.dart';
import '../../../core/security/app_role.dart';
import '../../../core/sync/sync_event.dart';
import '../../catalog/domain/repository_support.dart';
import '../../checkout/data/checkout_decoders.dart';
import '../../checkout/domain/checkout_models.dart';
import '../domain/offline_workspace.dart';
import 'offline_edge_adapter.dart';

typedef OfflineDatabaseResolver = Future<AppDatabase> Function(DatabaseScope);

/// A device-grant locator for the separate offline page. Its actor describes
/// signed issuance-time authority; it must never open the normal online shell.
class OfflineResumeDescriptor {
  const OfflineResumeDescriptor({
    required this.actor,
    required this.branchId,
    required this.label,
  });
  final AuthenticatedUser actor;
  final String branchId;
  final String label;
}

/// A separate, explicit device workspace. Its journal preserves paid tender
/// intents even when grant validation or SQLite capture cannot complete.
class SupabaseOfflineWorkspace implements OfflineWorkspace {
  static Future<List<OfflineResumeDescriptor>> resumeDescriptors({
    required AuthIdentity identity,
    required OfflineDeviceSecurity security,
    required OfflineGrantVerifier verifier,
    required OfflineDatabaseResolver database,
  }) async {
    if (!identity.emailVerified || verifier.trustedKeys.isEmpty) {
      return const [];
    }
    offlineUuid(identity.userId);
    final results = <OfflineResumeDescriptor>[];
    for (final locator in await security.retainedScopes(
      actorId: identity.userId,
    )) {
      try {
        final scope = locator.scope;
        final device = await security.restore(
          organizationId: scope.organizationId,
          actorId: identity.userId,
        );
        if (device == null || device.deviceId != scope.deviceId) continue;
        final databaseScope = DatabaseScope(
          organizationId: scope.organizationId,
          branchId: scope.branchId,
        );
        final db = await database(databaseScope);
        final row = await db.readOfflinePreparation(
          scope: databaseScope,
          actorId: identity.userId,
          deviceId: device.deviceId,
        );
        if (row == null || row.id != locator.grantId) continue;
        final snapshot = _object(jsonDecode(row.snapshotJson));
        final grant = await verifier.verify(
          wire: _object(jsonDecode(row.grantJson)),
          snapshot: snapshot,
          scope: scope,
          serverTime: locator.issuedAt,
        );
        if (canonicalHash(grant.toWire()) != canonicalHash(locator.toWire())) {
          continue;
        }
        final cache = await db.readOfflineCacheState(
          scope: databaseScope,
          actorId: identity.userId,
          deviceId: device.deviceId,
        );
        if (cache?.completeSnapshot != true ||
            cache?.grantId != grant.grantId) {
          continue;
        }
        // Expired/released grants may show preserved payments, but clock
        // rollback and missing keys/anchors never unlock even read-only resume.
        await security.estimatedTime(grant);
        final context = contextFromRow(
          Map<String, dynamic>.from(_object(snapshot['context'])),
        );
        results.add(
          OfflineResumeDescriptor(
            actor: AuthenticatedUser(
              userId: identity.userId,
              email: identity.email,
              organizationId: scope.organizationId,
              membershipId: scope.membershipId,
              role: AppRole.fromDatabase(scope.role),
              branchIds: {scope.branchId},
              allBranches: false,
              businessName: grant.businessName,
            ),
            branchId: scope.branchId,
            label: '${grant.businessName} · ${context.branchName}',
          ),
        );
      } on Object {
        // Corrupt or foreign locators convey no authorization. Other valid
        // independently verified scopes can still be presented explicitly.
      }
    }
    results.sort((a, b) => a.label.compareTo(b.label));
    return List.unmodifiable(results);
  }

  SupabaseOfflineWorkspace({
    required SupabaseClient client,
    required this.actor,
    required this.database,
    required this.security,
    required this.verifier,
    required this.journal,
    bool Function()? isRecoverySession,
    bool Function()? isExplicitlySignedOut,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _isRecoverySession = isRecoverySession,
       _isExplicitlySignedOut = isExplicitlySignedOut {
    _edge = OfflineEdgeAdapter(
      client: client,
      actor: actor,
      isRecoverySession: isRecoverySession,
      isExplicitlySignedOut: () =>
          _suspended || isExplicitlySignedOut?.call() == true,
      onAuthorizationDenied: suspend,
    );
  }

  final AuthenticatedUser actor;
  final OfflineDatabaseResolver database;
  final OfflineDeviceSecurity security;
  final OfflineGrantVerifier verifier;
  final OperationJournal journal;
  late final OfflineEdgeAdapter _edge;
  final DateTime Function() _clock;
  final bool Function()? _isRecoverySession, _isExplicitlySignedOut;
  String? _branchId;
  bool _active = false, _suspended = false;
  Future<void> _serial = Future.value();

  bool get _configured => verifier.trustedKeys.isNotEmpty;
  DatabaseScope _scope(String branchId) =>
      DatabaseScope(organizationId: actor.organizationId, branchId: branchId);

  void _requireLocalIdentity() {
    final session = _edge.client.auth.currentSession;
    if (_isExplicitlySignedOut?.call() == true ||
        _isRecoverySession?.call() == true ||
        (session == null && _isExplicitlySignedOut == null) ||
        (session != null && session.user.id != actor.userId)) {
      _deny('Unlock your authorized device workspace to continue.');
    }
  }

  void _requireUnlockedOnlineIdentity() {
    _requireLocalIdentity();
    if (_suspended) {
      _deny(
        'Online device authorization was denied. Review preserved payments before preparing again.',
      );
    }
    _edge.requireOnlineIdentity();
  }

  void _requireBranch(String branchId) {
    validateId(branchId);
    if (!actor.branchIds.contains(branchId)) {
      _deny('Choose an authorized branch.');
    }
  }

  Never _deny(String message) =>
      throw RepositoryFailure(RepositoryFailureType.permissionDenied, message);

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _serial.then((_) => operation());
    _serial = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<_Prepared?> _prepared(String branchId) async {
    _requireLocalIdentity();
    _requireBranch(branchId);
    final device = await security.restore(
      organizationId: actor.organizationId,
      actorId: actor.userId,
    );
    final retained = await security.restoreGrant(
      organizationId: actor.organizationId,
      actorId: actor.userId,
      branchId: branchId,
    );
    final deviceId = retained?.scope.deviceId ?? device?.deviceId;
    if (deviceId == null) return null;
    final db = await database(_scope(branchId));
    final row = await db.readOfflinePreparation(
      scope: _scope(branchId),
      actorId: actor.userId,
      deviceId: deviceId,
    );
    if (row == null) return null;
    final wire = _object(jsonDecode(row.grantJson));
    final snapshot = _object(jsonDecode(row.snapshotJson));
    final parsed = OfflineGrant.fromWire(wire);
    final expected = OfflineScope(
      organizationId: actor.organizationId,
      branchId: branchId,
      actorId: actor.userId,
      membershipId: parsed.scope.membershipId,
      deviceId: deviceId,
      shiftId: parsed.scope.shiftId,
      role: parsed.scope.role,
    );
    // Reverify immutable issuance bytes even for history after expiry. This is
    // signature validation, not a current-time authorization to sell.
    final grant = await verifier.verify(
      wire: wire,
      snapshot: snapshot,
      scope: expected,
      serverTime: parsed.issuedAt,
    );
    final cache = await db.readOfflineCacheState(
      scope: _scope(branchId),
      actorId: actor.userId,
      deviceId: deviceId,
    );
    final release = await db.readOfflineGrantRelease(
      scope: _scope(branchId),
      actorId: actor.userId,
      deviceId: deviceId,
      grantId: grant.grantId,
    );
    _requireLocalIdentity();
    return _Prepared(
      db,
      deviceId,
      grant,
      snapshot,
      row.preparedAt,
      cache,
      release != null,
    );
  }

  void _requireCurrentGrantAuthority(OfflineGrant grant) {
    if (grant.scope.membershipId != actor.membershipId ||
        grant.scope.role != actor.role.name) {
      _deny(
        'Current membership changed. Preserve and synchronize original payments before preparing new authority.',
      );
    }
  }

  @override
  Future<OfflineWorkspaceStatus> status({String? branchId}) async {
    _requireLocalIdentity();
    var selected = branchId ?? _branchId;
    if (selected == null && _configured) {
      for (final candidate in actor.branchIds.toList()..sort()) {
        if (await _prepared(candidate) != null) {
          selected = candidate;
          break;
        }
      }
    }
    if (selected == null || !_configured) {
      return OfflineWorkspaceStatus(
        configured: _configured,
        active: false,
        pendingCount: 0,
        failedCount: 0,
        blockedReason: _configured
            ? null
            : 'Offline signing keys are not configured.',
      );
    }
    _branchId = selected;
    final prepared = await _prepared(selected);
    final intents = await pendingPaymentIntents(branchId: selected);
    if (prepared == null) {
      return OfflineWorkspaceStatus(
        configured: true,
        active: false,
        pendingCount: 0,
        failedCount: 0,
        branchId: selected,
        unresolvedPaymentCount: intents.length,
      );
    }
    final rows = await prepared.db.listActorDeviceOutbox(
      scope: _scope(selected),
      actorId: actor.userId,
      deviceId: prepared.deviceId,
    );
    String? blocked;
    DateTime? estimatedServerTime;
    try {
      estimatedServerTime = await security.estimatedTime(prepared.grant);
      await security.authorize(
        grant: prepared.grant,
        scope: prepared.grant.scope,
      );
    } on OfflineSecurityException catch (failure) {
      blocked = failure.code == 'EXPIRED_GRANT'
          ? 'Offline authorization expired. Preserved receipts can still be synchronized.'
          : 'Device authorization needs online preparation before new sales.';
    }
    if (prepared.released) blocked = 'This offline grant has been released.';
    if (prepared.grant.scope.membershipId != actor.membershipId ||
        prepared.grant.scope.role != actor.role.name) {
      blocked =
          'Current membership changed. Original payments remain available for review and synchronization.';
    }
    if (!prepared.cacheComplete) {
      blocked = 'The complete verified cache is unavailable.';
    }
    final totals = await prepared.db.grantCapturedTotal(
      scope: _scope(selected),
      actorId: actor.userId,
      deviceId: prepared.deviceId,
      grantId: prepared.grant.grantId,
    );
    final sequence = await prepared.db.nextOfflineSequence(
      scope: _scope(selected),
      actorId: actor.userId,
      deviceId: prepared.deviceId,
      grantId: prepared.grant.grantId,
    );
    return OfflineWorkspaceStatus(
      configured: true,
      active: _active && blocked == null,
      branchId: selected,
      branchName: prepared.context.branchName,
      grantId: prepared.grant.grantId,
      expiresAt: prepared.grant.expiresAt,
      lastServerTime: prepared.cache?.serverTime,
      estimatedServerTime: estimatedServerTime,
      snapshotAt: prepared.preparedAt,
      lastSyncAt: prepared.cache?.observedAt,
      pendingCount: rows
          .where((row) => row.status == 'PENDING' || row.status == 'SYNCING')
          .length,
      failedCount: rows.where((row) => row.status == 'FAILED').length,
      unresolvedPaymentCount: intents.length,
      eventCount: sequence - 1,
      totalMinor: totals,
      maxEvents: prepared.grant.maxEvents,
      maxTotalMinor: prepared.grant.maxTotalMinor,
      released: prepared.released,
      blockedReason: blocked,
    );
  }

  @override
  Future<OfflineWorkspaceStatus> prepareOnline(
    String branchId,
  ) => _serialized(() async {
    _requireUnlockedOnlineIdentity();
    _requireBranch(branchId);
    _edge.requireOnlineIdentity();
    if (!_configured) _deny('Configure trusted offline signing keys first.');
    final existing = await _prepared(branchId);
    if (existing != null && !existing.released) {
      for (final pending in await journal.pending(
        type: 'offline_prepare',
        branchId: branchId,
      )) {
        if (pending.payload['device_id'] == existing.deviceId) {
          await journal.confirm(
            requestId: pending.requestId,
            result: {'grant_id': existing.grant.grantId},
          );
        }
      }
      _branchId = branchId;
      return status(branchId: branchId);
    }
    if ((await journal.pending(type: 'checkout_sale')).isNotEmpty) {
      _deny(
        'Resolve uncertain online checkouts before preparing offline sales.',
      );
    }
    if ((await pendingPaymentIntents(branchId: branchId)).isNotEmpty) {
      _deny(
        'Review the preserved payment intent before preparing another grant.',
      );
    }
    _requireUnlockedOnlineIdentity();
    final device = await security.enable(
      organizationId: actor.organizationId,
      actorId: actor.userId,
      explicitConsent: true,
    );
    try {
      _requireUnlockedOnlineIdentity();
    } on Object {
      await security.lock();
      rethrow;
    }
    final pending = await journal.pending(
      type: 'offline_prepare',
      branchId: branchId,
    );
    final requestId = pending.isEmpty ? newLocalId() : pending.first.requestId;
    await journal.prepare(
      requestId: requestId,
      type: 'offline_prepare',
      branchId: branchId,
      payload: {'device_id': device.deviceId},
    );
    _requireUnlockedOnlineIdentity();
    final challengeResponse = await _edge.call(
      action: 'enroll_challenge',
      branchId: branchId,
      deviceId: device.deviceId,
      values: {
        'public_key': device.publicKey,
        'device_name': Platform.localHostname.length > 100
            ? Platform.localHostname.substring(0, 100)
            : Platform.localHostname,
        'platform': Platform.operatingSystem,
      },
    );
    final challenge = _object(challengeResponse['challenge']);
    final signature = await security.signEnrollment(challenge);
    await _edge.call(
      action: 'enroll',
      branchId: branchId,
      deviceId: device.deviceId,
      values: {
        'challenge_id': offlineUuid(challenge['challenge_id']),
        'signature': signature,
      },
    );
    _requireUnlockedOnlineIdentity();
    await journal.markAttempted(requestId: requestId);
    final Map<String, Object?> response;
    try {
      response = await _edge.call(
        action: 'prepare',
        branchId: branchId,
        deviceId: device.deviceId,
        values: {'request_id': requestId},
      );
    } on OfflinePreparationExpired {
      await journal.reject(
        requestId: requestId,
        failureCode: 'offline_preparation_expired',
      );
      throw const RepositoryFailure(
        RepositoryFailureType.conflict,
        'The server confirmed this expired preparation never authorized sales. Prepare again online with a new request.',
      );
    }
    final wire = _object(response['grant']);
    final snapshot = _object(response['snapshot']);
    final parsed = OfflineGrant.fromWire(wire);
    final serverTime = offlineUtc(response['server_time']);
    final scope = OfflineScope(
      organizationId: actor.organizationId,
      branchId: branchId,
      actorId: actor.userId,
      membershipId: actor.membershipId,
      deviceId: device.deviceId,
      shiftId: parsed.scope.shiftId,
      role: actor.role.name,
    );
    final grant = await verifier.verify(
      wire: wire,
      snapshot: snapshot,
      scope: scope,
      serverTime: serverTime,
      allowExpired: true,
    );
    final db = await database(_scope(branchId));
    _requireUnlockedOnlineIdentity();
    await db.persistOfflinePreparation(
      scope: _scope(branchId),
      actorId: actor.userId,
      deviceId: device.deviceId,
      grantId: grant.grantId,
      grantWire: wire,
      snapshot: snapshot,
      batch: _snapshotBatch(snapshot, grant, serverTime),
      now: _clock().toUtc(),
    );
    _requireUnlockedOnlineIdentity();
    if (serverTime.isBefore(grant.expiresAt)) {
      await security.anchor(grant: grant, serverTime: serverTime);
    }
    await security.retainGrant(grant);
    _requireUnlockedOnlineIdentity();
    await journal.confirm(
      requestId: requestId,
      result: {'grant_id': grant.grantId},
    );
    _edge.requireOnlineIdentity();
    _branchId = branchId;
    _active = false;
    return status(branchId: branchId);
  });

  @override
  Future<OfflineWorkspaceStatus> enterOffline(String branchId) async {
    _requireLocalIdentity();
    if (_suspended) {
      _deny(
        'Online device authorization was denied. Preserved payments remain available for review.',
      );
    }
    if ((await journal.pending(type: 'checkout_sale')).isNotEmpty) {
      _deny(
        'Resolve uncertain online checkout requests before entering offline mode.',
      );
    }
    final prepared = await _prepared(branchId);
    if (prepared == null || !prepared.cacheComplete || prepared.released) {
      _deny('Prepare a complete verified offline workspace online first.');
    }
    _requireCurrentGrantAuthority(prepared.grant);
    await security.authorize(
      grant: prepared.grant,
      scope: prepared.grant.scope,
    );
    _branchId = branchId;
    _active = true;
    return status(branchId: branchId);
  }

  @override
  Future<void> leaveOffline() async {
    _active = false;
  }

  Future<_Prepared> _selected() async {
    _requireLocalIdentity();
    final branch = _branchId;
    if (branch == null) _deny('Choose a prepared offline workspace.');
    final prepared = await _prepared(branch);
    if (prepared == null) {
      _deny('The verified offline snapshot is unavailable.');
    }
    return prepared;
  }

  @override
  Future<PosContext> context() async => (await _selected()).context;

  @override
  Future<Shift?> currentShift() async => (await _selected()).shift;

  @override
  Future<List<OfflineCategory>> categories() async {
    final prepared = await _selected();
    return _objects(prepared.snapshot['categories'])
        .where((row) => row['active'] != false)
        .map(
          (row) => OfflineCategory(
            id: offlineUuid(row['id']),
            name: row['name'] as String,
          ),
        )
        .toList(growable: false);
  }

  Future<List<PosProduct>> _products(_Prepared prepared) async {
    final result = <PosProduct>[];
    for (final row in _objects(prepared.snapshot['products'])) {
      if (row['active'] == false) continue;
      final id = offlineUuid(row['id']);
      final available = await prepared.db.projectedQuantity(
        scope: _scope(prepared.grant.scope.branchId),
        actorId: actor.userId,
        deviceId: prepared.deviceId,
        productId: id,
      );
      if (available == null) continue;
      result.add(_product(row, available));
    }
    return result
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Future<DataPage<PosProduct>> searchProducts({
    String query = '',
    String? categoryId,
    PageRequest page = const PageRequest(),
  }) async {
    page.validate();
    if (query.length > 120) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Use a shorter search.',
      );
    }
    final prepared = await _selected();
    final lower = query.trim().toLowerCase();
    final products = (await _products(prepared))
        .where(
          (product) =>
              (categoryId == null || categoryId == product.categoryId) &&
              (lower.isEmpty ||
                  product.name.toLowerCase().contains(lower) ||
                  product.sku.toLowerCase().contains(lower) ||
                  (product.barcode?.toLowerCase().contains(lower) ?? false)),
        )
        .skip(page.offset)
        .take(page.limit + 1)
        .toList();
    return DataPage(
      items: products.take(page.limit).toList(),
      hasMore: products.length > page.limit,
      offset: page.offset,
    );
  }

  @override
  Future<PosProduct?> lookupProductByBarcode(String barcode) async {
    if (barcode.trim().isEmpty || barcode.length > 120) return null;
    for (final product in await _products(await _selected())) {
      if (product.barcode == barcode.trim()) return product;
    }
    return null;
  }

  List<CartLine> _intentLines(Map<String, Object?> payload) =>
      _objects(payload['lines'])
          .map(
            (line) => CartLine(
              product: _product(
                _object(line['product']),
                _integer(
                  _object(line['product'])['available_quantity'],
                  signed: true,
                ),
              ),
              quantity: _integer(line['quantity']),
            ),
          )
          .toList();

  CheckoutPayment _intentPayment(Map<String, Object?> payment) =>
      CheckoutPayment(
        method: paymentMethodFrom(payment['method']),
        amountMinor: _integer(payment['amount_minor']),
        tenderedMinor: payment['tendered_minor'] as int?,
        reference: payment['reference'] as String?,
        manualConfirmed: payment['manual_confirmed'] == true,
      );

  @override
  Future<void> recordPaymentFragment({
    required String requestId,
    required List<CartLine> lines,
    required int index,
    required CheckoutPayment payment,
  }) {
    final frozenLines = List<CartLine>.unmodifiable(lines);
    return _serialized(
      () => _recordPaymentFragment(
        requestId: requestId,
        lines: frozenLines,
        index: index,
        payment: payment,
      ),
    );
  }

  Future<void> _recordPaymentFragment({
    required String requestId,
    required List<CartLine> lines,
    required int index,
    required CheckoutPayment payment,
  }) async {
    final prepared = await _selected();
    requestId = offlineUuid(requestId);
    offlineInteger(index, min: 0, max: 4);
    final branch = prepared.grant.scope.branchId;
    final base = _intentPayload(
      OfflineCheckoutRequest(
        requestId: requestId,
        lines: lines,
        payments: const [],
      ),
      prepared,
    );
    base.remove('payments');
    final total = CartTotals.calculate(
      lines: lines,
      taxBps: prepared.grant.taxBps,
    ).totalMinor;
    final paymentValues = payment.validatedValues();
    if (total <= 0 || payment.amountMinor <= 0 || payment.amountMinor > total) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Payment must fit the original order total.',
      );
    }
    final all = await _pendingTenderFragments(branch);
    final own =
        all.where((row) => row.payload['request_id'] == requestId).toList()
          ..sort(
            (a, b) => _integer(
              a.payload['index'],
            ).compareTo(_integer(b.payload['index'])),
          );
    final id = const Uuid().v5(requestId, 'tender:$index');
    final existing = own.where((row) => row.requestId == id).firstOrNull;
    if (existing != null) {
      if (canonicalHash(existing.payload['order']) != canonicalHash(base) ||
          canonicalHash(existing.payload['payment']) !=
              canonicalHash(paymentValues) ||
          existing.payload['total_minor'] != total) {
        throw const RepositoryFailure(
          RepositoryFailureType.conflict,
          'This payment index already has different evidence. Keep its original amount and reference.',
        );
      }
    } else {
      if (all.any((row) => row.payload['request_id'] != requestId) ||
          (await journal.pending(
            type: 'offline_payment_intent',
            branchId: branch,
          )).any((row) => row.requestId != requestId)) {
        _deny(
          'Resolve the preserved payment intent before recording another sale.',
        );
      }
      if (index != own.length ||
          own.any(
            (row) => canonicalHash(row.payload['order']) != canonicalHash(base),
          )) {
        throw const RepositoryFailure(
          RepositoryFailureType.conflict,
          'Resume the original order and next payment index.',
        );
      }
      final applied = own.fold<int>(
        0,
        (sum, row) =>
            sum + _integer(_object(row.payload['payment'])['amount_minor']),
      );
      if (applied + payment.amountMinor > total) {
        throw const RepositoryFailure(
          RepositoryFailureType.validation,
          'Saved payment allocations cannot exceed the original total.',
        );
      }
      // Confirmed physical tender is immutable before key/expiry checks. If
      // authorization is lost after the dialog opened, money evidence survives
      // as a review record; it never becomes permission for an expired sale.
      await journal.prepare(
        requestId: id,
        type: 'offline_payment_fragment',
        branchId: branch,
        payload: {
          'request_id': requestId,
          'index': index,
          'order': base,
          'total_minor': total,
          'payment': paymentValues,
          'operator_confirmed_at': _clock().toUtc().toIso8601String(),
        },
      );
    }
    final saved = (await journal.pending(
      type: 'offline_payment_fragment',
      branchId: branch,
    )).singleWhere((row) => row.requestId == id);
    final proofId = const Uuid().v5(requestId, 'tender-proof:$index');
    final proofs = await journal.pending(
      type: 'offline_tender_proof',
      branchId: branch,
    );
    final proof = proofs.where((row) => row.requestId == proofId).firstOrNull;
    final digest = canonicalHash(saved.payload);
    if (proof != null) {
      await _verifyTenderProof(saved, proof);
      return;
    }
    if (!_active ||
        _suspended ||
        !prepared.cacheComplete ||
        prepared.released) {
      _deny(
        'The confirmed payment evidence is preserved. Unlock valid offline authorization before continuing; do not collect it again.',
      );
    }
    _requireCurrentGrantAuthority(prepared.grant);
    final sequence = await prepared.db.nextOfflineSequence(
      scope: _scope(branch),
      actorId: actor.userId,
      deviceId: prepared.deviceId,
      grantId: prepared.grant.grantId,
    );
    final captured = await prepared.db.grantCapturedTotal(
      scope: _scope(branch),
      actorId: actor.userId,
      deviceId: prepared.deviceId,
      grantId: prepared.grant.grantId,
    );
    if (sequence > prepared.grant.maxEvents ||
        BigInt.from(captured) + BigInt.from(total) >
            BigInt.from(prepared.grant.maxTotalMinor)) {
      _deny(
        'The preserved payment exceeds this grant allowance and needs review. Do not collect it again.',
      );
    }
    final actual = {
      for (final product in await _products(prepared)) product.id: product,
    };
    for (final line in lines) {
      final product = actual[line.product.id];
      if (product == null ||
          product.revision != line.product.revision ||
          product.priceMinor != line.product.priceMinor ||
          product.currency != line.product.currency ||
          product.organizationId != line.product.organizationId ||
          line.quantity > product.availableQuantity) {
        throw const RepositoryFailure(
          RepositoryFailureType.conflict,
          'The original order no longer matches this prepared catalog. Confirmed payment evidence is preserved for review.',
        );
      }
    }
    final signature = await security.signTenderFragment(
      grant: prepared.grant,
      fragmentDigest: digest,
      requestId: requestId,
      index: index,
    );
    final device = await security.restore(
      organizationId: actor.organizationId,
      actorId: actor.userId,
    );
    if (device == null || device.deviceId != prepared.deviceId || _suspended) {
      _deny(
        'Payment evidence is preserved; device authorization was interrupted.',
      );
    }
    await journal.prepare(
      requestId: proofId,
      type: 'offline_tender_proof',
      branchId: branch,
      payload: {
        'request_id': requestId,
        'index': index,
        'grant_id': prepared.grant.grantId,
        'fragment_digest': digest,
        'public_key': device.publicKey,
        'signature': signature,
      },
    );
  }

  Future<void> _verifyTenderProof(
    PendingOperation fragment,
    PendingOperation proof,
  ) async {
    final order = _object(fragment.payload['order']);
    if (proof.payload['fragment_digest'] != canonicalHash(fragment.payload) ||
        proof.payload['request_id'] != fragment.payload['request_id'] ||
        proof.payload['index'] != fragment.payload['index'] ||
        proof.payload['grant_id'] != order['grant_id']) {
      throw const OfflineStorageConflict();
    }
    final valid = await Ed25519().verify(
      utf8.encode(
        offlineTenderDomain +
            strictCanonicalJson({
              'fragment_digest': proof.payload['fragment_digest'],
              'request_id': proof.payload['request_id'],
              'grant_id': proof.payload['grant_id'],
              'index': proof.payload['index'],
            }),
      ),
      signature: Signature(
        decodeOfflineBytes(proof.payload['signature'] as String, length: 64),
        publicKey: SimplePublicKey(
          decodeOfflineBytes(proof.payload['public_key'] as String, length: 32),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) throw const OfflineStorageConflict();
  }

  Future<List<PendingOperation>> _pendingTenderFragments(String? branch) async {
    final fragments = await journal.pending(
      type: 'offline_payment_fragment',
      branchId: branch,
    );
    final seals = await journal.pending(
      type: 'offline_tender_finalization',
      branchId: branch,
    );
    final finalized = <String>{};
    for (final seal in seals) {
      final requestId = offlineUuid(seal.payload['request_id']);
      if (seal.requestId != const Uuid().v5(requestId, 'tender-finalization')) {
        throw const OfflineStorageConflict();
      }
      final deviceId = offlineUuid(seal.payload['device_id']);
      final db = await database(_scope(seal.branchId));
      final event = await db.readAuthorizedEvent(
        scope: _scope(seal.branchId),
        actorId: actor.userId,
        deviceId: deviceId,
        eventId: requestId,
      );
      if (event == null ||
          event.event.digest != seal.payload['event_digest'] ||
          _object(jsonDecode(event.event.payloadJson))['id'] !=
              seal.payload['document_id']) {
        throw const OfflineStorageConflict();
      }
      finalized.add(requestId);
    }
    return fragments
        .where(
          (fragment) => !finalized.contains(fragment.payload['request_id']),
        )
        .toList();
  }

  Future<void> _confirmTenderFragments(
    String requestId,
    String branch,
    String documentId,
  ) async {
    final fragments = (await journal.pending(
      type: 'offline_payment_fragment',
      branchId: branch,
    )).where((row) => row.payload['request_id'] == requestId);
    if (fragments.isEmpty) return;
    final prepared = await _prepared(branch);
    if (prepared == null) throw const OfflineStorageConflict();
    final event = await prepared.db.readAuthorizedEvent(
      scope: _scope(branch),
      actorId: actor.userId,
      deviceId: prepared.deviceId,
      eventId: requestId,
    );
    if (event == null) throw const OfflineStorageConflict();
    // A single immutable seal closes the fragment set. Confirming individual
    // rows could crash halfway and make the remaining indexes unreadable.
    // Evidence/proofs remain append-only and available in the journal.
    await journal.prepare(
      requestId: const Uuid().v5(requestId, 'tender-finalization'),
      type: 'offline_tender_finalization',
      branchId: branch,
      payload: {
        'request_id': requestId,
        'document_id': documentId,
        'device_id': prepared.deviceId,
        'event_digest': event.event.digest,
      },
    );
  }

  @override
  Future<LocalOfflineReceipt> checkout(
    OfflineCheckoutRequest request,
  ) => _serialized(() async {
    final prepared = await _selected();
    final branch = prepared.grant.scope.branchId;
    final requestId = offlineUuid(request.requestId);
    final existing = await prepared.db.readAuthorizedEvent(
      scope: _scope(branch),
      actorId: actor.userId,
      deviceId: prepared.deviceId,
      eventId: requestId,
    );
    if (existing != null) {
      final receipt = await _receipt(prepared, existing);
      _validateExisting(request, receipt, existing.authorization);
      await journal.confirm(
        requestId: requestId,
        result: {'event_id': requestId, 'document_id': receipt.draft.id},
      );
      await _confirmTenderFragments(requestId, branch, receipt.draft.id);
      return receipt;
    }
    final priorIntents = await pendingPaymentIntents(branchId: branch);
    final fragments = await _pendingTenderFragments(branch);
    final ownFragments =
        fragments
            .where((row) => row.payload['request_id'] == requestId)
            .toList()
          ..sort(
            (a, b) => _integer(
              a.payload['index'],
            ).compareTo(_integer(b.payload['index'])),
          );
    if (ownFragments.isNotEmpty) {
      final frozen = priorIntents.singleWhere(
        (intent) => intent.requestId == requestId,
      );
      final currentOrder = _intentPayload(request, prepared)
        ..remove('payments');
      if (ownFragments.any(
            (fragment) =>
                canonicalHash(fragment.payload['order']) !=
                canonicalHash(currentOrder),
          ) ||
          frozen.partial ||
          canonicalHash(_intentPayload(frozen, prepared)) !=
              canonicalHash(_intentPayload(request, prepared))) {
        throw const RepositoryFailure(
          RepositoryFailureType.conflict,
          'Finalize the exact preserved payment fragments and original order.',
        );
      }
      final proofs = await journal.pending(
        type: 'offline_tender_proof',
        branchId: branch,
      );
      for (final fragment in ownFragments) {
        final proofId = const Uuid().v5(
          requestId,
          'tender-proof:${fragment.payload['index']}',
        );
        var proof = proofs.where((row) => row.requestId == proofId).firstOrNull;
        if (proof == null) {
          // Recover the exact already-confirmed evidence, without asking for
          // money again. The same current grant/key/clock checks still apply.
          await _recordPaymentFragment(
            requestId: requestId,
            lines: request.lines,
            index: _integer(fragment.payload['index']),
            payment: _intentPayment(_object(fragment.payload['payment'])),
          );
          proof = (await journal.pending(
            type: 'offline_tender_proof',
            branchId: branch,
          )).singleWhere((row) => row.requestId == proofId);
        }
        await _verifyTenderProof(fragment, proof);
      }
    }
    final payload = _intentPayload(request, prepared);
    // Freeze the operator-confirmed physical tender before another clock/grant
    // check. A later failure cannot imply that the collected money vanished.
    await journal.prepare(
      requestId: requestId,
      type: 'offline_payment_intent',
      branchId: branch,
      payload: payload,
    );
    if (priorIntents.any((intent) => intent.requestId != requestId)) {
      _deny(
        'Resolve the preserved payment intent before recording another sale.',
      );
    }
    if (!_active) {
      _deny('Enter the prepared offline workspace explicitly before selling.');
    }
    if (!prepared.cacheComplete || prepared.released) {
      _deny('This offline grant cannot capture new sales.');
    }
    _requireCurrentGrantAuthority(prepared.grant);
    final observed = await security.authorize(
      grant: prepared.grant,
      scope: prepared.grant.scope,
    );
    final actualProducts = {
      for (final product in await _products(prepared)) product.id: product,
    };
    final lines = <CartLine>[];
    for (final line in request.lines) {
      final actual = actualProducts[line.product.id];
      if (actual == null ||
          actual.priceMinor != line.product.priceMinor ||
          actual.revision != line.product.revision ||
          actual.currency != line.product.currency ||
          line.product.organizationId != actor.organizationId) {
        throw const RepositoryFailure(
          RepositoryFailureType.conflict,
          'Use the original prepared catalog prices for offline checkout.',
        );
      }
      lines.add(CartLine(product: actual, quantity: line.quantity));
    }
    final totals = CartTotals.calculate(
      lines: lines,
      taxBps: prepared.grant.taxBps,
    );
    if (request.payments.isEmpty || request.payments.length > 5) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Choose one to five payments.',
      );
    }
    final payments = <SalePaymentDraft>[];
    final evidence = <String, Object?>{};
    var paid = BigInt.zero;
    for (var index = 0; index < request.payments.length; index++) {
      final payment = request.payments[index];
      final values = payment.validatedValues();
      final id = const Uuid().v5(requestId, 'payment:$index');
      payments.add(
        SalePaymentDraft(
          id: id,
          method: payment.method.name,
          amountMinor: payment.amountMinor,
          reference: values['reference'] as String?,
        ),
      );
      evidence[id] = payment.method == CheckoutPaymentMethod.cash
          ? {'tendered_minor': payment.tenderedMinor}
          : {'manual_confirmed': true};
      paid += BigInt.from(payment.amountMinor);
    }
    if (paid != BigInt.from(totals.totalMinor)) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Payment allocations must equal the original sale total.',
      );
    }
    final sequence = await prepared.db.nextOfflineSequence(
      scope: _scope(branch),
      actorId: actor.userId,
      deviceId: prepared.deviceId,
      grantId: prepared.grant.grantId,
    );
    final draft = SaleDraft(
      id: const Uuid().v5(requestId, 'sale'),
      eventId: requestId,
      scope: _scope(branch),
      deviceId: prepared.deviceId,
      shiftId: prepared.grant.scope.shiftId,
      cashierId: actor.userId,
      receiptNumber:
          'OFF-${prepared.deviceId.substring(0, 8)}-${prepared.grant.grantId.substring(0, 8)}-${sequence.toString().padLeft(4, '0')}',
      currency: prepared.grant.currency,
      createdAt: observed,
      items: totals.lines
          .map(
            (line) => SaleLineDraft(
              id: const Uuid().v5(requestId, 'line:${line.line.product.id}'),
              productId: line.line.product.id,
              sku: line.line.product.sku,
              name: line.line.product.name,
              quantity: line.line.quantity,
              unitPriceMinor: line.line.product.priceMinor,
              taxMinor: line.taxMinor,
            ),
          )
          .toList(),
      payments: payments,
    );
    draft.validate();
    final signature = await security.signEvent(
      grant: prepared.grant,
      eventDigest: draft.toEvent().digest,
      sequence: sequence,
      paymentEvidence: evidence,
    );
    final authorization = OfflineAuthorization(
      organizationId: actor.organizationId,
      branchId: branch,
      actorId: actor.userId,
      deviceId: prepared.deviceId,
      eventId: requestId,
      grantId: prepared.grant.grantId,
      sequence: sequence,
      paymentEvidence: evidence,
      signature: signature,
    );
    _requireLocalIdentity();
    if (_suspended) {
      _deny(
        'Device authorization was denied. The payment intent remains preserved.',
      );
    }
    await prepared.db.persistAuthorizedSale(
      draft: draft,
      authorization: authorization,
      shift: OfflineShiftSnapshot(
        scope: _scope(branch),
        id: prepared.shift.id,
        actorId: actor.userId,
        deviceId: prepared.deviceId,
        currency: prepared.shift.currency,
        openedAt: prepared.shift.openedAt,
        openingCashMinor: prepared.shift.openingCashMinor,
      ),
      maxEvents: prepared.grant.maxEvents,
      maxTotalMinor: prepared.grant.maxTotalMinor,
    );
    final saved = await prepared.db.readAuthorizedEvent(
      scope: _scope(branch),
      actorId: actor.userId,
      deviceId: prepared.deviceId,
      eventId: requestId,
    );
    if (saved == null) {
      throw const RepositoryFailure(
        RepositoryFailureType.unavailable,
        'The local receipt could not be confirmed. Retain and retry the same payment intent.',
      );
    }
    final receipt = await _receipt(prepared, saved);
    await journal.confirm(
      requestId: requestId,
      result: {'event_id': requestId, 'document_id': draft.id},
    );
    await _confirmTenderFragments(requestId, branch, draft.id);
    _requireLocalIdentity();
    return receipt;
  });

  Map<String, dynamic> _intentPayload(
    OfflineCheckoutRequest request,
    _Prepared prepared,
  ) => {
    'grant_id': prepared.grant.grantId,
    'device_id': prepared.deviceId,
    'shift_id': prepared.grant.scope.shiftId,
    'currency': prepared.grant.currency,
    'tax_bps': prepared.grant.taxBps,
    'settings_revision': prepared.grant.settingsRevision,
    'lines': request.lines
        .map(
          (line) => {
            'product': _productJson(line.product),
            'quantity': line.quantity,
          },
        )
        .toList(),
    'payments': request.payments
        .map((payment) => payment.validatedValues())
        .toList(),
  };

  @override
  Future<List<OfflineCheckoutRequest>> pendingPaymentIntents({
    String? branchId,
  }) async {
    _requireLocalIdentity();
    final rows = await journal.pending(
      type: 'offline_payment_intent',
      branchId: branchId ?? _branchId,
    );
    final result = <String, OfflineCheckoutRequest>{
      for (final row in rows)
        row.requestId: OfflineCheckoutRequest(
          requestId: row.requestId,
          lines: _intentLines(row.payload),
          payments: _objects(
            row.payload['payments'],
          ).map(_intentPayment).toList(),
        ),
    };
    final fragments = await _pendingTenderFragments(branchId ?? _branchId);
    final grouped = <String, List<PendingOperation>>{};
    for (final row in fragments) {
      final id = offlineUuid(row.payload['request_id']);
      (grouped[id] ??= []).add(row);
    }
    for (final entry in grouped.entries) {
      final group = entry.value
        ..sort(
          (a, b) => _integer(
            a.payload['index'],
          ).compareTo(_integer(b.payload['index'])),
        );
      final order = _object(group.first.payload['order']);
      final total = _integer(group.first.payload['total_minor']);
      final payments = <CheckoutPayment>[];
      for (var index = 0; index < group.length; index++) {
        final row = group[index];
        if (index > 4 ||
            row.payload['index'] != index ||
            row.requestId != const Uuid().v5(entry.key, 'tender:$index') ||
            row.payload['total_minor'] != total ||
            canonicalHash(row.payload['order']) != canonicalHash(order)) {
          throw const OfflineStorageConflict();
        }
        final payment = _intentPayment(_object(row.payload['payment']));
        payment.validatedValues();
        payments.add(payment);
      }
      final recovered = OfflineCheckoutRequest(
        requestId: entry.key,
        lines: _intentLines(order),
        payments: payments,
        expectedTotalMinor: total,
      );
      if (payments.fold<int>(0, (sum, payment) => sum + payment.amountMinor) >
          total) {
        throw const OfflineStorageConflict();
      }
      final complete = result[entry.key];
      if (complete != null &&
          (canonicalHash(
                    complete.payments.map((p) => p.validatedValues()).toList(),
                  ) !=
                  canonicalHash(
                    payments.map((p) => p.validatedValues()).toList(),
                  ) ||
              canonicalHash(
                    complete.lines
                        .map(
                          (l) => {
                            'product': _productJson(l.product),
                            'quantity': l.quantity,
                          },
                        )
                        .toList(),
                  ) !=
                  canonicalHash(order['lines']))) {
        throw const OfflineStorageConflict();
      }
      result[entry.key] = recovered;
    }
    return result.values.toList(growable: false);
  }

  @override
  Future<List<LocalOfflineReceipt>> listReceipts({String? branchId}) async {
    final branch = branchId ?? _branchId;
    if (branch == null) return const [];
    final prepared = await _prepared(branch);
    if (prepared == null) return const [];
    final rows = await prepared.db.listActorDeviceOutbox(
      scope: _scope(branch),
      actorId: actor.userId,
      deviceId: prepared.deviceId,
    );
    final receipts = <LocalOfflineReceipt>[];
    for (final row in rows.reversed) {
      final event = await prepared.db.readAuthorizedEvent(
        scope: _scope(branch),
        actorId: actor.userId,
        deviceId: prepared.deviceId,
        eventId: row.id,
      );
      if (event != null) {
        receipts.add(
          await _receipt(prepared, event, failureCode: row.lastError),
        );
      }
    }
    return receipts;
  }

  Future<LocalOfflineReceipt> _receipt(
    _Prepared prepared,
    AuthorizedOutboxEvent authorized, {
    String? failureCode,
  }) async {
    final original = await _originalPreparation(prepared, authorized);
    final event = authorized.event;
    final payload = _object(jsonDecode(event.payloadJson));
    final draft = SaleDraft(
      id: payload['id'] as String,
      eventId: event.eventId,
      scope: _scope(event.branchId),
      deviceId: event.deviceId,
      shiftId: payload['shift_id'] as String,
      cashierId: event.actorId,
      receiptNumber: payload['receipt_number'] as String,
      currency: payload['currency'] as String,
      createdAt: event.occurredAt,
      customerId: payload['customer_id'] as String?,
      items: _objects(payload['items'])
          .map(
            (item) => SaleLineDraft(
              id: item['id'] as String,
              productId: item['product_id'] as String,
              sku: item['sku_snapshot'] as String,
              name: item['name_snapshot'] as String,
              quantity: _integer(item['quantity']),
              unitPriceMinor: _integer(item['unit_price_minor']),
              discountMinor: _integer(item['discount_minor']),
              taxMinor: _integer(item['tax_minor']),
            ),
          )
          .toList(),
      payments: _objects(payload['payments'])
          .map(
            (payment) => SalePaymentDraft(
              id: payment['id'] as String,
              method: payment['method'] as String,
              amountMinor: _integer(payment['amount_minor']),
              reference: payment['reference'] as String?,
            ),
          )
          .toList(),
    );
    draft.validate();
    if (draft.toEvent().digest != event.digest) {
      throw const OfflineStorageConflict();
    }
    final acceptance = await prepared.db.readOfflineAcceptance(
      scope: _scope(event.branchId),
      actorId: actor.userId,
      deviceId: event.deviceId,
      eventId: event.eventId,
    );
    return LocalOfflineReceipt(
      draft: draft,
      status: OutboxStatus.values.firstWhere(
        (status) => status.storageValue == authorized.status,
      ),
      sequence: authorized.authorization.sequence,
      grantId: authorized.authorization.grantId,
      serverReceiptId: acceptance?.serverReceiptId,
      acceptedAt: acceptance == null
          ? null
          : offlineUtc(acceptance.acceptedAtIso),
      failureCode: failureCode,
      reconciliationCode: acceptance?.reconciliationCode,
      businessName: original.grant.businessName,
      branchName: original.context.branchName,
    );
  }

  Future<_Prepared> _originalPreparation(
    _Prepared selected,
    AuthorizedOutboxEvent authorized,
  ) async {
    final event = authorized.event;
    if (authorized.authorization.grantId == selected.grant.grantId) {
      return selected;
    }
    final row = await selected.db.readOfflinePreparation(
      scope: _scope(event.branchId),
      actorId: actor.userId,
      deviceId: event.deviceId,
      grantId: authorized.authorization.grantId,
    );
    if (row == null) throw const OfflineStorageConflict();
    final wire = _object(jsonDecode(row.grantJson));
    final parsed = OfflineGrant.fromWire(wire);
    if (parsed.scope.organizationId != actor.organizationId ||
        parsed.scope.actorId != actor.userId ||
        parsed.scope.branchId != event.branchId ||
        parsed.scope.deviceId != event.deviceId) {
      throw const OfflineStorageConflict();
    }
    final snapshot = _object(jsonDecode(row.snapshotJson));
    final verified = await verifier.verify(
      wire: wire,
      snapshot: snapshot,
      scope: parsed.scope,
      serverTime: parsed.issuedAt,
    );
    return _Prepared(
      selected.db,
      event.deviceId,
      verified,
      snapshot,
      row.preparedAt,
      selected.cache,
      true,
    );
  }

  @override
  Future<String> exportReceipt(String eventId) async {
    final prepared = await _selected();
    final authorized = await prepared.db.readAuthorizedEvent(
      scope: _scope(prepared.grant.scope.branchId),
      actorId: actor.userId,
      deviceId: prepared.deviceId,
      eventId: eventId,
    );
    if (authorized == null) {
      final intents = await journal.pending(
        type: 'offline_payment_intent',
        branchId: prepared.grant.scope.branchId,
      );
      for (final intent in intents) {
        if (intent.requestId == eventId) {
          return strictCanonicalJson({
            'status': 'unresolved_payment_intent',
            'request_id': eventId,
            'intent': intent.payload,
          });
        }
      }
      final fragments = (await journal.pending(
        type: 'offline_payment_fragment',
        branchId: prepared.grant.scope.branchId,
      )).where((row) => row.payload['request_id'] == eventId).toList();
      if (fragments.isNotEmpty) {
        final proofs = (await journal.pending(
          type: 'offline_tender_proof',
          branchId: prepared.grant.scope.branchId,
        )).where((row) => row.payload['request_id'] == eventId).toList();
        return strictCanonicalJson({
          'status': 'unresolved_payment_fragments',
          'request_id': eventId,
          'fragments': fragments.map((row) => row.payload).toList(),
          'proofs': proofs.map((row) => row.payload).toList(),
          'grant': prepared.grant.toWire(),
          'snapshot': prepared.snapshot,
        });
      }
      throw const RepositoryFailure(
        RepositoryFailureType.notFound,
        'The preserved receipt was not found.',
      );
    }
    final original = await _originalPreparation(prepared, authorized);
    return strictCanonicalJson({
      'event': _eventWire(authorized.event),
      'digest': authorized.event.digest,
      'authorization': authorized.authorization.toJson(),
      'signature': authorized.authorization.signature,
      'grant': original.grant.toWire(),
      'snapshot': original.snapshot,
    });
  }

  @override
  Future<OfflineSyncSummary> synchronize(
    String branchId,
  ) => _serialized(() async {
    _edge.requireOnlineIdentity();
    final prepared = await _prepared(branchId);
    if (prepared == null) {
      _deny('Prepare this device workspace before synchronizing.');
    }
    var accepted = 0, failed = 0, pulled = 0;
    String? stopped;
    final worker = newLocalId();
    for (var count = 0; count < 100; count++) {
      _edge.requireOnlineIdentity();
      final lease = await prepared.db.claimNextAuthorizedEvent(
        scope: _scope(branchId),
        actorId: actor.userId,
        deviceId: prepared.deviceId,
        workerId: worker,
        now: _clock().toUtc(),
      );
      if (lease == null) break;
      try {
        final authorized = await prepared.db.loadAuthorizedEvent(lease);
        if (authorized == null) {
          throw const FormatException('Missing signed event');
        }
        final response = await _edge.call(
          action: 'ingest',
          branchId: branchId,
          deviceId: prepared.deviceId,
          values: {
            'event': _eventWire(authorized.event),
            'digest': authorized.event.digest,
            'authorization': authorized.authorization.toJson(),
            'signature': authorized.authorization.signature,
          },
        );
        _validateResponseScope(response, authorized, prepared.deviceId);
        if (response['status'] != 'accepted') {
          if (response['status'] != 'review' &&
              response['status'] != 'conflict') {
            throw const FormatException('Unknown ingest status');
          }
          await prepared.db.failEvent(
            lease,
            code: SyncFailureCode.conflict,
            now: _clock().toUtc(),
          );
          failed++;
          stopped =
              'A paid offline receipt requires server review. Its original record is preserved.';
          break;
        }
        final receiptJson = _object(response['receipt']);
        final receipt = receiptFromRow(Map<String, dynamic>.from(receiptJson));
        final original = await _receipt(prepared, authorized);
        _validateServerReceipt(
          receipt,
          original.draft,
          authorized.authorization,
          (await _originalPreparation(prepared, authorized)).grant,
        );
        final receiptId = offlineUuid(response['server_receipt_id']);
        if (receipt.id != receiptId) {
          throw const FormatException('Receipt link mismatch');
        }
        final impacts = _objects(response['stock_impacts'])
            .map(
              (impact) => OfflineStockImpact(
                productId: offlineUuid(impact['product_id']),
                revision: _integer(impact['revision']),
              ),
            )
            .toList();
        final products = original.draft.items
            .map((item) => item.productId)
            .toSet();
        if (impacts.length != products.length ||
            impacts.map((impact) => impact.productId).toSet().length !=
                products.length ||
            impacts.any((impact) => !products.contains(impact.productId))) {
          throw const FormatException('Incomplete stock acknowledgment');
        }
        _edge.requireOnlineIdentity();
        await prepared.db.recordAcceptance(
          lease: lease,
          acceptance: ServerAcceptance(
            eventId: authorized.event.eventId,
            digest: authorized.event.digest,
            serverReceiptId: receiptId,
            acceptedAt: offlineUtc(response['accepted_at']),
          ),
          actorId: actor.userId,
          deviceId: prepared.deviceId,
          grantId: authorized.authorization.grantId,
          sequence: authorized.authorization.sequence,
          documentId: authorized.documentId,
          receipt: receiptJson,
          stockImpacts: impacts,
          reconciliationCode: _reconciliation(response['reconciliation_code']),
          now: _clock().toUtc(),
        );
        accepted++;
      } on Object catch (error) {
        final failure = _syncFailure(error);
        try {
          await prepared.db.failEvent(
            lease,
            code: failure,
            now: _clock().toUtc(),
          );
        } on LostOutboxLease {
          /* A new lease owns this preserved event. */
        }
        stopped = failure == SyncFailureCode.unauthorized
            ? 'Online authorization was denied. Original offline payments are preserved.'
            : failure == SyncFailureCode.conflict ||
                  failure == SyncFailureCode.invalidEvent
            ? 'A paid offline receipt needs review. Its original record is preserved.'
            : 'Synchronization could not be confirmed. Retry the same preserved events.';
        if (failure == SyncFailureCode.conflict ||
            failure == SyncFailureCode.invalidEvent ||
            failure == SyncFailureCode.unauthorized) {
          failed++;
        }
        break;
      }
    }
    if (stopped == null) {
      try {
        pulled = await _pull(prepared, branchId);
      } on Object {
        stopped =
            'Sales remain preserved. The latest catalog and stock pull could not be confirmed.';
      }
    }
    final remaining = await prepared.db.actorDeviceUnsyncedCount(
      scope: _scope(branchId),
      actorId: actor.userId,
      deviceId: prepared.deviceId,
    );
    _requireLocalIdentity();
    return OfflineSyncSummary(
      accepted: accepted,
      failed: failed,
      remaining: remaining,
      pulled: pulled,
      stoppedReason: stopped,
    );
  });

  Future<int> _pull(_Prepared prepared, String branchId) async {
    var pulled = 0;
    for (var page = 0; page < 20; page++) {
      final state = await prepared.db.readOfflineCacheState(
        scope: _scope(branchId),
        actorId: actor.userId,
        deviceId: prepared.deviceId,
      );
      if (state == null) throw const FormatException('Missing cache cursor');
      final cursor = int.parse(state.cursor);
      final response = await _edge.call(
        action: 'pull',
        branchId: branchId,
        deviceId: prepared.deviceId,
        values: {'cursor': cursor, 'limit': 100},
      );
      final next = _integer(response['cursor']);
      final changes = _objects(response['changes'])
          .map(
            (row) => OfflineCacheChange(
              kind: row['kind'] as String,
              id: row['id'] as String,
              revision: _integer(row['revision']),
              deleted: row['deleted'] as bool,
              value: row['value'] == null ? null : _object(row['value']),
            ),
          )
          .toList();
      if (next < cursor ||
          changes.length > 100 ||
          response['has_more'] is! bool ||
          (response['has_more'] == true && next <= cursor)) {
        throw const FormatException('Invalid pull continuation');
      }
      for (final change in changes) {
        _validateCacheChange(change, prepared);
      }
      var previousRevision = cursor;
      final latestChanges = <String, OfflineCacheChange>{};
      for (final change in changes) {
        if (change.revision <= previousRevision || change.revision > next) {
          throw const FormatException('Invalid pull revision ordering');
        }
        previousRevision = change.revision;
        // The feed may contain multiple changes for one product in a page.
        // Keep its last observation after validating every ordered feed entry.
        latestChanges['${change.kind}\u0000${change.id}'] = change;
      }
      _edge.requireOnlineIdentity();
      await prepared.db.applyOfflinePullBatch(
        scope: _scope(branchId),
        actorId: actor.userId,
        deviceId: prepared.deviceId,
        batch: OfflineCacheBatch(
          cursor: '$next',
          serverTime: offlineUtc(response['server_time']),
          changes: latestChanges.values.toList(growable: false),
          hasMore: response['has_more'] as bool,
        ),
        now: _clock().toUtc(),
        expectedCursor: state.cursor,
      );
      pulled += changes.length;
      if (response['has_more'] == false) break;
    }
    return pulled;
  }

  @override
  Future<bool> retryFailed({
    required String branchId,
    required String eventId,
  }) async {
    _edge.requireOnlineIdentity();
    final prepared = await _prepared(branchId);
    if (prepared == null) return false;
    final event = await prepared.db.readAuthorizedEvent(
      scope: _scope(branchId),
      actorId: actor.userId,
      deviceId: prepared.deviceId,
      eventId: eventId,
    );
    if (event == null) return false;
    return prepared.db.retryFailedEvent(
      scope: _scope(branchId),
      eventId: eventId,
      now: _clock().toUtc(),
    );
  }

  @override
  Future<OfflineWorkspaceStatus> releaseGrant(
    String branchId,
  ) => _serialized(() async {
    _edge.requireOnlineIdentity();
    final prepared = await _prepared(branchId);
    if (prepared == null) _deny('No prepared grant is available.');
    if (prepared.released) return status(branchId: branchId);
    final signingDevice = await security.restore(
      organizationId: actor.organizationId,
      actorId: actor.userId,
    );
    if (signingDevice == null || signingDevice.deviceId != prepared.deviceId) {
      _deny(
        'This device signing key was removed. Original sales can still synchronize; an administrator must review the grant before shift closure.',
      );
    }
    final unsynced = await prepared.db.actorDeviceUnsyncedCount(
      scope: _scope(branchId),
      actorId: actor.userId,
      deviceId: prepared.deviceId,
    );
    if (unsynced != 0 ||
        (await pendingPaymentIntents(branchId: branchId)).isNotEmpty) {
      _deny(
        'Resolve all preserved sales and payment intents before releasing this grant.',
      );
    }
    final finalSequence =
        (await prepared.db.nextOfflineSequence(
          scope: _scope(branchId),
          actorId: actor.userId,
          deviceId: prepared.deviceId,
          grantId: prepared.grant.grantId,
        )) -
        1;
    final signature = await security.signRelease(
      grantId: prepared.grant.grantId,
      finalSequence: finalSequence,
    );
    final response = await _edge.call(
      action: 'release',
      branchId: branchId,
      deviceId: prepared.deviceId,
      values: {
        'grant_id': prepared.grant.grantId,
        'final_sequence': finalSequence,
        'signature': signature,
      },
    );
    if (response['status'] != 'released' ||
        response['grant_id'] != prepared.grant.grantId ||
        response['final_sequence'] != finalSequence ||
        response['organization_id'] != actor.organizationId ||
        response['branch_id'] != branchId ||
        response['actor_id'] != actor.userId ||
        response['device_id'] != prepared.deviceId) {
      throw const RepositoryFailure(
        RepositoryFailureType.unavailable,
        'Grant release could not be confirmed. Retry the same release proof.',
      );
    }
    _edge.requireOnlineIdentity();
    await prepared.db.recordOfflineRelease(
      scope: _scope(branchId),
      actorId: actor.userId,
      deviceId: prepared.deviceId,
      grantId: prepared.grant.grantId,
      finalSequence: finalSequence,
      now: _clock().toUtc(),
    );
    await security.markReleased(prepared.grant.grantId);
    _active = false;
    return status(branchId: branchId);
  });

  @override
  Future<void> suspend() async {
    _suspended = true;
    _active = false;
    await security.lock();
  }
}

class _Prepared {
  const _Prepared(
    this.db,
    this.deviceId,
    this.grant,
    this.snapshot,
    this.preparedAt,
    this.cache,
    this.released,
  );
  final AppDatabase db;
  final String deviceId;
  final OfflineGrant grant;
  final Map<String, Object?> snapshot;
  final DateTime preparedAt;
  final OfflineCacheStateRow? cache;
  final bool released;
  bool get cacheComplete =>
      cache?.completeSnapshot == true && cache?.grantId == grant.grantId;
  PosContext get context =>
      contextFromRow(Map<String, dynamic>.from(_object(snapshot['context'])));
  Shift get shift =>
      shiftFromRow(Map<String, dynamic>.from(_object(snapshot['shift'])));
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('Expected offline object');
  final result = Map<String, Object?>.from(value);
  strictCanonicalJson(result);
  return result;
}

List<Map<String, Object?>> _objects(Object? value) {
  if (value is! List) throw const FormatException('Expected offline list');
  return value.map(_object).toList(growable: false);
}

int _integer(Object? value, {bool signed = false}) => offlineInteger(
  value,
  min: signed ? -maximumExactInteger : 0,
  max: maximumExactInteger,
);

PosProduct _product(Map<String, Object?> row, int quantity) => PosProduct(
  id: offlineUuid(row['id']),
  organizationId: offlineUuid(row['organization_id']),
  name: row['name'] as String,
  sku: row['sku'] as String,
  priceMinor: _integer(row['price_minor']),
  currency: validatePosCurrency(row['currency'] as String),
  unit: row['unit'] as String,
  revision: _integer(row['revision']),
  availableQuantity: quantity,
  categoryId: row['category_id'] as String?,
  barcode: row['barcode'] as String?,
  active: row['active'] != false,
);
Map<String, Object?> _productJson(PosProduct product) => {
  'id': product.id,
  'organization_id': product.organizationId,
  'name': product.name,
  'sku': product.sku,
  'price_minor': product.priceMinor,
  'currency': product.currency,
  'unit': product.unit,
  'revision': product.revision,
  'available_quantity': product.availableQuantity,
  'category_id': product.categoryId,
  'barcode': product.barcode,
  'active': product.active,
};
Map<String, Object?> _eventWire(SyncEvent event) => {
  'event_id': event.eventId,
  'organization_id': event.organizationId,
  'branch_id': event.branchId,
  'device_id': event.deviceId,
  'actor_id': event.actorId,
  'event_type': event.eventType,
  'occurred_at': event.occurredAtIso,
  'schema_version': event.schemaVersion,
  'payload': _object(jsonDecode(event.payloadJson)),
};

OfflineCacheBatch _snapshotBatch(
  Map<String, Object?> snapshot,
  OfflineGrant grant,
  DateTime serverTime,
) {
  final snapshotCursor = _integer(snapshot['cursor']);
  final changes = <OfflineCacheChange>[
    OfflineCacheChange(
      kind: 'context',
      id: grant.scope.branchId,
      revision: snapshotCursor,
      deleted: false,
      value: _object(snapshot['context']),
    ),
    OfflineCacheChange(
      kind: 'shift',
      id: grant.scope.shiftId,
      revision: snapshotCursor,
      deleted: false,
      value: _object(snapshot['shift']),
    ),
  ];
  for (final kind in ['product', 'category', 'stock']) {
    for (final row in _objects(
      snapshot[{
        'product': 'products',
        'category': 'categories',
        'stock': 'stock',
      }[kind]],
    )) {
      changes.add(
        OfflineCacheChange(
          kind: kind,
          id: offlineUuid(row[kind == 'stock' ? 'product_id' : 'id']),
          revision: snapshotCursor,
          deleted: false,
          value: row,
        ),
      );
    }
  }
  return OfflineCacheBatch(
    cursor: '$snapshotCursor',
    serverTime: serverTime,
    changes: changes,
    completeSnapshot: true,
    grantId: grant.grantId,
  );
}

void _validateExisting(
  OfflineCheckoutRequest request,
  LocalOfflineReceipt receipt,
  OfflineAuthorization authorization,
) {
  final expected =
      request.lines
          .map(
            (line) => {
              'product_id': line.product.id,
              'quantity': line.quantity,
              'unit_price_minor': line.product.priceMinor,
            },
          )
          .toList()
        ..sort(
          (a, b) =>
              (a['product_id'] as String).compareTo(b['product_id'] as String),
        );
  final actual =
      receipt.draft.items
          .map(
            (line) => {
              'product_id': line.productId,
              'quantity': line.quantity,
              'unit_price_minor': line.unitPriceMinor,
            },
          )
          .toList()
        ..sort(
          (a, b) =>
              (a['product_id'] as String).compareTo(b['product_id'] as String),
        );
  if (strictCanonicalJson(expected) != strictCanonicalJson(actual) ||
      request.payments.length != receipt.draft.payments.length) {
    throw const OfflineStorageConflict();
  }
  for (var index = 0; index < request.payments.length; index++) {
    final intended = request.payments[index],
        recorded = receipt.draft.payments[index];
    if (intended.method.name != recorded.method ||
        intended.amountMinor != recorded.amountMinor ||
        intended.reference?.trim() != recorded.reference) {
      throw const OfflineStorageConflict();
    }
    final expectedEvidence = intended.method == CheckoutPaymentMethod.cash
        ? {'tendered_minor': intended.tenderedMinor}
        : {'manual_confirmed': intended.manualConfirmed};
    if (strictCanonicalJson(expectedEvidence) !=
        strictCanonicalJson(authorization.paymentEvidence[recorded.id])) {
      throw const OfflineStorageConflict();
    }
  }
}

void _validateResponseScope(
  Map<String, Object?> response,
  AuthorizedOutboxEvent authorized,
  String deviceId,
) {
  final event = authorized.event;
  if (response['organization_id'] != event.organizationId ||
      response['branch_id'] != event.branchId ||
      response['actor_id'] != event.actorId ||
      response['device_id'] != deviceId ||
      response['grant_id'] != authorized.authorization.grantId ||
      response['sequence'] != authorized.authorization.sequence ||
      response['event_id'] != event.eventId ||
      response['digest'] != event.digest ||
      response['document_id'] != authorized.documentId) {
    throw const FormatException('Offline acceptance scope mismatch');
  }
}

void _validateServerReceipt(
  SaleReceipt receipt,
  SaleDraft draft,
  OfflineAuthorization authorization,
  OfflineGrant grant,
) {
  if (receipt.id != draft.id ||
      receipt.organizationId != draft.scope.organizationId ||
      receipt.branchId != draft.scope.branchId ||
      receipt.actorUserId != draft.cashierId ||
      receipt.shiftId != draft.shiftId ||
      receipt.requestId != draft.eventId ||
      receipt.currency != draft.currency ||
      receipt.taxBps != grant.taxBps ||
      receipt.businessName != grant.businessName ||
      receipt.createdAt != draft.createdAt ||
      receipt.subtotalMinor != draft.subtotalMinor ||
      receipt.discountMinor != draft.discountMinor ||
      receipt.taxMinor != draft.taxMinor ||
      receipt.totalMinor != draft.totalMinor ||
      receipt.items.length != draft.items.length ||
      receipt.payments.length != draft.payments.length) {
    throw const FormatException('Server receipt changed original paid amounts');
  }
  for (final line in draft.items) {
    final server = receipt.items
        .where((item) => item.productId == line.productId)
        .single;
    if (server.id != line.id ||
        server.quantity != line.quantity ||
        server.unitPriceMinor != line.unitPriceMinor ||
        server.discountMinor != line.discountMinor ||
        server.taxMinor != line.taxMinor ||
        server.name != line.name ||
        server.sku != line.sku) {
      throw const FormatException('Server receipt changed original paid item');
    }
  }
  for (final local in draft.payments) {
    final server = receipt.payments
        .where((payment) => payment.id == local.id)
        .single;
    final evidence = _object(authorization.paymentEvidence[local.id]);
    if (local.id != server.id ||
        local.method != server.method.name ||
        local.amountMinor != server.amountMinor ||
        local.reference != server.reference ||
        (local.method == 'cash' &&
            evidence['tendered_minor'] != server.tenderedMinor)) {
      throw const FormatException('Server receipt changed original payment');
    }
  }
}

String? _reconciliation(Object? value) {
  if (value == null) return null;
  if (value is! String || !RegExp(r'^[A-Z_]{1,80}$').hasMatch(value)) {
    throw const FormatException('Invalid reconciliation code');
  }
  return value;
}

void _validateCacheChange(OfflineCacheChange change, _Prepared prepared) {
  final value = change.value;
  if (change.deleted) return;
  if (value == null) throw const FormatException('Missing pull value');
  if (value.containsKey('cost_minor') || value.containsKey('unit_cost_minor')) {
    throw const FormatException('Restricted offline data');
  }
  if (change.kind == 'stock') {
    if (value['product_id'] != change.id) {
      throw const FormatException('Stock pull identity mismatch');
    }
    _integer(value['quantity'], signed: true);
    _integer(value['revision']);
  } else {
    if (value['organization_id'] != prepared.grant.scope.organizationId) {
      throw const FormatException('Foreign pull data');
    }
    if (change.kind == 'context' || change.kind == 'shift') {
      if (value['branch_id'] != prepared.grant.scope.branchId) {
        throw const FormatException('Foreign branch pull');
      }
    }
    if (change.kind == 'product' ||
        change.kind == 'category' ||
        change.kind == 'shift') {
      if (value['id'] != change.id) {
        throw const FormatException('Pull identity mismatch');
      }
    }
  }
}

SyncFailureCode _syncFailure(Object error) => switch (error) {
  RepositoryFailure(
    type: RepositoryFailureType.unauthenticated ||
        RepositoryFailureType.permissionDenied,
  ) =>
    SyncFailureCode.unauthorized,
  RepositoryFailure(type: RepositoryFailureType.conflict) =>
    SyncFailureCode.conflict,
  RepositoryFailure(type: RepositoryFailureType.validation) ||
  FormatException() ||
  OfflineSecurityException() => SyncFailureCode.invalidEvent,
  _ => SyncFailureCode.unavailable,
};
