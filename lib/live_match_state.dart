import 'tournament_models.dart';

/// Ephemeral tatami state shared locally and through realtime broadcasts.
class LiveMatchState {
  final String tatamiName;
  final String divisionId;
  final String divisionTitle;
  final CompetitionType competitionType;
  final CompetitionExecutionMode executionMode;
  final String? roundLabel;
  final Competitor? competitorA;
  final Competitor? competitorB;
  final String? nextRoundLabel;
  final Competitor? nextCompetitorA;
  final Competitor? nextCompetitorB;
  final bool hasTimer;
  final int timerTotalSeconds;
  final int timerRemainingSeconds;
  final bool timerRunning;
  final int? timerEndsAtMillis;
  final int period;
  final int competitorAPoints;
  final int competitorBPoints;
  final int competitorAWarningStage;
  final int competitorBWarningStage;
  final int updatedAt;

  const LiveMatchState({
    required this.tatamiName,
    required this.divisionId,
    required this.divisionTitle,
    required this.competitionType,
    required this.executionMode,
    required this.updatedAt,
    this.roundLabel,
    this.competitorA,
    this.competitorB,
    this.nextRoundLabel,
    this.nextCompetitorA,
    this.nextCompetitorB,
    this.hasTimer = false,
    this.timerTotalSeconds = 0,
    this.timerRemainingSeconds = 0,
    this.timerRunning = false,
    this.timerEndsAtMillis,
    this.period = 1,
    this.competitorAPoints = 0,
    this.competitorBPoints = 0,
    this.competitorAWarningStage = 0,
    this.competitorBWarningStage = 0,
  });

  bool get hasCurrentMatch => competitorA != null && competitorB != null;

  bool get hasNextMatch => nextCompetitorA != null && nextCompetitorB != null;

  Map<String, dynamic> toMap() => {
    'tatamiName': tatamiName,
    'divisionId': divisionId,
    'divisionTitle': divisionTitle,
    'competitionType': competitionType.name,
    'executionMode': executionMode.name,
    'roundLabel': roundLabel,
    'competitorA': _competitorMap(competitorA),
    'competitorB': _competitorMap(competitorB),
    'nextRoundLabel': nextRoundLabel,
    'nextCompetitorA': _competitorMap(nextCompetitorA),
    'nextCompetitorB': _competitorMap(nextCompetitorB),
    'hasTimer': hasTimer,
    'timerTotalSeconds': timerTotalSeconds,
    'timerRemainingSeconds': timerRemainingSeconds,
    'timerRunning': timerRunning,
    'timerEndsAtMillis': timerEndsAtMillis,
    'period': period,
    'competitorAPoints': competitorAPoints,
    'competitorBPoints': competitorBPoints,
    'competitorAWarningStage': competitorAWarningStage,
    'competitorBWarningStage': competitorBWarningStage,
    'updatedAt': updatedAt,
  };

  factory LiveMatchState.fromMap(Map<String, dynamic> map) {
    try {
      final state = LiveMatchState(
        tatamiName: _text(map['tatamiName']),
        divisionId: _text(map['divisionId']),
        divisionTitle: _text(map['divisionTitle']),
        competitionType: CompetitionType.values.byName(map['competitionType'] as String),
        executionMode: CompetitionExecutionMode.values.byName(map['executionMode'] as String),
        roundLabel: map['roundLabel'] as String?,
        competitorA: _competitor(map['competitorA']),
        competitorB: _competitor(map['competitorB']),
        nextRoundLabel: map['nextRoundLabel'] as String?,
        nextCompetitorA: _competitor(map['nextCompetitorA']),
        nextCompetitorB: _competitor(map['nextCompetitorB']),
        hasTimer: map['hasTimer'] as bool,
        timerTotalSeconds: _integer(map['timerTotalSeconds']),
        timerRemainingSeconds: _integer(map['timerRemainingSeconds']),
        timerRunning: map['timerRunning'] as bool,
        timerEndsAtMillis: map['timerEndsAtMillis'] as int?,
        period: _integer(map['period'], minimum: 1),
        competitorAPoints: _integer(map['competitorAPoints']),
        competitorBPoints: _integer(map['competitorBPoints']),
        competitorAWarningStage: _integer(map['competitorAWarningStage'], maximum: 3),
        competitorBWarningStage: _integer(map['competitorBWarningStage'], maximum: 3),
        updatedAt: _integer(map['updatedAt']),
      );
      if ((state.competitorA == null) != (state.competitorB == null) ||
          (state.timerRunning && (!state.hasTimer || state.timerEndsAtMillis == null))) {
        throw const FormatException('Incomplete live match state.');
      }
      return state;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid live match state.');
    }
  }

  static Map<String, dynamic>? _competitorMap(Competitor? competitor) =>
      competitor == null ? null : {
        'id': competitor.id,
        'number': competitor.number,
        'name': competitor.name,
      };

  static Competitor? _competitor(Object? value) {
    if (value == null) return null;
    final map = Map<String, dynamic>.from(value as Map);
    return Competitor(
      id: _text(map['id']),
      number: _text(map['number']),
      name: _text(map['name']),
      belt: '',
      beltRank: 0,
      gender: Gender.male,
      age: 0,
    );
  }

  static String _text(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Missing live match identifier or label.');
    }
    return value;
  }

  static int _integer(Object? value, {int minimum = 0, int? maximum}) {
    if (value is! int || value < minimum || (maximum != null && value > maximum)) {
      throw const FormatException('Invalid live match numeric value.');
    }
    return value;
  }
}
