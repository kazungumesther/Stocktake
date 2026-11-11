import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/local/database.dart';
import '../../providers.dart';

/// Add a new item (no [itemId]) or edit an existing one.
class ItemFormScreen extends ConsumerStatefulWidget {
  const ItemFormScreen({super.key, this.itemId});

  final String? itemId;

  @override
  ConsumerState<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends ConsumerState<ItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _quantity = TextEditingController(text: '0');
  final _unit = TextEditingController(text: 'pcs');
  final _location = TextEditingController();
  final _notes = TextEditingController();

  StockItem? _item;
  bool _loading = false;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    final id = widget.itemId;
    if (id != null) {
      _loading = true;
      _load(id);
    }
  }

  Future<void> _load(String id) async {
    final item = await ref.read(inventoryRepositoryProvider).byId(id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (item == null || item.deletedAt != null) {
        _missing = true;
        return;
      }
      _item = item;
      _name.text = item.name;
      _quantity.text = item.quantity.toString();
      _unit.text = item.unit;
      _location.text = item.location ?? '';
      _notes.text = item.notes ?? '';
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _unit.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _blankToNull(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(inventoryRepositoryProvider);
    final quantity = int.parse(_quantity.text.trim());
    final unit = _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim();

    final existing = _item;
    if (existing == null) {
      await repo.add(
        name: _name.text,
        quantity: quantity,
        unit: unit,
        location: _blankToNull(_location.text),
        notes: _blankToNull(_notes.text),
      );
    } else {
      await repo.save(
        existing.copyWith(
          name: _name.text.trim(),
          quantity: quantity,
          unit: unit,
          location: Value(_blankToNull(_location.text)),
          notes: Value(_blankToNull(_notes.text)),
        ),
      );
    }
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    final item = _item;
    if (item == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(inventoryRepositoryProvider);

    await repo.remove(item.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted ${item.name}'),
        action: SnackBarAction(label: 'Undo', onPressed: () => repo.restore(item.id)),
      ),
    );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.itemId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit item' : 'Add item'),
        actions: [
          if (_item != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _missing
              ? const Center(child: Text('This item no longer exists.'))
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          TextFormField(
                            controller: _name,
                            decoration: const InputDecoration(
                              labelText: 'Name',
                              border: OutlineInputBorder(),
                            ),
                            textCapitalization: TextCapitalization.words,
                            validator: (value) => (value == null || value.trim().isEmpty)
                                ? 'Enter a name'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _quantity,
                                  decoration: const InputDecoration(
                                    labelText: 'Quantity',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  validator: (value) =>
                                      int.tryParse((value ?? '').trim()) == null
                                          ? 'Enter a number'
                                          : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _unit,
                                  decoration: const InputDecoration(
                                    labelText: 'Unit',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _location,
                            decoration: const InputDecoration(
                              labelText: 'Location (optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _notes,
                            decoration: const InputDecoration(
                              labelText: 'Notes (optional)',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _save,
                            child: Text(editing ? 'Save changes' : 'Add item'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
