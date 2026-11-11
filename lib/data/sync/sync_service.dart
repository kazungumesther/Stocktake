import 'dart:math';

import 'package:drift/drift.dart';

import '../local/database.dart';
import '../remote/remote_inventory.dart';

/// How long to wait before retrying an item the server rejected:
/// 5s, 10s, 20s, 40s... capped at 15 minutes.
Duration backoffFor(int attempts) {
  if (attempts <= 0) return Duration.zero;
  final seconds = 5 * (1 << min(attempts - 1, 20));
  return Duration(seconds: min(seconds, 900));
}

class SyncResult {
  const SyncResult({
    this.pushed = 0,
    this.rejected = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.offline = false,
    this.skipped = false,
    this.message,
  });

  /// Items sent to the server.
  final int pushed;

  /// Items the server refused this time.
  final int rejected;

  /// Items received from (or changed by) the server.
  final int pulled;

  /// Local edits that lost to a newer edit made elsewhere.
  final int conflicts;

  /// The server couldn't be reached. Nothing was lost; it will be retried.
  final bool offline;

  /// Another sync was already running.
  final bool skipped;

  final String? message;
}

class _Tally {
  int pushed = 0;
  int rejected = 0;
  int pulled = 0;
  int conflicts = 0;

  SyncResult toResult({bool offline = false, String? message}) => SyncResult(
        pushed: pushed,
        rejected: rejected,
        pulled: pulled,
        conflicts: conflicts,
        offline: offline,
        message: message,
      );
}

/// Keeps the local database and the server in step.
///
/// Every item carries its own sync state, so "what still needs sending" is just
/// "every item that isn't synced". One sync is: pull what changed on the server,
/// merge it with last-write-wins, then push what is still pending.
class SyncService {
  SyncService({
    required AppDatabase db,
    required RemoteInventory remote,
    DateTime Function()? now,
    this.maxAttempts = 5,
    this.batchSize = 50,
    this.pullOverlap = const Duration(seconds: 10),
  })  : _db = db,
        _remote = remote,
        _now = now ?? DateTime.now;

  final AppDatabase _db;
  final RemoteInventory _remote;
  final DateTime Function() _now;

  /// After this many rejections an item is marked `failed` until the user retries.
  final int maxAttempts;
  final int batchSize;

  /// Pulls start slightly before the last cursor, so a change committed late is
  /// never missed. Merging is idempotent, so seeing a row twice is harmless.
  final Duration pullOverlap;

  static const _ownerKey = 'owner';
  static const _lastPullKey = 'last_pull';

  bool _running = false;
  bool get isRunning => _running;

  Future<SyncResult> syncNow({bool retryFailed = false}) async {
    if (_running) return const SyncResult(skipped: true);
    _running = true;
    final tally = _Tally();
    try {
      final userId = _remote.userId;
      if (userId == null) {
        return const SyncResult(offline: true, message: 'Not signed in');
      }
      await _claimDevice(userId);
      if (retryFailed) await _resetFailed();
      await _pull(tally);
      await _push(tally);
      return tally.toResult();
    } on RemoteUnavailable catch (e) {
      return tally.toResult(offline: true, message: e.message);
    } on RemoteRejected catch (e) {
      return tally.toResult(message: e.message);
    } finally {
      _running = false;
    }
  }

  /// If a different account signs in on this device, its data must not mix with
  /// the previous account's, so the local copy is cleared first.
  Future<void> _claimDevice(String userId) async {
    final owner = await _db.metaGet(_ownerKey);
    if (owner != null && owner != userId) await _db.wipeAll();
    if (owner != userId) await _db.metaSet(_ownerKey, userId);
  }

  Future<void> _resetFailed() async {
    await (_db.update(_db.stockItems)
          ..where((t) => t.syncStatus.equals(SyncStatus.failed.index)))
        .write(
      const StockItemsCompanion(
        syncStatus: Value(SyncStatus.pending),
        attempts: Value(0),
        lastError: Value(null),
        lastAttemptAt: Value(null),
      ),
    );
  }

  // ---------------------------------------------------------------- pull

  Future<void> _pull(_Tally tally) async {
    final stored = await _db.metaGet(_lastPullKey);
    final since =
        stored == null ? null : DateTime.parse(stored).subtract(pullOverlap);
    final remoteItems = await _remote.pullSince(since);

    DateTime? newest;
    for (final remote in remoteItems) {
      if (await _merge(remote, tally)) tally.pulled++;
      final serverTime = remote.serverUpdatedAt;
      if (serverTime != null && (newest == null || serverTime.isAfter(newest))) {
        newest = serverTime;
      }
    }
    if (newest != null) {
      await _db.metaSet(_lastPullKey, newest.toUtc().toIso8601String());
    }
  }

  /// Last-write-wins: the version with the newer `updatedAt` survives.
  /// Returns true when the local row changed.
  Future<bool> _merge(RemoteItem remote, _Tally tally) async {
    final local = await (_db.select(_db.stockItems)
          ..where((t) => t.id.equals(remote.id)))
        .getSingleOrNull();

    if (local == null) {
      await _db.into(_db.stockItems).insert(
            StockItemsCompanion.insert(
              id: remote.id,
              name: remote.name,
              quantity: Value(remote.quantity),
              unit: Value(remote.unit),
              location: Value(remote.location),
              notes: Value(remote.notes),
              updatedAt: remote.updatedAt,
              deletedAt: Value(remote.deletedAt),
              syncStatus: SyncStatus.synced,
            ),
          );
      return true;
    }

    // Our copy is the same age or newer: keep it (and push it if it's pending).
    if (!remote.updatedAt.isAfter(local.updatedAt)) return false;

    // The server's copy is newer. If we had an unsent edit, it loses.
    if (local.syncStatus != SyncStatus.synced) tally.conflicts++;

    await (_db.update(_db.stockItems)..where((t) => t.id.equals(remote.id))).write(
      StockItemsCompanion(
        name: Value(remote.name),
        quantity: Value(remote.quantity),
        unit: Value(remote.unit),
        location: Value(remote.location),
        notes: Value(remote.notes),
        updatedAt: Value(remote.updatedAt),
        deletedAt: Value(remote.deletedAt),
        syncStatus: const Value(SyncStatus.synced),
        attempts: const Value(0),
        lastError: const Value(null),
        lastAttemptAt: const Value(null),
      ),
    );
    return true;
  }

  // ---------------------------------------------------------------- push

  Future<void> _push(_Tally tally) async {
    final now = _now();
    final pending = await (_db.select(_db.stockItems)
          ..where((t) => t.syncStatus.equals(SyncStatus.pending.index))
          ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)]))
        .get();
    final ready = pending.where((item) => _isDue(item, now)).toList();

    for (var start = 0; start < ready.length; start += batchSize) {
      final batch = ready.sublist(start, min(start + batchSize, ready.length));
      try {
        await _remote.upsert(batch.map(_toRemote).toList());
        for (final item in batch) {
          await _markSynced(item);
        }
        tally.pushed += batch.length;
      } on RemoteRejected {
        // One bad item shouldn't hold back the rest, so send them one at a time.
        for (final item in batch) {
          try {
            await _remote.upsert([_toRemote(item)]);
            await _markSynced(item);
            tally.pushed++;
          } on RemoteRejected catch (e) {
            await _markRejected(item, e.message);
            tally.rejected++;
          }
        }
      }
      // RemoteUnavailable is not caught here: it stops the whole sync and the
      // items simply stay pending, with no attempt counted against them.
    }
  }

  bool _isDue(StockItem item, DateTime now) {
    final last = item.lastAttemptAt;
    if (item.attempts == 0 || last == null) return true;
    return !now.isBefore(last.add(backoffFor(item.attempts)));
  }

  /// Only marks the item synced if it wasn't edited while the request was in
  /// flight. If it was, the newer edit stays pending and goes out next time.
  Future<void> _markSynced(StockItem sent) async {
    await (_db.update(_db.stockItems)
          ..where((t) => t.id.equals(sent.id) & t.updatedAt.equals(sent.updatedAt)))
        .write(
      const StockItemsCompanion(
        syncStatus: Value(SyncStatus.synced),
        attempts: Value(0),
        lastError: Value(null),
        lastAttemptAt: Value(null),
      ),
    );
  }

  Future<void> _markRejected(StockItem sent, String message) async {
    final attempts = sent.attempts + 1;
    await (_db.update(_db.stockItems)
          ..where((t) => t.id.equals(sent.id) & t.updatedAt.equals(sent.updatedAt)))
        .write(
      StockItemsCompanion(
        attempts: Value(attempts),
        lastError: Value(message),
        lastAttemptAt: Value(_now()),
        syncStatus: Value(
          attempts >= maxAttempts ? SyncStatus.failed : SyncStatus.pending,
        ),
      ),
    );
  }

  RemoteItem _toRemote(StockItem item) => RemoteItem(
        id: item.id,
        name: item.name,
        quantity: item.quantity,
        unit: item.unit,
        location: item.location,
        notes: item.notes,
        updatedAt: item.updatedAt,
        deletedAt: item.deletedAt,
      );
}
