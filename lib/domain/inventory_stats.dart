import '../core/config.dart';
import '../data/local/database.dart';

/// Numbers for the dashboard, worked out from the list of items.
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
    final low = items.where((i) => i.quantity <= lowThreshold).toList()
      ..sort((a, b) {
        final byQuantity = a.quantity.compareTo(b.quantity);
        return byQuantity != 0 ? byQuantity : a.name.compareTo(b.name);
      });
    return InventoryStats(
      itemCount: items.length,
      totalQuantity: items.fold(0, (sum, i) => sum + i.quantity),
      lowStock: low,
    );
  }
}
