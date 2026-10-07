import 'dart:convert';
import 'dart:typed_data';

import 'tournament_models.dart';
import 'tournament_snapshot_merge.dart';

class TournamentBackup {
  static const int version = 1;
  static const String format = 'tiska-tournament-backup';
  static const List<String> _sections = [
    'competitors', 'divisions', 'tatamiDefinitions',
    'tatamiAssignments', 'tatamiLogs',
  ];

  final String tournamentId;
  final DateTime capturedAt;
  final Map<String, dynamic> _snapshot;

  TournamentBackup({
    required this.tournamentId,
    required Map<String, dynamic> snapshot,
    DateTime? capturedAt,
  }) : capturedAt = capturedAt ?? DateTime.now().toUtc(),
       _snapshot = _copy({
         for (final section in _sections) section: snapshot[section] ?? [],
       });

  Map<String, dynamic> get snapshot => _copy(_snapshot);

  List<Competitor> get competitors => [
    for (final row in _snapshot['competitors'] as List)
      Competitor.fromMap(row['id'] as String, _map(row['data'])),
  ];

  List<Division> get divisions => [
    for (final row in _snapshot['divisions'] as List)
      Division.fromMap(row['id'] as String, _map(row['data'])),
  ];

  List<TatamiDefinition> get tatamiDefinitions => [
    for (final row in _snapshot['tatamiDefinitions'] as List)
      TatamiDefinition.fromMap(_map(row)),
  ];

  Map<String, List<TatamiLogEntry>> get tatamiLogs => {
    for (final group in _snapshot['tatamiLogs'] as List)
      group['tatamiName'] as String: [
        for (final entry in group['entries'] as List)
          TatamiLogEntry.fromMap(_map(entry)),
      ],
  };

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode({
    'format': format,
    'version': version,
    'tournamentId': tournamentId,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'snapshot': _snapshot,
  })));

  factory TournamentBackup.decode(List<int> bytes) {
    try {
      final envelope = _map(jsonDecode(utf8.decode(bytes)));
      if (envelope['format'] != format || envelope['version'] != version) {
        throw const FormatException('Unsupported tournament backup format or version.');
      }
      final tournamentId = envelope['tournamentId'];
      final capturedAt = DateTime.tryParse(envelope['capturedAt'] as String);
      if (tournamentId is! String || tournamentId.isEmpty || capturedAt == null) {
        throw const FormatException('Invalid tournament backup metadata.');
      }
      final snapshot = _map(envelope['snapshot']);
      for (final section in _sections) {
        if (snapshot[section] is! List) {
          throw FormatException('Missing backup section: $section.');
        }
        final keys = <String>{};
        final key = section.startsWith('tatami')
            ? (section == 'tatamiDefinitions' ? 'name' : 'tatamiName')
            : 'id';
        for (final value in snapshot[section] as List) {
          final row = _map(value);
          final id = row[key];
          if (id is! String || id.isEmpty || !keys.add(id)) {
            throw FormatException('Invalid or duplicate $section identifier.');
          }
          if (key == 'id') _map(row['data']);
        }
      }
      final backup = TournamentBackup(
        tournamentId: tournamentId, capturedAt: capturedAt, snapshot: snapshot,
      );
      backup.competitors;
      backup.divisions;
      backup.tatamiDefinitions;
      backup.tatamiLogs;
      validateTournamentSnapshot({}, backup._snapshot);
      return backup;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid tournament backup data.');
    }
  }

  static Map<String, dynamic> _map(Object? value) =>
      Map<String, dynamic>.from(value as Map);

  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      _map(jsonDecode(jsonEncode(value)));
}