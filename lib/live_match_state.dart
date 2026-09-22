import 'tournament_models.dart';

/// Ephemeral, in-memory snapshot of what is currently happening on a tatami,
/// broadcast by the competition execution screen and consumed by the tatami
/// display screen. Not persisted to storage or the backend.
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
    this.period = 1,
    this.competitorAPoints = 0,
    this.competitorBPoints = 0,
    this.competitorAWarningStage = 0,
    this.competitorBWarningStage = 0,
  });

  bool get hasCurrentMatch => competitorA != null && competitorB != null;

  bool get hasNextMatch => nextCompetitorA != null && nextCompetitorB != null;
}
