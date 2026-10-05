import 'package:supabase_flutter/supabase_flutter.dart';

class TournamentRegistration {
  final String id;
  final String password;
  final DateTime createdAt;

  const TournamentRegistration({
    required this.id,
    required this.password,
    required this.createdAt,
  });
}

List<TournamentRegistration> tournamentsCreatedWithinLastThreeDays(
  Iterable<TournamentRegistration> tournaments, {
  DateTime? now,
}) {
  final currentTime = (now ?? DateTime.now()).toUtc();
  final cutoff = currentTime.subtract(const Duration(days: 3));
  final recent = tournaments.where((tournament) {
    final createdAt = tournament.createdAt.toUtc();
    return !createdAt.isBefore(cutoff) && !createdAt.isAfter(currentTime);
  }).toList();
  recent.sort((left, right) => right.createdAt.compareTo(left.createdAt));
  return recent;
}

class TournamentBackend {
  TournamentBackend({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const Duration _requestTimeout = Duration(seconds: 10);
  final SupabaseClient _client;

  Future<List<TournamentRegistration>> loadTournamentRegistrations() async {
    final response = await _client
        .from('tournament_credentials')
        .select('id, password, created_at')
        .timeout(_requestTimeout);

    final result = <TournamentRegistration>[];
    for (final row in response as List<dynamic>) {
      final item = row as Map<String, dynamic>;
      final id = item['id']?.toString();
      final password = item['password']?.toString();
      if (id != null && password != null) {
        result.add(
          TournamentRegistration(
            id: id,
            password: password,
            createdAt:
                DateTime.tryParse(item['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        );
      }
    }
    return result;
  }

  Future<Map<String, String>> loadTournamentCredentials() async {
    final registrations = await loadTournamentRegistrations();
    return <String, String>{
      for (final registration in registrations)
        registration.id: registration.password,
    };
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
