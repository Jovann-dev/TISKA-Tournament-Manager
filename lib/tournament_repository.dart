import 'dart:async';

import 'live_match_channel.dart';
import 'live_match_state.dart';
import 'tournament_backend.dart';
import 'tournament_backup.dart';
import 'tournament_local_store.dart';
import 'tournament_models.dart';
import 'tournament_snapshot_merge.dart';

enum TournamentSyncState { localOnly, syncing, synced, offline, conflict }

class TournamentSyncStatus {
  final TournamentSyncState state;
  final String message;
  const TournamentSyncStatus(this.state, this.message);
}

class DivisionExecutionSession {
  final TournamentRepository _repository;
  Division _division;
  Future<void> _operations = Future<void>.value();

  DivisionExecutionSession._(this._repository, this._division);

  Division get division => _division;
  List<Competitor> get competitors => List<Competitor>.unmodifiable(
    _division.competitorIds.map((id) =>
      _repository._competitors.singleWhere((item) => item.id == id)),
  );

  Future<void> _enqueue(Future<Division> Function(Division) operation) {
    final result = _operations.then((_) async {
      _division = await operation(_division);
    });
    _operations = result.catchError((Object error) {});
    return result;
  }

  Future<void> saveResults(
    List<DivisionMatchRecord> records,
    List<DivisionPlacement> placements,
  ) => _enqueue((expected) async {
    final updated = expected.copyWith(
      matchRecords: List<DivisionMatchRecord>.of(records),
      placements: List<DivisionPlacement>.of(placements),
    );
    await _repository.saveDivisionExecutionState(
      expected.assignedTatamiName, expected.id,
      matchRecords: updated.matchRecords,
      placements: updated.placements,
      expectedDivision: expected,
    );
    return updated;
  });

  Future<void> saveInProgress(DivisionInProgressMatch? match) =>
      _enqueue((expected) async {
        await _repository.saveDivisionInProgressMatch(
          expected.assignedTatamiName, expected.id, match,
          expectedDivision: expected,
        );
        return expected.copyWith(inProgressMatch: match);
      });

  Future<void> complete() => _enqueue((expected) async {
    await _repository.completeDivisionOnTatami(
      expected.assignedTatamiName, expected.id,
      expectedDivision: expected,
    );
    return _repository._divisions.singleWhere((item) => item.id == expected.id);
  });
}

class TournamentRepository {
  final TournamentLocalStore _localStore;
  final String tournamentId;
  final bool isAdmin;
  List<CompetitionCategory> _competitionCategories = defaultCompetitionCategories();
  final StreamController<List<CompetitionCategory>> _categoriesController =
      StreamController<List<CompetitionCategory>>.broadcast();
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
  LiveMatchChannel? _liveChannel;
  final TournamentBackend _backend;
  Timer? _remoteSyncTimer;
  Map<String, dynamic> _syncBase = <String, dynamic>{};
  Map<String, dynamic>? _pendingRemoteSnapshot;
  Future<void>? _syncOperation;
  bool _disposed = false;
  bool _deleting = false;
  int _localGeneration = 0;
  int _retryFailures = 0;
  DateTime _nextRetryAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _localWriteQueue = Future<void>.value();
  final StreamController<TournamentSyncStatus> _syncStatusController =
      StreamController<TournamentSyncStatus>.broadcast();
  TournamentSyncStatus _syncStatus = const TournamentSyncStatus(
    TournamentSyncState.localOnly,
    'Saved locally',
  );
  List<String> _tatamiOrder = const <String>[];

  bool _initialized = false;

  TournamentRepository({
    TournamentLocalStore? localStore,
    TournamentBackend? backend,
    this.tournamentId = '',
    this.isAdmin = false,
  }) : _localStore = localStore ?? TournamentLocalStore(),
       _backend = backend ?? TournamentBackend();

  Future<void> initialize({
    required List<TatamiDefinition> defaultTatamis,
  }) async {
    if (_initialized) {
      return;
    }

    await _loadSnapshot();
    if (tournamentId.trim().isNotEmpty) {
      await synchronize();
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
    if (tournamentId.trim().isNotEmpty) {
      _liveChannel = LiveMatchChannel(
        transport: _backend.createLiveMatchTransport(tournamentId),
        tournamentId: tournamentId,
        onState: _acceptLiveMatchState,
      )..start();
    }
  }

  Stream<TournamentSyncStatus> watchSyncStatus() =>
      _watchWithInitial(_syncStatus, _syncStatusController.stream);

  Stream<List<CompetitionCategory>> watchCompetitionCategories() =>
      _watchWithInitial(List<CompetitionCategory>.unmodifiable(_competitionCategories),
          _categoriesController.stream);

  Future<void> saveCompetitionCategory(CompetitionCategory category) async {
    if (!isAdmin) throw StateError('Only admins can manage competition categories.');
    final checked = CompetitionCategory.fromMap(Map<String, dynamic>.from(category.toMap()));
    final index = _competitionCategories.indexWhere((item) => item.id == checked.id);
    if (_competitionCategories.any((item) => item.id != checked.id &&
        item.name.toLowerCase() == checked.name.toLowerCase())) {
      throw StateError('A competition category with this name already exists.');
    }
    if (index != -1 && (_competitionCategories[index].name != checked.name ||
        _competitionCategories[index].template != checked.template)) {
      throw StateError('Existing category names and templates cannot be changed.');
    }
    if (index == -1) {
      _competitionCategories.add(checked);
    } else {
      _competitionCategories[index] = checked;
    }
    _emitCategories();
    await _persist();
  }

  Future<void> deleteCompetitionCategory(String categoryId) async {
    if (!isAdmin) throw StateError('Only admins can manage competition categories.');
    if (_divisions.any((division) => division.categoryId == categoryId)) {
      throw StateError('This category is used by a division. Disable it instead.');
    }
    _competitionCategories.removeWhere((item) => item.id == categoryId);
    _emitCategories();
    await _persist();
  }

  void _emitCategories() {
    _categoriesController.add(List<CompetitionCategory>.unmodifiable(_competitionCategories));
  }

  TournamentBackup captureBackup() => TournamentBackup(
    tournamentId: tournamentId,
    snapshot: _buildSnapshot(),
  );

  Future<void> restoreBackup(TournamentBackup backup) async {
    if (_disposed || _deleting || backup.tournamentId != tournamentId) {
      throw StateError('The backup must belong to the open tournament.');
    }
    final checked = TournamentBackup.decode(backup.encode());
    await synchronize();
    if (_syncStatus.state == TournamentSyncState.conflict) {
      throw StateError('Resolve synchronization conflicts before restoring.');
    }
    if (!isAdmin) {
      final restoredCategories = [for (final row in checked.snapshot['competitionCategories'] as List)
        CompetitionCategory.fromMap(Map<String, dynamic>.from(row as Map))];
      if (restoredCategories.length != _competitionCategories.length ||
          _competitionCategories.any((current) => !restoredCategories.any((item) =>
              item.id == current.id && item.name == current.name &&
              item.template == current.template && item.enabled == current.enabled &&
              item.teamRules == current.teamRules))) {
        throw StateError('Only admins can restore changes to competition categories.');
      }
    }
    final replacements = {for (final item in checked.divisions) item.id: item};
    final competitors = {for (final item in checked.competitors) item.id: item};
    for (final current in _divisions.where(divisionHasResults)) {
      final replacement = replacements[current.id];
      if (replacement == null ||
          !sameDivisionState(current, replacement) ||
          current.competitorIds.any((id) {
            final replacement = competitors[id];
            return replacement == null || !sameCompetitor(
              _competitors.singleWhere((item) => item.id == id), replacement,
            );
          })) {
        throw StateError('Redo affected started divisions before restoring a backup.');
      }
    }
    final snapshot = checked.snapshot;
    validateTournamentSnapshot(_buildSnapshot(), snapshot, enforceCategoryAvailability: false);
    _applySnapshot(snapshot);
    _emitAll();
    await _persist();
  }

  void _setSyncStatus(TournamentSyncState state, String message) {
    _syncStatus = TournamentSyncStatus(state, message);
    if (!_disposed) _syncStatusController.add(_syncStatus);
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
  /// points) from local execution or other devices in the same tournament.
  /// Broadcast state is ephemeral and is not written to tournament snapshots.
  Stream<LiveMatchState?> watchLiveMatchState(String tatamiName) {
    return _watchWithInitial<LiveMatchState?>(
      _liveMatchStates[tatamiName],
      _liveMatchController(tatamiName).stream,
    );
  }

  void publishLiveMatchState(LiveMatchState state) {
    if (_disposed || _deleting) return;
    if (!_divisions.any((division) =>
        division.id == state.divisionId &&
        division.assignedTatamiName == state.tatamiName &&
        division.progress == DivisionProgress.running)) {
      clearLiveMatchState(state.tatamiName, divisionId: state.divisionId);
      return;
    }
    final channel = _liveChannel;
    if (channel == null) {
      _acceptLiveMatchState(state.tatamiName, state);
    } else {
      channel.publish(state);
    }
  }

  void clearLiveMatchState(String tatamiName, {String? divisionId}) {
    if (_disposed) return;
    if (divisionId != null &&
        _liveMatchStates[tatamiName]?.divisionId != divisionId) {
      return;
    }
    final channel = _liveChannel;
    if (channel == null) {
      _acceptLiveMatchState(tatamiName, null);
    } else {
      channel.clear(tatamiName);
    }
  }

  void _acceptLiveMatchState(String tatamiName, LiveMatchState? state) {
    if (_disposed) return;
    if (state != null && !_divisions.any((division) =>
        division.id == state.divisionId &&
        division.assignedTatamiName == tatamiName &&
        division.progress == DivisionProgress.running)) {
      return;
    }
    _liveMatchStates[tatamiName] = state;
    _liveMatchController(tatamiName).add(state);
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
    _validateCompetitorReplacement([
      ..._competitors.where((item) => item.id != competitor.id),
      competitor,
    ]);
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
    _ensureCompetitorsUnlocked({competitorId});
    if (_divisions.any((division) => division.isTeamDivision && division.competitorIds.contains(competitorId))) {
      throw StateError('Remove this competitor from team rosters before deleting the registration.');
    }
    if (_divisions.any(
      (division) =>
          division.competitorIds.contains(competitorId) &&
          division.competitorIds.length <= 2,
    )) {
      throw StateError(
        'Remove this competitor from its queued divisions first.',
      );
    }
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
    _validateCompetitorReplacement(competitors);
    final replacementIds = competitors.map((item) => item.id).toSet();
    for (final division in _divisions) {
      if (!division.isTeamDivision && division.competitorIds.where(replacementIds.contains).length < 2) {
        throw StateError(
          'Import would leave "${division.title}" with fewer than two competitors.',
        );
      }
    }
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
    if (_divisions.any(divisionHasResults)) {
      throw StateError(
        'Redo started divisions before clearing tournament data.',
      );
    }
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

  Future<void> saveDivision(Division division) {
    return _saveDivisionAndAssignment(division);
  }

  /// Persists (or clears, when null) the currently unfinished match's
  /// points/warnings/timer/events so they survive leaving and re-entering
  /// the execution screen.
  Future<void> saveDivisionInProgressMatch(
    String tatamiName,
    String divisionId,
    DivisionInProgressMatch? inProgressMatch, {
    Division? expectedDivision,
  }
  ) async {
    final divisionIndex = _divisions.indexWhere(
      (item) => item.id == divisionId,
    );
    if (divisionIndex == -1) {
      if (expectedDivision != null) throw StateError('Division not found.');
      return;
    }
    final existing = _divisions[divisionIndex];
    _checkExecutionState(existing, expectedDivision);
    if (existing.assignedTatamiName != tatamiName ||
        (inProgressMatch != null &&
            existing.progress != DivisionProgress.running)) {
      return;
    }
    _divisions[divisionIndex] = _divisions[divisionIndex].copyWith(
      inProgressMatch: inProgressMatch,
    );
    _emitDivisions();
    await _persist();
  }

  Future<void> setTournamentUserPassword(String password) {
    if (tournamentId.trim().isEmpty) {
      throw StateError('A tournament ID is required.');
    }
    return _backend.setTournamentUserPassword(tournamentId, password);
  }

  Future<void> deleteTournament() async {
    if (_disposed || tournamentId.trim().isEmpty) {
      throw StateError('This tournament cannot be deleted.');
    }
    if (_deleting) return;

    _deleting = true;
    _remoteSyncTimer?.cancel();
    try {
      final syncOperation = _syncOperation;
      if (syncOperation != null) await syncOperation;
      await _localWriteQueue;
      await _backend.deleteTournament(tournamentId);

      _competitors.clear();
      _divisions.clear();
      _tatamiAssignments.clear();
      _tatamiOrder = const <String>[];
      _tatamiJudgeCounts.clear();
      _tatamiLogsByTatami.clear();
      _liveMatchStates.clear();
      _syncBase = <String, dynamic>{};
      _pendingRemoteSnapshot = null;
      _emitAll();
      await _localStore.clearTournamentData(tournamentId: tournamentId);
      _setSyncStatus(TournamentSyncState.localOnly, 'Tournament deleted');
    } catch (_) {
      _deleting = false;
      _startRemoteSync();
      rethrow;
    }
  }

  Future<void> saveDivisionExecutionState(
    String tatamiName,
    String divisionId, {
    required List<DivisionMatchRecord> matchRecords,
    required List<DivisionPlacement> placements,
    String? logMessage,
    Division? expectedDivision,
  }) async {
    final divisionIndex = _divisions.indexWhere(
      (item) => item.id == divisionId,
    );
    if (divisionIndex == -1) {
      throw StateError('Division not found.');
    }
    final existing = _divisions[divisionIndex];
    _checkExecutionState(existing, expectedDivision);
    if (existing.assignedTatamiName != tatamiName ||
        existing.progress != DivisionProgress.running) {
      throw StateError(
        'Division is no longer running on this tatami. Reopen it from the competition floor.',
      );
    }

    _divisions[divisionIndex] = _divisions[divisionIndex].copyWith(
      matchRecords: List<DivisionMatchRecord>.from(matchRecords),
      placements: List<DivisionPlacement>.from(placements),
    );
    _emitDivisions();
    _emitTatamiLogs();
    await _persist();
  }

  void _checkExecutionState(Division existing, Division? expected) {
    if (expected != null &&
        (_syncStatus.state == TournamentSyncState.conflict ||
            !sameDivisionState(existing, expected))) {
      throw StateError(
        'Division changed in another editor. Reopen it before saving results.',
      );
    }
  }

  Future<DivisionExecutionSession> openDivisionExecution(
    String tatamiName, String divisionId,
  ) async {
    await startDivisionOnTatami(tatamiName, divisionId);
    return DivisionExecutionSession._(
      this, _divisions.singleWhere((item) => item.id == divisionId),
    );
  }

  Future<void> startDivisionOnTatami(
    String tatamiName,
    String divisionId,
  ) async {
    await synchronize();
    if (_syncStatus.state == TournamentSyncState.conflict) {
      throw StateError(_syncStatus.message);
    }
    final divisionIndex = _divisions.indexWhere(
      (item) => item.id == divisionId,
    );
    if (divisionIndex == -1) {
      throw StateError('Division not found.');
    }
    if (!_tatamiOrder.contains(tatamiName)) {
      throw StateError('Tatami "$tatamiName" does not exist.');
    }

    final existing = _divisions[divisionIndex];
    if (existing.assignedTatamiName != tatamiName) {
      throw StateError(
        'Division has moved to another tatami. Reopen it there.',
      );
    }
    if (existing.progress == DivisionProgress.completed) {
      throw StateError('Redo a completed division before starting it.');
    }
    _ensureTatamiAvailable(tatamiName, divisionId);
    if (existing.progress == DivisionProgress.running) return;

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
    _appendDivisionLifecycleLog(
      tatamiName: tatamiName,
      division: division,
      activity: 'Started',
    );
    _emitDivisions();
    _emitTatami();
    _emitTatamiLogs();
    await _persist();
    await synchronize();
    if (_syncStatus.state == TournamentSyncState.conflict) {
      throw StateError(_syncStatus.message);
    }
  }

  Future<void> completeDivisionOnTatami(
    String tatamiName,
    String divisionId, {
    Division? expectedDivision,
  }
  ) async {
    final divisionIndex = _divisions.indexWhere(
      (item) => item.id == divisionId,
    );
    if (divisionIndex == -1) {
      throw StateError('Division not found.');
    }

    final existing = _divisions[divisionIndex];
  _checkExecutionState(existing, expectedDivision);
    if (existing.assignedTatamiName != tatamiName) {
      throw StateError('Division has moved to another tatami.');
    }
    if (existing.progress == DivisionProgress.completed) return;
    if (existing.progress != DivisionProgress.running) {
      throw StateError('Start the division before completing it.');
    }

    final division = _divisions[divisionIndex].copyWith(
      progress: DivisionProgress.completed,
      completedAt: DateTime.now().millisecondsSinceEpoch,
      inProgressMatch: null,
    );
    _divisions[divisionIndex] = division;
    final currentAssignment = _tatamiAssignments[tatamiName];
    if (currentAssignment?.divisionId == divisionId) {
      _tatamiAssignments[tatamiName] = TatamiAssignment(
        tatamiName: tatamiName,
        divisionId: null,
      );
    }
    _appendDivisionLifecycleLog(
      tatamiName: tatamiName,
      division: division,
      activity: 'Finished',
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
    if (!_tatamiOrder.contains(tatamiName)) {
      throw StateError('Tatami "$tatamiName" does not exist.');
    }

    final division = _divisions[divisionIndex].copyWith(
      progress: DivisionProgress.queued,
      startedAt: null,
      completedAt: null,
      priorityBoostedAt: DateTime.now().millisecondsSinceEpoch,
      assignedTatamiName: tatamiName,
      matchRecords: const <DivisionMatchRecord>[],
      placements: const <DivisionPlacement>[],
      inProgressMatch: null,
    );
    _divisions[divisionIndex] = division;
    _emitDivisions();
    _emitTatami();
    _emitTatamiLogs();
    await _persist();
  }

  Future<void> deleteDivision(String divisionId) async {
    if (_divisions.any(
      (division) => division.id == divisionId && divisionHasResults(division),
    )) {
      throw StateError('Redo the division before deleting it.');
    }
    _divisions.removeWhere((division) => division.id == divisionId);
    for (final entry in _tatamiAssignments.entries) {
      if (entry.value.divisionId == divisionId) {
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
    if (index != -1) {
      previousDivision = _divisions[index];
      if (!isAdmin && previousDivision.teamRules != division.teamRules) {
        throw StateError('Only admins can change saved team rules.');
      }
      if (divisionHasResults(previousDivision) &&
          !sameDivisionBracket(previousDivision, division)) {
        throw StateError(
          'Redo the division before changing its entrants, draw order, or competition criteria.',
        );
      }
      division = division.copyWith(
        competitionCategoryId: divisionHasResults(previousDivision)
          ? previousDivision.competitionCategoryId : division.competitionCategoryId,
        competitionCategoryName: divisionHasResults(previousDivision)
          ? previousDivision.competitionCategoryName : division.competitionCategoryName,
        competitionTemplate: divisionHasResults(previousDivision)
          ? previousDivision.competitionTemplate : division.competitionTemplate,
        progress: previousDivision.progress,
        startedAt: previousDivision.startedAt,
        completedAt: previousDivision.completedAt,
        priorityBoostedAt: previousDivision.priorityBoostedAt,
        matchRecords: previousDivision.matchRecords,
        placements: previousDivision.placements,
        inProgressMatch: previousDivision.inProgressMatch,
      );
    } else {
      division = division.copyWith(
        progress: DivisionProgress.queued,
        startedAt: null,
        completedAt: null,
        matchRecords: [],
        placements: [],
        inProgressMatch: null,
      );
    }
    final prospective = _buildSnapshot();
    prospective['divisions'] = [
      for (final item in _divisions.where((item) => item.id != division.id))
        {'id': item.id, 'data': item.toMap()},
      {'id': division.id, 'data': division.toMap()},
    ];
    validateTournamentSnapshot(_buildSnapshot(), prospective);
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
    if (previousDivision != null &&
        previousDivision.assignedTatamiName != division.assignedTatamiName) {
      _appendDivisionLifecycleLog(
        tatamiName: division.assignedTatamiName,
        division: division,
        activity:
            'Moved ${previousDivision.assignedTatamiName} -> ${division.assignedTatamiName}',
      );
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
      final selected = _divisions.where((item) => item.id == divisionId);
      if (selected.isEmpty) throw StateError('Division not found.');
      if (selected.single.progress == DivisionProgress.running) {
        _ensureTatamiAvailable(tatamiName, divisionId);
      }
      for (final entry in _tatamiAssignments.entries) {
        if (entry.value.divisionId == divisionId && entry.key != tatamiName) {
          _tatamiAssignments[entry.key] = entry.value.copyWith(
            divisionId: null,
          );
        }
      }

      final divisionIndex = _divisions.indexWhere(
        (division) => division.id == divisionId,
      );
      if (divisionIndex != -1) {
        final previousTatami = _divisions[divisionIndex].assignedTatamiName;
        _divisions[divisionIndex] = _divisions[divisionIndex].copyWith(
          assignedTatamiName: tatamiName,
        );
        _appendDivisionLifecycleLog(
          tatamiName: tatamiName,
          division: _divisions[divisionIndex],
          activity: 'Moved $previousTatami -> $tatamiName',
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
    _remoteSyncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (DateTime.now().isBefore(_nextRetryAt)) return;
      unawaited(synchronize());
    });
  }

  Future<void> synchronize() {
    if (_disposed || _deleting || tournamentId.trim().isEmpty) {
      return Future<void>.value();
    }
    return _syncOperation ??= _synchronize().whenComplete(() {
      _syncOperation = null;
    });
  }

  Future<void> _synchronize() async {
    _setSyncStatus(TournamentSyncState.syncing, 'Synchronizing');
    try {
      await _localWriteQueue;
      for (
        var attempt = 0;
        attempt < 4 && !_disposed && !_deleting;
        attempt++
      ) {
        final remote = await _backend.loadTournamentSnapshot(tournamentId);
        if (_disposed || _deleting) return;
        if (_pendingRemoteSnapshot == null) {
          _syncBase = remote;
          if (remote.isNotEmpty) {
            _applySnapshot(remote);
            _emitAll();
            await _saveLocalState();
          }
          break;
        }
        final generation = _localGeneration;
        final sent = _pendingRemoteSnapshot!;
        final candidate = mergeTournamentSnapshots(
          base: _syncBase,
          local: sent,
          remote: remote,
        );
        try {
          validateTournamentSnapshot(remote, candidate, enforceCategoryAvailability: false);
        } on StateError catch (error) {
          throw TournamentSyncConflict(error.message);
        }
        final saved = await _backend.saveTournamentSnapshot(
          tournamentId,
          candidate,
          expectedRevision: (remote['revision'] as num?)?.toInt() ?? 0,
        );
        if (_disposed || _deleting) return;
        if (saved == null) {
          if (attempt == 3) {
            throw const TournamentSyncConflict(
              'Other operators are saving. Local changes are retained; retry synchronization.',
            );
          }
          continue;
        }
        final latest = _buildSnapshot();
        if (generation == _localGeneration) {
          _syncBase = saved;
          _pendingRemoteSnapshot = null;
          _applySnapshot(saved);
        } else {
          final rebased = mergeTournamentSnapshots(
            base: sent,
            local: latest,
            remote: saved,
          );
          _syncBase = saved;
          _applySnapshot(rebased);
          _pendingRemoteSnapshot = rebased;
        }
        _emitAll();
        await _saveLocalState();
        if (_pendingRemoteSnapshot == null) break;
      }
      _retryFailures = 0;
      _nextRetryAt = DateTime.fromMillisecondsSinceEpoch(0);
      _setSyncStatus(
        _pendingRemoteSnapshot == null
            ? TournamentSyncState.synced
            : TournamentSyncState.offline,
        _pendingRemoteSnapshot == null
            ? 'Synchronized'
            : 'Saved locally; synchronization pending',
      );
    } on TournamentSyncConflict catch (error) {
      _nextRetryAt = DateTime.now().add(const Duration(seconds: 30));
      _setSyncStatus(TournamentSyncState.conflict, error.message);
    } catch (error) {
      _retryFailures = (_retryFailures + 1).clamp(1, 5);
      _nextRetryAt = DateTime.now().add(Duration(seconds: 1 << _retryFailures));
      _setSyncStatus(
        TournamentSyncState.offline,
        'Saved locally; synchronization pending: $error',
      );
    }
  }

  void _emitAll() {
    _emitCategories();
    _emitCompetitors();
    _emitDivisions();
    _emitTatamiNames();
    _emitTatamiDefinitions();
    _emitTatami();
    _emitTatamiLogs();
  }

  void _ensureTatamiAvailable(String tatamiName, String divisionId) {
    if (_divisions.any(
      (division) =>
          division.id != divisionId &&
          division.assignedTatamiName == tatamiName &&
          division.progress == DivisionProgress.running,
    )) {
      throw StateError(
        'Another division is already running on $tatamiName. Finish or redo it first.',
      );
    }
  }

  void _ensureCompetitorsUnlocked(Set<String> ids) {
    if (_divisions.any(
      (division) =>
          divisionHasResults(division) &&
          division.competitorIds.any(ids.contains),
    )) {
      throw StateError(
        'Competitors in started divisions cannot be edited or removed. Redo the divisions first.',
      );
    }
  }

  void _validateCompetitorReplacement(List<Competitor> replacements) {
    final ids = replacements.map((item) => item.id).toSet();
    final numbers = replacements.map((item) => item.number).toSet();
    if (ids.length != replacements.length ||
        numbers.length != replacements.length) {
      throw StateError('Competitor IDs and numbers must be unique.');
    }
    if (_divisions.any((division) => division.isTeamDivision && !division.competitorIds.every(ids.contains))) {
      throw StateError('Remove affected competitors from team rosters before replacing registrations.');
    }
    for (final previous in _competitors) {
      final matches = replacements.where((item) => item.id == previous.id);
      if (matches.isEmpty || !sameCompetitor(matches.single, previous)) {
        _ensureCompetitorsUnlocked({previous.id});
      }
    }
  }

  void _applySnapshot(Map<String, dynamic> snapshot) {
    _competitionCategories = snapshot.containsKey('competitionCategories')
      ? [for (final row in snapshot['competitionCategories'] as List)
        CompetitionCategory.fromMap(Map<String, dynamic>.from(row as Map))]
      : defaultCompetitionCategories();
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
                  .map(
                    (entry) => entry.lifecycleEntry(
                      division: _divisions
                          .where((division) => division.id == entry.divisionId)
                          .firstOrNull,
                    ),
                  )
                  .whereType<TatamiLogEntry>()
                  .toList();
              logs.sort(
                (left, right) => right.timestamp.compareTo(left.timestamp),
              );
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
    _applySnapshot(snapshot);
    final storedBase = snapshot['_syncBase'];
    _syncBase = storedBase is Map
        ? Map<String, dynamic>.from(storedBase)
        : <String, dynamic>{};
    if (snapshot['_syncPending'] != false && tournamentId.isNotEmpty) {
      _pendingRemoteSnapshot = _buildSnapshot();
    }
  }

  Future<void> _persist() async {
    _localGeneration++;
    if (tournamentId.trim().isNotEmpty) {
      _pendingRemoteSnapshot = _buildSnapshot();
    }
    await _saveLocalState();
    if (!_disposed &&
        _initialized &&
        !_deleting &&
        tournamentId.trim().isNotEmpty &&
        !DateTime.now().isBefore(_nextRetryAt)) {
      unawaited(synchronize());
    }
  }

  Map<String, dynamic> _buildSnapshot() {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    return <String, dynamic>{
      'updated_at': timestamp,
      'competitionCategories': _competitionCategories.map((item) => item.toMap()).toList(),
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
      'tatamiLogs': _tatamiLogsByTatami.keys
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
  }

  Future<void> _saveLocalState() {
    final snapshot = <String, dynamic>{
      ..._buildSnapshot(),
      '_syncBase': _syncBase,
      '_syncPending': _pendingRemoteSnapshot != null,
    };
    final write = _localWriteQueue.then(
      (_) => _localStore.saveSnapshot(snapshot, tournamentId: tournamentId),
    );
    _localWriteQueue = write.catchError((Object error) {
      _setSyncStatus(TournamentSyncState.offline, 'Local save failed: $error');
    });
    return write;
  }

  Future<void> dispose() async {
    _disposed = true;
    _remoteSyncTimer?.cancel();
    await _liveChannel?.dispose();
    await _localWriteQueue;
    await Future.wait([
      _categoriesController.close(),
      _competitorsController.close(),
      _divisionsController.close(),
      _tatamiController.close(),
      _tatamiNamesController.close(),
      _tatamiDefinitionsController.close(),
      _tatamiLogsController.close(),
      _syncStatusController.close(),
      ..._liveMatchControllers.values.map((controller) => controller.close()),
    ]);
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
    for (final state in _liveMatchStates.values.whereType<LiveMatchState>().toList()) {
      if (!_divisions.any((division) =>
          division.id == state.divisionId &&
          division.assignedTatamiName == state.tatamiName &&
          division.progress == DivisionProgress.running)) {
        clearLiveMatchState(state.tatamiName, divisionId: state.divisionId);
      }
    }
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

  void _appendDivisionLifecycleLog({
    required String tatamiName,
    required Division division,
    required String activity,
  }) {
    _appendTatamiLog(
      tatamiName,
      division.id,
      '$activity: ${division.title} (${division.competitorIds.length} competitors)',
      divisionTitle: division.title,
      activity: activity.startsWith('Moved ') ? 'Moved' : activity,
      competitorCount: division.competitorIds.length,
    );
  }

  void _appendTatamiLog(
    String tatamiName,
    String? divisionId,
    String message, {
    String? divisionTitle,
    String? activity,
    int? competitorCount,
  }) {
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
        divisionTitle: divisionTitle,
        activity: activity,
        competitorCount: competitorCount,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
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
}
