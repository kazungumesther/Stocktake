import 'package:supabase_flutter/supabase_flutter.dart';

/// An item as it exists on the server.
class RemoteItem {
  const RemoteItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.updatedAt,
    this.location,
    this.notes,
    this.deletedAt,
    this.serverUpdatedAt,
  });

  final String id;
  final String name;
  final int quantity;
  final String unit;
  final String? location;
  final String? notes;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Set by the server on every write. Used as the "what changed since?" cursor.
  final DateTime? serverUpdatedAt;

  RemoteItem withServerTime(DateTime time) => RemoteItem(
        id: id,
        name: name,
        quantity: quantity,
        unit: unit,
        updatedAt: updatedAt,
        location: location,
        notes: notes,
        deletedAt: deletedAt,
        serverUpdatedAt: time,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'location': location,
        'notes': notes,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
      };

  factory RemoteItem.fromJson(Map<String, dynamic> json) => RemoteItem(
        id: json['id'] as String,
        name: json['name'] as String,
        quantity: (json['quantity'] as num).toInt(),
        unit: json['unit'] as String,
        location: json['location'] as String?,
        notes: json['notes'] as String?,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        deletedAt: json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at'] as String),
        serverUpdatedAt: json['server_updated_at'] == null
            ? null
            : DateTime.parse(json['server_updated_at'] as String),
      );
}

/// The server could not be reached (offline, timeout, not signed in, token expired).
/// This is not the item's fault, so it never counts as a failed attempt.
class RemoteUnavailable implements Exception {
  const RemoteUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The server answered but refused the data (for example a rule was violated).
class RemoteRejected implements Exception {
  const RemoteRejected(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class RemoteInventory {
  /// The signed-in user, or null.
  String? get userId;

  Future<void> upsert(List<RemoteItem> items);

  /// Everything the server changed after [since] (everything when null).
  Future<List<RemoteItem>> pullSince(DateTime? since);
}

class SupabaseRemoteInventory implements RemoteInventory {
  SupabaseRemoteInventory(this._client);

  final SupabaseClient _client;
  static const _table = 'stock_items';
  static const _pageLimit = 5000;

  @override
  String? get userId => _client.auth.currentUser?.id;

  @override
  Future<void> upsert(List<RemoteItem> items) {
    return _guard(() async {
      await _client
          .from(_table)
          .upsert(items.map((item) => item.toJson()).toList());
    });
  }

  @override
  Future<List<RemoteItem>> pullSince(DateTime? since) {
    return _guard(() async {
      var query = _client.from(_table).select();
      if (since != null) {
        query = query.gt('server_updated_at', since.toUtc().toIso8601String());
      }
      final rows =
          await query.order('server_updated_at', ascending: true).limit(_pageLimit);
      return rows.map((row) => RemoteItem.fromJson(row)).toList();
    });
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    if (_client.auth.currentSession == null) {
      throw const RemoteUnavailable('Not signed in');
    }
    try {
      return await run();
    } on PostgrestException catch (e) {
      if (_isTransient(e)) throw RemoteUnavailable(e.message);
      throw RemoteRejected(e.message);
    } catch (e) {
      // Network errors, timeouts, auth refresh problems...
      throw RemoteUnavailable(e.toString());
    }
  }

  /// Auth problems (PGRST3xx) and server errors (5xx) are worth retrying later
  /// without blaming the item.
  bool _isTransient(PostgrestException e) {
    final code = e.code ?? '';
    final status = int.tryParse(code);
    return code.startsWith('PGRST3') || (status != null && status >= 500);
  }
}
