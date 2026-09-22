import 'package:flutter/material.dart';

import 'competition_results_screen.dart';
import 'draw_sheet_screen.dart';
import 'tournament_models.dart';

class TournamentResultsScreen extends StatefulWidget {
  final List<Division> divisions;
  final List<Competitor> competitors;
  final List<TatamiDefinition> tatamiDefinitions;

  const TournamentResultsScreen({
    super.key,
    required this.divisions,
    required this.competitors,
    required this.tatamiDefinitions,
  });

  @override
  State<TournamentResultsScreen> createState() =>
      _TournamentResultsScreenState();
}

class _TournamentResultsScreenState extends State<TournamentResultsScreen> {
  static const String _allTatamis = 'All tatamis';
  String _selectedTatami = _allTatamis;

  String _formatCompletedAt(int? completedAt) {
    if (completedAt == null) {
      return 'Unknown completion time';
    }
    final timestamp = DateTime.fromMillisecondsSinceEpoch(completedAt);
    final localizations = MaterialLocalizations.of(context);
    final timeOfDay = TimeOfDay.fromDateTime(timestamp);
    final timeLabel = localizations.formatTimeOfDay(timeOfDay);
    return '${timestamp.year}-${_twoDigits(timestamp.month)}-${_twoDigits(timestamp.day)} $timeLabel';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  List<String> get _tatamiFilterValues {
    final values = <String>{
      ...widget.tatamiDefinitions.map((definition) => definition.name),
      ...widget.divisions.map((division) => division.assignedTatamiName),
    }.toList()..sort();
    return <String>[_allTatamis, ...values];
  }

  List<Division> get _completedDivisions {
    final completed = widget.divisions
        .where((division) => division.progress == DivisionProgress.completed)
        .where(
          (division) =>
              _selectedTatami == _allTatamis ||
              division.assignedTatamiName == _selectedTatami,
        )
        .toList();
    completed.sort((left, right) {
      final leftCompleted = left.completedAt ?? 0;
      final rightCompleted = right.completedAt ?? 0;
      return leftCompleted.compareTo(rightCompleted);
    });
    return completed;
  }

  List<Competitor> _divisionCompetitors(Division division) {
    final competitors = widget.competitors
        .where((competitor) => division.competitorIds.contains(competitor.id))
        .toList();
    competitors.sort((left, right) => left.number.compareTo(right.number));
    return competitors;
  }

  Future<void> _showDivisionResults(Division division) {
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

  Future<void> _showDivisionDrawSheet(Division division) {
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

  @override
  Widget build(BuildContext context) {
    final completedDivisions = _completedDivisions;
    final tatamiFilters = _tatamiFilterValues;

    return Scaffold(
      appBar: AppBar(title: const Text('Tournament Results')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.emoji_events_outlined, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Results Archive',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Completed divisions: ${completedDivisions.length}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedTatami,
                      decoration: const InputDecoration(
                        labelText: 'Filter by tatami',
                        border: OutlineInputBorder(),
                      ),
                      items: tatamiFilters
                          .map(
                            (tatamiName) => DropdownMenuItem<String>(
                              value: tatamiName,
                              child: Text(tatamiName),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _selectedTatami = value;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (completedDivisions.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No completed divisions match the selected tatami filter.',
                      ),
                    ),
                  )
                else
                  ...completedDivisions.map(
                    (division) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    division.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tatami: ${division.assignedTatamiName}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Finished: ${_formatCompletedAt(division.completedAt)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Competitors: ${division.competitorIds.length}',
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
                                  onPressed: () =>
                                      _showDivisionResults(division),
                                  child: const Text('View Results'),
                                ),
                                OutlinedButton(
                                  onPressed: () =>
                                      _showDivisionDrawSheet(division),
                                  child: const Text('View Draw Sheet'),
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
