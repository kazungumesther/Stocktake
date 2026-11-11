import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocktake/data/local/database.dart';
import 'package:stocktake/data/local/inventory_repository.dart';

void main() {
  late AppDatabase db;
  late InventoryRepository repo;
  var tick = 0;
  var ids = 0;

  setUp(() {
    tick = 0;
    ids = 0;
    db = AppDatabase(NativeDatabase.memory());
    repo = InventoryRepository(
      db,
      // A clock that moves forward one minute per call, so order is predictable.
      now: () => DateTime.utc(2026, 11, 10, 12, tick++),
      newId: () => 'item-${ids++}',
    );
  });

  tearDown(() => db.close());

  test('a new item is saved locally and marked pending', () async {
    final id = await repo.add(name: 'Maize flour', quantity: 12, unit: 'kg');

    final item = await repo.byId(id);
    expect(item, isNotNull);
    expect(item!.name, 'Maize flour');
    expect(item.quantity, 12);
    expect(item.syncStatus, SyncStatus.pending);
  });

  test('saving an edit bumps updatedAt and resets the sync state', () async {
    final id = await repo.add(name: 'Rice', quantity: 5);
    final original = (await repo.byId(id))!;

    // Pretend it had failed to sync a few times.
    await db.update(db.stockItems).replace(original.copyWith(
          syncStatus: SyncStatus.failed,
          attempts: 3,
        ));
    final failed = (await repo.byId(id))!;

    await repo.save(failed.copyWith(quantity: 9));

    final saved = (await repo.byId(id))!;
    expect(saved.quantity, 9);
    expect(saved.syncStatus, SyncStatus.pending);
    expect(saved.attempts, 0);
    expect(saved.updatedAt.isAfter(original.updatedAt), isTrue);
  });

  test('removing an item hides it but keeps the row so it can sync', () async {
    final id = await repo.add(name: 'Salt');

    await repo.remove(id);

    expect(await repo.watchAll().first, isEmpty);
    final row = (await repo.byId(id))!;
    expect(row.deletedAt, isNotNull);
    expect(row.syncStatus, SyncStatus.pending);
  });

  test('restoring a deleted item brings it back as pending', () async {
    final id = await repo.add(name: 'Salt');
    await repo.remove(id);

    await repo.restore(id);

    final list = await repo.watchAll().first;
    expect(list.map((i) => i.name), ['Salt']);
    expect(list.single.deletedAt, isNull);
    expect(list.single.syncStatus, SyncStatus.pending);
  });

  test('search filters by name', () async {
    await repo.add(name: 'Sugar');
    await repo.add(name: 'Salt');
    await repo.add(name: 'Beans');

    final result = await repo.watchAll(query: 'sa').first;

    expect(result.map((i) => i.name), ['Salt']);
  });

  test('counts items that are not synced yet', () async {
    final a = await repo.add(name: 'A');
    await repo.add(name: 'B');
    final item = (await repo.byId(a))!;
    await db
        .update(db.stockItems)
        .replace(item.copyWith(syncStatus: SyncStatus.synced));

    expect(await repo.watchUnsyncedCount().first, 1);
  });
}
