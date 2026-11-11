import '../../data/local/database.dart';

/// Turns the item list into CSV text.
String itemsToCsv(List<StockItem> items) {
  const header = ['Name', 'Quantity', 'Unit', 'Location', 'Notes', 'Updated'];
  final rows = items.map(
    (i) => [
      i.name,
      i.quantity.toString(),
      i.unit,
      i.location ?? '',
      i.notes ?? '',
      i.updatedAt.toUtc().toIso8601String(),
    ],
  );
  return [header, ...rows].map((row) => row.map(_cell).join(',')).join('\r\n');
}

String _cell(String value) {
  var text = value;
  // Spreadsheet apps run cells that start with = + - @ as formulas, which is a
  // known injection risk for exported data. A leading quote makes them plain text.
  if (RegExp(r'^[=+\-@\t\r]').hasMatch(text)) text = "'$text";
  if (RegExp(r'[",\n\r]').hasMatch(text)) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}
