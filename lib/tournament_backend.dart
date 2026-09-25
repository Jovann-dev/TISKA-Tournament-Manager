import 'package:supabase_flutter/supabase_flutter.dart';

class TournamentBackend {
  TournamentBackend({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const Duration _requestTimeout = Duration(seconds: 10);
  final SupabaseClient _client;

  Future<Map<String, String>> loadTournamentCredentials() async {
    final response = await _client
        .from('tournament_credentials')
        .select('id, password')
        .timeout(_requestTimeout);

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

  Future<void> saveTournamentCredentials(
    String tournamentId,
    String password,
  ) async {
    await _client
        .from('tournament_credentials')
        .upsert({'id': tournamentId, 'password': password})
        .timeout(_requestTimeout);
  }

  Future<Map<String, dynamic>> loadTournamentSnapshot(
    String tournamentId,
  ) async {
    final response = await _client
        .from('tournaments')
        .select()
        .eq('id', tournamentId)
        .maybeSingle()
        .timeout(_requestTimeout);

    if (response == null) {
      return <String, dynamic>{};
    }

    final payload = response['snapshot'];
    if (payload is! Map) {
      return <String, dynamic>{};
    }

    return Map<String, dynamic>.from(payload);
  }

  Future<void> saveTournamentSnapshot(
    String tournamentId,
    Map<String, dynamic> snapshot,
  ) async {
    final payload = Map<String, dynamic>.from(snapshot);
    payload['updated_at'] = DateTime.now().toUtc().toIso8601String();

    await _client
        .from('tournaments')
        .upsert({
          'id': tournamentId,
          'snapshot': payload,
          'updated_at': payload['updated_at'],
        })
        .timeout(_requestTimeout);
  }
}
