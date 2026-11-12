import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../data/local/database.dart';
import '../../providers.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_status_button.dart';
import 'csv_export.dart';

enum _MenuAction { copyCsv, retryFailed, signOut }

class InventoryListScreen extends ConsumerWidget {
  const InventoryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(inventoryItemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stocktake'),
        actions: [
          const SyncStatusButton(),
          IconButton(
            tooltip: 'Dashboard',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => context.go('/dashboard'),
          ),
          PopupMenuButton<_MenuAction>(
            onSelected: (action) => _handleMenu(context, ref, action),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _MenuAction.copyCsv,
                child: Text('Copy as CSV'),
              ),
              if (AppConfig.hasSupabase)
                const PopupMenuItem(
                  value: _MenuAction.retryFailed,
                  child: Text('Retry failed items'),
                ),
              if (AppConfig.hasSupabase)
                const PopupMenuItem(
                  value: _MenuAction.signOut,
                  child: Text('Sign out'),
                ),
            ],
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search items',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) =>
                      ref.read(searchQueryProvider.notifier).set(value),
                ),
              ),
              Expanded(
                child: items.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) =>
                      Center(child: Text('Something went wrong: $error')),
                  data: (list) {
                    if (list.isEmpty) {
                      final searching = ref
                          .watch(searchQueryProvider)
                          .isNotEmpty;
                      return _EmptyState(searching: searching);
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: list.length,
                      itemBuilder: (context, index) => _ItemTile(
                        key: ValueKey(list[index].id),
                        item: list[index],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/item/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),

  
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        onDestinationSelected: (index) {
          if (index == 0) {
            context.go('/dashboard');
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventory',
          ),
        ],
      ),
    );
  }
}

Future<void> _handleMenu(
  BuildContext context,
  WidgetRef ref,
  _MenuAction action,
) async {
  final repo = ref.read(inventoryRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);

  switch (action) {
    case _MenuAction.copyCsv:
      final items = await repo.watchAll().first;
      await Clipboard.setData(ClipboardData(text: itemsToCsv(items)));
      messenger.showSnackBar(
        SnackBar(content: Text('Copied ${items.length} item(s) as CSV')),
      );

    case _MenuAction.retryFailed:
      await ref
          .read(syncControllerProvider.notifier)
          .syncNow(retryFailed: true);

    case _MenuAction.signOut:
      final unsynced = await repo.watchUnsyncedCount().first;
      if (!context.mounted) return;

      if (unsynced > 0) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sign out?'),
            content: Text(
              '$unsynced change(s) have not synced yet. They stay on this '
              'device and will sync when you sign back in with the same account.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sign out'),
              ),
            ],
          ),
        );

        if (confirmed != true) return;
      }

      await Supabase.instance.client.auth.signOut();
  }
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile({super.key, required this.item});

  final StockItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(inventoryRepositoryProvider);
    final scheme = Theme.of(context).colorScheme;
    final low = item.quantity <= AppConfig.lowStockThreshold;

    final details = [
      '${item.quantity} ${item.unit}',
      if (item.location != null && item.location!.isNotEmpty) item.location!,
    ].join(' · ');

    return Card(
      child: ListTile(
        onTap: () => context.push('/item/${item.id}'),
        title: Text(item.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(details, style: low ? TextStyle(color: scheme.error) : null),
            if (item.syncStatus == SyncStatus.failed && item.lastError != null)
              Text(
                'Sync failed: ${item.lastError}',
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Remove one',
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: item.quantity > 0
                  ? () => repo.save(item.copyWith(quantity: item.quantity - 1))
                  : null,
            ),
            IconButton(
              tooltip: 'Add one',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () =>
                  repo.save(item.copyWith(quantity: item.quantity + 1)),
            ),
            if (AppConfig.hasSupabase) _SyncIcon(status: item.syncStatus),
          ],
        ),
      ),
    );
  }
}

class _SyncIcon extends StatelessWidget {
  const _SyncIcon({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return switch (status) {
      SyncStatus.synced => Tooltip(
        message: 'Synced',
        child: Icon(Icons.cloud_done_outlined, color: scheme.primary),
      ),
      SyncStatus.pending => const Tooltip(
        message: 'Waiting to sync',
        child: Icon(Icons.schedule),
      ),
      SyncStatus.failed => Tooltip(
        message: 'Sync failed',
        child: Icon(Icons.error_outline, color: scheme.error),
      ),
    };
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off : Icons.inventory_2_outlined,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              searching ? 'No items match your search' : 'No items yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (!searching) ...[
              const SizedBox(height: 4),
              const Text('Add your first item. It works without a connection.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.push('/item/new'),
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
