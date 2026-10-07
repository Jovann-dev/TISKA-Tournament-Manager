import 'dart:convert';

import 'tournament_models.dart';

class TournamentSyncConflict implements Exception {
  final String message;
  const TournamentSyncConflict(this.message);

  @override
  String toString() => message;
}

Map<String, dynamic> mergeTournamentSnapshots({
  required Map<String, dynamic> base,
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
}) {
  final merged = Map<String, dynamic>.from(remote);
  for (final section in <String, String>{
    'competitors': 'id',
    'divisions': 'id',
    'tatamiDefinitions': 'name',
  }.entries) {
    merged[section.key] = _mergeRows(
      section.key,
      section.value,
      base[section.key],
      local[section.key],
      remote[section.key],
    );
  }
  List<Map<String, dynamic>> flattenLogs(Map<String, dynamic> snapshot) => [
    for (final group in (snapshot['tatamiLogs'] as List? ?? const []))
      for (final entry in (group['entries'] as List? ?? const []))
        Map<String, dynamic>.from(entry as Map),
  ];
  final logs = _mergeRows(
    'logs',
    'id',
    flattenLogs(base),
    flattenLogs(local),
    flattenLogs(remote),
  );
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final log in logs) {
    grouped.putIfAbsent(log['tatamiName'] as String, () => []).add(log);
  }
  merged['tatamiLogs'] = [
    for (final group in grouped.entries)
      {'tatamiName': group.key, 'entries': group.value},
  ];
  merged['tatamiAssignments'] = [
    for (final definition in merged['tatamiDefinitions'] as List)
      {
        'tatamiName': definition['name'],
        'divisionId': _runningDivisionId(
          merged['divisions'] as List,
          definition['name'] as String,
        ),
      },
  ];
  return merged;
}

String? _runningDivisionId(List divisions, String tatami) {
  for (final division in divisions) {
    final data = division['data'] as Map;
    if (data['assignedTatamiName'] == tatami && data['progress'] == 'running') {
      return division['id'] as String;
    }
  }
  return null;
}

List<Map<String, dynamic>> _mergeRows(
  String section,
  String key,
  Object? base,
  Object? local,
  Object? remote,
) {
  Map<String, Map<String, dynamic>> index(Object? rows) => {
    for (final row in (rows as List? ?? const []))
      row[key] as String: Map<String, dynamic>.from(row as Map),
  };
  final baseRows = index(base);
  final localRows = index(local);
  final remoteRows = index(remote);
  final result = <Map<String, dynamic>>[];
  for (final id in {...baseRows.keys, ...remoteRows.keys, ...localRows.keys}) {
    final original = baseRows[id];
    final mine = localRows[id];
    final theirs = remoteRows[id];
    final localChanged = !_same(original, mine);
    final remoteChanged = !_same(original, theirs);
    if (localChanged && remoteChanged && !_same(mine, theirs)) {
      throw TournamentSyncConflict(
        'Conflicting changes to $section "$id". Local changes are retained; '
        'resolve the conflict before synchronizing.',
      );
    }
    final chosen = localChanged ? mine : theirs;
    if (chosen != null) result.add(chosen);
  }
  return result;
}

bool _same(Object? left, Object? right) =>
    jsonEncode(_canonical(left)) == jsonEncode(_canonical(right));

bool divisionHasResults(Division division) =>
    division.progress != DivisionProgress.queued ||
    division.matchRecords.isNotEmpty ||
    division.placements.isNotEmpty ||
    division.inProgressMatch != null;

bool sameDivisionBracket(Division left, Division right) =>
    _same(left.competitorIds, right.competitorIds) &&
    left.competitionType == right.competitionType &&
    left.minAge == right.minAge &&
    left.maxAge == right.maxAge &&
    left.minBeltRank == right.minBeltRank &&
    left.maxBeltRank == right.maxBeltRank &&
    left.gender == right.gender;

bool sameCompetitor(Competitor left, Competitor right) =>
    _same(left.toMap(), right.toMap());

bool sameDivisionState(Division left, Division right) =>
  left.id == right.id && _same(left.toMap(), right.toMap());

void validateTournamentSnapshot(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) {
  List<Division> divisions(Map<String, dynamic> snapshot) => [
    for (final row in (snapshot['divisions'] as List? ?? const []))
      Division.fromMap(
        row['id'] as String,
        Map<String, dynamic>.from(row['data'] as Map),
      ),
  ];
  Map<String, Map> competitors(Map<String, dynamic> snapshot) => {
    for (final row in (snapshot['competitors'] as List? ?? const []))
      row['id'] as String: row['data'] as Map,
  };
  final previous = divisions(before);
  final current = divisions(after);
  final competitorRows = competitors(after);
  final previousCompetitors = competitors(before);
  final tatamis = {
    for (final row in (after['tatamiDefinitions'] as List? ?? const []))
      row['name'] as String,
  };
  final runningTatamis = <String>{};
  final numbers = <String>{};
  for (final competitor in competitorRows.values) {
    if (!numbers.add(competitor['number'] as String)) {
      throw StateError('Competitor numbers must be unique.');
    }
  }
  for (final division in current) {
    if (division.competitorIds.length < 2 ||
        division.competitorIds.length > 16 ||
        division.competitorIds.toSet().length !=
            division.competitorIds.length ||
        !division.competitorIds.every(competitorRows.containsKey)) {
      throw StateError(
        'Division "${division.title}" needs 2-16 unique registered competitors.',
      );
    }
    if (!tatamis.contains(division.assignedTatamiName)) {
      throw StateError('Division tatami does not exist.');
    }
    if (division.progress == DivisionProgress.running &&
        !runningTatamis.add(division.assignedTatamiName)) {
      throw StateError(
        'Only one division can run on ${division.assignedTatamiName}.',
      );
    }
  }
  for (final oldDivision in previous) {
    final replacements = current.where((item) => item.id == oldDivision.id);
    if (replacements.isEmpty) {
      if (divisionHasResults(oldDivision)) {
        throw StateError('Redo the division before deleting it.');
      }
      continue;
    }
    final replacement = replacements.single;
    if ((oldDivision.progress == DivisionProgress.queued &&
            replacement.progress == DivisionProgress.completed) ||
        (oldDivision.progress == DivisionProgress.completed &&
            replacement.progress == DivisionProgress.running)) {
      throw StateError(
        'Invalid division lifecycle transition. Start or redo the division first.',
      );
    }
    if (!divisionHasResults(oldDivision)) continue;
    final explicitlyReset =
        replacement.progress == DivisionProgress.queued &&
        replacement.matchRecords.isEmpty &&
        replacement.placements.isEmpty &&
        replacement.inProgressMatch == null &&
        replacement.startedAt == null &&
        replacement.completedAt == null;
    if (explicitlyReset) continue;
    if (replacement.progress == DivisionProgress.queued &&
        oldDivision.progress != DivisionProgress.queued) {
      throw StateError(
        'Redo must clear all results and unfinished match state.',
      );
    }
    if (!sameDivisionBracket(oldDivision, replacement)) {
      throw StateError('Redo the division before changing its bracket.');
    }
    for (final id in oldDivision.competitorIds) {
      if (!_same(previousCompetitors[id], competitorRows[id])) {
        throw StateError(
          'Competitors in a started division cannot be edited or removed. Redo it first.',
        );
      }
    }
  }
}

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}
