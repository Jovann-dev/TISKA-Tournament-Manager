import 'dart:async';

import 'package:flutter/material.dart';

import 'competition_results_screen.dart';
import 'live_match_state.dart';
import 'tournament_models.dart';

class CompetitionExecutionScreen extends StatefulWidget {
  final String tatamiName;
  final Division division;
  final List<Competitor> competitors;
  final int judgesCount;
  final Future<void> Function(String tatamiName, int judgesCount)
  onJudgeCountChanged;
  final Future<void> Function(String tatamiName, String divisionId)
  onStartDivision;
  final Future<void> Function(String tatamiName, String divisionId)
  onCompleteDivision;
  final Future<void> Function(
    String tatamiName,
    String divisionId, {
    required List<DivisionMatchRecord> matchRecords,
    required List<DivisionPlacement> placements,
    String? logMessage,
  })
  onSaveExecutionState;
  final void Function(LiveMatchState state) onPublishLiveState;
  final Future<void> Function(
    String tatamiName,
    String divisionId,
    DivisionInProgressMatch? inProgressMatch,
  )
  onSaveInProgressMatch;

  const CompetitionExecutionScreen({
    super.key,
    required this.tatamiName,
    required this.division,
    required this.competitors,
    required this.judgesCount,
    required this.onJudgeCountChanged,
    required this.onStartDivision,
    required this.onCompleteDivision,
    required this.onSaveExecutionState,
    required this.onPublishLiveState,
    required this.onSaveInProgressMatch,
  });

  @override
  State<CompetitionExecutionScreen> createState() =>
      _CompetitionExecutionScreenState();
}

class _CompetitionExecutionScreenState
    extends State<CompetitionExecutionScreen> {
  late final _CompetitionPlan _plan;
  late final List<Competitor> _planCompetitors;
  late final Map<String, Competitor> _competitorsById;
  final Map<String, _RecordedMatch> _results = <String, _RecordedMatch>{};
  final List<_PlannedMatch> _repechageMatches = <_PlannedMatch>[];
  List<_CompetitorSource> _repechageFinalistSources =
      const <_CompetitorSource>[];
  bool _initializing = true;
  bool _isSubmitting = false;
  late int _judgesCount;
  int _competitorAFlags = 0;
  String? _manualWinnerId;
  int _jiyuAPoints = 0;
  int _jiyuBPoints = 0;
  int _jiyuAWarningStage = 0;
  int _jiyuBWarningStage = 0;
  int _jiyuPeriod = 1;
  Duration _jiyuBaseDuration = const Duration(minutes: 1);
  Duration _jiyuTimeRemaining = const Duration(minutes: 1);
  bool _jiyuTimerRunning = false;
  bool _jiyuTimerExpired = false;
  String? _jiyuActiveMatchId;
  DateTime? _jiyuTimerEndsAt;
  Timer? _jiyuTimer;
  final List<DivisionMatchEventRecord> _jiyuEvents =
      <DivisionMatchEventRecord>[];
  DivisionInProgressMatch? _pendingHydrateInProgress;

  @override
  void initState() {
    super.initState();
    _judgesCount = widget.judgesCount == 3 ? 3 : 5;
    _planCompetitors = widget.competitors.length <= 16
        ? List<Competitor>.from(widget.competitors)
        : List<Competitor>.from(widget.competitors.take(16));
    _competitorsById = <String, Competitor>{
      for (final competitor in _planCompetitors) competitor.id: competitor,
    };
    _plan = _CompetitionPlan.build(_planCompetitors);
    _results.addAll(_hydrateRecordedMatches(widget.division.matchRecords));
    _pendingHydrateInProgress = widget.division.inProgressMatch;
    _prepareCompetition();
  }

  Map<String, _RecordedMatch> _hydrateRecordedMatches(
    List<DivisionMatchRecord> records,
  ) {
    final hydrated = <String, _RecordedMatch>{};
    for (final record in records) {
      final planMatch = _matchByIdForHydration(record.matchId, hydrated);
      final competitorA = _competitorsById[record.competitorAId];
      final competitorB = _competitorsById[record.competitorBId];
      final winner = _competitorsById[record.winnerId];
      final loser = _competitorsById[record.loserId];
      if (planMatch == null || competitorA == null || competitorB == null) {
        continue;
      }
      if (winner == null || loser == null) {
        continue;
      }
      hydrated[record.matchId] = _RecordedMatch(
        match: planMatch,
        competitorA: competitorA,
        competitorB: competitorB,
        winner: winner,
        loser: loser,
        competitorAFlags: record.competitorAFlags,
        competitorBFlags: record.competitorBFlags,
        events: record.events,
        competitorAPoints: record.competitorAPoints,
        competitorBPoints: record.competitorBPoints,
        competitorAWarningStage: record.competitorAWarningStage,
        competitorBWarningStage: record.competitorBWarningStage,
        finishReason: record.finishReason,
        reusedPreviousResult: record.reusedPreviousResult,
      );
    }
    return hydrated;
  }

  _PlannedMatch? _matchByIdForHydration(
    String matchId,
    Map<String, _RecordedMatch> hydrated,
  ) {
    _ensureRepechagePlan(hydrated);
    for (final match in _orderedMatchesWithoutPlanUpdates()) {
      if (match.id == matchId) {
        return match;
      }
    }
    return null;
  }

  Future<void> _prepareCompetition() async {
    if (widget.division.progress != DivisionProgress.running) {
      await widget.onStartDivision(widget.tatamiName, widget.division.id);
    }
    await _autoReusePreviousResults();
    if (!mounted) {
      return;
    }
    // Note: _autoReusePreviousResults already prepared the jiyu state (and
    // hydrated any saved in-progress match); don't force-reset it again here.
    setState(() {
      _initializing = false;
    });
    _publishLiveState();
  }

  _ResolvedMatch? get _currentMatch => _currentMatchFrom(_results);

  _ResolvedMatch? _currentMatchFrom(Map<String, _RecordedMatch> results) {
    for (final match in _orderedMatches(results)) {
      if (results.containsKey(match.id)) {
        continue;
      }
      final competitorA = _resolveSource(match.competitorA, results);
      final competitorB = _resolveSource(match.competitorB, results);
      if (competitorA != null && competitorB != null) {
        return _ResolvedMatch(
          match: match,
          competitorA: competitorA,
          competitorB: competitorB,
        );
      }
    }
    return null;
  }

  bool get _isFinished =>
      _orderedMatches(_results).isNotEmpty &&
      _results.length == _orderedMatches(_results).length;

  Competitor? _resolveSource(
    _CompetitorSource source,
    Map<String, _RecordedMatch> results,
  ) {
    switch (source.kind) {
      case _SourceKind.direct:
        return _planCompetitors[source.index!];
      case _SourceKind.directCompetitorId:
        return _competitorsById[source.competitorId!];
      case _SourceKind.winner:
        return results[source.matchId]?.winner;
      case _SourceKind.loser:
        return results[source.matchId]?.loser;
    }
  }

  List<_PlannedMatch> _orderedMatches(Map<String, _RecordedMatch> results) {
    _ensureRepechagePlan(results);
    return _orderedMatchesWithoutPlanUpdates();
  }

  List<_PlannedMatch> _orderedMatchesWithoutPlanUpdates() {
    final finalMatch = _plan.matchById(_plan.finalMatchId);
    if (finalMatch == null) {
      return List<_PlannedMatch>.from(_plan.matches);
    }
    final preFinalMatches = _plan.matches
        .where((match) => match.id != _plan.finalMatchId)
        .toList();
    return <_PlannedMatch>[
      ...preFinalMatches,
      ..._repechageMatches,
      finalMatch,
    ];
  }

  bool get _usesExtendedFlagBracket {
    switch (widget.division.competitionType) {
      case CompetitionType.kata:
      case CompetitionType.onTheSpotJodanChudanKumite:
      case CompetitionType.steppingJodanChudanKumite:
      case CompetitionType.kihonIpponKumite:
      case CompetitionType.kihonSanbonKumite:
      case CompetitionType.jiyuIpponKumite:
        return true;
      case CompetitionType.jiyuKumite:
        return false;
    }
  }

  bool get _isJiyuKumite =>
      widget.division.competitionType == CompetitionType.jiyuKumite;

  void _publishLiveState() {
    final current = _currentMatch;
    final orderedMatches = _orderedMatches(_results);

    String? nextRoundLabel;
    Competitor? nextCompetitorA;
    Competitor? nextCompetitorB;
    if (current != null) {
      final currentIndex = orderedMatches.indexWhere(
        (match) => match.id == current.match.id,
      );
      if (currentIndex != -1 && currentIndex + 1 < orderedMatches.length) {
        final nextPlanned = orderedMatches[currentIndex + 1];
        nextRoundLabel = nextPlanned.roundLabel;
        nextCompetitorA = _resolveSource(nextPlanned.competitorA, _results);
        nextCompetitorB = _resolveSource(nextPlanned.competitorB, _results);
      }
    }

    widget.onPublishLiveState(
      LiveMatchState(
        tatamiName: widget.tatamiName,
        divisionId: widget.division.id,
        divisionTitle: widget.division.title,
        competitionType: widget.division.competitionType,
        executionMode: widget.division.competitionType.executionMode,
        roundLabel: current?.match.roundLabel,
        competitorA: current?.competitorA,
        competitorB: current?.competitorB,
        nextRoundLabel: nextRoundLabel,
        nextCompetitorA: nextCompetitorA,
        nextCompetitorB: nextCompetitorB,
        hasTimer: _isJiyuKumite,
        timerTotalSeconds: _jiyuBaseDuration.inSeconds,
        timerRemainingSeconds: _jiyuTimeRemaining.inSeconds,
        timerRunning: _jiyuTimerRunning,
        timerEndsAtMillis: _jiyuTimerEndsAt?.millisecondsSinceEpoch,
        period: _jiyuPeriod,
        competitorAPoints: _jiyuAPoints,
        competitorBPoints: _jiyuBPoints,
        competitorAWarningStage: _jiyuAWarningStage,
        competitorBWarningStage: _jiyuBWarningStage,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Saves the unfinished jiyu kumite match's points/warnings/timer/events so
  /// they are not lost if the organizer leaves this screen before recording
  /// the match. Not called on every timer tick to avoid excessive writes.
  void _persistInProgressMatch() {
    if (!_isJiyuKumite) {
      return;
    }
    final currentMatch = _currentMatch;
    unawaited(
      widget.onSaveInProgressMatch(
        widget.tatamiName,
        widget.division.id,
        currentMatch == null
            ? null
            : DivisionInProgressMatch(
                matchId: currentMatch.match.id,
                competitorAPoints: _jiyuAPoints,
                competitorBPoints: _jiyuBPoints,
                competitorAWarningStage: _jiyuAWarningStage,
                competitorBWarningStage: _jiyuBWarningStage,
                period: _jiyuPeriod,
                timerRemainingSeconds: _jiyuTimeRemaining.inSeconds,
                events: List<DivisionMatchEventRecord>.from(_jiyuEvents),
              ),
      ),
    );
  }

  void _resetJiyuState({bool clearEvents = true}) {
    _jiyuAPoints = 0;
    _jiyuBPoints = 0;
    _jiyuAWarningStage = 0;
    _jiyuBWarningStage = 0;
    if (clearEvents) {
      _jiyuEvents.clear();
    }
  }

  Duration _defaultJiyuDurationForMatch(_ResolvedMatch match) {
    final blueRank = beltToRank('Blue');
    final highestRank = match.competitorA.beltRank > match.competitorB.beltRank
        ? match.competitorA.beltRank
        : match.competitorB.beltRank;
    if (highestRank <= blueRank) {
      return const Duration(minutes: 1);
    }
    return const Duration(minutes: 1, seconds: 30);
  }

  void _disposeJiyuTimer() {
    _jiyuTimer?.cancel();
    _jiyuTimer = null;
    _jiyuTimerEndsAt = null;
    _jiyuTimerRunning = false;
  }

  void _prepareJiyuStateForCurrentMatch({bool force = false}) {
    if (!_isJiyuKumite) {
      return;
    }
    final currentMatch = _currentMatch;
    if (currentMatch == null) {
      _disposeJiyuTimer();
      _jiyuActiveMatchId = null;
      _resetJiyuState();
      _jiyuPeriod = 1;
      _jiyuBaseDuration = const Duration(minutes: 1);
      _jiyuTimeRemaining = _jiyuBaseDuration;
      _jiyuTimerExpired = false;
      return;
    }
    if (!force && _jiyuActiveMatchId == currentMatch.match.id) {
      return;
    }

    _disposeJiyuTimer();
    _jiyuActiveMatchId = currentMatch.match.id;
    _jiyuPeriod = 1;
    _jiyuBaseDuration = _defaultJiyuDurationForMatch(currentMatch);
    _jiyuTimeRemaining = _jiyuBaseDuration;
    _jiyuTimerExpired = false;
    _resetJiyuState();

    final pending = _pendingHydrateInProgress;
    _pendingHydrateInProgress = null;
    if (pending != null && pending.matchId == currentMatch.match.id) {
      _jiyuAPoints = pending.competitorAPoints;
      _jiyuBPoints = pending.competitorBPoints;
      _jiyuAWarningStage = pending.competitorAWarningStage;
      _jiyuBWarningStage = pending.competitorBWarningStage;
      _jiyuPeriod = pending.period;
      _jiyuEvents
        ..clear()
        ..addAll(pending.events);
      final restoredRemaining = Duration(
        seconds: pending.timerRemainingSeconds,
      );
      _jiyuTimeRemaining = restoredRemaining > Duration.zero
          ? restoredRemaining
          : _jiyuBaseDuration;
      _jiyuTimerExpired = _jiyuTimeRemaining <= Duration.zero;
    }
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _startOrContinueJiyuTimer() {
    if (!_isJiyuKumite || _jiyuTimerRunning) {
      return;
    }
    if (_jiyuTimeRemaining <= Duration.zero) {
      setState(() {
        _jiyuTimerExpired = true;
      });
      return;
    }
    final endsAt = DateTime.now().add(_jiyuTimeRemaining);
    _jiyuTimerEndsAt = endsAt;
    _jiyuTimer?.cancel();
    _jiyuTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final deadline = _jiyuTimerEndsAt;
      if (deadline == null) {
        timer.cancel();
        return;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        setState(() {
          _jiyuTimeRemaining = Duration.zero;
          _jiyuTimerRunning = false;
          _jiyuTimerExpired = true;
          _jiyuTimerEndsAt = null;
        });
        _publishLiveState();
        timer.cancel();
        return;
      }
      setState(() {
        _jiyuTimeRemaining = remaining;
      });
      _publishLiveState();
    });
    setState(() {
      _jiyuTimerRunning = true;
      _jiyuTimerExpired = false;
    });
    _publishLiveState();
    _persistInProgressMatch();
  }

  void _pauseJiyuTimer() {
    if (!_jiyuTimerRunning) {
      return;
    }
    final deadline = _jiyuTimerEndsAt;
    _disposeJiyuTimer();
    setState(() {
      if (deadline != null) {
        final remaining = deadline.difference(DateTime.now());
        _jiyuTimeRemaining = remaining.isNegative ? Duration.zero : remaining;
      }
    });
    _publishLiveState();
    _persistInProgressMatch();
  }

  void _resetJiyuTimerOnly() {
    _disposeJiyuTimer();
    setState(() {
      _jiyuTimeRemaining = _jiyuBaseDuration;
      _jiyuTimerExpired = false;
    });
    _publishLiveState();
    _persistInProgressMatch();
  }

  void _resetJiyuScoreAndWarnings() {
    setState(() {
      _resetJiyuState(clearEvents: false);
      _jiyuEvents.removeWhere((event) => event.period == _jiyuPeriod);
    });
    _publishLiveState();
    _persistInProgressMatch();
  }

  void _startOvertimePeriod() {
    if (!_jiyuTimerExpired) {
      _showMessage('Overtime is available only after the timer reaches 00:00.');
      return;
    }
    _disposeJiyuTimer();
    setState(() {
      _jiyuPeriod += 1;
      _resetJiyuState(clearEvents: false);
      _jiyuTimeRemaining = _jiyuBaseDuration;
      _jiyuTimerExpired = false;
    });
    _publishLiveState();
    _persistInProgressMatch();
  }

  Future<Competitor?> _promptManualJiyuWinner(
    _ResolvedMatch currentMatch,
  ) async {
    final selectedWinnerId = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Match Winner'),
          content: const Text('Scores and warnings are tied. Choose winner.'),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(currentMatch.competitorA.id),
              child: Text(
                '${currentMatch.competitorA.number} ${currentMatch.competitorA.name}',
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(currentMatch.competitorB.id),
              child: Text(
                '${currentMatch.competitorB.number} ${currentMatch.competitorB.name}',
              ),
            ),
          ],
        );
      },
    );
    if (selectedWinnerId == null) {
      return null;
    }
    return selectedWinnerId == currentMatch.competitorA.id
        ? currentMatch.competitorA
        : currentMatch.competitorB;
  }

  Future<void> _endCurrentJiyuMatch() async {
    final currentMatch = _currentMatch;
    if (currentMatch == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this match?'),
        content: Text(
          'Record the result for ${currentMatch.competitorA.name} vs '
          '${currentMatch.competitorB.name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End Match'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    Competitor? winner;
    if (_jiyuAPoints > _jiyuBPoints) {
      winner = currentMatch.competitorA;
    } else if (_jiyuBPoints > _jiyuAPoints) {
      winner = currentMatch.competitorB;
    } else if (_jiyuAWarningStage < _jiyuBWarningStage) {
      winner = currentMatch.competitorA;
    } else if (_jiyuBWarningStage < _jiyuAWarningStage) {
      winner = currentMatch.competitorB;
    } else {
      winner = await _promptManualJiyuWinner(currentMatch);
      if (winner == null) {
        return;
      }
    }

    final loser = winner.id == currentMatch.competitorA.id
        ? currentMatch.competitorB
        : currentMatch.competitorA;
    await _completeJiyuMatch(
      currentMatch: currentMatch,
      winner: winner,
      loser: loser,
      finishReason: KumiteFinishReason.manual,
    );
  }

  int _nextWarningStage(int currentStage) {
    if (currentStage < 3) {
      return currentStage + 1;
    }
    return 3;
  }

  void _undoLastJiyuEvent() {
    final currentMatch = _currentMatch;
    if (currentMatch == null) {
      return;
    }
    final eventIndex = _jiyuEvents.lastIndexWhere(
      (event) => event.period == _jiyuPeriod,
    );
    if (eventIndex == -1) {
      _showMessage('No event is available to undo in this period.');
      return;
    }

    setState(() {
      _jiyuEvents.removeAt(eventIndex);
      _jiyuAPoints = 0;
      _jiyuBPoints = 0;
      _jiyuAWarningStage = 0;
      _jiyuBWarningStage = 0;
      for (final event in _jiyuEvents.where(
        (event) => event.period == _jiyuPeriod,
      )) {
        final isCompetitorA = event.competitorId == currentMatch.competitorA.id;
        if (event.kind == KumiteEventKind.wazaAri ||
            event.kind == KumiteEventKind.ippon) {
          if (isCompetitorA) {
            _jiyuAPoints += event.pointsAwarded;
          } else {
            _jiyuBPoints += event.pointsAwarded;
          }
        } else if (event.kind == KumiteEventKind.warning) {
          final stage = (event.warningStage?.index ?? -1) + 1;
          if (isCompetitorA) {
            _jiyuAWarningStage = stage;
          } else {
            _jiyuBWarningStage = stage;
          }
        }
      }
    });
    _publishLiveState();
    _persistInProgressMatch();
  }

  void _recordJiyuEvent(
    Competitor competitor,
    KumiteEventKind kind, {
    KumiteWarningType? warningType,
  }) {
    final currentMatch = _currentMatch;
    if (currentMatch == null || !_isJiyuKumite) {
      return;
    }

    final isCompetitorA = competitor.id == currentMatch.competitorA.id;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      switch (kind) {
        case KumiteEventKind.wazaAri:
          if (isCompetitorA) {
            _jiyuAPoints += 1;
          } else {
            _jiyuBPoints += 1;
          }
          _jiyuEvents.add(
            DivisionMatchEventRecord(
              competitorId: competitor.id,
              kind: kind,
              timestamp: timestamp,
              pointsAwarded: 1,
              period: _jiyuPeriod,
            ),
          );
          break;
        case KumiteEventKind.ippon:
          if (isCompetitorA) {
            _jiyuAPoints += 2;
          } else {
            _jiyuBPoints += 2;
          }
          _jiyuEvents.add(
            DivisionMatchEventRecord(
              competitorId: competitor.id,
              kind: kind,
              timestamp: timestamp,
              pointsAwarded: 2,
              period: _jiyuPeriod,
            ),
          );
          break;
        case KumiteEventKind.warning:
          final stage = isCompetitorA
              ? _nextWarningStage(_jiyuAWarningStage)
              : _nextWarningStage(_jiyuBWarningStage);
          if (isCompetitorA) {
            _jiyuAWarningStage = stage;
          } else {
            _jiyuBWarningStage = stage;
          }
          _jiyuEvents.add(
            DivisionMatchEventRecord(
              competitorId: competitor.id,
              kind: kind,
              warningType: warningType,
              warningStage: KumiteWarningStage.values[stage - 1],
              timestamp: timestamp,
              period: _jiyuPeriod,
            ),
          );
          break;
        case KumiteEventKind.shikaku:
          _jiyuEvents.add(
            DivisionMatchEventRecord(
              competitorId: competitor.id,
              kind: kind,
              timestamp: timestamp,
              period: _jiyuPeriod,
            ),
          );
          break;
      }
    });
    _publishLiveState();
    _persistInProgressMatch();

    final winnerByWarning = _jiyuAWarningStage >= 3
        ? currentMatch.competitorB
        : _jiyuBWarningStage >= 3
        ? currentMatch.competitorA
        : null;
    final winnerByShikaku = kind == KumiteEventKind.shikaku
        ? (isCompetitorA ? currentMatch.competitorB : currentMatch.competitorA)
        : null;

    final winner = winnerByWarning ?? winnerByShikaku;
    if (winner != null) {
      final loser = winner.id == currentMatch.competitorA.id
          ? currentMatch.competitorB
          : currentMatch.competitorA;
      _completeJiyuMatch(
        currentMatch: currentMatch,
        winner: winner,
        loser: loser,
        finishReason: winnerByWarning != null
            ? KumiteFinishReason.warning
            : KumiteFinishReason.shikaku,
      );
    }
  }

  Future<void> _completeJiyuMatch({
    required _ResolvedMatch currentMatch,
    required Competitor winner,
    required Competitor loser,
    required KumiteFinishReason finishReason,
  }) async {
    final completedRecord = _RecordedMatch(
      match: currentMatch.match,
      competitorA: currentMatch.competitorA,
      competitorB: currentMatch.competitorB,
      winner: winner,
      loser: loser,
      competitorAPoints: _jiyuAPoints,
      competitorBPoints: _jiyuBPoints,
      competitorAWarningStage: _jiyuAWarningStage,
      competitorBWarningStage: _jiyuBWarningStage,
      events: List<DivisionMatchEventRecord>.from(_jiyuEvents),
      finishReason: finishReason,
    );

    setState(() {
      _results[currentMatch.match.id] = completedRecord;
      _prepareJiyuStateForCurrentMatch(force: true);
    });
    _publishLiveState();
    _persistInProgressMatch();
    final enteredSummary =
        '${currentMatch.match.roundLabel} recorded: '
        '${winner.number} ${winner.name} defeated ${loser.number} ${loser.name}.';
    await _autoReusePreviousResults(initialLogMessage: enteredSummary);
  }

  void _ensureRepechagePlan(Map<String, _RecordedMatch> results) {
    if (!_usesExtendedFlagBracket || _planCompetitors.length <= 4) {
      return;
    }
    if (_repechageMatches.isNotEmpty || _repechageFinalistSources.isNotEmpty) {
      return;
    }
    final finalMatch = _plan.matchById(_plan.finalMatchId);
    if (finalMatch == null) {
      return;
    }

    final candidateSources = <_CompetitorSource>[];
    final seen = <String>{};
    final leftOpponents = _collectRankedRepechageOpponentsForFinalSource(
      finalistSource: finalMatch.competitorA,
      results: results,
    );
    final rightOpponents = _collectRankedRepechageOpponentsForFinalSource(
      finalistSource: finalMatch.competitorB,
      results: results,
    );
    for (final competitor in <Competitor>[
      ...leftOpponents,
      ...rightOpponents,
    ]) {
      if (seen.add(competitor.id)) {
        candidateSources.add(
          _CompetitorSource.directCompetitorId(competitor.id),
        );
      }
    }

    if (candidateSources.isEmpty) {
      return;
    }
    if (candidateSources.length <= 2) {
      _repechageFinalistSources = candidateSources;
      return;
    }

    var roundNumber = 1;
    var matchCounter = 1;
    var currentRound = List<_CompetitorSource>.from(candidateSources);
    while (currentRound.length > 2) {
      final nextRound = <_CompetitorSource>[];
      String? previousMatchId;
      var index = 0;
      while (index < currentRound.length) {
        final competitorA = currentRound[index];
        if (index + 1 < currentRound.length) {
          final competitorB = currentRound[index + 1];
          final matchId = 'repechage_$matchCounter';
          matchCounter += 1;
          _repechageMatches.add(
            _PlannedMatch(
              id: matchId,
              roundLabel: 'Repechage Round $roundNumber',
              competitorA: competitorA,
              competitorB: competitorB,
            ),
          );
          nextRound.add(_CompetitorSource.winner(matchId));
          previousMatchId = matchId;
          index += 2;
          continue;
        }

        if (previousMatchId == null) {
          nextRound.add(competitorA);
          index += 1;
          continue;
        }

        final feedInMatchId = 'repechage_$matchCounter';
        matchCounter += 1;
        _repechageMatches.add(
          _PlannedMatch(
            id: feedInMatchId,
            roundLabel: 'Repechage Round $roundNumber',
            competitorA: competitorA,
            competitorB: _CompetitorSource.loser(previousMatchId),
          ),
        );
        nextRound.add(_CompetitorSource.winner(feedInMatchId));
        previousMatchId = feedInMatchId;
        index += 1;
      }
      currentRound = nextRound;
      roundNumber += 1;
    }
    _repechageFinalistSources = currentRound;
  }

  List<Competitor> _collectRankedRepechageOpponentsForFinalSource({
    required _CompetitorSource finalistSource,
    required Map<String, _RecordedMatch> results,
  }) {
    switch (finalistSource.kind) {
      case _SourceKind.winner:
      case _SourceKind.loser:
        final branchRootMatchId = finalistSource.matchId;
        if (branchRootMatchId == null) {
          return const <Competitor>[];
        }
        final finalist = _resolveSource(finalistSource, results);
        if (finalist == null) {
          return const <Competitor>[];
        }
        return _collectRankedRepechageOpponents(
          branchRootMatchId: branchRootMatchId,
          results: results,
        );
      case _SourceKind.direct:
      case _SourceKind.directCompetitorId:
        return const <Competitor>[];
    }
  }

  List<Competitor> _collectRankedRepechageOpponents({
    required String branchRootMatchId,
    required Map<String, _RecordedMatch> results,
  }) {
    final branchWinner = results[branchRootMatchId]?.winner;
    if (branchWinner == null) {
      return const <Competitor>[];
    }
    return _opponentsLostToCompetitorInBranch(
      branchRootMatchId: branchRootMatchId,
      winnerId: branchWinner.id,
      results: results,
    );
  }

  List<Competitor> _opponentsLostToCompetitorInBranch({
    required String branchRootMatchId,
    required String winnerId,
    required Map<String, _RecordedMatch> results,
  }) {
    final rankedOpponents = <Competitor>[];
    final seen = <String>{};

    void collectFromSource(_CompetitorSource source, String competitorId) {
      if (source.kind != _SourceKind.winner &&
          source.kind != _SourceKind.loser) {
        return;
      }
      final sourceMatchId = source.matchId;
      if (sourceMatchId == null) {
        return;
      }
      final sourceResult = results[sourceMatchId];
      if (sourceResult == null) {
        return;
      }

      if (source.kind == _SourceKind.winner &&
          sourceResult.winner.id != competitorId) {
        return;
      }
      if (source.kind == _SourceKind.loser &&
          sourceResult.loser.id != competitorId) {
        return;
      }

      final sourceMatch = sourceResult.match;
      final fromA = sourceResult.competitorA.id == competitorId;
      final opponent = fromA
          ? sourceResult.competitorB
          : sourceResult.competitorA;
      if (seen.add(opponent.id)) {
        rankedOpponents.add(opponent);
      }

      final competitorSource = fromA
          ? sourceMatch.competitorA
          : sourceMatch.competitorB;
      collectFromSource(competitorSource, competitorId);
    }

    final branchResult = results[branchRootMatchId];
    if (branchResult == null) {
      return const <Competitor>[];
    }
    final fromA = branchResult.competitorA.id == winnerId;
    final immediateOpponent = fromA
        ? branchResult.competitorB
        : branchResult.competitorA;
    if (seen.add(immediateOpponent.id)) {
      rankedOpponents.add(immediateOpponent);
    }
    final branchSource = fromA
        ? branchResult.match.competitorA
        : branchResult.match.competitorB;
    collectFromSource(branchSource, winnerId);
    return rankedOpponents;
  }

  Future<void> _updateJudgesCount(int judgesCount) async {
    setState(() {
      _isSubmitting = true;
    });
    try {
      await widget.onJudgeCountChanged(widget.tatamiName, judgesCount);
      if (!mounted) {
        return;
      }
      setState(() {
        _judgesCount = judgesCount == 3 ? 3 : 5;
        if (_competitorAFlags > _judgesCount) {
          _competitorAFlags = _judgesCount;
        }
        if (_competitorAFlags * 2 == _judgesCount) {
          _competitorAFlags = 0;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _redoPreviousMatch() async {
    if (_results.isEmpty) {
      _showMessage('No previous match is available to redo.');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final orderedMatches = _orderedMatches(_results);
      var lastRecordedIndex = -1;
      for (var index = 0; index < orderedMatches.length; index++) {
        if (_results.containsKey(orderedMatches[index].id)) {
          lastRecordedIndex = index;
        }
      }

      if (lastRecordedIndex == -1) {
        _showMessage('No previous match is available to redo.');
        return;
      }

      final targetMatch = orderedMatches[lastRecordedIndex];
      final updatedResults = Map<String, _RecordedMatch>.from(_results);
      for (
        var index = lastRecordedIndex;
        index < orderedMatches.length;
        index++
      ) {
        updatedResults.remove(orderedMatches[index].id);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _results
          ..clear()
          ..addAll(updatedResults);
        _competitorAFlags = 0;
        _manualWinnerId = null;
        _prepareJiyuStateForCurrentMatch(force: true);
      });
      _publishLiveState();
      _persistInProgressMatch();

      await _autoReusePreviousResults(
        initialLogMessage:
            'Previous match reopened: ${targetMatch.roundLabel}.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Unable to redo previous match: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _recordCurrentMatch() async {
    final currentMatch = _currentMatch;
    if (currentMatch == null) {
      return;
    }

    if (_isJiyuKumite) {
      return;
    }

    late Competitor winner;
    late Competitor loser;
    int? competitorAFlags;
    int? competitorBFlags;

    if (widget.division.competitionType.executionMode ==
        CompetitionExecutionMode.flagVoting) {
      competitorAFlags = _competitorAFlags;
      competitorBFlags = _judgesCount - _competitorAFlags;
      if (competitorAFlags == competitorBFlags) {
        _showMessage('A winner is required. Choose a non-tied flag split.');
        return;
      }
      if (competitorAFlags > competitorBFlags) {
        winner = currentMatch.competitorA;
        loser = currentMatch.competitorB;
      } else {
        winner = currentMatch.competitorB;
        loser = currentMatch.competitorA;
      }
    } else {
      final manualWinnerId = _manualWinnerId;
      if (manualWinnerId == null) {
        _showMessage('Select the winner before moving to the next match.');
        return;
      }
      if (manualWinnerId == currentMatch.competitorA.id) {
        winner = currentMatch.competitorA;
        loser = currentMatch.competitorB;
      } else {
        winner = currentMatch.competitorB;
        loser = currentMatch.competitorA;
      }
    }

    setState(() {
      _results[currentMatch.match.id] = _RecordedMatch(
        match: currentMatch.match,
        competitorA: currentMatch.competitorA,
        competitorB: currentMatch.competitorB,
        winner: winner,
        loser: loser,
        competitorAFlags: competitorAFlags,
        competitorBFlags: competitorBFlags,
      );
      _competitorAFlags = 0;
      _manualWinnerId = null;
    });
    _publishLiveState();

    final enteredSummary =
        '${currentMatch.match.roundLabel} recorded: '
        '${winner.number} ${winner.name} defeated ${loser.number} ${loser.name}.';
    await _autoReusePreviousResults(initialLogMessage: enteredSummary);
  }

  Future<void> _autoReusePreviousResults({String? initialLogMessage}) async {
    final updatedResults = Map<String, _RecordedMatch>.from(_results);
    final logMessages = <String>[];
    if (initialLogMessage != null && initialLogMessage.isNotEmpty) {
      logMessages.add(initialLogMessage);
    }

    while (true) {
      final currentMatch = _currentMatchFrom(updatedResults);
      if (currentMatch == null) {
        break;
      }
      final previousResult = _findHeadToHeadResult(
        updatedResults,
        currentMatch.competitorA.id,
        currentMatch.competitorB.id,
      );
      if (previousResult == null) {
        break;
      }
      final reused = _buildReusedResult(currentMatch, previousResult);
      updatedResults[currentMatch.match.id] = reused;
      logMessages.add(
        '${currentMatch.match.roundLabel} reused previous result: '
        '${reused.winner.number} ${reused.winner.name} advances over '
        '${reused.loser.number} ${reused.loser.name}.',
      );
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _results
        ..clear()
        ..addAll(updatedResults);
      _prepareJiyuStateForCurrentMatch(force: true);
    });
    _publishLiveState();
    _persistInProgressMatch();
    await widget.onSaveExecutionState(
      widget.tatamiName,
      widget.division.id,
      matchRecords: _toMatchRecords(updatedResults),
      placements: _buildPlacements(updatedResults),
      logMessage: logMessages.isEmpty ? null : logMessages.join(' '),
    );
  }

  _RecordedMatch? _findHeadToHeadResult(
    Map<String, _RecordedMatch> results,
    String competitorAId,
    String competitorBId,
  ) {
    for (final match in _orderedMatches(results)) {
      final result = results[match.id];
      if (result == null) {
        continue;
      }
      final sameCompetitors =
          (result.competitorA.id == competitorAId &&
              result.competitorB.id == competitorBId) ||
          (result.competitorA.id == competitorBId &&
              result.competitorB.id == competitorAId);
      if (sameCompetitors) {
        return result;
      }
    }
    return null;
  }

  _RecordedMatch _buildReusedResult(
    _ResolvedMatch currentMatch,
    _RecordedMatch previousResult,
  ) {
    final winner = previousResult.winner.id == currentMatch.competitorA.id
        ? currentMatch.competitorA
        : currentMatch.competitorB;
    final loser = winner.id == currentMatch.competitorA.id
        ? currentMatch.competitorB
        : currentMatch.competitorA;

    int? competitorAFlags;
    int? competitorBFlags;
    if (previousResult.competitorAFlags != null &&
        previousResult.competitorBFlags != null) {
      if (previousResult.competitorA.id == currentMatch.competitorA.id) {
        competitorAFlags = previousResult.competitorAFlags;
        competitorBFlags = previousResult.competitorBFlags;
      } else {
        competitorAFlags = previousResult.competitorBFlags;
        competitorBFlags = previousResult.competitorAFlags;
      }
    }

    return _RecordedMatch(
      match: currentMatch.match,
      competitorA: currentMatch.competitorA,
      competitorB: currentMatch.competitorB,
      winner: winner,
      loser: loser,
      competitorAFlags: competitorAFlags,
      competitorBFlags: competitorBFlags,
      events: previousResult.events,
      competitorAPoints: previousResult.competitorAPoints,
      competitorBPoints: previousResult.competitorBPoints,
      competitorAWarningStage: previousResult.competitorAWarningStage,
      competitorBWarningStage: previousResult.competitorBWarningStage,
      finishReason: previousResult.finishReason,
      reusedPreviousResult: true,
    );
  }

  List<DivisionMatchRecord> _toMatchRecords(
    Map<String, _RecordedMatch> results,
  ) {
    final records = <DivisionMatchRecord>[];
    for (final match in _orderedMatches(results)) {
      final result = results[match.id];
      if (result == null) {
        continue;
      }
      records.add(
        DivisionMatchRecord(
          matchId: result.match.id,
          roundLabel: result.match.roundLabel,
          competitorAId: result.competitorA.id,
          competitorBId: result.competitorB.id,
          winnerId: result.winner.id,
          loserId: result.loser.id,
          competitorAFlags: result.competitorAFlags,
          competitorBFlags: result.competitorBFlags,
          events: result.events,
          competitorAPoints: result.competitorAPoints,
          competitorBPoints: result.competitorBPoints,
          competitorAWarningStage: result.competitorAWarningStage,
          competitorBWarningStage: result.competitorBWarningStage,
          finishReason: result.finishReason,
          reusedPreviousResult: result.reusedPreviousResult,
        ),
      );
    }
    return records;
  }

  List<DivisionPlacement> _buildPlacements(
    Map<String, _RecordedMatch> results,
  ) {
    final allMatches = _orderedMatches(results);
    if (allMatches.isEmpty || results.length != allMatches.length) {
      return const <DivisionPlacement>[];
    }

    final finalMatch = results[_plan.finalMatchId];
    if (finalMatch == null) {
      return const <DivisionPlacement>[];
    }

    final thirdPlaceIds = <String>[];
    final seen = <String>{finalMatch.winner.id, finalMatch.loser.id};

    if (_usesExtendedFlagBracket && _planCompetitors.length > 4) {
      for (final source in _repechageFinalistSources) {
        final competitor = _resolveSource(source, results);
        if (competitor == null) {
          continue;
        }
        if (seen.add(competitor.id)) {
          thirdPlaceIds.add(competitor.id);
        }
      }
    } else {
      for (final semifinalMatchId in _plan.semifinalMatchIds) {
        final result = results[semifinalMatchId];
        if (result == null) {
          continue;
        }
        if (seen.add(result.loser.id)) {
          thirdPlaceIds.add(result.loser.id);
        }
      }
    }

    final placements = <DivisionPlacement>[
      DivisionPlacement(
        placeLabel: '1st Place',
        competitorIds: <String>[finalMatch.winner.id],
      ),
      DivisionPlacement(
        placeLabel: '2nd Place',
        competitorIds: <String>[finalMatch.loser.id],
      ),
    ];
    if (thirdPlaceIds.isNotEmpty) {
      placements.add(
        DivisionPlacement(
          placeLabel: thirdPlaceIds.length == 1
              ? '3rd Place'
              : '3rd Place (Joint)',
          competitorIds: thirdPlaceIds,
        ),
      );
    }
    return placements;
  }

  Future<void> _finishCompetition() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete competition?'),
        content: const Text(
          'This records the final placements and marks the division finished.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _isSubmitting = true;
    });
    try {
      final placements = _buildPlacements(_results);
      final matchRecords = _toMatchRecords(_results);
      await widget.onSaveExecutionState(
        widget.tatamiName,
        widget.division.id,
        matchRecords: matchRecords,
        placements: placements,
        logMessage: 'Competition finished with final placements recorded.',
      );
      await widget.onCompleteDivision(widget.tatamiName, widget.division.id);
      await widget.onSaveInProgressMatch(
        widget.tatamiName,
        widget.division.id,
        null,
      );
      if (!mounted) {
        return;
      }
      final completedDivision = widget.division.copyWith(
        progress: DivisionProgress.completed,
        completedAt: DateTime.now().millisecondsSinceEpoch,
        matchRecords: matchRecords,
        placements: placements,
      );
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CompetitionResultsScreen(
            division: completedDivision,
            competitors: widget.competitors,
          ),
        ),
      );
      if (!mounted) {
        return;
      }
      Navigator.pop(context, completedDivision);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Unable to complete competition: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  List<_PlacementGroup> get _placements {
    final placements = _buildPlacements(_results);
    return placements
        .map(
          (placement) => _PlacementGroup(
            placeLabel: placement.placeLabel,
            competitors: placement.competitorIds
                .map((competitorId) => _competitorsById[competitorId])
                .whereType<Competitor>()
                .toList(),
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    _persistInProgressMatch();
    _disposeJiyuTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentMatch = _currentMatch;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.tatamiName} Competition')),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.division.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.division.competitionType.label} | ${_planCompetitors.length} competitors${widget.competitors.length > _planCompetitors.length ? ' (first ${_planCompetitors.length} used)' : ''}',
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.division.competitionType.executionMode ==
                                    CompetitionExecutionMode.flagVoting
                                ? 'Flag voting mode'
                                : 'Manual winner mode',
                          ),
                        ),
                        SizedBox(
                          width: 140,
                          child: DropdownButtonFormField<int>(
                            initialValue: _judgesCount,
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
                            onChanged: _isSubmitting
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
                  ),
                ),
                const SizedBox(height: 16),
                if (currentMatch != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentMatch.match.roundLabel,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${currentMatch.competitorA.number} - ${currentMatch.competitorA.name}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${currentMatch.competitorB.number} - ${currentMatch.competitorB.name}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          if (_isJiyuKumite)
                            _JiyuKumiteEditor(
                              competitorA: currentMatch.competitorA,
                              competitorB: currentMatch.competitorB,
                              pointsA: _jiyuAPoints,
                              pointsB: _jiyuBPoints,
                              warningStageA: _jiyuAWarningStage,
                              warningStageB: _jiyuBWarningStage,
                              currentPeriod: _jiyuPeriod,
                              timerLabel: _formatDuration(_jiyuTimeRemaining),
                              isTimerRunning: _jiyuTimerRunning,
                              timerExpired: _jiyuTimerExpired,
                              events: List<DivisionMatchEventRecord>.from(
                                _jiyuEvents,
                              ),
                              onPointA: (points) => _recordJiyuEvent(
                                currentMatch.competitorA,
                                points == 1
                                    ? KumiteEventKind.wazaAri
                                    : KumiteEventKind.ippon,
                              ),
                              onPointB: (points) => _recordJiyuEvent(
                                currentMatch.competitorB,
                                points == 1
                                    ? KumiteEventKind.wazaAri
                                    : KumiteEventKind.ippon,
                              ),
                              onWarningA: (warningType) => _recordJiyuEvent(
                                currentMatch.competitorA,
                                KumiteEventKind.warning,
                                warningType: warningType,
                              ),
                              onWarningB: (warningType) => _recordJiyuEvent(
                                currentMatch.competitorB,
                                KumiteEventKind.warning,
                                warningType: warningType,
                              ),
                              onShikakuA: () => _recordJiyuEvent(
                                currentMatch.competitorA,
                                KumiteEventKind.shikaku,
                              ),
                              onShikakuB: () => _recordJiyuEvent(
                                currentMatch.competitorB,
                                KumiteEventKind.shikaku,
                              ),
                              onStartOrContinueTimer: _startOrContinueJiyuTimer,
                              onPauseTimer: _pauseJiyuTimer,
                              onResetTimer: _resetJiyuTimerOnly,
                              onResetScoreAndWarnings:
                                  _resetJiyuScoreAndWarnings,
                              onUndoLastEvent: _undoLastJiyuEvent,
                              onEndMatch: _endCurrentJiyuMatch,
                              onOvertime: _startOvertimePeriod,
                            )
                          else if (widget
                                  .division
                                  .competitionType
                                  .executionMode ==
                              CompetitionExecutionMode.flagVoting)
                            _FlagVotingEditor(
                              judgesCount: _judgesCount,
                              competitorAName: currentMatch.competitorA.name,
                              competitorBName: currentMatch.competitorB.name,
                              competitorAFlags: _competitorAFlags,
                              onChanged: (value) {
                                setState(() {
                                  _competitorAFlags = value;
                                });
                              },
                            )
                          else
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Select winner'),
                                const SizedBox(height: 8),
                                SegmentedButton<String>(
                                  segments: [
                                    ButtonSegment<String>(
                                      value: currentMatch.competitorA.id,
                                      label: Text(
                                        currentMatch.competitorA.name,
                                      ),
                                    ),
                                    ButtonSegment<String>(
                                      value: currentMatch.competitorB.id,
                                      label: Text(
                                        currentMatch.competitorB.name,
                                      ),
                                    ),
                                  ],
                                  selected: _manualWinnerId == null
                                      ? const <String>{}
                                      : <String>{_manualWinnerId!},
                                  onSelectionChanged: (selection) {
                                    setState(() {
                                      _manualWinnerId = selection.isEmpty
                                          ? null
                                          : selection.first;
                                    });
                                  },
                                ),
                              ],
                            ),
                          if (!_isJiyuKumite) ...[
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : _recordCurrentMatch,
                              child: Text(
                                _results.length + 1 ==
                                        _orderedMatches(_results).length
                                    ? 'Record Final Result'
                                    : 'Next Match',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else if (_isFinished)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Placements',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          ..._placements.map(
                            (placement) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                '${placement.placeLabel}: ${placement.competitors.map((competitor) => '${competitor.number} - ${competitor.name}').join(', ')}',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _isSubmitting
                                ? null
                                : _finishCompetition,
                            child: const Text('Complete Competition'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Competition bracket could not be created.'),
                    ),
                  ),
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _isSubmitting ? null : _redoPreviousMatch,
                      icon: const Icon(Icons.replay),
                      label: const Text('Redo Previous Match'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Recorded matches',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (_results.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No matches recorded yet.'),
                    ),
                  )
                else
                  ..._orderedMatches(
                    _results,
                  ).where((match) => _results.containsKey(match.id)).map((
                    match,
                  ) {
                    final result = _results[match.id]!;
                    final summary = result.competitorAFlags == null
                        ? 'Winner: ${result.winner.name}'
                        : '${result.competitorA.name} ${result.competitorAFlags} - ${result.competitorBFlags} ${result.competitorB.name}';
                    final reusedNote = result.reusedPreviousResult
                        ? ' (reused previous result)'
                        : '';
                    return Card(
                      child: ListTile(
                        title: Text('${match.roundLabel}$reusedNote'),
                        subtitle: Text(summary),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

class _FlagVotingEditor extends StatefulWidget {
  final int judgesCount;
  final String competitorAName;
  final String competitorBName;
  final int competitorAFlags;
  final ValueChanged<int> onChanged;

  const _FlagVotingEditor({
    required this.judgesCount,
    required this.competitorAName,
    required this.competitorBName,
    required this.competitorAFlags,
    required this.onChanged,
  });

  @override
  State<_FlagVotingEditor> createState() => _FlagVotingEditorState();
}

class _FlagVotingEditorState extends State<_FlagVotingEditor> {
  late final TextEditingController _shiroController;
  late final TextEditingController _akaController;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _shiroController = TextEditingController(
      text: widget.competitorAFlags.toString(),
    );
    _akaController = TextEditingController(
      text: (widget.judgesCount - widget.competitorAFlags).toString(),
    );
  }

  @override
  void didUpdateWidget(covariant _FlagVotingEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.competitorAFlags != widget.competitorAFlags ||
        oldWidget.judgesCount != widget.judgesCount) {
      _syncControllers(widget.competitorAFlags);
    }
  }

  @override
  void dispose() {
    _shiroController.dispose();
    _akaController.dispose();
    super.dispose();
  }

  void _syncControllers(int shiroFlags) {
    final clampedShiro = shiroFlags.clamp(0, widget.judgesCount);
    final akaFlags = widget.judgesCount - clampedShiro;
    _isSyncing = true;
    _shiroController.value = TextEditingValue(
      text: clampedShiro.toString(),
      selection: TextSelection.collapsed(
        offset: clampedShiro.toString().length,
      ),
    );
    _akaController.value = TextEditingValue(
      text: akaFlags.toString(),
      selection: TextSelection.collapsed(offset: akaFlags.toString().length),
    );
    _isSyncing = false;
  }

  void _updateFromShiro(String value) {
    if (_isSyncing) {
      return;
    }
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      return;
    }
    final clamped = parsed.clamp(0, widget.judgesCount);
    _syncControllers(clamped);
    widget.onChanged(clamped);
  }

  void _updateFromAka(String value) {
    if (_isSyncing) {
      return;
    }
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      return;
    }
    final clamped = parsed.clamp(0, widget.judgesCount);
    final shiroFlags = widget.judgesCount - clamped;
    _syncControllers(shiroFlags);
    widget.onChanged(shiroFlags);
  }

  Widget _buildSideField({
    required BuildContext context,
    required String title,
    required String sideLabel,
    required String competitorName,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    required Color accentColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFB0B6C3)),
          borderRadius: BorderRadius.circular(6),
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: accentColor, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(sideLabel),
            const SizedBox(height: 2),
            Text(competitorName, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                hintText: '0 - ${widget.judgesCount}',
              ),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shiroFlags = int.tryParse(_shiroController.text.trim()) ?? 0;
    final akaFlags = widget.judgesCount - shiroFlags;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSideField(
              context: context,
              title: 'Shiro',
              sideLabel: 'White - Left',
              competitorName: widget.competitorAName,
              controller: _shiroController,
              onChanged: _updateFromShiro,
              accentColor: const Color(0xFF314E8A),
            ),
            const SizedBox(width: 12),
            _buildSideField(
              context: context,
              title: 'Aka',
              sideLabel: 'Red - Right',
              competitorName: widget.competitorBName,
              controller: _akaController,
              onChanged: _updateFromAka,
              accentColor: const Color(0xFFB03030),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Shiro: $shiroFlags   Aka: $akaFlags'),
        if (shiroFlags * 2 == widget.judgesCount)
          Text(
            'Tie scores are not valid. Select a majority winner.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

class _JiyuKumiteEditor extends StatelessWidget {
  final Competitor competitorA;
  final Competitor competitorB;
  final int pointsA;
  final int pointsB;
  final int warningStageA;
  final int warningStageB;
  final int currentPeriod;
  final String timerLabel;
  final bool isTimerRunning;
  final bool timerExpired;
  final List<DivisionMatchEventRecord> events;
  final ValueChanged<int> onPointA;
  final ValueChanged<int> onPointB;
  final ValueChanged<KumiteWarningType> onWarningA;
  final ValueChanged<KumiteWarningType> onWarningB;
  final VoidCallback onShikakuA;
  final VoidCallback onShikakuB;
  final VoidCallback onStartOrContinueTimer;
  final VoidCallback onPauseTimer;
  final VoidCallback onResetTimer;
  final VoidCallback onResetScoreAndWarnings;
  final VoidCallback onUndoLastEvent;
  final Future<void> Function() onEndMatch;
  final VoidCallback onOvertime;

  const _JiyuKumiteEditor({
    required this.competitorA,
    required this.competitorB,
    required this.pointsA,
    required this.pointsB,
    required this.warningStageA,
    required this.warningStageB,
    required this.currentPeriod,
    required this.timerLabel,
    required this.isTimerRunning,
    required this.timerExpired,
    required this.events,
    required this.onPointA,
    required this.onPointB,
    required this.onWarningA,
    required this.onWarningB,
    required this.onShikakuA,
    required this.onShikakuB,
    required this.onStartOrContinueTimer,
    required this.onPauseTimer,
    required this.onResetTimer,
    required this.onResetScoreAndWarnings,
    required this.onUndoLastEvent,
    required this.onEndMatch,
    required this.onOvertime,
  });

  bool _canWarn(int currentStage, int targetStage) {
    return currentStage == targetStage - 1;
  }

  /// Same chronological symbol sequence used in the draw sheet subscripts.
  String _symbolsFor(String competitorId) {
    return events
        .where((event) => event.competitorId == competitorId)
        .map((event) => event.shortLabel)
        .join(' ');
  }

  Widget _buildCompetitorBlock(
    BuildContext context, {
    required Competitor competitor,
    required int points,
    required int warningStage,
    required ValueChanged<int> onPoint,
    required ValueChanged<KumiteWarningType> onWarning,
    required VoidCallback onShikaku,
  }) {
    final stageLabels = <String>['Keikoku', 'Chui', 'Hansoku'];
    final warningButtons = <Map<String, Object>>[
      {'label': 'JK', 'type': KumiteWarningType.jogai, 'stage': 1},
      {'label': 'MK', 'type': KumiteWarningType.mobobi, 'stage': 1},
      {'label': 'CK', 'type': KumiteWarningType.contact, 'stage': 1},
      {'label': 'JC', 'type': KumiteWarningType.jogai, 'stage': 2},
      {'label': 'MC', 'type': KumiteWarningType.mobobi, 'stage': 2},
      {'label': 'CC', 'type': KumiteWarningType.contact, 'stage': 2},
      {'label': 'JH', 'type': KumiteWarningType.jogai, 'stage': 3},
      {'label': 'MH', 'type': KumiteWarningType.mobobi, 'stage': 3},
      {'label': 'CH', 'type': KumiteWarningType.contact, 'stage': 3},
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${competitor.number} - ${competitor.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('Points: $points'),
                const SizedBox(width: 12),
                Text(
                  warningStage == 0
                      ? 'Warnings: none'
                      : 'Warnings: ${stageLabels[warningStage - 1]}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => onPoint(1),
                  child: const Text('Waza-ari'),
                ),
                ElevatedButton(
                  onPressed: () => onPoint(2),
                  child: const Text('Ippon'),
                ),
                ...warningButtons.map((button) {
                  final label = button['label'] as String;
                  final type = button['type'] as KumiteWarningType;
                  final stage = button['stage'] as int;
                  return OutlinedButton(
                    onPressed: _canWarn(warningStage, stage)
                        ? () => onWarning(type)
                        : null,
                    child: Text(label),
                  );
                }),
                TextButton(onPressed: onShikaku, child: const Text('Shikaku')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _symbolsFor(competitor.id).isEmpty
                  ? 'Symbols: none yet'
                  : 'Symbols: ${_symbolsFor(competitor.id)}',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentPeriod == 1
                      ? 'Regulation Time'
                      : 'Overtime $currentPeriod',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Timer: $timerLabel',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: onStartOrContinueTimer,
                      child: Text(
                        isTimerRunning ? 'Running...' : 'Start/Continue',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: isTimerRunning ? onPauseTimer : null,
                      child: const Text('Pause'),
                    ),
                    OutlinedButton(
                      onPressed: onResetTimer,
                      child: const Text('Reset Time'),
                    ),
                    OutlinedButton(
                      onPressed: onResetScoreAndWarnings,
                      child: const Text('Reset Score/Warnings'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          events.any((event) => event.period == currentPeriod)
                          ? onUndoLastEvent
                          : null,
                      icon: const Icon(Icons.undo_rounded),
                      label: const Text('Undo Last Event'),
                    ),
                    FilledButton(
                      onPressed: onEndMatch,
                      child: const Text('End Match'),
                    ),
                    if (timerExpired)
                      FilledButton.tonal(
                        onPressed: onOvertime,
                        child: const Text('Overtime'),
                      ),
                  ],
                ),
                if (timerExpired)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Time has expired. Start overtime or end the match.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildCompetitorBlock(
          context,
          competitor: competitorA,
          points: pointsA,
          warningStage: warningStageA,
          onPoint: onPointA,
          onWarning: onWarningA,
          onShikaku: onShikakuA,
        ),
        const SizedBox(height: 12),
        _buildCompetitorBlock(
          context,
          competitor: competitorB,
          points: pointsB,
          warningStage: warningStageB,
          onPoint: onPointB,
          onWarning: onWarningB,
          onShikaku: onShikakuB,
        ),
      ],
    );
  }
}

class _CompetitionPlan {
  final List<_PlannedMatch> matches;
  final String finalMatchId;
  final List<String> semifinalMatchIds;

  const _CompetitionPlan({
    required this.matches,
    required this.finalMatchId,
    required this.semifinalMatchIds,
  });

  _PlannedMatch? matchById(String matchId) {
    for (final match in matches) {
      if (match.id == matchId) {
        return match;
      }
    }
    return null;
  }

  factory _CompetitionPlan.build(List<Competitor> competitors) {
    if (competitors.length < 2) {
      return const _CompetitionPlan(
        matches: <_PlannedMatch>[],
        finalMatchId: '',
        semifinalMatchIds: <String>[],
      );
    }
    final matches = <_PlannedMatch>[];
    final semifinalIds = <String>[];
    var matchCounter = 1;
    List<_CompetitorSource> currentRound = List<_CompetitorSource>.generate(
      competitors.length,
      (index) => _CompetitorSource.direct(index),
    );

    while (currentRound.length > 1) {
      final nextRound = <_CompetitorSource>[];
      final roundLabel = _roundLabel(currentRound.length);
      final roundMatchIds = <String>[];
      var index = 0;
      while (index < currentRound.length) {
        final competitorA = currentRound[index];
        if (index + 1 < currentRound.length) {
          final competitorB = currentRound[index + 1];
          final matchId = 'match_$matchCounter';
          matchCounter += 1;
          matches.add(
            _PlannedMatch(
              id: matchId,
              roundLabel: roundLabel,
              competitorA: competitorA,
              competitorB: competitorB,
            ),
          );
          roundMatchIds.add(matchId);
          nextRound.add(_CompetitorSource.winner(matchId));
          index += 2;
          continue;
        }

        // Odd bracket sizes use a BYE: last competitor auto-advances.
        nextRound.add(competitorA);
        index += 1;
      }

      if (nextRound.length == 2) {
        semifinalIds
          ..clear()
          ..addAll(roundMatchIds);
      }

      currentRound = nextRound;
    }

    return _CompetitionPlan(
      matches: matches,
      finalMatchId: matches.isEmpty ? '' : matches.last.id,
      semifinalMatchIds: semifinalIds,
    );
  }

  static String _roundLabel(int roundSize) {
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
}

class _PlannedMatch {
  final String id;
  final String roundLabel;
  final _CompetitorSource competitorA;
  final _CompetitorSource competitorB;

  const _PlannedMatch({
    required this.id,
    required this.roundLabel,
    required this.competitorA,
    required this.competitorB,
  });
}

enum _SourceKind { direct, directCompetitorId, winner, loser }

class _CompetitorSource {
  final _SourceKind kind;
  final int? index;
  final String? competitorId;
  final String? matchId;

  const _CompetitorSource._({
    required this.kind,
    this.index,
    this.competitorId,
    this.matchId,
  });

  const _CompetitorSource.direct(int index)
    : this._(kind: _SourceKind.direct, index: index);

  const _CompetitorSource.directCompetitorId(String competitorId)
    : this._(kind: _SourceKind.directCompetitorId, competitorId: competitorId);

  const _CompetitorSource.winner(String matchId)
    : this._(kind: _SourceKind.winner, matchId: matchId);

  const _CompetitorSource.loser(String matchId)
    : this._(kind: _SourceKind.loser, matchId: matchId);
}

class _ResolvedMatch {
  final _PlannedMatch match;
  final Competitor competitorA;
  final Competitor competitorB;

  const _ResolvedMatch({
    required this.match,
    required this.competitorA,
    required this.competitorB,
  });
}

class _RecordedMatch {
  final _PlannedMatch match;
  final Competitor competitorA;
  final Competitor competitorB;
  final Competitor winner;
  final Competitor loser;
  final int? competitorAFlags;
  final int? competitorBFlags;
  final List<DivisionMatchEventRecord> events;
  final int? competitorAPoints;
  final int? competitorBPoints;
  final int? competitorAWarningStage;
  final int? competitorBWarningStage;
  final KumiteFinishReason? finishReason;
  final bool reusedPreviousResult;

  const _RecordedMatch({
    required this.match,
    required this.competitorA,
    required this.competitorB,
    required this.winner,
    required this.loser,
    this.competitorAFlags,
    this.competitorBFlags,
    this.events = const <DivisionMatchEventRecord>[],
    this.competitorAPoints,
    this.competitorBPoints,
    this.competitorAWarningStage,
    this.competitorBWarningStage,
    this.finishReason,
    this.reusedPreviousResult = false,
  });
}

class _PlacementGroup {
  final String placeLabel;
  final List<Competitor> competitors;

  const _PlacementGroup({required this.placeLabel, required this.competitors});
}
