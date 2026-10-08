import 'package:flutter/material.dart';

import 'tournament_models.dart';

class TeamMemberDetails extends StatelessWidget {
  final Division division;
  final String teamId;
  final List<Competitor> competitors;
  final VoidCallback? onViewRoster;
  final Color? foregroundColor;
  final double fontSize;

  const TeamMemberDetails({
    super.key,
    required this.division,
    required this.teamId,
    required this.competitors,
    this.onViewRoster,
    this.foregroundColor,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final team = division.teamById(teamId);
    if (team == null) return const SizedBox.shrink();
    final byId = {
      for (final competitor in competitors) competitor.id: competitor,
    };
    final style = TextStyle(fontSize: fontSize, color: foregroundColor);
    if (team.memberIds.length <= 3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final id in team.memberIds)
            Text(
              byId[id] == null
                  ? 'Missing competitor: $id'
                  : '${byId[id]!.number} - ${byId[id]!.name}',
              style: style,
            ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          label: '${team.memberIds.length} team members',
          child: Container(
            key: ValueKey('team-member-count-$teamId'),
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color:
                    foregroundColor ?? Theme.of(context).colorScheme.onSurface,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Text('${team.memberIds.length}', style: style),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: onViewRoster == null
              ? Text('See draw sheet roster', style: style)
              : TextButton(
                  onPressed: onViewRoster,
                  child: Text('See draw sheet roster', style: style),
                ),
        ),
      ],
    );
  }
}

class TeamRosterPanel extends StatelessWidget {
  final Division division;
  final List<Competitor> competitors;
  final bool printFriendly;

  const TeamRosterPanel({
    super.key,
    required this.division,
    required this.competitors,
    this.printFriendly = false,
  });

  @override
  Widget build(BuildContext context) {
    final byId = {
      for (final competitor in competitors) competitor.id: competitor,
    };
    final style = TextStyle(fontSize: printFriendly ? 11 : 14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Team Rosters', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Table(
          columnWidths: const {0: FixedColumnWidth(100), 1: FlexColumnWidth()},
          border: TableBorder(
            horizontalInside: BorderSide(color: Theme.of(context).dividerColor),
          ),
          children: [
            for (final team in division.teams)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Team ${team.number}${team.name?.trim().isNotEmpty ?? false ? '\n${team.name}' : ''}',
                      style: style,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      team.memberIds
                          .map(
                            (id) => byId[id] == null
                                ? 'Missing competitor: $id'
                                : '${byId[id]!.number} - ${byId[id]!.name}',
                          )
                          .join('\n'),
                      style: style,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class TeamRosterPage extends StatelessWidget {
  final Division division;
  final List<Competitor> competitors;
  const TeamRosterPage({
    super.key,
    required this.division,
    required this.competitors,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(division.competitionLabel)),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: TeamRosterPanel(division: division, competitors: competitors),
    ),
  );
}
