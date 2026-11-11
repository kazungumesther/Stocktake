import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocktake/data/local/database.dart';
import 'package:stocktake/data/local/inventory_repository.dart';
import 'package:stocktake/data/remote/remote_inventory.dart';
import 'package:stocktake/data/sync/sync_service.dart';

/// An in-memory stand-in for the server. It follows the same rule as the real
/// one: an older edit never overwrites a newer one.
class FakeRemote implements RemoteInventory {
  @override
  String? userId = 'user-1';

  final Map<String, RemoteItem> rows = {};
  bool offline = false;
  Set<String> rejectIds = {};
  int upsertCalls = 0;
  Future<void> Function(List<RemoteItem> items)? onUpsert;
  DateTime _serverClock = DateTime.utc(2026, 11, 10, 11);

  DateTime _tick() => _serverClock = _serverClock.add(const Duration(seconds: 1));

  @override
  Future<void> upsert(List<RemoteItem> items) async {
    upsertCalls++;
    if (offline) throw const RemoteUnavailable('offline');
    if (items.any((i) => rejectIds.contains(i.id))) {
      throw const RemoteRejected('rejected');
    }
    await onUpsert?.call(items);
    for (final item in items) {
      final existing = rows[item.id];
      if (existing != null && item.updatedAt.isBefore(existing.updatedAt)) continue;
      rows[item.id] = item.withServerTime(_tick());
    }
  }

  @override
  Future<List<RemoteItem>> pullSince(DateTime? since) async {
    if (offline) throw const RemoteUnavailable('offline');
    final list = rows.values
        .where((r) => since == null || r.serverUpdatedAt!.isAfter(since))
        .toList()
      ..sort((a, b) => a.serverUpdatedAt!.compareTo(b.serverUpdatedAt!));
    return list;
  }

  /// Simulates an edit made on another device.
  void remoteEdit(RemoteItem item) {
    rows[item.id] = item.withServerTime(_tick());
  }
}

RemoteItem remoteItem(
  String id,
  String name, {
  int quantity = 1,
  required DateTime updatedAt,
  DateTime? deletedAt,
}) {
  return RemoteItem(
    id: id,
    name: name,
    quantity: quantity,
    unit: 'pcs',
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );
}

void main() {
  late AppDatabase db;
  late InventoryRepository repo;
  late FakeRemote remote;
  late SyncService sync;
  var clock = DateTime.utc(2026, 11, 10, 12);

  DateTime now() => clock;
  void advance(Duration d) => clock = clock.add(d);

  setUp(() {
    clock = DateTime.utc(2026, 11, 10, 12);
    db = AppDatabase(NativeDatabase.memory());
    repo = InventoryRepository(db, now: now);
    remote = FakeRemote();
    sync = SyncService(db: db, remote: remote, now: now);
  });

  tearDown(() => db.close());

  group('backoffFor', () {
    test('grows and is capped', () {
      expect(backoffFor(0), Duration.zero);
      expect(backoffFor(1), const Duration(seconds: 5));
      expect(backoffFor(3), const Duration(seconds: 20));
      expect(backoffFor(20), const Duration(minutes: 15));
    });
  });

  group('pushing', () {
    test('sends pending items and marks them synced', () async {
      final id = await repo.add(name: 'Rice', quantity: 4);

      final result = await sync.syncNow();

      expect(result.pushed, 1);
      expect(remote.rows[id]!.name, 'Rice');
      expect((await repo.byId(id))!.syncStatus, SyncStatus.synced);
    });

    test('stays pending, without counting an attempt, when offline', () async {
      remote.offline = true;
      final id = await repo.add(name: 'Rice');

      final result = await sync.syncNow();

      expect(result.offline, isTrue);
      final item = (await repo.byId(id))!;
      expect(item.syncStatus, SyncStatus.pending);
      expect(item.attempts, 0);
    });

    test('is not signed in: nothing happens and it reports offline', () async {
      remote.userId = null;
      await repo.add(name: 'Rice');

      final result = await sync.syncNow();

      expect(result.offline, isTrue);
      expect(remote.upsertCalls, 0);
    });

    test('a rejected item does not block the others and waits before retrying', () async {
      final good = await repo.add(name: 'Good');
      final bad = await repo.add(name: 'Bad');
      remote.rejectIds = {bad};

      final first = await sync.syncNow();
      expect(first.pushed, 1);
      expect(first.rejected, 1);
      expect((await repo.byId(good))!.syncStatus, SyncStatus.synced);
      final badItem = (await repo.byId(bad))!;
      expect(badItem.attempts, 1);
      expect(badItem.syncStatus, SyncStatus.pending);
      expect(badItem.lastError, 'rejected');

      // Too soon: it is not tried again.
      remote.upsertCalls = 0;
      await sync.syncNow();
      expect(remote.upsertCalls, 0);

      // After the backoff it is tried again.
      advance(const Duration(seconds: 6));
      await sync.syncNow();
      expect((await repo.byId(bad))!.attempts, 2);
    });

    test('gives up after the maximum attempts until the user retries', () async {
      final bad = await repo.add(name: 'Bad');
      remote.rejectIds = {bad};

      for (var i = 0; i < 5; i++) {
        await sync.syncNow();
        advance(const Duration(minutes: 20));
      }
      final failed = (await repo.byId(bad))!;
      expect(failed.syncStatus, SyncStatus.failed);
      expect(failed.attempts, 5);

      // The server accepts it now, but a failed item is not retried by itself.
      remote.rejectIds = {};
      await sync.syncNow();
      expect((await repo.byId(bad))!.syncStatus, SyncStatus.failed);

      final result = await sync.syncNow(retryFailed: true);
      expect(result.pushed, 1);
      expect((await repo.byId(bad))!.syncStatus, SyncStatus.synced);
    });

    test('an edit made while the request is in flight stays pending', () async {
      final id = await repo.add(name: 'Rice', quantity: 1);
      remote.onUpsert = (_) async {
        advance(const Duration(seconds: 1));
        final current = (await repo.byId(id))!;
        await repo.save(current.copyWith(quantity: 99));
      };

      await sync.syncNow();

      final after = (await repo.byId(id))!;
      expect(after.quantity, 99);
      expect(after.syncStatus, SyncStatus.pending);

      remote.onUpsert = null;
      await sync.syncNow();
      expect(remote.rows[id]!.quantity, 99);
      expect((await repo.byId(id))!.syncStatus, SyncStatus.synced);
    });
  });

  group('pulling', () {
    test('brings in items created on another device', () async {
      remote.remoteEdit(remoteItem('r1', 'Beans', quantity: 7, updatedAt: clock));

      final result = await sync.syncNow();

      expect(result.pulled, 1);
      final list = await repo.watchAll().first;
      expect(list.map((i) => i.name), ['Beans']);
      expect(list.single.syncStatus, SyncStatus.synced);
    });

    test('a newer edit from elsewhere replaces an unsent local edit', () async {
      final id = await repo.add(name: 'Rice', quantity: 1);
      advance(const Duration(minutes: 5));
      remote.remoteEdit(remoteItem(id, 'Rice', quantity: 50, updatedAt: clock));

      final result = await sync.syncNow();

      expect(result.conflicts, 1);
      final item = (await repo.byId(id))!;
      expect(item.quantity, 50);
      expect(item.syncStatus, SyncStatus.synced);
    });

    test('a newer local edit wins and is pushed', () async {
      remote.remoteEdit(remoteItem('x1', 'Old', quantity: 1, updatedAt: clock));
      await sync.syncNow();

      advance(const Duration(minutes: 5));
      final item = (await repo.byId('x1'))!;
      await repo.save(item.copyWith(quantity: 9)); // local edit at 12:05

      // Another device edited earlier than that.
      remote.remoteEdit(remoteItem(
        'x1',
        'Old',
        quantity: 3,
        updatedAt: DateTime.utc(2026, 11, 10, 12, 2),
      ));
      final result = await sync.syncNow();

      expect(result.conflicts, 0);
      expect(remote.rows['x1']!.quantity, 9);
      expect((await repo.byId('x1'))!.syncStatus, SyncStatus.synced);
    });

    test('an item deleted on another device disappears from the list', () async {
      remote.remoteEdit(remoteItem('d1', 'Salt', updatedAt: clock));
      await sync.syncNow();
      expect(await repo.watchAll().first, hasLength(1));

      advance(const Duration(minutes: 1));
      remote.remoteEdit(remoteItem('d1', 'Salt', updatedAt: clock, deletedAt: clock));
      await sync.syncNow();

      expect(await repo.watchAll().first, isEmpty);
      expect((await repo.byId('d1'))!.deletedAt, isNotNull);
    });
  });

  group('accounts', () {
    test('a different user signing in on the same device starts clean', () async {
      await repo.add(name: 'Mine');
      await sync.syncNow();
      expect(await repo.watchAll().first, hasLength(1));

      remote
        ..userId = 'user-2'
        ..rows.clear();
      await sync.syncNow();

      expect(await repo.watchAll().first, isEmpty);
    });
  });
}
