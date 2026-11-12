import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers.dart';

class SyncUiState {
  const SyncUiState({
    this.running = false,
    this.offline = false,
    this.lastSyncedAt,
    this.message,
  });

  final bool running;
  final bool offline;
  final DateTime? lastSyncedAt;
  final String? message;

  SyncUiState copyWith({bool? running}) => SyncUiState(
        running: running ?? this.running,
        offline: offline,
        lastSyncedAt: lastSyncedAt,
        message: message,
      );
}


class SyncController extends Notifier<SyncUiState> {
  Timer? _debounce;
  Timer? _periodic;
  StreamSubscription<dynamic>? _connectivity;
  StreamSubscription<dynamic>? _auth;
  StreamSubscription<int>? _unsynced;
  bool _disposed = false;

  @override
  SyncUiState build() {
    ref.onDispose(() {
      _disposed = true;
      _stop();
    });
    return const SyncUiState();
  }

  void start() {
    if (ref.read(syncServiceProvider) == null) return; // local-only mode
    _stop();

    _connectivity = Connectivity().onConnectivityChanged.listen((_) => syncSoon());
    _auth = Supabase.instance.client.auth.onAuthStateChange.listen((_) => syncSoon());

    
    var last = 0;
    _unsynced = ref
        .read(inventoryRepositoryProvider)
        .watchUnsyncedCount()
        .listen((count) {
      if (count > last) syncSoon();
      last = count;
    });

    _periodic = Timer.periodic(const Duration(seconds: 60), (_) => syncNow());
    syncSoon();
  }

  void syncSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), syncNow);
  }

  Future<void> syncNow({bool retryFailed = false}) async {
    if (_disposed) return;
    final service = ref.read(syncServiceProvider);
    if (service == null) return;

    state = state.copyWith(running: true);
    try {
      final result = await service.syncNow(retryFailed: retryFailed);
      if (_disposed) return;
      if (result.skipped) {
        state = state.copyWith(running: service.isRunning);
        return;
      }
      state = SyncUiState(
        offline: result.offline,
        lastSyncedAt: result.offline ? state.lastSyncedAt : DateTime.now(),
        message: result.message,
      );
    } catch (e) {
      if (_disposed) return;
      state = SyncUiState(lastSyncedAt: state.lastSyncedAt, message: e.toString());
    }
  }

  void _stop() {
    _debounce?.cancel();
    _periodic?.cancel();
    _connectivity?.cancel();
    _auth?.cancel();
    _unsynced?.cancel();
  }
}

final syncControllerProvider =
    NotifierProvider<SyncController, SyncUiState>(SyncController.new);
