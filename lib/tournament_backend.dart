import 'package:supabase_flutter/supabase_flutter.dart';

class TournamentRegistration {
  final String id;
  final String password;
  final String? userPassword;
  final DateTime createdAt;

  const TournamentRegistration({
    required this.id,
    required this.password,
    this.userPassword,
    required this.createdAt,
  });
}

enum TournamentAccessRole { admin, user }

TournamentAccessRole? tournamentAccessRoleForPassword(
  TournamentRegistration tournament,
  String password,
) {
  if (password == tournament.password) return TournamentAccessRole.admin;
  if (tournament.userPassword != null && password == tournament.userPassword) {
    return TournamentAccessRole.user;
  }
  return null;
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
        .select('id, password, user_password, created_at')
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
            userPassword: item['user_password']?.toString(),
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

  Future<void> setTournamentUserPassword(
    String tournamentId,
    String userPassword,
  ) async {
    final registration = await _client
        .from('tournament_credentials')
        .select('password')
        .eq('id', tournamentId)
        .maybeSingle()
        .timeout(_requestTimeout);
    if (registration == null) {
      throw StateError('Tournament not found.');
    }
    if (registration['password'] == userPassword) {
      throw StateError(
        'The user password must differ from the admin password.',
      );
    }

    await _client
        .from('tournament_credentials')
        .update({'user_password': userPassword})
        .eq('id', tournamentId)
        .timeout(_requestTimeout);
  }

  Future<void> deleteTournament(String tournamentId) async {
    final response = await _client
        .rpc('delete_tournament', params: {'p_id': tournamentId})
        .timeout(_requestTimeout);
    if (response != true) {
      throw StateError('The tournament could not be deleted.');
    }
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

    return <String, dynamic>{
      ...Map<String, dynamic>.from(payload),
      'revision': (response['revision'] as num?)?.toInt() ?? 0,
    };
  }

  Future<Map<String, dynamic>?> saveTournamentSnapshot(
    String tournamentId,
    Map<String, dynamic> snapshot, {
    required int expectedRevision,
  }) async {
    final response = await _client
        .rpc(
          'save_tournament_snapshot',
          params: {
            'p_id': tournamentId,
            'p_expected_revision': expectedRevision,
            'p_snapshot': snapshot,
          },
        )
        .timeout(_requestTimeout);
    if (response == null) return null;
    return Map<String, dynamic>.from(response as Map);
  }
}
