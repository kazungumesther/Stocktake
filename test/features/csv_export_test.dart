import 'package:flutter_test/flutter_test.dart';
import 'package:stocktake/data/local/database.dart';
import 'package:stocktake/features/inventory/csv_export.dart';

StockItem item({required String name, String? notes, String? location}) => StockItem(
      id: name,
      name: name,
      quantity: 3,
      unit: 'kg',
      location: location,
      notes: notes,
      updatedAt: DateTime.utc(2026, 11, 10, 12),
      syncStatus: SyncStatus.synced,
      attempts: 0,
    );

void main() {
  test('writes a header and one row per item', () {
    final lines = itemsToCsv([item(name: 'Rice', location: 'Shelf 2')]).split('\r\n');

    expect(lines, hasLength(2));
    expect(lines[0], 'Name,Quantity,Unit,Location,Notes,Updated');
    expect(lines[1], 'Rice,3,kg,Shelf 2,,2026-11-10T12:00:00.000Z');
  });

  test('quotes commas, quotes and new lines', () {
    final csv = itemsToCsv([item(name: 'Rice', notes: 'Said "hi", then\nleft')]);

    expect(csv, contains('"Said ""hi"", then\nleft"'));
  });

  test('neutralises spreadsheet formulas', () {
    final csv = itemsToCsv([item(name: '=SUM(A1:A9)')]);

    expect(csv, contains("'=SUM(A1:A9)"));
  });
}
