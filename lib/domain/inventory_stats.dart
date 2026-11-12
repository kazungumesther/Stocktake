
import '../core/config.dart';
import '../data/local/database.dart';

class InventoryStats {
  const InventoryStats({
    required this.itemCount,
    required this.totalQuantity,
    required this.lowStock,
  });

  final int itemCount;
  final int totalQuantity;
  final List<StockItem> lowStock;

  factory InventoryStats.from(
    List<StockItem> items, {
    int lowThreshold = AppConfig.lowStockThreshold,
  }) {
    final low = items
        .where((item) => item.deletedAt == null)
        .where((item) => item.quantity <= lowThreshold)
        .toList()
      ..sort((a, b) {
        final byQuantity = a.quantity.compareTo(b.quantity);
        return byQuantity != 0 ? byQuantity : a.name.compareTo(b.name);
      });

    final activeItems = items.where((item) => item.deletedAt == null);

    return InventoryStats(
      itemCount: activeItems.length,
      totalQuantity: activeItems.fold(
        0,
        (sum, item) => sum + item.quantity,
      ),
      lowStock: low,
    );
  }
}
