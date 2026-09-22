import 'package:flutter/material.dart';

import 'draw_sheet_screen.dart';
import 'tournament_models.dart';

class CompetitionResultsScreen extends StatefulWidget {
  final Division division;
  final List<Competitor> competitors;

  const CompetitionResultsScreen({
    super.key,
    required this.division,
    required this.competitors,
  });

  @override
  State<CompetitionResultsScreen> createState() =>
      _CompetitionResultsScreenState();
}

class _CompetitionResultsScreenState extends State<CompetitionResultsScreen> {
  bool _showNonPlacers = false;

  Map<String, Competitor> get _competitorsById => <String, Competitor>{
    for (final competitor in widget.competitors) competitor.id: competitor,
  };

  List<Competitor> get _nonPlacers {
    final placedIds = widget.division.placements
        .expand((placement) => placement.competitorIds)
        .toSet();
    return widget.competitors
        .where((competitor) => !placedIds.contains(competitor.id))
        .toList();
  }

  String _competitorLabel(String competitorId) {
    final competitor = _competitorsById[competitorId];
    if (competitor == null) {
      return competitorId;
    }
    return '${competitor.number} - ${competitor.name}';
  }

  Future<void> _showDrawSheet() {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DrawSheetScreen(
          division: widget.division,
          competitors: widget.competitors,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Competition Results')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Results: ${widget.division.title}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _showDrawSheet,
              child: const Text('View Draw Sheet'),
            ),
          ),
          const SizedBox(height: 8),
          if (widget.division.placements.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No placements were recorded for this competition.',
                ),
              ),
            )
          else
            ...widget.division.placements.map(
              (placement) => Card(
                child: ListTile(
                  title: Text(placement.placeLabel),
                  subtitle: Text(
                    placement.competitorIds.map(_competitorLabel).join(', '),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _nonPlacers.isEmpty
                ? null
                : () {
                    setState(() {
                      _showNonPlacers = !_showNonPlacers;
                    });
                  },
            child: Text(
              _showNonPlacers
                  ? 'Hide Other Competitors'
                  : 'Show Other Competitors',
            ),
          ),
          if (_showNonPlacers)
            ..._nonPlacers.map(
              (competitor) => Card(
                child: ListTile(
                  title: Text('${competitor.number} - ${competitor.name}'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
