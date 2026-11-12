
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

// ignore_for_file: uri_has_not_been_generated
part 'database.g.dart';

enum SyncStatus { synced, pending, failed }

class StockItems extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  IntColumn get quantity => integer().withDefault(const Constant(0))();
  TextColumn get unit => text().withDefault(const Constant('pcs'))();
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();

  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  IntColumn get syncStatus => intEnum<SyncStatus>()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [StockItems, SyncMeta])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(
          executor ??
              driftDatabase(
                name: 'stocktake',
                web: DriftWebOptions(
                  sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                  driftWorker: Uri.parse('drift_worker.js'),
                ),
              ),
        );

  @override
  int get schemaVersion => 1;

  Future<String?> metaGet(String key) async {
    final row = await (select(syncMeta)
          ..where((tbl) => tbl.key.equals(key)))
        .getSingleOrNull();

    return row?.value;
  }

  Future<void> metaSet(String key, String value) {
    return into(syncMeta).insertOnConflictUpdate(
      SyncMetaCompanion.insert(key: key, value: value),
    );
  }

  Future<void> wipeAll() {
    return transaction(() async {
      await delete(stockItems).go();
      await delete(syncMeta).go();
    });
  }
}
