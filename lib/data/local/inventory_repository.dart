import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

/// All reads and writes of stock items go through here. The local database is
/// the source of truth: every change is saved on the device first and marked
/// `pending`, and the sync service sends it to the server later.
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

  /// Live list of items that haven't been deleted, optionally filtered by name.
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

  /// How many items are waiting to be sent (includes failed ones and deletions).
  Stream<int> watchUnsyncedCount() {
    final count = _db.stockItems.id.count();
    final query = _db.selectOnly(_db.stockItems)
      ..addColumns([count])
      ..where(_db.stockItems.syncStatus.equals(SyncStatus.synced.index).not());
    return query.map((row) => row.read(count) ?? 0).watchSingle();
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

  /// Saves an edited item and marks it pending again.
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

  /// Soft delete, so the deletion can reach the server.
  Future<void> remove(String id) async {
    final now = _now();
    await (_db.update(_db.stockItems)..where((t) => t.id.equals(id))).write(
      StockItemsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.pending),
        attempts: const Value(0),
        lastError: const Value(null),
        lastAttemptAt: const Value(null),
      ),
    );
  }

  /// Undo for [remove].
  Future<void> restore(String id) async {
    await (_db.update(_db.stockItems)..where((t) => t.id.equals(id))).write(
      StockItemsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(_now()),
        syncStatus: const Value(SyncStatus.pending),
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
