import 'package:flutter/material.dart';

import 'tournament_local_store.dart';
import 'tournament_models.dart';

class DrawSheetScreen extends StatelessWidget {
  final Division division;
  final List<Competitor> competitors;

  const DrawSheetScreen({
    super.key,
    required this.division,
    required this.competitors,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Division Draw Sheet'),
        actions: [
          IconButton(
            tooltip: 'Save draw sheet snapshot',
            icon: const Icon(Icons.save_alt),
            onPressed: () => _saveSnapshot(context),
          ),
        ],
      ),
      body: DrawSheetContent(division: division, competitors: competitors),
    );
  }

  Future<void> _saveSnapshot(BuildContext context) async {
    final store = TournamentLocalStore();
    final competitorById = <String, Competitor>{
      for (final competitor in competitors) competitor.id: competitor,
    };
    final snapshot = <String, Object?>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'divisionId': division.id,
      'divisionTitle': division.title,
      'division': <String, Object?>{
        'id': division.id,
        'data': division.toMap(),
      },
      'competitors': division.competitorIds.map((competitorId) {
        final competitor = competitorById[competitorId];
        if (competitor == null) {
          return <String, Object?>{
            'id': competitorId,
            'data': const <String, Object?>{},
          };
        }
        return <String, Object?>{
          'id': competitor.id,
          'data': competitor.toMap(),
        };
      }).toList(),
    };

    await store.prependDrawSheetSnapshot(snapshot);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Draw sheet snapshot saved locally.')),
    );
  }
}

class DrawSheetContent extends StatelessWidget {
  final Division division;
  final List<Competitor> competitors;
  final bool printFriendly;

  const DrawSheetContent({
    super.key,
    required this.division,
    required this.competitors,
    this.printFriendly = false,
  });

  @override
  Widget build(BuildContext context) {
    final competitorById = <String, Competitor>{
      for (final competitor in competitors) competitor.id: competitor,
    };
    final orderedCompetitors = division.competitorIds
        .map((id) => competitorById[id])
        .whereType<Competitor>()
        .toList();
    final model = _DrawSheetModel.fromDivision(
      division: division,
      competitors: orderedCompetitors,
    );
    final pageBackground = printFriendly
        ? Colors.white
        : const Color(0xFFF4F5F8);

    return Container(
      color: pageBackground,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: 980,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _HeaderCard(
                        division: division,
                        competitors: orderedCompetitors,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: _ResultsPanel(
                        placements: model.placements,
                        competitorById: model.competitorById,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _BracketPanel(
                        title: 'Main Draw',
                        rounds: model.mainRounds,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 420,
                    child: _BracketPanel(
                      title: 'Repechage',
                      rounds: model.repechageRounds,
                      compact: true,
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

class _HeaderCard extends StatelessWidget {
  final Division division;
  final List<Competitor> competitors;

  const _HeaderCard({required this.division, required this.competitors});

  String _formatTimestamp(int? timestamp) {
    if (timestamp == null) {
      return 'Not completed';
    }
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _square(bool selected) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFD3D3D3) : Colors.white,
        border: Border.all(color: const Color(0xFF111111), width: 1),
      ),
    );
  }

  Widget _sectionTitle(String value) {
    return Text(
      value,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    );
  }

  String _birthYearRange() {
    if (competitors.isEmpty) {
      return '-';
    }
    final years = competitors.map((competitor) {
      final birthDate = competitor.birthDate;
      if (birthDate != null) {
        return birthDate.year;
      }
      return DateTime.now().year - competitor.age;
    }).toList();
    years.sort();
    final minYear = years.first;
    final maxYear = years.last;
    return minYear == maxYear ? '$minYear' : '$minYear-$maxYear';
  }

  bool _isBeltGroupActive(int minRank, int maxRank) {
    return division.maxBeltRank >= minRank && division.minBeltRank <= maxRank;
  }

  bool _isCompetitionSelected(CompetitionType type) {
    return division.competitionType == type;
  }

  @override
  Widget build(BuildContext context) {
    final beltGroups = <({String label, int minRank, int maxRank})>[
      (
        label: 'Kiddies',
        minRank: beltToRank('Kiddies'),
        maxRank: beltToRank('Kiddies'),
      ),
      (
        label: 'White - Yellow',
        minRank: beltToRank('White'),
        maxRank: beltToRank('Yellow'),
      ),
      (
        label: 'Orange - Green',
        minRank: beltToRank('Orange'),
        maxRank: beltToRank('Green'),
      ),
      (
        label: 'Blue - Purple',
        minRank: beltToRank('Blue'),
        maxRank: beltToRank('Purple'),
      ),
      (
        label: 'Red, Brown, Black',
        minRank: beltToRank('Red'),
        maxRank: beltToRank('Black'),
      ),
    ];
    final kumiteTypeRows = <({CompetitionType type, String label})>[
      (
        type: CompetitionType.onTheSpotJodanChudanKumite,
        label: 'On the Spot Jodan & Chudan',
      ),
      (
        type: CompetitionType.steppingJodanChudanKumite,
        label: 'Stepping Jodan & Chudan',
      ),
      (type: CompetitionType.kihonIpponKumite, label: 'Kihon Ippon'),
      (type: CompetitionType.kihonSanbonKumite, label: 'Kihon Sanbon'),
      (type: CompetitionType.jiyuIpponKumite, label: 'Jiyu Ippon'),
      (type: CompetitionType.jiyuKumite, label: 'Jiyu Kumite'),
    ];
    final birthYearRange = _birthYearRange();

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'TISKA DRAW SHEET',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YEAR: $birthYearRange',
                        style: const TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'FLOOR: ${division.assignedTatamiName}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Gender',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _square(
                            division.gender == DivisionGender.maleOnly ||
                                division.gender == DivisionGender.mixed,
                          ),
                          const SizedBox(width: 6),
                          const Text('Male', style: TextStyle(fontSize: 11)),
                          const SizedBox(width: 14),
                          _square(
                            division.gender == DivisionGender.femaleOnly ||
                                division.gender == DivisionGender.mixed,
                          ),
                          const SizedBox(width: 6),
                          const Text('Female', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _sectionTitle('Competition'),
                      const SizedBox(height: 4),
                      for (final row
                          in <({CompetitionType? type, String label})>[
                            (type: CompetitionType.kata, label: 'Kata'),
                            ...kumiteTypeRows,
                          ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  row.label,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              _square(_isCompetitionSelected(row.type!)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('Belt Range'),
                      const SizedBox(height: 4),
                      Text(
                        division.beltRangeLabel,
                        style: const TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 6),
                      for (final group in beltGroups)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  group.label,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              _square(
                                _isBeltGroupActive(
                                  group.minRank,
                                  group.maxRank,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Tatami: ${division.assignedTatamiName}',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(width: 14),
                Text(
                  'Competitors: ${division.competitorIds.length}',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Finished: ${_formatTimestamp(division.completedAt)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BracketPanel extends StatelessWidget {
  final String title;
  final List<_RoundData> rounds;
  final bool compact;

  const _BracketPanel({
    required this.title,
    required this.rounds,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final columnWidth = compact ? 130.0 : 160.0;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFD6DAE3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: rounds.isEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text('No matches available.'),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List<Widget>.generate(rounds.length, (index) {
                      final round = rounds[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          right: index == rounds.length - 1 ? 0 : 16,
                        ),
                        child: SizedBox(
                          width: columnWidth,
                          child: _RoundColumn(
                            round: round,
                            compact: compact,
                            topInset:
                                _topInsetFor(index) +
                                (index > 0 &&
                                        rounds[index - 1]
                                                .loserArrowAfterIndex !=
                                            null
                                    ? 14
                                    : 0),
                            matchGap: _matchGapFor(index),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
      ),
    );
  }

  double _topInsetFor(int roundIndex) {
    final base = compact ? 10.0 : 14.0;
    var inset = base;
    for (var index = 0; index < roundIndex; index++) {
      inset += _roundStrideFor(index) / 2;
    }
    return inset;
  }

  double _matchGapFor(int roundIndex) {
    return _roundStrideFor(roundIndex) - _matchVisualHeight();
  }

  double _roundStrideFor(int roundIndex) {
    final baseStride = _matchVisualHeight() + (compact ? 10.0 : 14.0);
    return baseStride * (1 << roundIndex);
  }

  double _matchVisualHeight() {
    return compact ? 60.0 : 74.0;
  }
}

class _RoundColumn extends StatelessWidget {
  final _RoundData round;
  final bool compact;
  final double topInset;
  final double matchGap;

  const _RoundColumn({
    required this.round,
    required this.compact,
    required this.topInset,
    required this.matchGap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(round.displayLabel, style: Theme.of(context).textTheme.titleSmall),
        SizedBox(height: topInset),
        ...List<Widget>.generate(round.matches.length, (index) {
          final match = round.matches[index];
          final showLoserArrow = round.loserArrowAfterIndex == index;
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == round.matches.length - 1
                  ? 0
                  : matchGap + (showLoserArrow ? 28 : 0),
            ),
            child: Column(
              children: [
                _MatchTile(
                  competitorANumber: match.competitorANumber,
                  competitorBNumber: match.competitorBNumber,
                  topMarker: match.topMarker,
                  bottomMarker: match.bottomMarker,
                  competitorASubscript: match.competitorASubscript,
                  competitorBSubscript: match.competitorBSubscript,
                  details: match.details,
                  compact: compact,
                ),
                if (showLoserArrow) const _LoserFeedArrow(),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _LoserFeedArrow extends StatelessWidget {
  const _LoserFeedArrow();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Loser', style: Theme.of(context).textTheme.bodySmall),
        const Icon(Icons.arrow_downward, size: 16),
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  final String competitorANumber;
  final String competitorBNumber;
  final _MarkerType topMarker;
  final _MarkerType bottomMarker;
  final String? competitorASubscript;
  final String? competitorBSubscript;
  final String? details;
  final bool compact;

  const _MatchTile({
    required this.competitorANumber,
    required this.competitorBNumber,
    required this.topMarker,
    required this.bottomMarker,
    required this.competitorASubscript,
    required this.competitorBSubscript,
    required this.details,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final height = compact ? 22.0 : 26.0;
    final connectorWidth = compact ? 22.0 : 30.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                children: [
                  _CompetitorBox(
                    number: competitorANumber,
                    color: const Color(0xFFFFE5E5),
                    height: height,
                    marker: topMarker,
                  ),
                  if (competitorASubscript != null &&
                      competitorASubscript!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 8,
                        top: 1,
                        bottom: 2,
                      ),
                      child: Text(
                        competitorASubscript!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 9,
                          color: const Color(0xFF3D4453),
                        ),
                      ),
                    ),
                  _CompetitorBox(
                    number: competitorBNumber,
                    color: Colors.white,
                    height: height,
                    marker: bottomMarker,
                  ),
                  if (competitorBSubscript != null &&
                      competitorBSubscript!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 1),
                      child: Text(
                        competitorBSubscript!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 9,
                          color: const Color(0xFF3D4453),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: connectorWidth,
              height: height * 2,
              child: CustomPaint(
                painter: _ConnectorPainter(color: const Color(0xFF8A94A6)),
              ),
            ),
          ],
        ),
        if (details != null && details!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(details!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _CompetitorBox extends StatelessWidget {
  final String number;
  final Color color;
  final double height;
  final _MarkerType marker;

  const _CompetitorBox({
    required this.number,
    required this.color,
    required this.height,
    required this.marker,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: const Color(0xFFB0B6C3)),
        borderRadius: BorderRadius.circular(2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              number.isEmpty ? ' ' : number,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          _MatchMarker(marker: marker),
        ],
      ),
    );
  }
}

class _MatchMarker extends StatelessWidget {
  final _MarkerType marker;

  const _MatchMarker({required this.marker});

  @override
  Widget build(BuildContext context) {
    switch (marker) {
      case _MarkerType.none:
        return const SizedBox(width: 10, height: 10);
      case _MarkerType.winner:
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF303848), width: 1.2),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      case _MarkerType.loser:
        return SizedBox(
          width: 10,
          height: 10,
          child: CustomPaint(
            painter: _CrossPainter(color: const Color(0xFF303848)),
          ),
        );
    }
  }
}

class _ConnectorPainter extends CustomPainter {
  final Color color;

  const _ConnectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final topY = size.height * 0.25;
    final bottomY = size.height * 0.75;
    final midX = size.width * 0.45;
    final rightX = size.width;
    final midY = size.height * 0.5;
    canvas.drawLine(Offset(0, topY), Offset(midX, topY), paint);
    canvas.drawLine(Offset(0, bottomY), Offset(midX, bottomY), paint);
    canvas.drawLine(Offset(midX, topY), Offset(midX, bottomY), paint);
    canvas.drawLine(Offset(midX, midY), Offset(rightX, midY), paint);
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _CrossPainter extends CustomPainter {
  final Color color;

  const _CrossPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      const Offset(1, 1),
      Offset(size.width - 1, size.height - 1),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - 1, 1),
      Offset(1, size.height - 1),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CrossPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ResultsPanel extends StatelessWidget {
  final List<DivisionPlacement> placements;
  final Map<String, Competitor> competitorById;

  const _ResultsPanel({required this.placements, required this.competitorById});

  List<InlineSpan> _winnerSpan(String competitorId) {
    final competitor = competitorById[competitorId];
    if (competitor == null) {
      return <InlineSpan>[TextSpan(text: competitorId)];
    }
    final spans = <InlineSpan>[
      TextSpan(text: '${competitor.number} - ${competitor.name}'),
    ];
    if (competitor.club.trim().isNotEmpty) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: Transform.translate(
            offset: const Offset(0, 2),
            child: Text(
              ' ${competitor.club}',
              style: const TextStyle(fontSize: 9, color: Color(0xFF4A5568)),
            ),
          ),
        ),
      );
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFD6DAE3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Results', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (placements.isEmpty)
              const Text('No placements available.')
            else
              ...placements.map(
                (placement) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          placement.placeLabel,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.only(bottom: 6),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFB0B6C3)),
                            ),
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: placement.competitorIds
                                .map(
                                  (competitorId) => Text.rich(
                                    TextSpan(
                                      children: _winnerSpan(competitorId),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DrawSheetModel {
  final List<_RoundData> mainRounds;
  final List<_RoundData> repechageRounds;
  final List<DivisionPlacement> placements;
  final Map<String, Competitor> competitorById;

  const _DrawSheetModel({
    required this.mainRounds,
    required this.repechageRounds,
    required this.placements,
    required this.competitorById,
  });

  factory _DrawSheetModel.fromDivision({
    required Division division,
    required List<Competitor> competitors,
  }) {
    final byId = <String, Competitor>{
      for (final competitor in competitors) competitor.id: competitor,
    };

    final mainRecords = division.matchRecords
        .where(
          (record) => !record.roundLabel.toLowerCase().startsWith('repechage'),
        )
        .toList();
    final repechageRecords = division.matchRecords
        .where(
          (record) => record.roundLabel.toLowerCase().startsWith('repechage'),
        )
        .toList();
    final repechageCompetitors = competitors.length > 4
        ? _repechageCompetitors(mainRecords, byId)
        : const <Competitor>[];
    final mainRounds = competitors.length == 3
        ? _threeCompetitorRounds(
            division: division,
            competitors: competitors,
            records: mainRecords,
            byId: byId,
          )
        : competitors.length > 3
        ? _plannedBracketRounds(
            competitors: competitors,
            records: mainRecords,
            byId: byId,
            competitionType: division.competitionType,
          )
        : _toRounds(
            mainRecords,
            byId,
            competitors: competitors,
            competitionType: division.competitionType,
            isMain: true,
          );
    final repechageRounds = switch (repechageCompetitors.length) {
      3 => _threeCompetitorRepechageRounds(
        competitors: repechageCompetitors,
        records: repechageRecords,
        byId: byId,
        competitionType: division.competitionType,
      ),
      > 3 => _plannedBracketRounds(
        competitors: repechageCompetitors,
        records: repechageRecords,
        byId: byId,
        competitionType: division.competitionType,
        matchIdPrefix: 'repechage_',
        isRepechage: true,
        includeFinalRound: false,
      ),
      _ => _toRounds(
        repechageRecords,
        byId,
        competitors: competitors,
        competitionType: division.competitionType,
        isMain: false,
      ),
    };

    return _DrawSheetModel(
      mainRounds: mainRounds,
      repechageRounds: repechageRounds,
      placements: division.placements,
      competitorById: byId,
    );
  }

  static List<Competitor> _repechageCompetitors(
    List<DivisionMatchRecord> mainRecords,
    Map<String, Competitor> byId,
  ) {
    final finalRecord = mainRecords.cast<DivisionMatchRecord?>().firstWhere(
      (record) => record?.roundLabel.toLowerCase() == 'final',
      orElse: () => null,
    );
    final finalistIds = finalRecord == null
        ? mainRecords
              .where((record) => record.roundLabel.toLowerCase() == 'semifinal')
              .map((record) => record.winnerId)
              .toList()
        : <String>[finalRecord.competitorAId, finalRecord.competitorBId];
    if (finalistIds.length < 2) {
      return const <Competitor>[];
    }

    final candidates = <Competitor>[];
    final seen = <String>{};
    for (final finalistId in finalistIds) {
      for (final record in mainRecords.reversed) {
        if (record.roundLabel.toLowerCase() == 'final' ||
            record.winnerId != finalistId) {
          continue;
        }
        final opponent = byId[record.loserId];
        if (opponent != null && seen.add(opponent.id)) {
          candidates.add(opponent);
        }
      }
    }
    return candidates;
  }

  static List<_RoundData> _threeCompetitorRepechageRounds({
    required List<Competitor> competitors,
    required List<DivisionMatchRecord> records,
    required Map<String, Competitor> byId,
    required CompetitionType competitionType,
  }) {
    final firstRecord = _recordForId(records, 'repechage_1');
    final validFirstRecord =
        firstRecord != null &&
            _recordMatchesPair(
              firstRecord,
              competitors[0].id,
              competitors[1].id,
            )
        ? firstRecord
        : null;
    final firstLoserId = validFirstRecord?.loserId;
    final secondRecord = _recordForId(records, 'repechage_2');
    final validSecondRecord =
        secondRecord != null &&
            firstLoserId != null &&
            _recordMatchesPair(secondRecord, competitors[2].id, firstLoserId)
        ? secondRecord
        : null;
    final firstMatch = validFirstRecord == null
        ? _plannedMatchData(competitors[0], competitors[1])
        : _matchDataForRecord(validFirstRecord, byId, competitionType);
    final secondMatch = validSecondRecord == null
        ? _plannedMatchData(
            byId[competitors[2].id],
            firstLoserId == null ? null : byId[firstLoserId],
          )
        : _matchDataForRecord(
            validSecondRecord,
            byId,
            competitionType,
            topCompetitorId: competitors[2].id,
            bottomCompetitorId: firstLoserId,
          );

    return <_RoundData>[
      _RoundData(
        label: 'Repechage',
        matches: <_MatchData>[firstMatch, secondMatch],
        loserArrowAfterIndex: 0,
      ),
    ];
  }

  static List<_RoundData> _threeCompetitorRounds({
    required Division division,
    required List<Competitor> competitors,
    required List<DivisionMatchRecord> records,
    required Map<String, Competitor> byId,
  }) {
    final firstRecord = _recordForId(records, 'match_1');
    final validFirstRecord =
        firstRecord != null &&
            _recordMatchesPair(
              firstRecord,
              competitors[0].id,
              competitors[1].id,
            )
        ? firstRecord
        : null;
    final firstWinnerId = validFirstRecord?.winnerId;
    final firstLoserId = validFirstRecord?.loserId;

    final secondRecord = _recordForId(records, 'match_2');
    final validSecondRecord =
        secondRecord != null &&
            firstLoserId != null &&
            _recordMatchesPair(secondRecord, firstLoserId, competitors[2].id)
        ? secondRecord
        : null;
    final secondWinnerId = validSecondRecord?.winnerId;

    final finalRecord = _recordForId(records, 'match_3');
    final validFinalRecord =
        finalRecord != null &&
            firstWinnerId != null &&
            secondWinnerId != null &&
            _recordMatchesPair(finalRecord, firstWinnerId, secondWinnerId)
        ? finalRecord
        : null;

    final firstMatch = validFirstRecord == null
        ? _plannedMatchData(competitors[0], competitors[1])
        : _matchDataForRecord(validFirstRecord, byId, division.competitionType);
    final secondMatch = validSecondRecord == null
        ? _plannedMatchData(
            competitors[2],
            firstLoserId == null ? null : byId[firstLoserId],
          )
        : _matchDataForRecord(
            validSecondRecord,
            byId,
            division.competitionType,
            topCompetitorId: competitors[2].id,
            bottomCompetitorId: firstLoserId,
          );
    final finalMatch = validFinalRecord == null
        ? _plannedMatchData(
            firstWinnerId == null ? null : byId[firstWinnerId],
            secondWinnerId == null ? null : byId[secondWinnerId],
          )
        : _matchDataForRecord(validFinalRecord, byId, division.competitionType);

    return <_RoundData>[
      _RoundData(
        label: 'Semifinal',
        displayLabel: 'Semi-Finals',
        matches: <_MatchData>[firstMatch, secondMatch],
        loserArrowAfterIndex: 0,
      ),
      _RoundData(
        label: 'Final',
        displayLabel: 'Finals',
        matches: <_MatchData>[finalMatch],
      ),
    ];
  }

  static List<_RoundData> _plannedBracketRounds({
    required List<Competitor> competitors,
    required List<DivisionMatchRecord> records,
    required Map<String, Competitor> byId,
    required CompetitionType competitionType,
    String matchIdPrefix = 'match_',
    bool isRepechage = false,
    bool includeFinalRound = true,
  }) {
    final bracketSize = competitors.length == 4
        ? 4
        : competitors.length < 8
        ? 8
        : 16;
    final byeCount = bracketSize - competitors.length;
    final pairedCompetitorCount = competitors.length - byeCount;
    final recordById = <String, DivisionMatchRecord>{
      for (final record in records) record.matchId: record,
    };
    final rounds = <_RoundData>[];
    var matchCounter = 1;

    List<_MatchData> buildRoundMatches(
      List<String?> competitorIds,
      List<String?> nextAdvancers,
    ) {
      final matches = <_MatchData>[];
      for (var index = 0; index < competitorIds.length; index += 2) {
        final competitorAId = competitorIds[index];
        final competitorBId = competitorIds[index + 1];
        final matchId = '$matchIdPrefix$matchCounter';
        matchCounter += 1;

        final record = recordById[matchId];
        final validRecord =
            competitorAId != null &&
                competitorBId != null &&
                record != null &&
                _recordMatchesPair(record, competitorAId, competitorBId)
            ? record
            : null;
        if (validRecord != null) {
          matches.add(_matchDataForRecord(validRecord, byId, competitionType));
          nextAdvancers.add(validRecord.winnerId);
        } else {
          matches.add(
            _plannedMatchData(
              competitorAId == null ? null : byId[competitorAId],
              competitorBId == null ? null : byId[competitorBId],
            ),
          );
          nextAdvancers.add(null);
        }
      }
      return matches;
    }

    final firstRoundAdvancers = <String?>[];
    final firstRoundIds = <String?>[];
    for (var index = 0; index < pairedCompetitorCount; index++) {
      firstRoundIds.add(competitors[index].id);
    }
    for (
      var index = pairedCompetitorCount;
      index < competitors.length;
      index++
    ) {
      firstRoundIds
        ..add(competitors[index].id)
        ..add(null);
    }
    while (firstRoundIds.length < bracketSize) {
      firstRoundIds.add(null);
    }
    final firstRoundMatches = <_MatchData>[];
    for (var index = 0; index < firstRoundIds.length; index += 2) {
      final competitorAId = firstRoundIds[index];
      final competitorBId = firstRoundIds[index + 1];
      if (competitorAId == null || competitorBId == null) {
        final byeCompetitorId = competitorAId ?? competitorBId;
        final byeCompetitor = byeCompetitorId == null
            ? null
            : byId[byeCompetitorId];
        firstRoundMatches.add(
          _plannedMatchData(
            byeCompetitor,
            null,
            topMarker: byeCompetitor == null
                ? _MarkerType.none
                : _MarkerType.winner,
            topSubscript: byeCompetitor == null ? null : 'BYE advance',
            bottomSubscript: byeCompetitor == null ? null : 'BYE',
            winnerNumber: byeCompetitor?.number ?? '',
          ),
        );
        firstRoundAdvancers.add(byeCompetitorId);
        continue;
      }

      final matchId = '$matchIdPrefix$matchCounter';
      matchCounter += 1;
      final record = recordById[matchId];
      final validRecord =
          record != null &&
              _recordMatchesPair(record, competitorAId, competitorBId)
          ? record
          : null;
      if (validRecord != null) {
        firstRoundMatches.add(
          _matchDataForRecord(validRecord, byId, competitionType),
        );
        firstRoundAdvancers.add(validRecord.winnerId);
      } else {
        firstRoundMatches.add(
          _plannedMatchData(byId[competitorAId], byId[competitorBId]),
        );
        firstRoundAdvancers.add(null);
      }
    }

    rounds.add(
      _RoundData(
        label: isRepechage
            ? 'Repechage Round 1'
            : _plannedRoundLabel(bracketSize),
        displayLabel: isRepechage
            ? 'Repechage Round 1'
            : _displayRoundLabel(_plannedRoundLabel(bracketSize)),
        matches: firstRoundMatches,
      ),
    );

    var currentRound = firstRoundAdvancers;
    var roundNumber = 2;
    while (currentRound.length > (includeFinalRound ? 1 : 2)) {
      final nextAdvancers = <String?>[];
      final matches = buildRoundMatches(currentRound, nextAdvancers);
      final roundLabel = _plannedRoundLabel(currentRound.length);
      rounds.add(
        _RoundData(
          label: isRepechage ? 'Repechage Round $roundNumber' : roundLabel,
          displayLabel: isRepechage
              ? 'Repechage Round $roundNumber'
              : _displayRoundLabel(roundLabel),
          matches: matches,
        ),
      );
      currentRound = nextAdvancers;
      roundNumber += 1;
    }

    return rounds;
  }

  static DivisionMatchRecord? _recordForId(
    List<DivisionMatchRecord> records,
    String matchId,
  ) {
    for (final record in records) {
      if (record.matchId == matchId) {
        return record;
      }
    }
    return null;
  }

  static bool _recordMatchesPair(
    DivisionMatchRecord record,
    String competitorAId,
    String competitorBId,
  ) {
    return (record.competitorAId == competitorAId &&
            record.competitorBId == competitorBId) ||
        (record.competitorAId == competitorBId &&
            record.competitorBId == competitorAId);
  }

  static _MatchData _plannedMatchData(
    Competitor? competitorA,
    Competitor? competitorB, {
    _MarkerType topMarker = _MarkerType.none,
    _MarkerType bottomMarker = _MarkerType.none,
    String? topSubscript,
    String? bottomSubscript,
    String winnerNumber = '',
  }) {
    return _MatchData(
      competitorANumber: competitorA?.number ?? '',
      competitorBNumber: competitorB?.number ?? '',
      topMarker: topMarker,
      bottomMarker: bottomMarker,
      competitorASubscript: topSubscript,
      competitorBSubscript: bottomSubscript,
      details: null,
      winnerNumber: winnerNumber,
    );
  }

  static _MatchData _matchDataForRecord(
    DivisionMatchRecord record,
    Map<String, Competitor> byId,
    CompetitionType competitionType, {
    String? topCompetitorId,
    String? bottomCompetitorId,
  }) {
    final topId = topCompetitorId ?? record.competitorAId;
    final bottomId = bottomCompetitorId ?? record.competitorBId;
    return _MatchData(
      competitorANumber: byId[topId]?.number ?? '',
      competitorBNumber: byId[bottomId]?.number ?? '',
      topMarker: record.winnerId == topId
          ? _MarkerType.winner
          : _MarkerType.loser,
      bottomMarker: record.winnerId == bottomId
          ? _MarkerType.winner
          : _MarkerType.loser,
      competitorASubscript: _competitorSubscript(
        record: record,
        competitorId: topId,
        competitionType: competitionType,
      ),
      competitorBSubscript: _competitorSubscript(
        record: record,
        competitorId: bottomId,
        competitionType: competitionType,
      ),
      details: _matchDetails(record),
      winnerNumber: byId[record.winnerId]?.number ?? '',
    );
  }

  static List<_RoundData> _toRounds(
    List<DivisionMatchRecord> records,
    Map<String, Competitor> byId, {
    required List<Competitor> competitors,
    required CompetitionType competitionType,
    required bool isMain,
  }) {
    if (records.isEmpty) {
      return const <_RoundData>[];
    }

    final grouped = <String, List<DivisionMatchRecord>>{};
    for (final record in records) {
      grouped
          .putIfAbsent(record.roundLabel, () => <DivisionMatchRecord>[])
          .add(record);
    }

    final labels = grouped.keys.toList()
      ..sort(
        (a, b) => _roundRank(
          a,
          isMain: isMain,
        ).compareTo(_roundRank(b, isMain: isMain)),
      );

    final rounds = <_RoundData>[];
    List<String?> previousRoundAdvancers = const <String?>[];
    int? previousExpectedMatches;
    for (var labelIndex = 0; labelIndex < labels.length; labelIndex++) {
      final label = labels[labelIndex];
      final roundRecords = grouped[label]!;
      final winnerIds = <String?>[];
      final matchData = roundRecords
          .map(
            (record) => _MatchData(
              competitorANumber: byId[record.competitorAId]?.number ?? '',
              competitorBNumber: byId[record.competitorBId]?.number ?? '',
              topMarker: record.winnerId == record.competitorAId
                  ? _MarkerType.winner
                  : _MarkerType.loser,
              bottomMarker: record.winnerId == record.competitorBId
                  ? _MarkerType.winner
                  : _MarkerType.loser,
              competitorASubscript: _competitorSubscript(
                record: record,
                competitorId: record.competitorAId,
                competitionType: competitionType,
              ),
              competitorBSubscript: _competitorSubscript(
                record: record,
                competitorId: record.competitorBId,
                competitionType: competitionType,
              ),
              details: _matchDetails(record),
              winnerNumber: byId[record.winnerId]?.number ?? '',
            ),
          )
          .toList();
      winnerIds.addAll(roundRecords.map((record) => record.winnerId));

      int? expectedMatches;
      List<String?> byeAdvancers = <String?>[];

      final isFirstMainRound = isMain && labelIndex == 0;
      if (isFirstMainRound && competitors.length > 4) {
        expectedMatches = (competitors.length + 1) ~/ 2;
        if (competitors.length.isOdd) {
          byeAdvancers = <String?>[competitors.last.id];
        }
      } else if (isMain && previousExpectedMatches != null) {
        expectedMatches = (previousExpectedMatches / 2).ceil();
        if (previousRoundAdvancers.length.isOdd &&
            previousRoundAdvancers.isNotEmpty) {
          byeAdvancers = <String?>[previousRoundAdvancers.last];
        }
      }

      if (isMain && expectedMatches != null) {
        while (matchData.length < expectedMatches) {
          final byeCompetitorId = byeAdvancers.isNotEmpty
              ? byeAdvancers.removeAt(0)
              : null;
          final byeCompetitor = byeCompetitorId == null
              ? null
              : byId[byeCompetitorId];
          matchData.add(
            _MatchData(
              competitorANumber: byeCompetitor?.number ?? '',
              competitorBNumber: '',
              topMarker: byeCompetitor == null
                  ? _MarkerType.none
                  : _MarkerType.winner,
              bottomMarker: byeCompetitor == null
                  ? _MarkerType.none
                  : _MarkerType.loser,
              competitorASubscript: byeCompetitor == null
                  ? null
                  : 'BYE advance',
              competitorBSubscript: byeCompetitor == null ? null : 'BYE',
              details: null,
              winnerNumber: byeCompetitor?.number ?? '',
            ),
          );
          winnerIds.add(byeCompetitorId);
        }

        previousExpectedMatches = expectedMatches;
      }

      previousRoundAdvancers = winnerIds;

      if (!isMain) {
        previousExpectedMatches = null;
        previousRoundAdvancers = const <String?>[];
      }

      rounds.add(
        _RoundData(
          label: label,
          displayLabel: _displayRoundLabel(label),
          matches: matchData,
        ),
      );
    }

    return rounds;
  }

  static String? _matchDetails(DivisionMatchRecord record) {
    if (record.finishReason == null) {
      return null;
    }
    return 'Finish: ${record.finishReason!.label}';
  }

  static String? _competitorSubscript({
    required DivisionMatchRecord record,
    required String competitorId,
    required CompetitionType competitionType,
  }) {
    if (competitionType == CompetitionType.jiyuKumite) {
      final symbols = record.events
          .where((event) => event.competitorId == competitorId)
          .map((event) => event.shortLabel)
          .toList();
      if (symbols.isEmpty) {
        return null;
      }
      return symbols.join(' ');
    }

    final isFlagStyle =
        competitionType.executionMode == CompetitionExecutionMode.flagVoting;
    if (isFlagStyle) {
      final flags = competitorId == record.competitorAId
          ? record.competitorAFlags
          : record.competitorBFlags;
      if (flags != null) {
        return 'Flags $flags';
      }
    }
    return null;
  }

  static String _displayRoundLabel(String label) {
    final lower = label.toLowerCase();
    if (lower == 'semifinal' || lower == 'round of 3') {
      return 'Semi-Finals';
    }
    if (lower == 'round of 7') {
      return 'Quarterfinal';
    }
    return label;
  }

  static String _plannedRoundLabel(int roundSize) {
    switch (roundSize) {
      case 2:
        return 'Final';
      case 4:
        return 'Semifinal';
      case 8:
        return 'Quarterfinal';
      default:
        return 'Round of $roundSize';
    }
  }

  static int _roundRank(String label, {required bool isMain}) {
    final lower = label.toLowerCase();
    if (!isMain && lower.startsWith('repechage round')) {
      final number =
          int.tryParse(lower.replaceFirst('repechage round', '').trim()) ?? 999;
      return number;
    }
    if (!isMain && lower == 'repechage final') {
      return 999;
    }
    final effectiveSize = _effectiveRoundSize(lower);
    if (effectiveSize != null) {
      return 5000 - effectiveSize;
    }
    if (lower.startsWith('round of')) {
      final size =
          int.tryParse(lower.replaceFirst('round of', '').trim()) ?? 999;
      if (size == 3) {
        return 5000 - 4;
      }
      if (size == 7) {
        return 5000 - 8;
      }
      return 5000 - size;
    }
    return 200;
  }

  static int? _effectiveRoundSize(String lower) {
    if (lower == 'final') {
      return 2;
    }
    if (lower == 'semifinal') {
      return 4;
    }
    if (lower == 'quarterfinal') {
      return 8;
    }
    if (lower.startsWith('round of')) {
      final size = int.tryParse(lower.replaceFirst('round of', '').trim());
      if (size == null) {
        return null;
      }
      if (size == 3) {
        return 4;
      }
      if (size == 7) {
        return 8;
      }
      return size;
    }
    return null;
  }
}

class _RoundData {
  final String label;
  final String displayLabel;
  final List<_MatchData> matches;
  final int? loserArrowAfterIndex;

  const _RoundData({
    required this.label,
    String? displayLabel,
    required this.matches,
    this.loserArrowAfterIndex,
  }) : displayLabel = displayLabel ?? label;
}

class _MatchData {
  final String competitorANumber;
  final String competitorBNumber;
  final _MarkerType topMarker;
  final _MarkerType bottomMarker;
  final String? competitorASubscript;
  final String? competitorBSubscript;
  final String? details;
  final String winnerNumber;

  const _MatchData({
    required this.competitorANumber,
    required this.competitorBNumber,
    required this.topMarker,
    required this.bottomMarker,
    required this.competitorASubscript,
    required this.competitorBSubscript,
    required this.details,
    required this.winnerNumber,
  });
}

enum _MarkerType { none, winner, loser }
