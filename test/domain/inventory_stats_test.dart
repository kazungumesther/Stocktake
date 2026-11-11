import 'package:flutter_test/flutter_test.dart';
import 'package:stocktake/data/local/database.dart';
import 'package:stocktake/domain/inventory_stats.dart';

StockItem item(String name, int quantity) => StockItem(
      id: name,
      name: name,
      quantity: quantity,
      unit: 'pcs',
      updatedAt: DateTime.utc(2026, 11, 10),
      syncStatus: SyncStatus.synced,
      attempts: 0,
    );

void main() {
  test('counts items and units', () {
    final stats = InventoryStats.from([item('A', 10), item('B', 20)]);

    expect(stats.itemCount, 2);
    expect(stats.totalQuantity, 30);
  });

  test('lists low-stock items with the emptiest first', () {
    final stats = InventoryStats.from(
      [item('Rice', 4), item('Salt', 0), item('Beans', 50), item('Maize', 4)],
      lowThreshold: 5,
    );

    expect(stats.lowStock.map((i) => i.name), ['Salt', 'Maize', 'Rice']);
  });

  test('handles an empty list', () {
    final stats = InventoryStats.from([]);

    expect(stats.itemCount, 0);
    expect(stats.totalQuantity, 0);
    expect(stats.lowStock, isEmpty);
  });
}
