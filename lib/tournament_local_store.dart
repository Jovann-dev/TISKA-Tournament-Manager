import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TournamentLocalStore {
  static const String _snapshotKey = 'tiska_snapshot_v1';
  static const String _drawSheetSnapshotsKey = 'tiska_draw_sheet_snapshots_v1';
  static const String _credentialsKey = 'tiska_tournament_credentials_v1';
  static const String _activeTournamentKey = 'tiska_active_tournament_id_v1';

  String _scopeKey(String baseKey, String tournamentId) {
    final normalized = tournamentId.trim();
    if (normalized.isEmpty) {
      return baseKey;
    }
    return '${baseKey}_$normalized';
  }

  Future<Map<String, dynamic>?> loadSnapshot({String tournamentId = ''}) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _scopeKey(_snapshotKey, tournamentId);
    final encoded = preferences.getString(key);
    if (encoded == null || encoded.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> saveSnapshot(
    Map<String, Object?> snapshot, {
    String tournamentId = '',
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _scopeKey(_snapshotKey, tournamentId);
    final encoded = jsonEncode(snapshot);
    await preferences.setString(key, encoded);
  }

  Future<void> prependDrawSheetSnapshot(
    Map<String, Object?> snapshot, {
    String tournamentId = '',
    int maxItems = 100,
  }) async {
    final items = await loadDrawSheetSnapshots(tournamentId: tournamentId);
    items.insert(0, Map<String, dynamic>.from(snapshot));
    if (items.length > maxItems) {
      items.removeRange(maxItems, items.length);
    }

    final preferences = await SharedPreferences.getInstance();
    final key = _scopeKey(_drawSheetSnapshotsKey, tournamentId);
    await preferences.setString(key, jsonEncode(items));
  }

  Future<List<Map<String, dynamic>>> loadDrawSheetSnapshots({
    String tournamentId = '',
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _scopeKey(_drawSheetSnapshotsKey, tournamentId);
    final encoded = preferences.getString(key);
    if (encoded == null || encoded.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    final decoded = jsonDecode(encoded);
    if (decoded is! List<dynamic>) {
      return <Map<String, dynamic>>[];
    }

    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, String>> loadTournamentCredentials() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_credentialsKey);
    if (encoded == null || encoded.isEmpty) {
      return <String, String>{};
    }

    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      return <String, String>{};
    }

    return decoded.map<String, String>((key, value) {
      return MapEntry(key.toString(), value.toString());
    });
  }

  Future<void> saveTournamentCredentials(Map<String, String> credentials) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _credentialsKey,
      jsonEncode(credentials),
    );
  }

  Future<List<String>> loadSavedTournamentIds() async {
    final credentials = await loadTournamentCredentials();
    final ids = credentials.keys.toList();
    ids.sort();
    return ids;
  }

  Future<String?> loadActiveTournamentId() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_activeTournamentKey);
  }

  Future<void> setActiveTournamentId(String tournamentId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_activeTournamentKey, tournamentId);
  }
}
