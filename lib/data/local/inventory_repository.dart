
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

class InventoryRepository {
  InventoryRepository(
    this._db, {
    DateTime Function()? now,
    String Function()? newId,
  })  : _now = now ?? DateTime.now,
        _newId = newId ?? (() => const Uuid().v4());

  final AppDatabase _db;
  final DateTime Function() _now;
  final String Function() _newId;

  Stream<List<StockItem>> watchAll({String query = ''}) {
    final select = _db.select(_db.stockItems)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);

    final text = query.trim();

    if (text.isNotEmpty) {
      select.where((t) => t.name.like('%$text%'));
    }

    return select.watch();
  }

  Stream<int> watchUnsyncedCount() {
    final count = _db.stockItems.id.count();

    final query = _db.selectOnly(_db.stockItems)
      ..addColumns([count])
      ..where(
        _db.stockItems.syncStatus.equals(SyncStatus.synced.index).not(),
      );

    return query
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }

  Future<String> add({
    required String name,
    int quantity = 0,
    String unit = 'pcs',
    String? location,
    String? notes,
  }) async {
    final id = _newId();

    await _db.into(_db.stockItems).insert(
          StockItemsCompanion.insert(
            id: id,
            name: name.trim(),
            quantity: Value(quantity),
            unit: Value(unit),
            location: Value(location),
            notes: Value(notes),
            updatedAt: _now(),
            syncStatus: SyncStatus.pending,
          ),
        );

    return id;
  }

  Future<void> save(StockItem edited) async {
    await _db.update(_db.stockItems).replace(
          edited.copyWith(
            updatedAt: _now(),
            syncStatus: SyncStatus.pending,
            attempts: 0,
            lastError: const Value(null),
            lastAttemptAt: const Value(null),
          ),
        );
  }

  Future<void> remove(String id) async {
    final now = _now();

    await (_db.update(_db.stockItems)..where((t) => t.id.equals(id))).write(
      StockItemsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: Value(SyncStatus.pending),
        attempts: const Value(0),
        lastError: const Value(null),
        lastAttemptAt: const Value(null),
      ),
    );
  }

  Future<void> restore(String id) async {
    await (_db.update(_db.stockItems)..where((t) => t.id.equals(id))).write(
      StockItemsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(_now()),
        syncStatus: Value(SyncStatus.pending),
        attempts: const Value(0),
        lastError: const Value(null),
        lastAttemptAt: const Value(null),
      ),
    );
  }

  Future<StockItem?> byId(String id) {
    return (_db.select(_db.stockItems)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }
}
