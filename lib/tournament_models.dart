enum Gender { male, female, notSpecified }

enum DivisionGender { mixed, maleOnly, femaleOnly, notSpecifiedOnly }

enum CompetitionType {
  kata,
  onTheSpotJodanChudanKumite,
  steppingJodanChudanKumite,
  kihonIpponKumite,
  kihonSanbonKumite,
  jiyuIpponKumite,
  jiyuKumite,
}

enum DivisionProgress { queued, running, completed }

enum CompetitionExecutionMode { flagVoting, manualWinner }

enum CompetitionTemplate { flagVoting, points }

extension CompetitionTemplateDetails on CompetitionTemplate {
  String get label => switch (this) {
    CompetitionTemplate.flagVoting => 'Flag-Based Scoring',
    CompetitionTemplate.points => 'Points-Based Scoring',
  };

  CompetitionExecutionMode get executionMode => switch (this) {
    CompetitionTemplate.flagVoting => CompetitionExecutionMode.flagVoting,
    CompetitionTemplate.points => CompetitionExecutionMode.manualWinner,
  };
}

class CompetitionCategory {
  final String id;
  final String name;
  final CompetitionTemplate template;
  final bool enabled;

  const CompetitionCategory({
    required this.id, required this.name, required this.template,
    this.enabled = true,
  });

  CompetitionType get legacyType => template == CompetitionTemplate.points
      ? CompetitionType.jiyuKumite : parseCompetitionType(id);

  CompetitionCategory copyWith({bool? enabled}) => CompetitionCategory(
    id: id, name: name, template: template, enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toMap() => {
    'id': id, 'name': name, 'template': template.name, 'enabled': enabled,
  };

  factory CompetitionCategory.fromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final name = map['name'];
    if (id is! String || id.trim().isEmpty || name is! String || name.trim().isEmpty ||
        map['enabled'] is! bool) {
      throw const FormatException('Invalid competition category.');
    }
    return CompetitionCategory(
      id: id, name: name.trim(),
      template: CompetitionTemplate.values.byName(map['template'] as String),
      enabled: map['enabled'] as bool,
    );
  }
}

List<CompetitionCategory> defaultCompetitionCategories() => [
  for (final type in CompetitionType.values)
    CompetitionCategory(
      id: type.name, name: type.label,
      template: type == CompetitionType.jiyuKumite
          ? CompetitionTemplate.points : CompetitionTemplate.flagVoting,
    ),
];

enum KumiteEventKind { wazaAri, ippon, warning, shikaku }

enum KumiteWarningType { jogai, mobobi, contact }

enum KumiteWarningStage { first, second, third }

enum KumiteFinishReason { points, warning, shikaku, manual }

extension GenderLabel on Gender {
  String get label => switch (this) {
    Gender.male => 'Male',
    Gender.female => 'Female',
    Gender.notSpecified => 'Not Specified',
  };
}

extension GenderCodec on Gender {
  String get storageValue => name;
}

extension DivisionGenderLabel on DivisionGender {
  String get label {
    switch (this) {
      case DivisionGender.mixed:
        return 'Mixed';
      case DivisionGender.maleOnly:
        return 'Male';
      case DivisionGender.femaleOnly:
        return 'Female';
      case DivisionGender.notSpecifiedOnly:
        return 'Not Specified';
    }
  }
}

extension DivisionGenderCodec on DivisionGender {
  String get storageValue => name;
}

extension CompetitionTypeLabel on CompetitionType {
  String get label {
    switch (this) {
      case CompetitionType.kata:
        return 'Kata';
      case CompetitionType.onTheSpotJodanChudanKumite:
        return 'On the Spot Jodan & Chudan Kumite';
      case CompetitionType.steppingJodanChudanKumite:
        return 'Stepping Jodan & Chudan Kumite';
      case CompetitionType.kihonIpponKumite:
        return 'Kihon Ippon Kumite';
      case CompetitionType.kihonSanbonKumite:
        return 'Kihon Sanbon Kumite';
      case CompetitionType.jiyuIpponKumite:
        return 'Jiyu Ippon Kumite';
      case CompetitionType.jiyuKumite:
        return 'Jiyu Kumite';
    }
  }
}

extension CompetitionTypeCodec on CompetitionType {
  String get storageValue => name;
}

extension CompetitionTypeExecution on CompetitionType {
  CompetitionExecutionMode get executionMode {
    switch (this) {
      case CompetitionType.kata:
      case CompetitionType.onTheSpotJodanChudanKumite:
      case CompetitionType.steppingJodanChudanKumite:
      case CompetitionType.kihonIpponKumite:
      case CompetitionType.kihonSanbonKumite:
      case CompetitionType.jiyuIpponKumite:
        return CompetitionExecutionMode.flagVoting;
      case CompetitionType.jiyuKumite:
        return CompetitionExecutionMode.manualWinner;
    }
  }
}

extension KumiteEventKindLabel on KumiteEventKind {
  String get label {
    switch (this) {
      case KumiteEventKind.wazaAri:
        return 'Waza-ari';
      case KumiteEventKind.ippon:
        return 'Ippon';
      case KumiteEventKind.warning:
        return 'Warning';
      case KumiteEventKind.shikaku:
        return 'Shikaku';
    }
  }
}

extension KumiteWarningTypeLabel on KumiteWarningType {
  String get code {
    switch (this) {
      case KumiteWarningType.jogai:
        return 'J';
      case KumiteWarningType.mobobi:
        return 'M';
      case KumiteWarningType.contact:
        return 'C';
    }
  }

  String get label {
    switch (this) {
      case KumiteWarningType.jogai:
        return 'Jogai';
      case KumiteWarningType.mobobi:
        return 'Mobobi';
      case KumiteWarningType.contact:
        return 'Contact';
    }
  }
}

extension KumiteWarningStageLabel on KumiteWarningStage {
  String get label {
    switch (this) {
      case KumiteWarningStage.first:
        return 'Keikoku';
      case KumiteWarningStage.second:
        return 'Chui';
      case KumiteWarningStage.third:
        return 'Hansoku';
    }
  }
}

extension KumiteWarningStageCodec on KumiteWarningStage {
  String get storageValue => name;
}

extension KumiteFinishReasonLabel on KumiteFinishReason {
  String get label {
    switch (this) {
      case KumiteFinishReason.points:
        return 'Points';
      case KumiteFinishReason.warning:
        return 'Warnings';
      case KumiteFinishReason.shikaku:
        return 'Shikaku';
      case KumiteFinishReason.manual:
        return 'Manual';
    }
  }
}

extension KumiteFinishReasonCodec on KumiteFinishReason {
  String get storageValue => name;
}

class DivisionMatchEventRecord {
  final String competitorId;
  final KumiteEventKind kind;
  final KumiteWarningType? warningType;
  final KumiteWarningStage? warningStage;
  final int pointsAwarded;
  final int period;
  final int timestamp;

  const DivisionMatchEventRecord({
    required this.competitorId,
    required this.kind,
    required this.timestamp,
    this.warningType,
    this.warningStage,
    this.pointsAwarded = 0,
    this.period = 1,
  });

  String get shortLabel {
    switch (kind) {
      case KumiteEventKind.wazaAri:
        return '○';
      case KumiteEventKind.ippon:
        return '●';
      case KumiteEventKind.shikaku:
        return 'S';
      case KumiteEventKind.warning:
        final warningCode = warningType?.code ?? '?';
        final stageCode = switch (warningStage) {
          KumiteWarningStage.first => 'K',
          KumiteWarningStage.second => 'C',
          KumiteWarningStage.third => 'H',
          null => '?',
        };
        return '$warningCode$stageCode';
    }
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'competitorId': competitorId,
      'kind': kind.name,
      'warningType': warningType?.name,
      'warningStage': warningStage?.storageValue,
      'pointsAwarded': pointsAwarded,
      'period': period,
      'timestamp': timestamp,
    };
  }

  static DivisionMatchEventRecord fromMap(Map<String, dynamic> map) {
    return DivisionMatchEventRecord(
      competitorId: (map['competitorId'] as String?) ?? '',
      kind: KumiteEventKind.values.firstWhere(
        (value) => value.name == map['kind'],
        orElse: () => KumiteEventKind.warning,
      ),
      warningType: map['warningType'] == null
          ? null
          : KumiteWarningType.values.firstWhere(
              (value) => value.name == map['warningType'],
              orElse: () => KumiteWarningType.contact,
            ),
      warningStage: map['warningStage'] == null
          ? null
          : KumiteWarningStage.values.firstWhere(
              (value) => value.name == map['warningStage'],
              orElse: () => KumiteWarningStage.first,
            ),
      pointsAwarded: (map['pointsAwarded'] as num?)?.toInt() ?? 0,
      period: (map['period'] as num?)?.toInt() ?? 1,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
    );
  }
}

extension DivisionProgressCodec on DivisionProgress {
  String get storageValue => name;
}

extension DivisionProgressLabel on DivisionProgress {
  String get label {
    switch (this) {
      case DivisionProgress.queued:
        return 'Queued';
      case DivisionProgress.running:
        return 'Running';
      case DivisionProgress.completed:
        return 'Completed';
    }
  }
}

class Competitor {
  final String id;
  final String number;
  final String name;
  final String belt;
  final int beltRank;
  final Gender gender;
  final int age;
  final DateTime? birthDate;
  final String club;

  const Competitor({
    required this.id,
    required this.number,
    required this.name,
    required this.belt,
    required this.beltRank,
    required this.gender,
    required this.age,
    this.birthDate,
    this.club = '',
  });

  Competitor copyWith({
    String? id,
    String? number,
    String? name,
    String? belt,
    int? beltRank,
    Gender? gender,
    int? age,
    Object? birthDate = _unset,
    String? club,
  }) {
    return Competitor(
      id: id ?? this.id,
      number: number ?? this.number,
      name: name ?? this.name,
      belt: belt ?? this.belt,
      beltRank: beltRank ?? this.beltRank,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      birthDate: identical(birthDate, _unset)
          ? this.birthDate
          : birthDate as DateTime?,
      club: club ?? this.club,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'number': number,
      'name': name,
      'belt': belt,
      'beltRank': beltRank,
      'gender': gender.storageValue,
      'age': age,
      'birthDate': birthDate?.toIso8601String(),
      'club': club,
    };
  }

  static Competitor fromMap(String id, Map<String, dynamic> map) {
    final belt = (map['belt'] as String?) ?? 'White';
    final birthDateValue = map['birthDate'] as String?;
    final parsedBirthDate = birthDateValue == null
        ? null
        : DateTime.tryParse(birthDateValue);
    return Competitor(
      id: id,
      number: (map['number'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      belt: belt,
      beltRank: (map['beltRank'] as num?)?.toInt() ?? beltToRank(belt),
      gender: parseGender(map['gender'] as String?),
      age: (map['age'] as num?)?.toInt() ?? 0,
      birthDate: parsedBirthDate,
      club: (map['club'] as String?) ?? '',
    );
  }
}

class Division {
  final String id;
  final CompetitionType competitionType;
  final String? competitionCategoryId;
  final String? competitionCategoryName;
  final CompetitionTemplate? competitionTemplate;
  final int minBeltRank;
  final int maxBeltRank;
  final int minAge;
  final int maxAge;
  final DivisionGender gender;
  final String assignedTatamiName;
  final int createdAt;
  final List<String> competitorIds;
  final DivisionProgress progress;
  final int? startedAt;
  final int? completedAt;
  final int? priorityBoostedAt;
  final List<DivisionMatchRecord> matchRecords;
  final List<DivisionPlacement> placements;
  final DivisionInProgressMatch? inProgressMatch;

  const Division({
    required this.id,
    required this.competitionType,
    this.competitionCategoryId,
    this.competitionCategoryName,
    this.competitionTemplate,
    required this.minBeltRank,
    required this.maxBeltRank,
    required this.minAge,
    required this.maxAge,
    required this.gender,
    required this.assignedTatamiName,
    required this.createdAt,
    required this.competitorIds,
    this.progress = DivisionProgress.queued,
    this.startedAt,
    this.completedAt,
    this.priorityBoostedAt,
    this.matchRecords = const <DivisionMatchRecord>[],
    this.placements = const <DivisionPlacement>[],
    this.inProgressMatch,
  });

  Division copyWith({
    String? id,
    CompetitionType? competitionType,
    Object? competitionCategoryId = _unset,
    Object? competitionCategoryName = _unset,
    Object? competitionTemplate = _unset,
    int? minBeltRank,
    int? maxBeltRank,
    int? minAge,
    int? maxAge,
    DivisionGender? gender,
    String? assignedTatamiName,
    int? createdAt,
    List<String>? competitorIds,
    DivisionProgress? progress,
    Object? startedAt = _unset,
    Object? completedAt = _unset,
    Object? priorityBoostedAt = _unset,
    List<DivisionMatchRecord>? matchRecords,
    List<DivisionPlacement>? placements,
    Object? inProgressMatch = _unset,
  }) {
    return Division(
      id: id ?? this.id,
      competitionType: competitionType ?? this.competitionType,
        competitionCategoryId: identical(competitionCategoryId, _unset)
          ? this.competitionCategoryId : competitionCategoryId as String?,
        competitionCategoryName: identical(competitionCategoryName, _unset)
          ? this.competitionCategoryName : competitionCategoryName as String?,
        competitionTemplate: identical(competitionTemplate, _unset)
          ? this.competitionTemplate : competitionTemplate as CompetitionTemplate?,
      minBeltRank: minBeltRank ?? this.minBeltRank,
      maxBeltRank: maxBeltRank ?? this.maxBeltRank,
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
      gender: gender ?? this.gender,
      assignedTatamiName: assignedTatamiName ?? this.assignedTatamiName,
      createdAt: createdAt ?? this.createdAt,
      competitorIds: competitorIds ?? this.competitorIds,
      progress: progress ?? this.progress,
      startedAt: identical(startedAt, _unset)
          ? this.startedAt
          : startedAt as int?,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as int?,
      priorityBoostedAt: identical(priorityBoostedAt, _unset)
          ? this.priorityBoostedAt
          : priorityBoostedAt as int?,
      matchRecords: matchRecords ?? this.matchRecords,
      placements: placements ?? this.placements,
      inProgressMatch: identical(inProgressMatch, _unset)
          ? this.inProgressMatch
          : inProgressMatch as DivisionInProgressMatch?,
    );
  }

  String get beltRangeLabel {
    if (minBeltRank == maxBeltRank) {
      return beltLabelFromRank(minBeltRank);
    }
    return '${beltLabelFromRank(minBeltRank)}-${beltLabelFromRank(maxBeltRank)}';
  }

  String get ageRangeLabel {
    if (minAge == maxAge) {
      return 'Age $minAge';
    }
    return 'Ages $minAge-$maxAge';
  }

    String get categoryId => competitionCategoryId ?? competitionType.name;
    String get competitionLabel => competitionCategoryName ?? competitionType.label;
    CompetitionTemplate get scoringTemplate => competitionTemplate ??
      (competitionType == CompetitionType.jiyuKumite
        ? CompetitionTemplate.points : CompetitionTemplate.flagVoting);
    CompetitionExecutionMode get executionMode => scoringTemplate.executionMode;
    CompetitionType get scoringType => scoringTemplate == CompetitionTemplate.points
        ? CompetitionType.jiyuKumite
        : (competitionType == CompetitionType.jiyuKumite ? CompetitionType.kata : competitionType);

    String get title =>
      '$competitionLabel: ${gender.label} $beltRangeLabel, $ageRangeLabel';

  bool matchesCompetitor(Competitor competitor) {
    final beltMatches =
        competitor.beltRank >= minBeltRank &&
        competitor.beltRank <= maxBeltRank;
    final ageMatches = competitor.age >= minAge && competitor.age <= maxAge;
    final genderMatches = switch (gender) {
      DivisionGender.mixed => true,
      DivisionGender.maleOnly => competitor.gender == Gender.male,
      DivisionGender.femaleOnly => competitor.gender == Gender.female,
      DivisionGender.notSpecifiedOnly => competitor.gender == Gender.notSpecified,
    };
    return beltMatches && ageMatches && genderMatches;
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'competitionType': competitionType.storageValue,
      if (competitionCategoryId != null) 'competitionCategoryId': competitionCategoryId,
      if (competitionCategoryName != null) 'competitionCategoryName': competitionCategoryName,
      if (competitionTemplate != null) 'competitionTemplate': competitionTemplate!.name,
      'minBeltRank': minBeltRank,
      'maxBeltRank': maxBeltRank,
      'minAge': minAge,
      'maxAge': maxAge,
      'gender': gender.storageValue,
      'assignedTatamiName': assignedTatamiName,
      'createdAt': createdAt,
      'competitorIds': competitorIds,
      'progress': progress.storageValue,
      'startedAt': startedAt,
      'completedAt': completedAt,
      'priorityBoostedAt': priorityBoostedAt,
      'matchRecords': matchRecords.map((record) => record.toMap()).toList(),
      'placements': placements.map((placement) => placement.toMap()).toList(),
      'inProgressMatch': inProgressMatch?.toMap(),
    };
  }

  static Division fromMap(String id, Map<String, dynamic> map) {
    return Division(
      id: id,
      competitionType: parseCompetitionType(map['competitionType'] as String?),
        competitionCategoryId: map['competitionCategoryId'] as String?,
        competitionCategoryName: map['competitionCategoryName'] as String?,
        competitionTemplate: map['competitionTemplate'] == null ? null
          : CompetitionTemplate.values.byName(map['competitionTemplate'] as String),
      minBeltRank: (map['minBeltRank'] as num?)?.toInt() ?? 1,
      maxBeltRank: (map['maxBeltRank'] as num?)?.toInt() ?? 10,
      minAge: (map['minAge'] as num?)?.toInt() ?? 0,
      maxAge: (map['maxAge'] as num?)?.toInt() ?? 99,
      gender: parseDivisionGender(map['gender'] as String?),
      assignedTatamiName: (map['assignedTatamiName'] as String?) ?? 'Tatami 1',
      createdAt: (map['createdAt'] as num?)?.toInt() ?? int.tryParse(id) ?? 0,
      competitorIds: ((map['competitorIds'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<String>()
          .toList(),
      progress: parseDivisionProgress(map['progress'] as String?),
      startedAt: (map['startedAt'] as num?)?.toInt(),
      completedAt: (map['completedAt'] as num?)?.toInt(),
      priorityBoostedAt: (map['priorityBoostedAt'] as num?)?.toInt(),
      matchRecords: ((map['matchRecords'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(DivisionMatchRecord.fromMap)
          .toList(),
      placements: ((map['placements'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(DivisionPlacement.fromMap)
          .toList(),
      inProgressMatch: map['inProgressMatch'] == null
          ? null
          : DivisionInProgressMatch.fromMap(
              Map<String, dynamic>.from(map['inProgressMatch'] as Map),
            ),
    );
  }
}

class DivisionMatchRecord {
  final String matchId;
  final String roundLabel;
  final String competitorAId;
  final String competitorBId;
  final String winnerId;
  final String loserId;
  final int? competitorAFlags;
  final int? competitorBFlags;
  final List<DivisionMatchEventRecord> events;
  final int? competitorAPoints;
  final int? competitorBPoints;
  final int? competitorAWarningStage;
  final int? competitorBWarningStage;
  final KumiteFinishReason? finishReason;
  final bool reusedPreviousResult;

  const DivisionMatchRecord({
    required this.matchId,
    required this.roundLabel,
    required this.competitorAId,
    required this.competitorBId,
    required this.winnerId,
    required this.loserId,
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

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'matchId': matchId,
      'roundLabel': roundLabel,
      'competitorAId': competitorAId,
      'competitorBId': competitorBId,
      'winnerId': winnerId,
      'loserId': loserId,
      'competitorAFlags': competitorAFlags,
      'competitorBFlags': competitorBFlags,
      'events': events.map((event) => event.toMap()).toList(),
      'competitorAPoints': competitorAPoints,
      'competitorBPoints': competitorBPoints,
      'competitorAWarningStage': competitorAWarningStage,
      'competitorBWarningStage': competitorBWarningStage,
      'finishReason': finishReason?.storageValue,
      'reusedPreviousResult': reusedPreviousResult,
    };
  }

  static DivisionMatchRecord fromMap(Map<String, dynamic> map) {
    return DivisionMatchRecord(
      matchId: (map['matchId'] as String?) ?? '',
      roundLabel: (map['roundLabel'] as String?) ?? '',
      competitorAId: (map['competitorAId'] as String?) ?? '',
      competitorBId: (map['competitorBId'] as String?) ?? '',
      winnerId: (map['winnerId'] as String?) ?? '',
      loserId: (map['loserId'] as String?) ?? '',
      competitorAFlags: (map['competitorAFlags'] as num?)?.toInt(),
      competitorBFlags: (map['competitorBFlags'] as num?)?.toInt(),
      events: ((map['events'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(DivisionMatchEventRecord.fromMap)
          .toList(),
      competitorAPoints: (map['competitorAPoints'] as num?)?.toInt(),
      competitorBPoints: (map['competitorBPoints'] as num?)?.toInt(),
      competitorAWarningStage: (map['competitorAWarningStage'] as num?)
          ?.toInt(),
      competitorBWarningStage: (map['competitorBWarningStage'] as num?)
          ?.toInt(),
      finishReason: map['finishReason'] == null
          ? null
          : KumiteFinishReason.values.firstWhere(
              (value) => value.name == map['finishReason'],
              orElse: () => KumiteFinishReason.manual,
            ),
      reusedPreviousResult: (map['reusedPreviousResult'] as bool?) ?? false,
    );
  }
}

class DivisionPlacement {
  final String placeLabel;
  final List<String> competitorIds;

  const DivisionPlacement({
    required this.placeLabel,
    required this.competitorIds,
  });

  Map<String, Object> toMap() {
    return <String, Object>{
      'placeLabel': placeLabel,
      'competitorIds': competitorIds,
    };
  }

  static DivisionPlacement fromMap(Map<String, dynamic> map) {
    return DivisionPlacement(
      placeLabel: (map['placeLabel'] as String?) ?? '',
      competitorIds: ((map['competitorIds'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<String>()
          .toList(),
    );
  }
}

/// Snapshot of an unfinished jiyu kumite match (points/warnings/timer/events)
/// persisted so it survives leaving and re-entering the execution screen.
class DivisionInProgressMatch {
  final String matchId;
  final int competitorAPoints;
  final int competitorBPoints;
  final int competitorAWarningStage;
  final int competitorBWarningStage;
  final int period;
  final int timerRemainingSeconds;
  final int? timerRemainingMilliseconds;
  final bool timerRunning;
  final int? timerEndsAtMillis;
  final List<DivisionMatchEventRecord> events;

  const DivisionInProgressMatch({
    required this.matchId,
    this.competitorAPoints = 0,
    this.competitorBPoints = 0,
    this.competitorAWarningStage = 0,
    this.competitorBWarningStage = 0,
    this.period = 1,
    this.timerRemainingSeconds = 0,
    this.timerRemainingMilliseconds,
    this.timerRunning = false,
    this.timerEndsAtMillis,
    this.events = const <DivisionMatchEventRecord>[],
  });

  Duration remainingAt(DateTime now) {
    final remaining = timerRunning && timerEndsAtMillis != null
        ? timerEndsAtMillis! - now.millisecondsSinceEpoch
        : timerRemainingMilliseconds ?? timerRemainingSeconds * 1000;
    return Duration(milliseconds: remaining < 0 ? 0 : remaining);
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'matchId': matchId,
      'competitorAPoints': competitorAPoints,
      'competitorBPoints': competitorBPoints,
      'competitorAWarningStage': competitorAWarningStage,
      'competitorBWarningStage': competitorBWarningStage,
      'period': period,
      'timerRemainingSeconds': timerRemainingSeconds,
      'timerRemainingMilliseconds': timerRemainingMilliseconds,
      'timerRunning': timerRunning,
      'timerEndsAtMillis': timerEndsAtMillis,
      'events': events.map((event) => event.toMap()).toList(),
    };
  }

  static DivisionInProgressMatch fromMap(Map<String, dynamic> map) {
    return DivisionInProgressMatch(
      matchId: (map['matchId'] as String?) ?? '',
      competitorAPoints: (map['competitorAPoints'] as num?)?.toInt() ?? 0,
      competitorBPoints: (map['competitorBPoints'] as num?)?.toInt() ?? 0,
      competitorAWarningStage:
          (map['competitorAWarningStage'] as num?)?.toInt() ?? 0,
      competitorBWarningStage:
          (map['competitorBWarningStage'] as num?)?.toInt() ?? 0,
      period: (map['period'] as num?)?.toInt() ?? 1,
      timerRemainingSeconds:
          (map['timerRemainingSeconds'] as num?)?.toInt() ?? 0,
        timerRemainingMilliseconds:
          (map['timerRemainingMilliseconds'] as num?)?.toInt(),
        timerRunning: map['timerRunning'] == true,
        timerEndsAtMillis: (map['timerEndsAtMillis'] as num?)?.toInt(),
      events: ((map['events'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(DivisionMatchEventRecord.fromMap)
          .toList(),
    );
  }
}

class TatamiLogEntry {
  final String id;
  final String tatamiName;
  final String message;
  final String? divisionId;
  final String? divisionTitle;
  final String? activity;
  final int? competitorCount;
  final int timestamp;

  const TatamiLogEntry({
    required this.id,
    required this.tatamiName,
    required this.message,
    required this.timestamp,
    this.divisionId,
    this.divisionTitle,
    this.activity,
    this.competitorCount,
  });

  TatamiLogEntry? lifecycleEntry({Division? division}) {
    if (divisionId == null || divisionId!.isEmpty) return null;
    final source = activity ?? message;
    final String normalized;
    if (source == 'Started' || source.startsWith('Started:') ||
        source.startsWith('Division started:')) {
      normalized = 'Started';
    } else if (source == 'Finished' || source.startsWith('Finished:') ||
        source.startsWith('Division concluded:') ||
        source.startsWith('Division finished:')) {
      normalized = 'Finished';
    } else if (source == 'Moved' || source.startsWith('Moved ') ||
        source.startsWith('Division moved to this tatami:') ||
        source.startsWith('Division reassigned away:')) {
      normalized = 'Moved';
    } else {
      return null;
    }
    return TatamiLogEntry(
      id: id, tatamiName: tatamiName, divisionId: divisionId,
      divisionTitle: divisionTitle ?? division?.title,
      activity: normalized, timestamp: timestamp, message: message,
      competitorCount: competitorCount ?? division?.competitorIds.length,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'tatamiName': tatamiName,
      'message': message,
      'divisionId': divisionId,
      'divisionTitle': divisionTitle,
      'activity': activity,
      'competitorCount': competitorCount,
      'timestamp': timestamp,
    };
  }

  static TatamiLogEntry fromMap(Map<String, dynamic> map) {
    return TatamiLogEntry(
      id: (map['id'] as String?) ?? '',
      tatamiName: (map['tatamiName'] as String?) ?? '',
      message: (map['message'] as String?) ?? '',
      divisionId: map['divisionId'] as String?,
      divisionTitle: map['divisionTitle'] as String?,
      activity: map['activity'] as String?,
      competitorCount: (map['competitorCount'] as num?)?.toInt(),
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
    );
  }
}

class TatamiDefinition {
  final String name;
  final int judgesCount;

  const TatamiDefinition({required this.name, required this.judgesCount});

  TatamiDefinition copyWith({String? name, int? judgesCount}) {
    return TatamiDefinition(
      name: name ?? this.name,
      judgesCount: judgesCount ?? this.judgesCount,
    );
  }

  Map<String, Object> toMap() {
    return <String, Object>{'name': name, 'judgesCount': judgesCount};
  }

  static TatamiDefinition fromMap(Map<String, dynamic> map) {
    return TatamiDefinition(
      name: (map['name'] as String?) ?? '',
      judgesCount: (map['judgesCount'] as num?)?.toInt() ?? 5,
    );
  }
}

class TatamiAssignment {
  final String tatamiName;
  final String? divisionId;

  const TatamiAssignment({required this.tatamiName, this.divisionId});

  TatamiAssignment copyWith({String? tatamiName, Object? divisionId = _unset}) {
    return TatamiAssignment(
      tatamiName: tatamiName ?? this.tatamiName,
      divisionId: identical(divisionId, _unset)
          ? this.divisionId
          : divisionId as String?,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'tatamiName': tatamiName,
      'divisionId': divisionId,
    };
  }

  static TatamiAssignment fromMap(String id, Map<String, dynamic> map) {
    return TatamiAssignment(
      tatamiName: (map['tatamiName'] as String?) ?? id,
      divisionId: map['divisionId'] as String?,
    );
  }
}

const Object _unset = Object();

const List<String> kiddiesBeltColors = [
  'None', 'White', 'Yellow', 'Orange', 'Green', 'Blue', 'Purple', 'Red', 'Black',
];

String normalizeKiddiesBeltColor(String? value) => kiddiesBeltColors.firstWhere(
  (color) => color.toLowerCase() == value?.trim().toLowerCase(),
  orElse: () => 'None',
);

String kiddiesBeltColor(String belt) {
  final parts = belt.split(' - ');
  return parts.length == 2 && parts.first.toLowerCase() == 'kiddies'
      ? normalizeKiddiesBeltColor(parts.last)
      : 'None';
}

const List<String> beltOrder = <String>[
  'White',
  'Kiddies',
  'Yellow',
  'Orange',
  'Green',
  'Blue',
  'Purple',
  'Red',
  'Brown',
  'Black',
  'None',
];

int beltToRank(String belt) {
  final normalizedBelt = belt.trim().toLowerCase();
  if (normalizedBelt.startsWith('kiddies - ')) {
    return 2;
  }
  switch (normalizedBelt) {
    case 'none':
      return 0;
    case 'white':
      return 1;
    case 'kiddies':
      return 2;
    case 'yellow':
      return 3;
    case 'orange':
      return 4;
    case 'green':
      return 5;
    case 'blue':
      return 6;
    case 'purple':
      return 7;
    case 'red':
      return 8;
    case 'brown':
      return 9;
    case 'black':
      return 10;
    default:
      return 0;
  }
}

String beltLabelFromRank(int rank) {
  if (rank == 0) {
    return 'None';
  }
  if (rank < 1 || rank > beltOrder.length) {
    return 'Unknown';
  }
  return beltOrder[rank - 1];
}

Gender parseGender(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'male' || 'm' => Gender.male,
    'female' || 'f' => Gender.female,
    _ => Gender.notSpecified,
  };
}

DivisionGender parseDivisionGender(String? value) {
  return DivisionGender.values.firstWhere(
    (gender) => gender.name == value,
    orElse: () => DivisionGender.mixed,
  );
}

CompetitionType parseCompetitionType(String? value) {
  return CompetitionType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => CompetitionType.kata,
  );
}

DivisionProgress parseDivisionProgress(String? value) {
  return DivisionProgress.values.firstWhere(
    (progress) => progress.name == value,
    orElse: () => DivisionProgress.queued,
  );
}
