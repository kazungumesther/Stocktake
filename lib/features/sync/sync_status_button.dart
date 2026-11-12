import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../providers.dart';
import 'sync_controller.dart';


class SyncStatusButton extends ConsumerWidget {
  const SyncStatusButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppConfig.hasSupabase) return const SizedBox.shrink();

    final sync = ref.watch(syncControllerProvider);
    final unsynced = ref.watch(unsyncedCountProvider).value ?? 0;

    final IconData icon;
    final String tooltip;
    if (sync.running) {
      icon = Icons.sync;
      tooltip = 'Syncing…';
    } else if (sync.offline) {
      icon = Icons.cloud_off;
      tooltip = unsynced > 0
          ? 'Offline. $unsynced change(s) will sync when you are back online.'
          : 'Offline';
    } else if (sync.message != null) {
      icon = Icons.warning_amber_rounded;
      tooltip = 'Sync problem: ${sync.message}. Tap to retry.';
    } else if (unsynced > 0) {
      icon = Icons.cloud_upload_outlined;
      tooltip = '$unsynced change(s) waiting to sync. Tap to sync now.';
    } else {
      icon = Icons.cloud_done_outlined;
      tooltip = 'Everything is synced.';
    }

    return IconButton(
      tooltip: tooltip,
      onPressed: sync.running
          ? null
          : () => ref.read(syncControllerProvider.notifier).syncNow(),
      icon: Badge.count(
        count: unsynced,
        isLabelVisible: unsynced > 0,
        child: Icon(icon),
      ),
    );
  }
}
