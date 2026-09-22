import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';

import 'live_match_state.dart';
import 'tournament_backend.dart';
import 'tournament_local_store.dart';
import 'tournament_models.dart';

class TournamentRepository {
  final TournamentLocalStore _localStore;
  final String tournamentId;
  final List<Competitor> _competitors = <Competitor>[];
  final List<Division> _divisions = <Division>[];
  final Map<String, TatamiAssignment> _tatamiAssignments =
      <String, TatamiAssignment>{};
  final StreamController<List<Competitor>> _competitorsController =
      StreamController<List<Competitor>>.broadcast();
  final StreamController<List<Division>> _divisionsController =
      StreamController<List<Division>>.broadcast();
  final StreamController<List<TatamiAssignment>> _tatamiController =
      StreamController<List<TatamiAssignment>>.broadcast();
  final StreamController<List<String>> _tatamiNamesController =
      StreamController<List<String>>.broadcast();
  final StreamController<List<TatamiDefinition>> _tatamiDefinitionsController =
      StreamController<List<TatamiDefinition>>.broadcast();
  final StreamController<Map<String, List<TatamiLogEntry>>>
  _tatamiLogsController =
      StreamController<Map<String, List<TatamiLogEntry>>>.broadcast();
  final Map<String, List<TatamiLogEntry>> _tatamiLogsByTatami =
      <String, List<TatamiLogEntry>>{};
  final Map<String, int> _tatamiJudgeCounts = <String, int>{};
  final Map<String, LiveMatchState?> _liveMatchStates =
      <String, LiveMatchState?>{};
  final Map<String, StreamController<LiveMatchState?>> _liveMatchControllers =
      <String, StreamController<LiveMatchState?>>{};
  final TournamentBackend _backend = TournamentBackend();
  Timer? _remoteSyncTimer;
  DateTime? _lastLocalUpdatedAt;
  List<String> _tatamiOrder = const <String>[];

  bool _initialized = false;

  TournamentRepository({
    TournamentLocalStore? localStore,
    this.tournamentId = '',
  }) : _localStore = localStore ?? TournamentLocalStore();

  Future<void> initialize({
    required List<TatamiDefinition> defaultTatamis,
  }) async {
    if (_initialized) {
      return;
    }

    await _loadSnapshot();
    if (tournamentId.trim().isNotEmpty) {
      final remoteSnapshot = await _backend.loadTournamentSnapshot(tournamentId);
      if (remoteSnapshot.isNotEmpty) {
        _lastLocalUpdatedAt = _snapshotUpdatedAt(remoteSnapshot);
        _applySnapshot(remoteSnapshot);
      }
    }

    if (_tatamiOrder.isEmpty) {
      await configureTatamiDefinitions(defaultTatamis);
    } else {
      _emitTatamiNames();
      _emitTatamiDefinitions();
      _emitTatami();
      _emitTatamiLogs();
    }
    _emitCompetitors();
    _emitDivisions();
    _initialized = true;
    _startRemoteSync();
  }

  Stream<List<Competitor>> watchCompetitors() {
    return _watchWithInitial<List<Competitor>>(
      _sortedCompetitors(),
      _competitorsController.stream,
    );
  }

  Stream<List<Division>> watchDivisions() {
    return _watchWithInitial<List<Division>>(
      _sortedDivisions(),
      _divisionsController.stream,
    );
  }

  Stream<List<String>> watchTatamiNames() {
    return _watchWithInitial<List<String>>(
      List<String>.from(_tatamiOrder),
      _tatamiNamesController.stream,
    );
  }

  Stream<List<TatamiDefinition>> watchTatamiDefinitions() {
    return _watchWithInitial<List<TatamiDefinition>>(
      _currentTatamiDefinitions(),
      _tatamiDefinitionsController.stream,
    );
  }

  Stream<List<TatamiAssignment>> watchTatamiAssignments() {
    return _watchWithInitial<List<TatamiAssignment>>(
      _orderedTatamiAssignments(),
      _tatamiController.stream,
    );
  }

  Stream<Map<String, List<TatamiLogEntry>>> watchTatamiLogs() {
    return _watchWithInitial<Map<String, List<TatamiLogEntry>>>(
      _copyTatamiLogs(),
      _tatamiLogsController.stream,
    );
  }

  StreamController<LiveMatchState?> _liveMatchController(String tatamiName) {
    return _liveMatchControllers.putIfAbsent(
      tatamiName,
      () => StreamController<LiveMatchState?>.broadcast(),
    );
  }

  /// Watches the live on-tatami state (current match, next match, timer,
  /// points) broadcast by the competition execution screen. This is
  /// in-memory only and not persisted across app restarts.
  Stream<LiveMatchState?> watchLiveMatchState(String tatamiName) {
    return _watchWithInitial<LiveMatchState?>(
      _liveMatchStates[tatamiName],
      _liveMatchController(tatamiName).stream,
    );
  }

  void publishLiveMatchState(LiveMatchState state) {
    _liveMatchStates[state.tatamiName] = state;
    _liveMatchController(state.tatamiName).add(state);
  }

  void clearLiveMatchState(String tatamiName) {
    _liveMatchStates[tatamiName] = null;
    _liveMatchController(tatamiName).add(null);
  }

  Future<void> ensureDefaultTatamis(List<String> tatamiNames) async {
    if (_tatamiOrder.isNotEmpty) {
      return;
    }
    final normalized = _normalizeTatamiNames(tatamiNames);
    if (normalized.isEmpty) {
      throw StateError('At least one tatami is required.');
    }
    _tatamiOrder = normalized;
    for (final tatamiName in _tatamiOrder) {
      _tatamiAssignments.putIfAbsent(
        tatamiName,
        () => TatamiAssignment(tatamiName: tatamiName),
      );
      _tatamiJudgeCounts.putIfAbsent(tatamiName, () => 5);
      _tatamiLogsByTatami.putIfAbsent(tatamiName, () => <TatamiLogEntry>[]);
    }
    _emitTatamiNames();
    _emitTatamiDefinitions();
    _emitTatami();
    _emitTatamiLogs();
    await _persist();
  }

  Future<void> configureTatamiDefinitions(
    List<TatamiDefinition> definitions,
  ) async {
    final normalized = _normalizeTatamiDefinitions(definitions);
    if (normalized.isEmpty) {
      throw StateError('At least one tatami is required.');
    }

    final names = normalized.map((definition) => definition.name).toList();
    final normalizedSet = names.toSet();
    final removedTatamis = _tatamiOrder
        .where((name) => !normalizedSet.contains(name))
        .toList();
    final blocked = <String>[];
    for (final name in removedTatamis) {
      final assignedDivisions = _divisions
          .where((division) => division.assignedTatamiName == name)
          .toList();
      if (assignedDivisions.isNotEmpty) {
        for (final division in assignedDivisions) {
          blocked.add('$name (${division.title})');
        }
      }
    }
    if (blocked.isNotEmpty) {
      throw StateError(
        'Cannot remove tatamis with assigned divisions. Reassign these first: ${blocked.join(', ')}',
      );
    }

    _tatamiOrder = names;
    for (final definition in normalized) {
      _tatamiAssignments.putIfAbsent(
        definition.name,
        () => TatamiAssignment(tatamiName: definition.name),
      );
      _tatamiJudgeCounts[definition.name] = _validatedJudgeCount(
        definition.judgesCount,
      );
      _tatamiLogsByTatami.putIfAbsent(
        definition.name,
        () => <TatamiLogEntry>[],
      );
    }
    for (final tatamiName in removedTatamis) {
      _tatamiAssignments.remove(tatamiName);
      _tatamiLogsByTatami.remove(tatamiName);
      _tatamiJudgeCounts.remove(tatamiName);
    }
    _emitTatamiNames();
    _emitTatamiDefinitions();
    _emitTatami();
    _emitTatamiLogs();
    await _persist();
  }

  Future<void> configureTatamis(List<String> tatamiNames) async {
    final definitions = tatamiNames.map((name) {
      final existingJudges = _tatamiJudgeCounts[name] ?? 5;
      return TatamiDefinition(name: name, judgesCount: existingJudges);
    }).toList();
    await configureTatamiDefinitions(definitions);
  }

  Future<void> updateTatamiJudgeCount(
    String tatamiName,
    int judgesCount,
  ) async {
    if (!_tatamiOrder.contains(tatamiName)) {
      throw StateError('Tatami "$tatamiName" does not exist.');
    }
    _tatamiJudgeCounts[tatamiName] = _validatedJudgeCount(judgesCount);
    _emitTatamiDefinitions();
    _emitTatamiLogs();
    await _persist();
  }

  List<String> _normalizeTatamiNames(List<String> tatamiNames) {
    final normalized = <String>[];
    final seen = <String>{};

    for (final tatamiName in tatamiNames) {
      final clean = tatamiName.trim();
      if (clean.isEmpty) {
        continue;
      }
      if (seen.add(clean)) {
        normalized.add(clean);
      }
    }
    return normalized;
  }

  List<TatamiDefinition> _normalizeTatamiDefinitions(
    List<TatamiDefinition> definitions,
  ) {
    final normalized = <TatamiDefinition>[];
    final seen = <String>{};

    for (final definition in definitions) {
      final clean = definition.name.trim();
      if (clean.isEmpty || !seen.add(clean)) {
        continue;
      }
      normalized.add(
        TatamiDefinition(
          name: clean,
          judgesCount: _validatedJudgeCount(definition.judgesCount),
        ),
      );
    }
    return normalized;
  }

  int _validatedJudgeCount(int judgesCount) {
    return judgesCount == 3 ? 3 : 5;
  }

  Future<void> saveCompetitor(Competitor competitor) async {
    final index = _competitors.indexWhere((item) => item.id == competitor.id);
    if (index == -1) {
      _competitors.add(competitor);
    } else {
      _competitors[index] = competitor;
    }
    _emitCompetitors();
    await _persist();
  }

  Future<void> deleteCompetitor(String competitorId) async {
    _competitors.removeWhere((item) => item.id == competitorId);
    for (var index = 0; index < _divisions.length; index++) {
      final division = _divisions[index];
      _divisions[index] = division.copyWith(
        competitorIds: division.competitorIds
            .where((id) => id != competitorId)
            .toList(),
      );
    }
    _emitCompetitors();
    _emitDivisions();
    await _persist();
  }

  Future<void> replaceCompetitors(List<Competitor> competitors) async {
    _competitors
      ..clear()
      ..addAll(competitors);

    final validIds = competitors.map((competitor) => competitor.id).toSet();
    for (var index = 0; index < _divisions.length; index++) {
      final division = _divisions[index];
      _divisions[index] = division.copyWith(
        competitorIds: division.competitorIds
            .where((id) => validIds.contains(id))
            .toList(),
      );
    }

    _emitCompetitors();
    _emitDivisions();
    await _persist();
  }

  Future<void> clearTournamentData() async {
    _competitors.clear();
    _divisions.clear();

    for (final tatamiName in _tatamiOrder) {
      _tatamiAssignments[tatamiName] = TatamiAssignment(
        tatamiName: tatamiName,
        divisionId: null,
      );
      _tatamiLogsByTatami[tatamiName] = <TatamiLogEntry>[];
    }

    _emitCompetitors();
    _emitDivisions();
    _emitTatami();
    _emitTatamiLogs();
    await _persist();
  }

  Future<String> exportDrawSheetsToFolder(String folderPath) async {
    final target = Directory(folderPath);
    if (!await target.exists()) {
      throw StateError('Selected folder does not exist.');
    }

    final byId = <String, Competitor>{
      for (final competitor in _competitors) competitor.id: competitor,
    };
    final timestamp = DateTime.now().toIso8601String();
    final summary = <String, Object?>{
      'exportedAt': timestamp,
      'competitorCount': _competitors.length,
      'divisionCount': _divisions.length,
      'divisions': _divisions
          .map(
            (division) => <String, Object?>{
              'id': division.id,
              'title': division.title,
              'tatami': division.assignedTatamiName,
              'progress': division.progress.storageValue,
              'completedAt': division.completedAt,
              'matchCount': division.matchRecords.length,
            },
          )
          .toList(),
    };

    final summaryFile = File(
      '${target.path}${Platform.pathSeparator}tournament_drawsheet_summary.json',
    );
    await summaryFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(summary),
      flush: true,
    );

    final workbook = Excel.createExcel();
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Competitors') {
      workbook.rename(defaultSheet, 'Competitors');
    }
    final competitorsSheet = workbook['Competitors'];
    competitorsSheet.appendRow(<CellValue?>[
      TextCellValue('number'),
      TextCellValue('name'),
      TextCellValue('belt'),
      TextCellValue('birth_year'),
      TextCellValue('club'),
    ]);
    for (final competitor in _competitors) {
      final birthYear =
          competitor.birthDate?.year ?? (DateTime.now().year - competitor.age);
      competitorsSheet.appendRow(<CellValue?>[
        TextCellValue(competitor.number),
        TextCellValue(competitor.name),
        TextCellValue(competitor.belt),
        IntCellValue(birthYear),
        TextCellValue(competitor.club),
      ]);
    }
    final workbookBytes = workbook.save();
    if (workbookBytes == null) {
      throw StateError('Unable to generate competitors XLSX file.');
    }
    final competitorsFile = File(
      '${target.path}${Platform.pathSeparator}competitors.xlsx',
    );
    await competitorsFile.writeAsBytes(workbookBytes, flush: true);

    for (final division in _divisions) {
      final divisionPayload = <String, Object?>{
        'exportedAt': timestamp,
        'division': <String, Object?>{
          'id': division.id,
          'title': division.title,
          'data': division.toMap(),
        },
        'competitors': division.competitorIds
            .map((id) => byId[id])
            .whereType<Competitor>()
            .map(
              (competitor) => <String, Object?>{
                'id': competitor.id,
                'data': competitor.toMap(),
              },
            )
            .toList(),
      };

      final fileName = _safeFileName(
        '${division.assignedTatamiName}_${division.title}_${division.id}.json',
      );
      final file = File('${target.path}${Platform.pathSeparator}$fileName');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(divisionPayload),
        flush: true,
      );
    }

    return summaryFile.path;
  }

  Future<void> saveDivision(Division division) {
    return _saveDivisionAndAssignment(division);
  }

  /// Persists (or clears, when null) the currently unfinished match's
  /// points/warnings/timer/events so they survive leaving and re-entering
  /// the execution screen.
  Future<void> saveDivisionInProgressMatch(
    String tatamiName,
    String divisionId,
    DivisionInProgressMatch? inProgressMatch,
  ) async {
    final divisionIndex = _divisions.indexWhere(
      (item) => item.id == divisionId,
    );
    if (divisionIndex == -1) {
      return;
    }
    _divisions[divisionIndex] = _divisions[divisionIndex].copyWith(
      inProgressMatch: inProgressMatch,
    );
    _emitDivisions();
    await _persist();
  }

  Future<void> saveDivisionExecutionState(
    String tatamiName,
    String divisionId, {
    required List<DivisionMatchRecord> matchRecords,
    required List<DivisionPlacement> placements,
    String? logMessage,
  }) async {
    final divisionIndex = _divisions.indexWhere(
      (item) => item.id == divisionId,
    );
    if (divisionIndex == -1) {
      throw StateError('Division not found.');
    }

    _divisions[divisionIndex] = _divisions[divisionIndex].copyWith(
      matchRecords: List<DivisionMatchRecord>.from(matchRecords),
      placements: List<DivisionPlacement>.from(placements),
    );
    final effectiveLogMessage = logMessage != null && logMessage.isNotEmpty
        ? logMessage
        : (matchRecords.isNotEmpty || placements.isNotEmpty)
        ? 'Results saved: ${_divisions[divisionIndex].title}'
        : null;
    if (effectiveLogMessage != null) {
      _appendTatamiLog(tatamiName, divisionId, effectiveLogMessage);
    }
    _emitDivisions();
    _emitTatamiLogs();
    await _persist();
  }

  Future<void> startDivisionOnTatami(
    String tatamiName,
    String divisionId,
  ) async {
    final divisionIndex = _divisions.indexWhere(
      (item) => item.id == divisionId,
    );
    if (divisionIndex == -1) {
      throw StateError('Division not found.');
    }
    if (!_tatamiOrder.contains(tatamiName)) {
      throw StateError('Tatami "$tatamiName" does not exist.');
    }

    final division = _divisions[divisionIndex].copyWith(
      progress: DivisionProgress.running,
      startedAt: DateTime.now().millisecondsSinceEpoch,
      completedAt: null,
    );
    _divisions[divisionIndex] = division;
    _tatamiAssignments[tatamiName] = TatamiAssignment(
      tatamiName: tatamiName,
      divisionId: divisionId,
    );
    _emitDivisions();
    _emitTatami();
    _emitTatamiLogs();
    await _persist();
  }

  Future<void> completeDivisionOnTatami(
    String tatamiName,
    String divisionId,
  ) async {
    final divisionIndex = _divisions.indexWhere(
      (item) => item.id == divisionId,
    );
    if (divisionIndex == -1) {
      throw StateError('Division not found.');
    }

    final division = _divisions[divisionIndex].copyWith(
      progress: DivisionProgress.completed,
      completedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _divisions[divisionIndex] = division;
    final currentAssignment = _tatamiAssignments[tatamiName];
    if (currentAssignment?.divisionId == divisionId) {
      _tatamiAssignments[tatamiName] = TatamiAssignment(
        tatamiName: tatamiName,
        divisionId: null,
      );
    }
    _appendTatamiLog(
      tatamiName,
      divisionId,
      'Division concluded: ${division.title}',
    );
    _emitDivisions();
    _emitTatami();
    _emitTatamiLogs();
    await _persist();
  }

  Future<void> redoDivisionOnTatami(
    String tatamiName,
    String divisionId,
  ) async {
    final divisionIndex = _divisions.indexWhere(
      (item) => item.id == divisionId,
    );
    if (divisionIndex == -1) {
      throw StateError('Division not found.');
    }

    final division = _divisions[divisionIndex].copyWith(
      progress: DivisionProgress.queued,
      startedAt: null,
      completedAt: null,
      priorityBoostedAt: DateTime.now().millisecondsSinceEpoch,
      assignedTatamiName: tatamiName,
      matchRecords: const <DivisionMatchRecord>[],
      placements: const <DivisionPlacement>[],
    );
    _divisions[divisionIndex] = division;
    _appendTatamiLog(
      tatamiName,
      divisionId,
      'Division selected to redo: ${division.title}',
    );
    _emitDivisions();
    _emitTatami();
    _emitTatamiLogs();
    await _persist();
  }

  Future<void> deleteDivision(String divisionId) async {
    final removedDivision = _divisions.cast<Division?>().firstWhere(
      (division) => division?.id == divisionId,
      orElse: () => null,
    );
    _divisions.removeWhere((division) => division.id == divisionId);
    for (final entry in _tatamiAssignments.entries) {
      if (entry.value.divisionId == divisionId) {
        if (removedDivision != null) {
          _appendTatamiLog(
            entry.key,
            divisionId,
            'Division selected to delete: ${removedDivision.title}',
          );
        }
        _tatamiAssignments[entry.key] = entry.value.copyWith(divisionId: null);
      }
    }
    _emitDivisions();
    _emitTatami();
    _emitTatamiLogs();
    await _persist();
  }

  Future<void> assignDivisionToTatami(String tatamiName, String? divisionId) {
    return _assignDivisionToTatami(tatamiName, divisionId);
  }

  Future<void> _saveDivisionAndAssignment(Division division) async {
    if (!_tatamiOrder.contains(division.assignedTatamiName)) {
      throw StateError(
        'Tatami "${division.assignedTatamiName}" does not exist. Configure tatamis first.',
      );
    }

    Division? previousDivision;
    final index = _divisions.indexWhere((item) => item.id == division.id);
    if (index == -1) {
      _divisions.add(division);
    } else {
      previousDivision = _divisions[index];
      _divisions[index] = division;
    }

    for (final entry in _tatamiAssignments.entries) {
      if (entry.value.divisionId == division.id &&
          entry.key != division.assignedTatamiName) {
        _tatamiAssignments[entry.key] = entry.value.copyWith(divisionId: null);
      }
    }

    _tatamiAssignments[division.assignedTatamiName] = TatamiAssignment(
      tatamiName: division.assignedTatamiName,
      divisionId: division.id,
    );
    if (previousDivision == null) {
      _appendTatamiLog(
        division.assignedTatamiName,
        division.id,
        'Division assigned to this tatami: ${division.title}',
      );
    } else {
      if (previousDivision.assignedTatamiName != division.assignedTatamiName) {
        _appendTatamiLog(
          division.assignedTatamiName,
          division.id,
          'Division moved to this tatami: ${division.title}',
        );
      }
    }
    _emitDivisions();
    _emitTatami();
    _emitTatamiLogs();
    await _persist();
  }

  Future<void> _assignDivisionToTatami(
    String tatamiName,
    String? divisionId,
  ) async {
    if (!_tatamiOrder.contains(tatamiName)) {
      throw StateError('Tatami "$tatamiName" does not exist.');
    }

    if (divisionId != null) {
      final division = _divisions.cast<Division?>().firstWhere(
        (item) => item?.id == divisionId,
        orElse: () => null,
      );
      for (final entry in _tatamiAssignments.entries) {
        if (entry.value.divisionId == divisionId && entry.key != tatamiName) {
          _tatamiAssignments[entry.key] = entry.value.copyWith(
            divisionId: null,
          );
          if (division != null) {
            _appendTatamiLog(
              entry.key,
              divisionId,
              'Division reassigned away: ${division.title}',
            );
          }
        }
      }

      final divisionIndex = _divisions.indexWhere(
        (division) => division.id == divisionId,
      );
      if (divisionIndex != -1) {
        _divisions[divisionIndex] = _divisions[divisionIndex].copyWith(
          assignedTatamiName: tatamiName,
        );
        _appendTatamiLog(
          tatamiName,
          divisionId,
          'Division moved to this tatami: ${_divisions[divisionIndex].title}',
        );
      }
    }

    _tatamiAssignments[tatamiName] = TatamiAssignment(
      tatamiName: tatamiName,
      divisionId: divisionId,
    );
    _emitDivisions();
    _emitTatami();
    _emitTatamiLogs();
    await _persist();
  }

  void _startRemoteSync() {
    if (tournamentId.trim().isEmpty) {
      return;
    }

    _remoteSyncTimer?.cancel();
    _remoteSyncTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final remoteSnapshot = await _backend.loadTournamentSnapshot(tournamentId);
        if (remoteSnapshot.isEmpty) {
          return;
        }

        final remoteUpdatedAt = _snapshotUpdatedAt(remoteSnapshot);
        if (_lastLocalUpdatedAt != null && remoteUpdatedAt != null &&
            !remoteUpdatedAt.isAfter(_lastLocalUpdatedAt!)) {
          return;
        }

        if (_initialized) {
          _applySnapshot(remoteSnapshot);
          _emitCompetitors();
          _emitDivisions();
          _emitTatamiNames();
          _emitTatamiDefinitions();
          _emitTatami();
          _emitTatamiLogs();
        }
      } catch (_) {
        // Intentionally ignore refresh errors so a temporary backend hiccup does not
        // break the local tournament flow.
      }
    });
  }

  DateTime? _snapshotUpdatedAt(Map<String, dynamic> snapshot) {
    final raw = snapshot['updated_at'];
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  void _applySnapshot(Map<String, dynamic> snapshot) {
    List<Map<String, dynamic>> asMapList(Object? value) {
      final source = value as List<dynamic>? ?? const <dynamic>[];
      return source
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    final competitorsData = asMapList(snapshot['competitors']);
    final divisionsData = asMapList(snapshot['divisions']);
    final tatamiDefinitionsData = asMapList(snapshot['tatamiDefinitions']);
    final tatamiAssignmentsData = asMapList(snapshot['tatamiAssignments']);
    final tatamiLogsData = asMapList(snapshot['tatamiLogs']);

    _competitors
      ..clear()
      ..addAll(
        competitorsData.map((item) {
          final data = Map<String, dynamic>.from(
            item['data'] as Map? ?? const <String, dynamic>{},
          );
          return Competitor.fromMap((item['id'] as String?) ?? '', data);
        }),
      );

    _divisions
      ..clear()
      ..addAll(
        divisionsData.map((item) {
          final data = Map<String, dynamic>.from(
            item['data'] as Map? ?? const <String, dynamic>{},
          );
          return Division.fromMap((item['id'] as String?) ?? '', data);
        }),
      );

    _tatamiOrder = tatamiDefinitionsData
        .map((item) => TatamiDefinition.fromMap(item))
        .map((item) => item.name)
        .where((name) => name.isNotEmpty)
        .toList();

    _tatamiJudgeCounts
      ..clear()
      ..addEntries(
        tatamiDefinitionsData
            .map(TatamiDefinition.fromMap)
            .where((definition) => definition.name.isNotEmpty)
            .map(
              (definition) => MapEntry(
                definition.name,
                _validatedJudgeCount(definition.judgesCount),
              ),
            ),
      );

    _tatamiAssignments
      ..clear()
      ..addEntries(
        tatamiAssignmentsData
            .map((item) => TatamiAssignment.fromMap('', item))
            .where((assignment) => assignment.tatamiName.isNotEmpty)
            .map((assignment) => MapEntry(assignment.tatamiName, assignment)),
      );

    _tatamiLogsByTatami
      ..clear()
      ..addEntries(
        tatamiLogsData
            .map((item) {
              final tatamiName = (item['tatamiName'] as String?) ?? '';
              final logs = asMapList(item['entries'])
                  .map(TatamiLogEntry.fromMap)
                  .toList();
              return MapEntry(tatamiName, logs);
            })
            .where((entry) => entry.key.isNotEmpty),
      );

    for (final tatamiName in _tatamiOrder) {
      _tatamiAssignments.putIfAbsent(
        tatamiName,
        () => TatamiAssignment(tatamiName: tatamiName),
      );
      _tatamiJudgeCounts.putIfAbsent(tatamiName, () => 5);
      _tatamiLogsByTatami.putIfAbsent(tatamiName, () => <TatamiLogEntry>[]);
    }
  }

  Future<void> _loadSnapshot() async {
    final snapshot = await _localStore.loadSnapshot(tournamentId: tournamentId);
    if (snapshot == null) {
      return;
    }
    _lastLocalUpdatedAt = _snapshotUpdatedAt(snapshot);
    _applySnapshot(snapshot);
  }

  Future<void> _persist() async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final snapshot = <String, Object?>{
      'updated_at': timestamp,
      'competitors': _competitors
          .map(
            (competitor) => <String, Object?>{
              'id': competitor.id,
              'data': competitor.toMap(),
            },
          )
          .toList(),
      'divisions': _divisions
          .map(
            (division) => <String, Object?>{
              'id': division.id,
              'data': division.toMap(),
            },
          )
          .toList(),
      'tatamiDefinitions': _currentTatamiDefinitions()
          .map((definition) => definition.toMap())
          .toList(),
      'tatamiAssignments': _orderedTatamiAssignments()
          .map((assignment) => assignment.toMap())
          .toList(),
      'tatamiLogs': _tatamiOrder
          .map(
            (tatamiName) => <String, Object?>{
              'tatamiName': tatamiName,
              'entries':
                  (_tatamiLogsByTatami[tatamiName] ?? const <TatamiLogEntry>[])
                      .map((entry) => entry.toMap())
                      .toList(),
            },
          )
          .toList(),
    };

    _lastLocalUpdatedAt = DateTime.parse(timestamp).toUtc();
    await _localStore.saveSnapshot(snapshot, tournamentId: tournamentId);
    if (tournamentId.trim().isNotEmpty) {
      await _backend.saveTournamentSnapshot(tournamentId, snapshot);
    }
  }

  Stream<T> _watchWithInitial<T>(T initialValue, Stream<T> updates) async* {
    yield initialValue;
    yield* updates;
  }

  List<Competitor> _sortedCompetitors() {
    final competitors = List<Competitor>.from(_competitors);
    competitors.sort((left, right) => left.number.compareTo(right.number));
    return competitors;
  }

  List<Division> _sortedDivisions() {
    final divisions = List<Division>.from(_divisions);
    divisions.sort((left, right) {
      final leftBoost = left.priorityBoostedAt ?? -1;
      final rightBoost = right.priorityBoostedAt ?? -1;
      if (leftBoost != rightBoost) {
        return rightBoost.compareTo(leftBoost);
      }
      final createdAtComparison = left.createdAt.compareTo(right.createdAt);
      if (createdAtComparison != 0) {
        return createdAtComparison;
      }
      return left.title.compareTo(right.title);
    });
    return divisions;
  }

  List<TatamiAssignment> _orderedTatamiAssignments() {
    final names = _tatamiOrder.isEmpty
        ? (() {
            final fallback = _tatamiAssignments.keys.toList();
            fallback.sort();
            return fallback;
          })()
        : _tatamiOrder;
    return names
        .map(
          (name) =>
              _tatamiAssignments[name] ?? TatamiAssignment(tatamiName: name),
        )
        .toList();
  }

  void _emitCompetitors() {
    _competitorsController.add(_sortedCompetitors());
  }

  void _emitDivisions() {
    _divisionsController.add(_sortedDivisions());
  }

  void _emitTatami() {
    _tatamiController.add(_orderedTatamiAssignments());
  }

  void _emitTatamiNames() {
    _tatamiNamesController.add(List<String>.from(_tatamiOrder));
  }

  void _emitTatamiDefinitions() {
    _tatamiDefinitionsController.add(_currentTatamiDefinitions());
  }

  void _emitTatamiLogs() {
    _tatamiLogsController.add(_copyTatamiLogs());
  }

  Map<String, List<TatamiLogEntry>> _copyTatamiLogs() {
    return <String, List<TatamiLogEntry>>{
      for (final entry in _tatamiLogsByTatami.entries)
        entry.key: List<TatamiLogEntry>.from(entry.value),
    };
  }

  void _appendTatamiLog(String tatamiName, String? divisionId, String message) {
    final entries = _tatamiLogsByTatami.putIfAbsent(
      tatamiName,
      () => <TatamiLogEntry>[],
    );
    entries.insert(
      0,
      TatamiLogEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        tatamiName: tatamiName,
        message: message,
        divisionId: divisionId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (entries.length > 200) {
      entries.removeRange(200, entries.length);
    }
  }

  List<TatamiDefinition> _currentTatamiDefinitions() {
    return _tatamiOrder
        .map(
          (name) => TatamiDefinition(
            name: name,
            judgesCount: _tatamiJudgeCounts[name] ?? 5,
          ),
        )
        .toList();
  }

  String _safeFileName(String value) {
    return value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }
}
