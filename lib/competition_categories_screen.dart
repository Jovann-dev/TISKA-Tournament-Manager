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
  TeamRules _teamRules = const TeamRules();
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
          teamRules: _teamRules,
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

  Future<void> _editTeamRules(CompetitionCategory category) async {
    var rules = category.teamRules;
    final selected = await showDialog<TeamRules>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${category.name} Rules'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(child: _TeamRulesEditor(
            initialRules: rules, onChanged: (value) => rules = value,
          )),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton.icon(onPressed: () => Navigator.pop(context, rules),
            icon: const Icon(Icons.save_outlined), label: const Text('Save')),
        ],
      ),
    );
    if (selected != null && mounted) {
      await _perform(() => widget.onSave(category.copyWith(teamRules: selected)));
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
                      template != CompetitionTemplate.points
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
                if (_template == CompetitionTemplate.flagTeams) ...[
                  const SizedBox(height: 16),
                  _TeamRulesEditor(initialRules: _teamRules,
                    enabled: !_busy, onChanged: (rules) => _teamRules = rules),
                ],
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
                    subtitle: Text(category.template == CompetitionTemplate.flagTeams
                      ? '${category.template.label}\nMembers: ${category.teamRules.minimumMembers}-${category.teamRules.maximumMembers ?? 'None'}'
                      : category.template.label),
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
                    secondary: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (category.template == CompetitionTemplate.flagTeams)
                        IconButton(tooltip: 'Team rules for ${category.name}',
                          onPressed: _busy ? null : () => _editTeamRules(category),
                          icon: const Icon(Icons.settings_outlined)),
                      IconButton(tooltip: 'Remove ${category.name}',
                        onPressed: _busy ? null : () => _removeCategory(category),
                        icon: const Icon(Icons.delete_outline)),
                    ]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamRulesEditor extends StatefulWidget {
  final TeamRules initialRules;
  final bool enabled;
  final void Function(TeamRules) onChanged;
  const _TeamRulesEditor({required this.initialRules, required this.onChanged, this.enabled = true});

  @override
  State<_TeamRulesEditor> createState() => _TeamRulesEditorState();
}

class _TeamRulesEditorState extends State<_TeamRulesEditor> {
  late final TextEditingController _minimum;
  late final TextEditingController _maximum;
  late bool _hasMaximum;
  late bool _shared;
  late bool _names;

  @override
  void initState() {
    super.initState();
    _minimum = TextEditingController(text: '${widget.initialRules.minimumMembers}');
    _maximum = TextEditingController(text: widget.initialRules.maximumMembers?.toString() ?? '');
    _hasMaximum = widget.initialRules.maximumMembers != null;
    _shared = widget.initialRules.allowSharedMembers;
    _names = widget.initialRules.allowNames;
  }

  void _changed() {
    setState(() {});
    widget.onChanged(TeamRules(
      minimumMembers: int.tryParse(_minimum.text) ?? 0,
      maximumMembers: _hasMaximum ? (int.tryParse(_maximum.text) ?? 0) : null,
      allowSharedMembers: _shared, allowNames: _names,
    ));
  }

  @override
  void dispose() {
    _minimum.dispose();
    _maximum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minimum = int.tryParse(_minimum.text) ?? 0;
    final maximum = int.tryParse(_maximum.text) ?? 0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(key: const ValueKey('team-minimum'), controller: _minimum,
        enabled: widget.enabled, keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: 'Minimum Members',
          errorText: minimum < 1 ? 'Minimum must be at least 1.' : null),
        onChanged: (_) => _changed()),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Maximum Team Size'),
        subtitle: !_hasMaximum ? const Text('None') : null, value: _hasMaximum,
        onChanged: !widget.enabled ? null : (value) {
          _hasMaximum = value;
          if (value && _maximum.text.isEmpty) _maximum.text = '$minimum';
          _changed();
        }),
      if (_hasMaximum) TextField(key: const ValueKey('team-maximum'), controller: _maximum,
        enabled: widget.enabled, keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: 'Maximum Members',
          errorText: maximum < minimum ? 'Maximum must be at least the minimum.' : null),
        onChanged: (_) => _changed()),
      SwitchListTile(key: const ValueKey('team-shared-members'), contentPadding: EdgeInsets.zero,
        title: const Text('Competitors May Join Multiple Teams'), value: _shared,
        onChanged: !widget.enabled ? null : (value) { _shared = value; _changed(); }),
      SwitchListTile(key: const ValueKey('team-allow-names'), contentPadding: EdgeInsets.zero,
        title: const Text('Allow Team Names'), value: _names,
        onChanged: !widget.enabled ? null : (value) { _names = value; _changed(); }),
    ]);
  }
}
