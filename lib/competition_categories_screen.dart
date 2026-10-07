import 'dart:async';

import 'package:flutter/material.dart';

import 'tournament_models.dart';

class CompetitionCategoriesScreen extends StatefulWidget {
  final Stream<List<CompetitionCategory>> Function() watchCategories;
  final Future<void> Function(CompetitionCategory) onSave;
  final Future<void> Function(String) onDelete;

  const CompetitionCategoriesScreen({
    super.key,
    required this.watchCategories,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<CompetitionCategoriesScreen> createState() =>
      _CompetitionCategoriesScreenState();
}

class _CompetitionCategoriesScreenState
    extends State<CompetitionCategoriesScreen> {
  final _nameController = TextEditingController();
  CompetitionTemplate _template = CompetitionTemplate.flagVoting;
  List<CompetitionCategory> _categories = [];
  StreamSubscription<List<CompetitionCategory>>? _subscription;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = widget.watchCategories().listen(
      (categories) {
        if (!mounted) return;
        setState(() {
          _categories = categories;
          _error = null;
        });
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = error.toString());
      },
    );
  }

  Future<bool> _perform(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update categories: $error')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createCategory() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a category name.')));
      return;
    }
    final saved = await _perform(
      () => widget.onSave(
        CompetitionCategory(
          id: 'category-${DateTime.now().microsecondsSinceEpoch}',
          name: name,
          template: _template,
        ),
      ),
    );
    if (saved && mounted) _nameController.clear();
  }

  Future<void> _removeCategory(CompetitionCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove competition category?'),
        content: Text(category.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _perform(() => widget.onDelete(category.id));
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Competition Categories')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Competition Templates',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final template in CompetitionTemplate.values)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      template == CompetitionTemplate.flagVoting
                          ? Icons.flag_outlined
                          : Icons.scoreboard_outlined,
                    ),
                    title: Text(template.label),
                  ),
                const Divider(height: 32),
                TextField(
                  key: const ValueKey('competition-category-name'),
                  controller: _nameController,
                  enabled: !_busy,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Category Name'),
                ),
                DropdownButtonFormField<CompetitionTemplate>(
                  initialValue: _template,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Competition Template',
                  ),
                  items: [
                    for (final template in CompetitionTemplate.values)
                      DropdownMenuItem(
                        value: template,
                        child: Text(template.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) setState(() => _template = value);
                        },
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    key: const ValueKey('add-competition-category'),
                    onPressed: _busy ? null : _createCategory,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Category'),
                  ),
                ),
                const Divider(height: 32),
                if (_error != null) Text(_error!),
                Text(
                  'Available Categories',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final category in _categories)
                  CheckboxListTile(
                    key: ValueKey('category-enabled-${category.id}'),
                    contentPadding: EdgeInsets.zero,
                    value: category.enabled,
                    title: Text(category.name),
                    subtitle: Text(category.template.label),
                    onChanged: _busy
                        ? null
                        : (enabled) {
                            if (enabled != null) {
                              _perform(
                                () => widget.onSave(
                                  category.copyWith(enabled: enabled),
                                ),
                              );
                            }
                          },
                    secondary: IconButton(
                      tooltip: 'Remove ${category.name}',
                      onPressed: _busy ? null : () => _removeCategory(category),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
