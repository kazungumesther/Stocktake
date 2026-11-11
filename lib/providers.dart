import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'data/local/database.dart';
import 'data/local/inventory_repository.dart';
import 'data/remote/remote_inventory.dart';
import 'data/sync/sync_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(ref.watch(databaseProvider));
});

/// Null in local-only mode (no Supabase settings).
final remoteInventoryProvider = Provider<RemoteInventory?>((ref) {
  if (!AppConfig.hasSupabase) return null;
  return SupabaseRemoteInventory(Supabase.instance.client);
});

final syncServiceProvider = Provider<SyncService?>((ref) {
  final remote = ref.watch(remoteInventoryProvider);
  if (remote == null) return null;
  return SyncService(db: ref.watch(databaseProvider), remote: remote);
});

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final searchQueryProvider =
    NotifierProvider<SearchQuery, String>(SearchQuery.new);

/// The list on the home screen: filtered by the search box.
final inventoryItemsProvider = StreamProvider<List<StockItem>>((ref) {
  final query = ref.watch(searchQueryProvider);
  return ref.watch(inventoryRepositoryProvider).watchAll(query: query);
});

/// Every item, ignoring the search box. The dashboard uses this.
final allItemsProvider = StreamProvider<List<StockItem>>((ref) {
  return ref.watch(inventoryRepositoryProvider).watchAll();
});

final unsyncedCountProvider = StreamProvider<int>((ref) {
  return ref.watch(inventoryRepositoryProvider).watchUnsyncedCount();
});
