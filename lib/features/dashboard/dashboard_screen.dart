import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../domain/inventory_stats.dart';
import '../../providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(allItemsProvider);
    final unsynced = ref.watch(unsyncedCountProvider).value ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (list) {
          final stats = InventoryStats.from(list);
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _StatCard(label: 'Items', value: '${stats.itemCount}'),
                      _StatCard(label: 'Total units', value: '${stats.totalQuantity}'),
                      _StatCard(
                        label: 'Low stock',
                        value: '${stats.lowStock.length}',
                        warn: stats.lowStock.isNotEmpty,
                      ),
                      if (AppConfig.hasSupabase)
                        _StatCard(label: 'Waiting to sync', value: '$unsynced'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Low stock (${AppConfig.lowStockThreshold} or fewer)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (stats.lowStock.isEmpty)
                    const Text('Nothing is running low.')
                  else
                    for (final item in stats.lowStock)
                      ListTile(
                        title: Text(item.name),
                        trailing: Text('${item.quantity} ${item.unit}'),
                        onTap: () => context.push('/item/${item.id}'),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: warn ? scheme.error : null,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
