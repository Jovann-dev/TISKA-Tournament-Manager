import 'package:supabase_flutter/supabase_flutter.dart';

class TournamentBackend {
  TournamentBackend({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, String>> loadTournamentCredentials() async {
    final response = await _client
        .from('tournament_credentials')
        .select('id, password');

    final result = <String, String>{};
    for (final row in response as List<dynamic>) {
      final item = row as Map<String, dynamic>;
      final id = item['id']?.toString();
      final password = item['password']?.toString();
      if (id != null && password != null) {
        result[id] = password;
      }
    }
    return result;
  }

  Future<void> saveTournamentCredentials(String tournamentId, String password) async {
    await _client.from('tournament_credentials').upsert({
      'id': tournamentId,
      'password': password,
    });
  }

  Future<Map<String, dynamic>> loadTournamentSnapshot(String tournamentId) async {
    final response = await _client
        .from('tournaments')
        .select()
        .eq('id', tournamentId)
        .maybeSingle();

    if (response == null) {
      return <String, dynamic>{};
    }

    return Map<String, dynamic>.from(response);
  }

  Future<void> saveTournamentSnapshot(
    String tournamentId,
    Map<String, dynamic> snapshot,
  ) async {
    await _client.from('tournaments').upsert({
      'id': tournamentId,
      'snapshot': snapshot,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
