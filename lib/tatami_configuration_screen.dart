import 'package:flutter/material.dart';

import 'tournament_models.dart';

class TatamiConfigurationScreen extends StatefulWidget {
  final List<TatamiDefinition> tatamiDefinitions;
  final Future<void> Function(List<TatamiDefinition> tatamiDefinitions) onSave;

  const TatamiConfigurationScreen({
    super.key,
    required this.tatamiDefinitions,
    required this.onSave,
  });

  @override
  State<TatamiConfigurationScreen> createState() =>
      _TatamiConfigurationScreenState();
}

class _TatamiConfigurationScreenState extends State<TatamiConfigurationScreen> {
  final List<TextEditingController> _controllers =
      <TextEditingController>[];
  final List<int> _judgeCounts = <int>[];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final source = widget.tatamiDefinitions.isEmpty
        ? const <TatamiDefinition>[TatamiDefinition(name: 'Tatami 1', judgesCount: 5)]
        : widget.tatamiDefinitions;
    for (final definition in source) {
      _controllers.add(TextEditingController(text: definition.name));
      _judgeCounts.add(definition.judgesCount == 3 ? 3 : 5);
    }
  }

  void _addTatami() {
    setState(() {
      _controllers.add(
        TextEditingController(text: 'Tatami ${_controllers.length + 1}'),
      );
      _judgeCounts.add(5);
    });
  }

  void _removeTatami(int index) {
    if (_controllers.length == 1) {
      _showMessage('At least one tatami is required.');
      return;
    }

    setState(() {
      final controller = _controllers.removeAt(index);
      controller.dispose();
      _judgeCounts.removeAt(index);
    });
  }

  Future<void> _save() async {
    final definitions = _controllers.asMap().entries
        .map(
          (entry) => TatamiDefinition(
            name: entry.value.text.trim(),
            judgesCount: _judgeCounts[entry.key],
          ),
        )
        .where((definition) => definition.name.isNotEmpty)
        .toList();

    if (definitions.isEmpty) {
      _showMessage('Enter at least one tatami name.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.onSave(definitions);
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
      });
      _showMessage('Unable to save tatami configuration: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configure Tatamis')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Set tatami names and order',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Tatamis with assigned divisions cannot be removed until those divisions are reassigned.',
          ),
          const SizedBox(height: 16),
          ..._controllers.asMap().entries.map((entry) {
            final index = entry.key;
            final controller = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      enabled: !_isSaving,
                      decoration: InputDecoration(
                        labelText: 'Tatami ${index + 1} Name',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<int>(
                      initialValue: _judgeCounts[index],
                      decoration: const InputDecoration(
                        labelText: 'Judges',
                        border: OutlineInputBorder(),
                      ),
                      items: const [3, 5]
                          .map(
                            (count) => DropdownMenuItem<int>(
                              value: count,
                              child: Text('$count'),
                            ),
                          )
                          .toList(),
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _judgeCounts[index] = value;
                              });
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: _isSaving ? null : () => _removeTatami(index),
                    icon: const Icon(Icons.delete, color: Colors.red),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _isSaving ? null : _addTatami,
              icon: const Icon(Icons.add),
              label: const Text('Add Tatami'),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            child: const Text('Save Tatami Configuration'),
          ),
          if (_isSaving) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}
