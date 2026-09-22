import 'dart:async';

import 'package:flutter/material.dart';

import 'live_match_state.dart';
import 'tournament_models.dart';

/// Read-only, big-screen friendly view of a single tatami intended for a
/// spectator display or projector. It mirrors what is happening live in the
/// Competition Floor screen: the current match, the next match up, the
/// timer/score for kumite matches, and the final results once a division
/// completes.
class TatamiDisplayScreen extends StatefulWidget {
  final Stream<List<TatamiDefinition>> Function() watchTatamiDefinitions;
  final Stream<List<Division>> Function() watchDivisions;
  final Stream<List<Competitor>> Function() watchCompetitors;
  final Stream<LiveMatchState?> Function(String tatamiName)
  watchLiveMatchState;

  const TatamiDisplayScreen({
    super.key,
    required this.watchTatamiDefinitions,
    required this.watchDivisions,
    required this.watchCompetitors,
    required this.watchLiveMatchState,
  });

  @override
  State<TatamiDisplayScreen> createState() => _TatamiDisplayScreenState();
}

class _TatamiDisplayScreenState extends State<TatamiDisplayScreen> {
  StreamSubscription<List<TatamiDefinition>>? _tatamiDefinitionsSubscription;
  StreamSubscription<List<Division>>? _divisionsSubscription;
  StreamSubscription<List<Competitor>>? _competitorsSubscription;
  StreamSubscription<LiveMatchState?>? _liveStateSubscription;

  List<TatamiDefinition> _tatamiDefinitions = const <TatamiDefinition>[];
  List<Division> _divisions = const <Division>[];
  List<Competitor> _competitors = const <Competitor>[];
  LiveMatchState? _liveState;
  String? _selectedTatamiName;

  @override
  void initState() {
    super.initState();
    _tatamiDefinitionsSubscription = widget.watchTatamiDefinitions().listen((
      definitions,
    ) {
      setState(() {
        _tatamiDefinitions = definitions;
        _selectedTatamiName ??= definitions.isNotEmpty
            ? definitions.first.name
            : null;
        _resubscribeLiveState();
      });
    });
    _divisionsSubscription = widget.watchDivisions().listen((divisions) {
      setState(() {
        _divisions = divisions;
      });
    });
    _competitorsSubscription = widget.watchCompetitors().listen((
      competitors,
    ) {
      setState(() {
        _competitors = competitors;
      });
    });
  }

  void _resubscribeLiveState() {
    _liveStateSubscription?.cancel();
    final tatamiName = _selectedTatamiName;
    if (tatamiName == null) {
      _liveState = null;
      return;
    }
    _liveStateSubscription = widget
        .watchLiveMatchState(tatamiName)
        .listen((state) {
          if (!mounted) {
            return;
          }
          setState(() {
            _liveState = state;
          });
        });
  }

  void _selectTatami(String tatamiName) {
    if (tatamiName == _selectedTatamiName) {
      return;
    }
    setState(() {
      _selectedTatamiName = tatamiName;
      _liveState = null;
      _resubscribeLiveState();
    });
  }

  Map<String, Competitor> get _competitorsById => <String, Competitor>{
    for (final competitor in _competitors) competitor.id: competitor,
  };

  List<Division> get _divisionsForSelectedTatami {
    final tatamiName = _selectedTatamiName;
    if (tatamiName == null) {
      return const <Division>[];
    }
    return _divisions
        .where((division) => division.assignedTatamiName == tatamiName)
        .toList();
  }

  /// The division actively being run on this tatami, matching how the
  /// Competition Floor screen tracks "Start"/"Resume" per division.
  Division? get _runningDivision {
    for (final division in _divisionsForSelectedTatami) {
      if (division.progress == DivisionProgress.running) {
        return division;
      }
    }
    return null;
  }

  /// The most recently finished division for this tatami. Stays on screen
  /// as results until the organizer starts the next queued division.
  Division? get _mostRecentlyCompletedDivision {
    Division? latest;
    for (final division in _divisionsForSelectedTatami) {
      if (division.progress != DivisionProgress.completed) {
        continue;
      }
      if (latest == null ||
          (division.completedAt ?? 0) > (latest.completedAt ?? 0)) {
        latest = division;
      }
    }
    return latest;
  }

  bool get _hasQueuedDivision => _divisionsForSelectedTatami.any(
    (division) => division.progress == DivisionProgress.queued,
  );

  @override
  void dispose() {
    _tatamiDefinitionsSubscription?.cancel();
    _divisionsSubscription?.cancel();
    _competitorsSubscription?.cancel();
    _liveStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runningDivision = _runningDivision;
    final completedDivision = runningDivision == null
        ? _mostRecentlyCompletedDivision
        : null;
    final liveState = _liveState;
    final showingLiveMatch =
        runningDivision != null &&
        liveState != null &&
        liveState.divisionId == runningDivision.id;

    Widget content;
    if (_selectedTatamiName == null) {
      content = const _DisplayPlaceholder(
        icon: Icons.grid_view_rounded,
        title: 'No tatamis configured',
        subtitle: 'Configure tatamis from the home screen first.',
      );
    } else if (runningDivision != null) {
      content = showingLiveMatch
          ? _LiveMatchView(division: runningDivision, liveState: liveState)
          : _DisplayPlaceholder(
              icon: Icons.hourglass_top_rounded,
              title: runningDivision.title,
              subtitle: 'Preparing the next match...',
            );
    } else if (completedDivision != null) {
      content = _LiveResultsView(
        division: completedDivision,
        competitorsById: _competitorsById,
      );
    } else if (_hasQueuedDivision) {
      content = _DisplayPlaceholder(
        icon: Icons.hourglass_top_rounded,
        title: _selectedTatamiName!,
        subtitle: 'Waiting for the organizer to start the next division...',
      );
    } else {
      content = _DisplayPlaceholder(
        icon: Icons.hourglass_top_rounded,
        title: _selectedTatamiName!,
        subtitle: 'Waiting for a division to be assigned...',
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF14161B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1D22),
        foregroundColor: Colors.white,
        title: const Text('Tatami Display'),
        actions: [
          if (_tatamiDefinitions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTatamiName,
                  dropdownColor: const Color(0xFF1B1D22),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  iconEnabledColor: Colors.white,
                  items: _tatamiDefinitions
                      .map(
                        (definition) => DropdownMenuItem<String>(
                          value: definition.name,
                          child: Text(definition.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _selectTatami(value);
                    }
                  },
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: content),
            if (showingLiveMatch) _NextUpRibbon(liveState: liveState),
          ],
        ),
      ),
    );
  }
}

class _DisplayPlaceholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DisplayPlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: Colors.white24),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 18),
          ),
        ],
      ),
    );
  }
}

class _LiveMatchView extends StatelessWidget {
  final Division division;
  final LiveMatchState liveState;

  const _LiveMatchView({required this.division, required this.liveState});

  String _formatSeconds(int totalSeconds) {
    final clamped = totalSeconds < 0 ? 0 : totalSeconds;
    final minutes = (clamped ~/ 60).toString().padLeft(2, '0');
    final seconds = (clamped % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (!liveState.hasCurrentMatch) {
      return const _DisplayPlaceholder(
        icon: Icons.hourglass_top_rounded,
        title: 'Preparing next match',
        subtitle: 'Please stand by.',
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            liveState.divisionTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            liveState.roundLabel ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 18),
          if (liveState.hasTimer) ...[
            _TimerBanner(
              remainingSeconds: liveState.timerRemainingSeconds,
              running: liveState.timerRunning,
              period: liveState.period,
              formatter: _formatSeconds,
            ),
            const SizedBox(height: 18),
          ],
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _CompetitorPanel(
                    competitor: liveState.competitorA!,
                    accentColor: const Color(0xFFB1181A),
                    points: liveState.hasTimer
                        ? liveState.competitorAPoints
                        : null,
                    warningStage: liveState.hasTimer
                        ? liveState.competitorAWarningStage
                        : null,
                  ),
                ),
                const SizedBox(
                  width: 90,
                  child: Center(
                    child: Text(
                      'VS',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _CompetitorPanel(
                    competitor: liveState.competitorB!,
                    accentColor: const Color(0xFF1B4C8F),
                    points: liveState.hasTimer
                        ? liveState.competitorBPoints
                        : null,
                    warningStage: liveState.hasTimer
                        ? liveState.competitorBWarningStage
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width ribbon fixed at the bottom of the display showing who competes
/// after the current match.
class _NextUpRibbon extends StatelessWidget {
  final LiveMatchState liveState;

  const _NextUpRibbon({required this.liveState});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFD9A62A),
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.arrow_forward_rounded, color: Color(0xFF1B1D22)),
          const SizedBox(width: 10),
          const Text(
            'NEXT UP',
            style: TextStyle(
              color: Color(0xFF1B1D22),
              fontWeight: FontWeight.w800,
              fontSize: 15,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              liveState.hasNextMatch
                  ? '${liveState.nextCompetitorA!.number} ${liveState.nextCompetitorA!.name}   vs   '
                        '${liveState.nextCompetitorB!.number} ${liveState.nextCompetitorB!.name}'
                  : 'Final match of the division',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF1B1D22),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimerBanner extends StatelessWidget {
  final int remainingSeconds;
  final bool running;
  final int period;
  final String Function(int) formatter;

  const _TimerBanner({
    required this.remainingSeconds,
    required this.running,
    required this.period,
    required this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1F222A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            running ? Icons.timer_rounded : Icons.pause_circle_outline,
            color: running ? const Color(0xFFD9A62A) : Colors.white38,
          ),
          const SizedBox(width: 12),
          Text(
            formatter(remainingSeconds),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (period > 1) ...[
            const SizedBox(width: 16),
            Text(
              'PERIOD $period',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompetitorPanel extends StatelessWidget {
  final Competitor competitor;
  final Color accentColor;
  final int? points;
  final int? warningStage;

  const _CompetitorPanel({
    required this.competitor,
    required this.accentColor,
    this.points,
    this.warningStage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accentColor.withValues(alpha: 0.85), const Color(0xFF14161B)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'No. ${competitor.number}',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            competitor.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${competitor.belt}${competitor.club.isNotEmpty ? ' • ${competitor.club}' : ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          if (points != null) ...[
            const SizedBox(height: 18),
            Text(
              points.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 54,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Text(
              'POINTS',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                letterSpacing: 2,
              ),
            ),
          ],
          if (warningStage != null && warningStage! > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              alignment: WrapAlignment.center,
              children: List<Widget>.generate(
                warningStage!,
                (_) => const Icon(
                  Icons.warning_rounded,
                  color: Color(0xFFD9A62A),
                  size: 20,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveResultsView extends StatelessWidget {
  final Division division;
  final Map<String, Competitor> competitorsById;

  const _LiveResultsView({
    required this.division,
    required this.competitorsById,
  });

  String _competitorLabel(String competitorId) {
    final competitor = competitorsById[competitorId];
    if (competitor == null) {
      return competitorId;
    }
    return '${competitor.number} - ${competitor.name}';
  }

  Color _medalColor(int index) {
    switch (index) {
      case 0:
        return const Color(0xFFD9A62A);
      case 1:
        return const Color(0xFFC0C4CC);
      case 2:
        return const Color(0xFFB1181A);
      default:
        return Colors.white24;
    }
  }

  List<Competitor> _nonPlacers() {
    final placedIds = division.placements
        .expand((placement) => placement.competitorIds)
        .toSet();
    return competitorsById.values
        .where(
          (competitor) =>
              division.competitorIds.contains(competitor.id) &&
              !placedIds.contains(competitor.id),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final placements = division.placements;
    final nonPlacers = _nonPlacers();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'RESULTS',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            division.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          if (placements.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Text(
                  'No placements were recorded for this competition.',
                  style: TextStyle(color: Colors.white60, fontSize: 16),
                ),
              ),
            )
          else
            ...List.generate(placements.length, (index) {
              final placement = placements[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F222A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _medalColor(index), width: 2),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.emoji_events_rounded,
                      color: _medalColor(index),
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            placement.placeLabel,
                            style: TextStyle(
                              color: _medalColor(index),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            placement.competitorIds
                                .map(_competitorLabel)
                                .join(', '),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          if (nonPlacers.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Also competed',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              nonPlacers
                  .map((competitor) => '${competitor.number} ${competitor.name}')
                  .join(', '),
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Waiting for the next division to start...',
              style: TextStyle(color: Colors.white38, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}
