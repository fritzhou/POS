import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/sync/sync_event.dart';

void main() {
  test('canonical encoding sorts nested keys and preserves array ordering', () {
    expect(
      canonicalJson({
        'z': [
          3,
          {'b': 2, 'a': 1},
        ],
        'a': 'line\nquote"',
      }),
      canonicalJson({
        'a': 'line\nquote"',
        'z': [
          3,
          {'a': 1, 'b': 2},
        ],
      }),
    );
    expect(canonicalJson([1, 2]), isNot(canonicalJson([2, 1])));
  });

  test(
    'canonical payloads reject floating-point and unsafe integer amounts',
    () {
      expect(() => canonicalJson({'amount': 0.1}), throwsArgumentError);
      expect(
        () => canonicalJson({'amount': 9007199254740992}),
        throwsArgumentError,
      );
      expect(
        () => canonicalJson({'date': DateTime.utc(2026)}),
        throwsArgumentError,
      );
    },
  );

  test(
    'digest binds immutable event identity, scope, metadata and payload',
    () {
      final id = newLocalId();
      SyncEvent event(String branch, Map<String, Object?> payload) => SyncEvent(
        eventId: id,
        organizationId: 'org-1',
        branchId: branch,
        deviceId: 'device-1',
        actorId: 'user-1',
        eventType: 'sale.created',
        occurredAt: DateTime.utc(2026),
        payload: payload,
      );
      final first = event('branch-a', {'b': 2, 'a': 1});
      expect(first.digest, event('branch-a', {'a': 1, 'b': 2}).digest);
      expect(first.digest, isNot(event('branch-b', {'a': 1, 'b': 2}).digest));
      expect(first.digest, isNot(event('branch-a', {'a': 1, 'b': 3}).digest));
      expect(first.digest, hasLength(64));
    },
  );
}
