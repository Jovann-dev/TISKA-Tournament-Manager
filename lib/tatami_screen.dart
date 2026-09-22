import 'package:flutter/material.dart';

import 'competition_execution_screen.dart';
import 'competition_results_screen.dart';
import 'draw_sheet_screen.dart';
import 'live_match_state.dart';
import 'tournament_models.dart';

class TatamiScreen extends StatefulWidget {
  final List<TatamiDefinition> tatamiDefinitions;
  final List<Division> divisions;
  final List<Competitor> competitors;
  final Map<String, List<TatamiLogEntry>> tatamiLogs;
  final Future<void> Function(String tatamiName, String? divisionId) onAssign;
  final Future<void> Function(String divisionId) onDeleteDivision;
  final Future<void> Function(String tatamiName, String divisionId)
  onStartDivision;
  final Future<void> Function(String tatamiName, String divisionId)
  onCompleteDivision;
  final Future<void> Function(String tatamiName, String divisionId)
  onRedoDivision;
  final Future<void> Function(String tatamiName, int judgesCount)
  onUpdateJudgeCount;
  final Future<void> Function(
    String tatamiName,
    String divisionId, {
    required List<DivisionMatchRecord> matchRecords,
    required List<DivisionPlacement> placements,
    String? logMessage,
  })
  onSaveExecutionState;
  final void Function(LiveMatchState state) onPublishLiveState;

  const TatamiScreen({
    super.key,
    required this.tatamiDefinitions,
    required this.divisions,
    required this.competitors,
    required this.tatamiLogs,
    required this.onAssign,
    required this.onDeleteDivision,
    required this.onStartDivision,
    required this.onCompleteDivision,
    required this.onRedoDivision,
    required this.onUpdateJudgeCount,
    required this.onSaveExecutionState,
    required this.onPublishLiveState,
  });

  @override
  State<TatamiScreen> createState() => _TatamiScreenState();
}

class _TatamiScreenState extends State<TatamiScreen> {
  final Set<String> _updatingTatamis = <String>{};
  bool _isDeletingDivision = false;
  late String selectedTatamiName;
  late List<Division> _divisions;

  List<String> get _tatamiNames =>
      widget.tatamiDefinitions.map((definition) => definition.name).toList();

  TatamiDefinition get _selectedTatamiDefinition {
    return widget.tatamiDefinitions.firstWhere(
      (definition) => definition.name == selectedTatamiName,
      orElse: () => const TatamiDefinition(name: 'Tatami 1', judgesCount: 5),
    );
  }

  Future<void> _performTatamiAction(Future<void> Function() action) async {
    if (_updatingTatamis.contains(selectedTatamiName)) {
      return;
    }
    setState(() {
      _updatingTatamis.add(selectedTatamiName);
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update competition state: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingTatamis.remove(selectedTatamiName);
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    selectedTatamiName = widget.tatamiDefinitions.isEmpty
        ? ''
        : widget.tatamiDefinitions.first.name;
    _divisions = List<Division>.from(widget.divisions);
  }

  @override
  void didUpdateWidget(covariant TatamiScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tatamiDefinitions.isEmpty) {
      return;
    }
    if (!_tatamiNames.contains(selectedTatamiName)) {
      setState(() {
        selectedTatamiName = widget.tatamiDefinitions.first.name;
      });
    }
    _divisions = List<Division>.from(widget.divisions);
  }

  void _replaceDivision(Division updatedDivision) {
    final index = _divisions.indexWhere(
      (division) => division.id == updatedDivision.id,
    );
    setState(() {
      if (index == -1) {
        _divisions.add(updatedDivision);
      } else {
        _divisions[index] = updatedDivision;
      }
    });
  }

  void _removeDivisionLocally(String divisionId) {
    setState(() {
      _divisions.removeWhere((division) => division.id == divisionId);
    });
  }

  List<Competitor> _divisionCompetitors(Division division) {
    final divisionCompetitors = widget.competitors
        .where((competitor) => division.competitorIds.contains(competitor.id))
        .toList();
    divisionCompetitors.sort(
      (left, right) => left.number.compareTo(right.number),
    );
    return divisionCompetitors;
  }

  String _formatCompletedAt(int? timestamp) {
    if (timestamp == null) {
      return 'Unknown completion time';
    }
    final completedAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final localizations = MaterialLocalizations.of(context);
    final timeOfDay = TimeOfDay.fromDateTime(completedAt);
    final timeLabel = localizations.formatTimeOfDay(timeOfDay);
    return '${completedAt.year}-${_twoDigits(completedAt.month)}-${_twoDigits(completedAt.day)} $timeLabel';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  Future<void> _redoDivision(Division division) {
    return _performTatamiAction(() async {
      await widget.onRedoDivision(selectedTatamiName, division.id);
      _replaceDivision(
        division.copyWith(
          progress: DivisionProgress.queued,
          startedAt: null,
          completedAt: null,
          priorityBoostedAt: DateTime.now().millisecondsSinceEpoch,
          matchRecords: const <DivisionMatchRecord>[],
          placements: const <DivisionPlacement>[],
        ),
      );
    });
  }

  Future<void> _changeDivisionTatami(Division division) async {
    String candidateTatami = division.assignedTatamiName;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Change Division Tatami'),
              content: DropdownButtonFormField<String>(
                initialValue: candidateTatami,
                decoration: const InputDecoration(
                  labelText: 'Assign to Tatami',
                  border: OutlineInputBorder(),
                ),
                items: _tatamiNames
                    .map(
                      (tatami) => DropdownMenuItem<String>(
                        value: tatami,
                        child: Text(tatami),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setDialogState(() {
                    candidateTatami = value;
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, candidateTatami),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted ||
        selected == null ||
        selected == division.assignedTatamiName) {
      return;
    }

    await _performTatamiAction(() async {
      await widget.onAssign(selected, division.id);
      _replaceDivision(division.copyWith(assignedTatamiName: selected));
    });
  }

  Future<void> _confirmDeleteDivision(Division division) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Division?'),
          content: Text('Delete "${division.title}"? This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isDeletingDivision = true;
    });
    try {
      await widget.onDeleteDivision(division.id);
      if (!mounted) {
        return;
      }
      _removeDivisionLocally(division.id);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to delete division: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingDivision = false;
        });
      }
    }
  }

  Future<void> _updateJudgesCount(int judgesCount) {
    return _performTatamiAction(
      () => widget.onUpdateJudgeCount(selectedTatamiName, judgesCount),
    );
  }

  Future<void> _openExecution(Division division) async {
    final result = await Navigator.push<Division>(
      context,
      MaterialPageRoute(
        builder: (context) => CompetitionExecutionScreen(
          tatamiName: selectedTatamiName,
          division: division,
          competitors: _divisionCompetitors(division),
          judgesCount: _selectedTatamiDefinition.judgesCount,
          onJudgeCountChanged: widget.onUpdateJudgeCount,
          onStartDivision: widget.onStartDivision,
          onCompleteDivision: widget.onCompleteDivision,
          onSaveExecutionState: widget.onSaveExecutionState,
          onPublishLiveState: widget.onPublishLiveState,
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    _replaceDivision(result);
  }

  Future<void> _showResults(Division division) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CompetitionResultsScreen(
          division: division,
          competitors: _divisionCompetitors(division),
        ),
      ),
    );
  }

  Future<void> _showDrawSheet(Division division) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DrawSheetScreen(
          division: division,
          competitors: _divisionCompetitors(division),
        ),
      ),
    );
  }

  void _showTatamiLog() {
    final logEntries =
        widget.tatamiLogs[selectedTatamiName] ?? const <TatamiLogEntry>[];
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$selectedTatamiName Log'),
          content: SizedBox(
            width: 500,
            child: logEntries.isEmpty
                ? const Text('No events recorded yet.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: logEntries.length,
                    separatorBuilder: (_, _) => const Divider(height: 16),
                    itemBuilder: (context, index) {
                      final entry = logEntries[index];
                      final timestamp = DateTime.fromMillisecondsSinceEpoch(
                        entry.timestamp,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.message),
                          const SizedBox(height: 4),
                          Text(
                            '$timestamp',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tatamiDefinitions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Manage Competition')),
        body: const Center(
          child: Text('Configure at least one tatami to manage competition.'),
        ),
      );
    }

    final assignedToSelectedTatami = _divisions
        .where((division) => division.assignedTatamiName == selectedTatamiName)
        .toList();
    final queuedOrRunning = assignedToSelectedTatami
        .where((division) => division.progress != DivisionProgress.completed)
        .toList();
    final completed = assignedToSelectedTatami
        .where((division) => division.progress == DivisionProgress.completed)
        .toList();
    final isUpdating = _updatingTatamis.contains(selectedTatamiName);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Competition'),
        actions: [
          IconButton(
            tooltip: 'View Tatami Log',
            onPressed: _showTatamiLog,
            icon: const Icon(Icons.receipt_long),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1140),
            child: _divisions.isEmpty
                ? const Center(
                    child: Text(
                      'Create divisions before assigning a tatami schedule.',
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.sports_kabaddi_rounded,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Tatami Operations',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Tatamis: ${widget.tatamiDefinitions.length} | Active/Queued: ${queuedOrRunning.length} | Completed: ${completed.length}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Competition control',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: selectedTatamiName,
                                      decoration: const InputDecoration(
                                        labelText: 'Tatami',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: _tatamiNames
                                          .map(
                                            (tatamiName) =>
                                                DropdownMenuItem<String>(
                                                  value: tatamiName,
                                                  child: Text(tatamiName),
                                                ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        if (value != null) {
                                          setState(() {
                                            selectedTatamiName = value;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 140,
                                    child: DropdownButtonFormField<int>(
                                      initialValue:
                                          _selectedTatamiDefinition.judgesCount,
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
                                      onChanged: isUpdating
                                          ? null
                                          : (value) {
                                              if (value != null) {
                                                _updateJudgesCount(value);
                                              }
                                            },
                                    ),
                                  ),
                                ],
                              ),
                              if (isUpdating) ...[
                                const SizedBox(height: 12),
                                const LinearProgressIndicator(),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                'Assigned divisions are prioritized oldest-first. Completed divisions can be redone to move back to the top.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Assigned divisions',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      if (queuedOrRunning.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'No active or queued divisions assigned.',
                            ),
                          ),
                        )
                      else
                        ...queuedOrRunning.map(
                          (division) => Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          division.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${division.ageRangeLabel} | Competitors ${division.competitorIds.length} | ${division.progress.label}',
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _divisionCompetitors(division)
                                              .map(
                                                (c) => '${c.number} ${c.name}',
                                              )
                                              .join(', '),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      ElevatedButton(
                                        onPressed:
                                            isUpdating || _isDeletingDivision
                                            ? null
                                            : () => _openExecution(division),
                                        child: Text(
                                          division.progress ==
                                                  DivisionProgress.running
                                              ? 'Resume'
                                              : 'Start',
                                        ),
                                      ),
                                      OutlinedButton(
                                        onPressed:
                                            isUpdating || _isDeletingDivision
                                            ? null
                                            : () => _changeDivisionTatami(
                                                division,
                                              ),
                                        child: const Text('Change'),
                                      ),
                                      OutlinedButton(
                                        onPressed:
                                            isUpdating || _isDeletingDivision
                                            ? null
                                            : () => _confirmDeleteDivision(
                                                division,
                                              ),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'Completed divisions',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      if (completed.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'No completed divisions for this tatami yet.',
                            ),
                          ),
                        )
                      else
                        ...completed.map(
                          (division) => Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          division.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${division.ageRangeLabel} | Competitors ${division.competitorIds.length} | ${division.progress.label}',
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Finished: ${_formatCompletedAt(division.completedAt)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _divisionCompetitors(division)
                                              .map(
                                                (c) => '${c.number} ${c.name}',
                                              )
                                              .join(', '),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton(
                                        onPressed: () => _showResults(division),
                                        child: const Text('View Results'),
                                      ),
                                      OutlinedButton(
                                        onPressed: () =>
                                            _showDrawSheet(division),
                                        child: const Text('View Draw Sheet'),
                                      ),
                                      ElevatedButton(
                                        onPressed:
                                            isUpdating || _isDeletingDivision
                                            ? null
                                            : () => _redoDivision(division),
                                        child: const Text('Redo'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
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
