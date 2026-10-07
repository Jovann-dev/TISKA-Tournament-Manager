import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tiska_tournament_manager/live_match_channel.dart';
import 'package:tiska_tournament_manager/live_match_state.dart';
import 'package:tiska_tournament_manager/supabase_config.dart';
import 'package:tiska_tournament_manager/tournament_backend.dart';
import 'package:tiska_tournament_manager/tournament_backup.dart';
import 'package:tiska_tournament_manager/tournament_local_store.dart';
import 'package:tiska_tournament_manager/tournament_models.dart';
import 'package:tiska_tournament_manager/tournament_repository.dart';
import 'package:tiska_tournament_manager/tournament_snapshot_merge.dart';
import 'package:tiska_tournament_manager/division_process_log_spreadsheet_codec.dart';

Map<String, dynamic> clone(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

class FakeLiveBus {
  final List<FakeLiveTransport> clients = [];

  FakeLiveTransport transport() {
    final client = FakeLiveTransport(this);
    clients.add(client);
    return client;
  }
}

class FakeLiveTransport implements LiveMatchTransport {
  final FakeLiveBus bus;
  final List<Map<String, dynamic>> sent = [];
  void Function(Map<String, dynamic>)? onMessage;
  void Function(bool)? onConnectionChanged;
  bool connected = false;
  bool failSends = false;
  bool disposed = false;

  FakeLiveTransport(this.bus);

  @override
  void connect({
    required void Function(Map<String, dynamic>) onMessage,
    required void Function(bool) onConnectionChanged,
  }) {
    this.onMessage = onMessage;
    this.onConnectionChanged = onConnectionChanged;
    setConnected(true);
  }

  void setConnected(bool value) {
    connected = value;
    onConnectionChanged?.call(value);
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (!connected || failSends) throw StateError('Broadcast unavailable');
    sent.add(clone(message));
    for (final client in bus.clients.toList()) {
      if (client != this && client.connected && !client.disposed) {
        client.onMessage?.call(clone(message));
      }
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    connected = false;
    bus.clients.remove(this);
  }
}

class MemoryStore extends TournamentLocalStore {
  Map<String, dynamic>? value;

  @override
  Future<Map<String, dynamic>?> loadSnapshot({
    String tournamentId = '',
  }) async => value == null ? null : clone(value!);

  @override
  Future<void> saveSnapshot(
    Map<String, Object?> snapshot, {
    String tournamentId = '',
  }) async {
    value = clone(Map<String, dynamic>.from(snapshot));
  }

  @override
  Future<void> clearTournamentData({required String tournamentId}) async {
    value = null;
  }
}

class FakeBackend extends TournamentBackend {
  final FakeLiveBus liveBus = FakeLiveBus();
  Map<String, dynamic> remote;
  bool offline = false;
  int competingWrites = 0;
  bool loseNextAcknowledgement = false;
  bool deleted = false;
  String? savedUserPassword;
  Completer<void>? saveStarted;
  Completer<void>? continueSave;

  FakeBackend(this.remote)
    : super(client: SupabaseClient('http://localhost', 'test-key'));

  @override
  LiveMatchTransport createLiveMatchTransport(String tournamentId) => liveBus.transport();

  @override
  Future<Map<String, dynamic>> loadTournamentSnapshot(
    String tournamentId,
  ) async {
    if (offline) throw StateError('Network unavailable');
    return clone(remote);
  }

  @override
  Future<Map<String, dynamic>?> saveTournamentSnapshot(
    String tournamentId,
    Map<String, dynamic> snapshot, {
    required int expectedRevision,
  }) async {
    if (offline) throw StateError('Network unavailable');
    if (saveStarted != null && !saveStarted!.isCompleted) {
      saveStarted!.complete();
    }
    await continueSave?.future;
    if (competingWrites > 0) {
      competingWrites--;
      remote['revision'] = (remote['revision'] as int) + 1;
      return null;
    }
    if (expectedRevision != remote['revision']) return null;
    validateTournamentSnapshot(remote, snapshot, enforceCategoryAvailability: false);
    remote = clone({...snapshot, 'revision': expectedRevision + 1});
    if (loseNextAcknowledgement) {
      loseNextAcknowledgement = false;
      throw StateError('Acknowledgement lost after commit');
    }
    return clone(remote);
  }

  @override
  Future<void> setTournamentUserPassword(
    String tournamentId,
    String userPassword,
  ) async {
    savedUserPassword = userPassword;
  }

  @override
  Future<void> deleteTournament(String tournamentId) async {
    deleted = true;
    remote.clear();
  }
}

List<Competitor> entrants() => [
  for (var index = 0; index < 4; index++)
    Competitor(
      id: 'c$index',
      number: '$index',
      name: 'Entrant $index',
      belt: 'White',
      beltRank: 1,
      gender: Gender.male,
      age: 10,
    ),
];

Division division(String id, String tatami, List<String> ids) => Division(
  id: id,
  competitionType: CompetitionType.kata,
  minBeltRank: 1,
  maxBeltRank: 1,
  minAge: 10,
  maxAge: 10,
  gender: DivisionGender.maleOnly,
  assignedTatamiName: tatami,
  createdAt: 0,
  competitorIds: ids,
);

Map<String, dynamic> initialSnapshot({bool sameTatami = false}) => {
  'revision': 1,
  'competitors': [
    for (final item in entrants()) {'id': item.id, 'data': item.toMap()},
  ],
  'divisions': [
    {
      'id': 'one',
      'data': division('one', 'Tatami 1', ['c0', 'c1']).toMap(),
    },
    {
      'id': 'two',
      'data': division('two', sameTatami ? 'Tatami 1' : 'Tatami 2', [
        'c2',
        'c3',
      ]).toMap(),
    },
  ],
  'tatamiDefinitions': [
    {'name': 'Tatami 1', 'judgesCount': 5},
    {'name': 'Tatami 2', 'judgesCount': 5},
  ],
  'tatamiLogs': [],
};

Future<TournamentRepository> repository(
  FakeBackend backend,
  MemoryStore store, {
  bool isAdmin = false,
}
) async {
  final result = TournamentRepository(
    backend: backend,
    localStore: store,
    tournamentId: 'test',
    isAdmin: isAdmin,
  );
  await result.initialize(defaultTatamis: []);
  addTearDown(result.dispose);
  return result;
}

Map<String, dynamic> snapshot(Map<String, int> scores) => {
  'divisions': [
    for (final entry in scores.entries)
      {
        'id': entry.key,
        'data': {'score': entry.value},
      },
  ],
};

void main() {
  test('non-admin restore cannot change the category catalog', () async {
    final backend = FakeBackend(initialSnapshot());
    final user = await repository(backend, MemoryStore());
    final snapshot = user.captureBackup().snapshot;
    (snapshot['competitionCategories'] as List).add(const CompetitionCategory(
      id: 'custom', name: 'Open Kata', template: CompetitionTemplate.flagVoting,
    ).toMap());
    await expectLater(user.restoreBackup(TournamentBackup(
      tournamentId: 'test', snapshot: snapshot,
    )), throwsStateError);
    expect(await user.watchCompetitionCategories().first, hasLength(CompetitionType.values.length));
  });

  test('unchanged legacy started divisions do not acquire category metadata', () async {
    final backend = FakeBackend(initialSnapshot());
    final result = await repository(backend, MemoryStore());
    await result.startDivisionOnTatami('Tatami 1', 'one');
    final current = (await result.watchDivisions().first).first;
    await result.saveDivision(current.copyWith(
      competitionCategoryId: CompetitionType.kata.name,
      competitionCategoryName: CompetitionType.kata.label,
      competitionTemplate: CompetitionTemplate.flagVoting,
    ));
    final saved = (await result.watchDivisions().first).first;
    expect(saved.competitionCategoryId, isNull);
    expect(saved.competitionTemplate, isNull);
  });

  test('admin categories persist and disabled categories retain existing divisions', () async {
    final backend = FakeBackend(initialSnapshot());
    final admin = await repository(backend, MemoryStore(), isAdmin: true);
    const custom = CompetitionCategory(
      id: 'custom-points', name: 'Open Kumite', template: CompetitionTemplate.points,
    );
    await admin.saveCompetitionCategory(custom);
    final customDivision = division('custom', 'Tatami 1', ['c0', 'c1']).copyWith(
      competitionType: custom.legacyType,
      competitionCategoryId: custom.id, competitionCategoryName: custom.name,
      competitionTemplate: custom.template,
    );
    await admin.saveDivision(customDivision);
    await admin.saveCompetitionCategory(custom.copyWith(enabled: false));
    await expectLater(admin.saveDivision(customDivision.copyWith(id: 'another')), throwsStateError);
    await expectLater(admin.deleteCompetitionCategory(custom.id), throwsStateError);
    final backup = TournamentBackup.decode(admin.captureBackup().encode());
    expect(backup.divisions.singleWhere((item) => item.id == 'custom').competitionLabel, custom.name);
    await admin.synchronize();
    final user = await repository(backend, MemoryStore());
    expect((await user.watchCompetitionCategories().first).singleWhere((item) => item.id == custom.id).enabled, isFalse);
    await expectLater(user.saveCompetitionCategory(custom), throwsStateError);
    await expectLater(user.deleteCompetitionCategory(custom.id), throwsStateError);
    await admin.deleteCompetitionCategory(CompetitionType.jiyuIpponKumite.name);
    expect((await admin.watchCompetitionCategories().first).any((item) => item.id == CompetitionType.jiyuIpponKumite.name), isFalse);
  });

  test('custom category divisions preserve names and scoring templates', () {
    final custom = division('custom', 'Tatami 1', ['c0', 'c1']).copyWith(
      competitionCategoryId: 'custom-points',
      competitionCategoryName: 'Open Kumite',
      competitionTemplate: CompetitionTemplate.points,
    );
    final restored = Division.fromMap(custom.id, Map<String, dynamic>.from(custom.toMap()));
    expect(restored.categoryId, 'custom-points');
    expect(restored.title, startsWith('Open Kumite:'));
    expect(restored.scoringTemplate, CompetitionTemplate.points);
    expect(restored.executionMode, CompetitionExecutionMode.manualWinner);
    expect(division('old', 'Tatami 1', ['c0', 'c1']).scoringTemplate, CompetitionTemplate.flagVoting);
    expect(defaultCompetitionCategories(), hasLength(CompetitionType.values.length));
  });

  test('Supabase live broadcast reaches a separate client', () async {
    final publisherClient = SupabaseClient(SupabaseConfig.url, SupabaseConfig.publishableKey);
    final viewerClient = SupabaseClient(SupabaseConfig.url, SupabaseConfig.publishableKey);
    final tournamentId = '__live_smoke_${DateTime.now().microsecondsSinceEpoch}';
    final received = Completer<LiveMatchState>();
    final cleared = Completer<void>();
    final publisher = LiveMatchChannel(
      transport: SupabaseLiveMatchTransport(publisherClient, tournamentId),
      tournamentId: tournamentId,
      onState: (_, _) {},
    );
    final viewer = LiveMatchChannel(
      transport: SupabaseLiveMatchTransport(viewerClient, tournamentId),
      tournamentId: tournamentId,
      onState: (_, state) {
        if (state != null && !received.isCompleted) received.complete(state);
        if (state == null && received.isCompleted && !cleared.isCompleted) cleared.complete();
      },
    );
    try {
      publisher.publish(LiveMatchState(
        tatamiName: 'Smoke Tatami', divisionId: 'synthetic', divisionTitle: 'Synthetic live test',
        competitionType: CompetitionType.jiyuKumite,
        executionMode: CompetitionExecutionMode.manualWinner,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        competitorAPoints: 2, competitorBWarningStage: 1,
      ));
      publisher.start();
      viewer.start();
      final state = await received.future.timeout(const Duration(seconds: 15));
      expect(state.competitorAPoints, 2);
      expect(state.competitorBWarningStage, 1);
      publisher.clear('Smoke Tatami');
      await cleared.future.timeout(const Duration(seconds: 5));
    } finally {
      await Future.wait([publisher.dispose(), viewer.dispose()]);
      await publisherClient.dispose();
      await viewerClient.dispose();
    }
  }, skip: !const bool.fromEnvironment('TISKA_LIVE_SMOKE_TEST'));

  test('two repositories share live scores without snapshot writes', () async {
    final backend = FakeBackend(initialSnapshot());
    final publisher = await repository(backend, MemoryStore());
    await publisher.startDivisionOnTatami('Tatami 1', 'one');
    final viewer = await repository(backend, MemoryStore());
    final revision = backend.remote['revision'];

    publisher.publishLiveMatchState(LiveMatchState(
      tatamiName: 'Tatami 1', divisionId: 'one', divisionTitle: 'Division',
      competitionType: CompetitionType.jiyuKumite,
      executionMode: CompetitionExecutionMode.manualWinner,
      updatedAt: 1000, competitorA: entrants()[0], competitorB: entrants()[1],
      hasTimer: true, timerTotalSeconds: 90, timerRemainingSeconds: 30,
      timerRunning: true, timerEndsAtMillis: 31000, competitorAPoints: 2,
    ));

    final received = await viewer.watchLiveMatchState('Tatami 1').first;
    expect(received!.competitorAPoints, 2);
    expect(received.timerEndsAtMillis, 31000);
    expect(backend.remote['revision'], revision);
    publisher.clearLiveMatchState('Tatami 1', divisionId: 'one');
    expect(await viewer.watchLiveMatchState('Tatami 1').first, isNull);
  });

  testWidgets('live broadcasts reach late viewers and recover after reconnect', (tester) async {
    final bus = FakeLiveBus();
    final publisherTransport = bus.transport();
    final viewerTransport = bus.transport();
    final otherTransport = bus.transport();
    LiveMatchState? received;
    LiveMatchState? otherReceived;
    final publisher = LiveMatchChannel(
      transport: publisherTransport,
      tournamentId: 'test',
      onState: (_, _) {},
    );
    final viewer = LiveMatchChannel(
      transport: viewerTransport,
      tournamentId: 'test',
      onState: (_, state) => received = state,
    );
    final other = LiveMatchChannel(
      transport: otherTransport,
      tournamentId: 'other',
      onState: (_, state) => otherReceived = state,
    );
    publisher.start();
    publisher.publish(LiveMatchState(
      tatamiName: 'Tatami 1', divisionId: 'one', divisionTitle: 'Division',
      competitionType: CompetitionType.kata,
      executionMode: CompetitionExecutionMode.flagVoting,
      updatedAt: 1, competitorA: entrants()[0], competitorB: entrants()[1],
    ));
    viewer.start();
    other.start();
    expect(received!.competitorA!.id, 'c0');
    expect(otherReceived, isNull);
    viewerTransport.setConnected(false);
    expect(received, isNull);
    viewerTransport.setConnected(true);
    expect(received!.divisionId, 'one');
    publisher.clear('Tatami 1');
    expect(received, isNull);
    await publisher.dispose();
    await viewer.dispose();
    await other.dispose();
  });

  testWidgets('live heartbeats recover failed sends and expire lost publishers', (tester) async {
    final bus = FakeLiveBus();
    final publisherTransport = bus.transport();
    final viewerTransport = bus.transport();
    var now = DateTime.utc(2026);
    LiveMatchState? received;
    final publisher = LiveMatchChannel(
      transport: publisherTransport, tournamentId: 'test',
      onState: (_, _) {}, now: () => now,
    );
    final viewer = LiveMatchChannel(
      transport: viewerTransport, tournamentId: 'test',
      onState: (_, state) => received = state, now: () => now,
    );
    publisher.start();
    viewer.start();
    publisherTransport.failSends = true;
    publisher.publish(const LiveMatchState(
      tatamiName: 'Tatami 1', divisionId: 'one', divisionTitle: 'Division',
      competitionType: CompetitionType.kata,
      executionMode: CompetitionExecutionMode.flagVoting, updatedAt: 1,
    ));
    await tester.pump();
    expect(received, isNull);
    publisherTransport.failSends = false;
    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(received!.divisionId, 'one');
    publisherTransport.setConnected(false);
    now = now.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 20));
    expect(received, isNull);
    publisherTransport.setConnected(true);
    expect(received!.divisionId, 'one');
    await publisher.dispose();
    expect(received, isNull);
    await viewer.dispose();
    expect(publisherTransport.disposed, isTrue);
    expect(viewerTransport.disposed, isTrue);
  });

  testWidgets('live receivers ignore malformed and reordered packets', (tester) async {
    final transport = FakeLiveBus().transport();
    LiveMatchState? received;
    final viewer = LiveMatchChannel(
      transport: transport, tournamentId: 'test',
      onState: (_, state) => received = state,
    );
    viewer.start();
    final state = LiveMatchState(
      tatamiName: 'Tatami 1', divisionId: 'one', divisionTitle: 'Division',
      competitionType: CompetitionType.kata,
      executionMode: CompetitionExecutionMode.flagVoting, updatedAt: 1,
      competitorAPoints: 2,
    );
    final message = <String, dynamic>{
      'version': 1, 'tournamentId': 'test', 'senderId': 'publisher',
      'sequence': 2, 'kind': 'state', 'tatamiName': 'Tatami 1',
      'state': state.toMap(),
    };
    transport.onMessage!(message);
    expect(received!.competitorAPoints, 2);
    transport.onMessage!({...message, 'sequence': 1, 'state': {...state.toMap(), 'competitorAPoints': 0}});
    transport.onMessage!({...message, 'sequence': 3, 'state': 'invalid'});
    transport.onMessage!({...message, 'sequence': 3, 'state': {...state.toMap(), 'competitorAPoints': -1}});
    expect(received!.competitorAPoints, 2);
    await viewer.dispose();
  });

  test('live match wire format preserves display state without personal details', () {
    final state = LiveMatchState(
      tatamiName: 'Tatami 1',
      divisionId: 'one',
      divisionTitle: 'Test division',
      competitionType: CompetitionType.jiyuKumite,
      executionMode: CompetitionExecutionMode.manualWinner,
      updatedAt: 1000,
      competitorA: entrants().first.copyWith(
        club: 'Private club', birthDate: DateTime(2016),
      ),
      competitorB: entrants()[1],
      hasTimer: true,
      timerTotalSeconds: 90,
      timerRemainingSeconds: 35,
      timerRunning: true,
      timerEndsAtMillis: 36000,
      competitorAPoints: 2,
      competitorBWarningStage: 1,
    );
    final payload = state.toMap();
    final restored = LiveMatchState.fromMap(clone(payload));
    expect(restored.competitorA!.id, 'c0');
    expect(restored.competitorB!.name, 'Entrant 1');
    expect(restored.competitorAPoints, 2);
    expect(restored.competitorBWarningStage, 1);
    expect(restored.timerEndsAtMillis, 36000);
    expect((payload['competitorA'] as Map).keys.toSet(), {'id', 'number', 'name'});
    expect(() => LiveMatchState.fromMap({...payload, 'competitorAPoints': -1}), throwsFormatException);
    expect(() => LiveMatchState.fromMap({...payload, 'competitionType': 'unknown'}), throwsFormatException);
  });

  test('backups are detached, versioned and exclude synchronization metadata', () async {
    final backend = FakeBackend(initialSnapshot());
    final result = await repository(backend, MemoryStore());
    final backup = result.captureBackup();
    await result.saveCompetitor(entrants().first.copyWith(name: 'Changed'));
    final restored = TournamentBackup.decode(backup.encode());
    expect(restored.competitors.first.name, 'Entrant 0');
    expect(restored.snapshot.containsKey('_syncBase'), isFalse);
    expect(restored.snapshot.containsKey('revision'), isFalse);
    final detached = backup.snapshot;
    (detached['competitors'] as List).clear();
    expect(backup.competitors, hasLength(4));
    final invalid = jsonDecode(utf8.decode(backup.encode())) as Map;
    invalid['version'] = 99;
    expect(() => TournamentBackup.decode(utf8.encode(jsonEncode(invalid))), throwsFormatException);
  });

  test('empty tournaments produce valid restorable backups', () {
    final backup = TournamentBackup(tournamentId: 'test', snapshot: {});
    final restored = TournamentBackup.decode(backup.encode());

    expect(restored.tournamentId, 'test');
    expect(restored.competitors, isEmpty);
    expect(restored.divisions, isEmpty);
    expect(restored.tatamiDefinitions, isEmpty);
    expect(restored.tatamiLogs, isEmpty);
  });

  test('backup decoding rejects malformed data and invalid references', () {
    final backup = TournamentBackup(
      tournamentId: 'test',
      snapshot: initialSnapshot(),
    );
    List<int> altered(void Function(Map<String, dynamic>) change) {
      final envelope = jsonDecode(utf8.decode(backup.encode()))
          as Map<String, dynamic>;
      change(envelope);
      return utf8.encode(jsonEncode(envelope));
    }

    expect(() => TournamentBackup.decode(utf8.encode('{')), throwsFormatException);
    expect(
      () => TournamentBackup.decode(altered((envelope) {
        envelope['capturedAt'] = 'invalid';
      })),
      throwsFormatException,
    );
    expect(
      () => TournamentBackup.decode(altered((envelope) {
        (envelope['snapshot'] as Map).remove('divisions');
      })),
      throwsFormatException,
    );
    expect(
      () => TournamentBackup.decode(altered((envelope) {
        final rows = (envelope['snapshot'] as Map)['competitors'] as List;
        rows.add(rows.first);
      })),
      throwsFormatException,
    );
    expect(
      () => TournamentBackup.decode(altered((envelope) {
        final rows = (envelope['snapshot'] as Map)['divisions'] as List;
        rows.first['data']['competitorIds'] = ['missing', 'c1'];
      })),
      throwsFormatException,
    );
  });

  test('offline backup restore persists and synchronizes on reconnect', () async {
    final backend = FakeBackend(initialSnapshot());
    final store = MemoryStore();
    final result = await repository(backend, store);
    final backup = result.captureBackup();
    backend.offline = true;
    await result.saveCompetitor(entrants().first.copyWith(name: 'Changed'));

    await result.restoreBackup(backup);

    expect(store.value!['_syncPending'], isTrue);
    expect((store.value!['competitors'] as List).first['data']['name'], 'Entrant 0');
    expect((await result.watchCompetitors().first).first.name, 'Entrant 0');
    backend.offline = false;
    await result.synchronize();
    expect(store.value!['_syncPending'], isFalse);
    expect((backend.remote['competitors'] as List).first['data']['name'], 'Entrant 0');
  });

  test('backup restore rejects other tournaments and changes to started divisions', () async {
    final backend = FakeBackend(initialSnapshot());
    final result = await repository(backend, MemoryStore());
    final backup = result.captureBackup();
    await result.saveCompetitor(entrants().first.copyWith(name: 'Changed'));
    await result.restoreBackup(backup);
    expect((await result.watchCompetitors().first).first.name, 'Entrant 0');
    await expectLater(result.restoreBackup(TournamentBackup(
      tournamentId: 'other', snapshot: backup.snapshot,
    )), throwsStateError);
    await result.startDivisionOnTatami('Tatami 1', 'one');
    await expectLater(result.restoreBackup(backup), throwsStateError);
    expect((await result.watchDivisions().first).first.progress, DivisionProgress.running);
  });

  test('execution sessions refresh and reject another editor changes', () async {
    final backend = FakeBackend(initialSnapshot());
    final result = await repository(backend, MemoryStore());
    await result.startDivisionOnTatami('Tatami 1', 'one');
    const record = DivisionMatchRecord(
      matchId: 'match_1', roundLabel: 'Final',
      competitorAId: 'c0', competitorBId: 'c1',
      winnerId: 'c0', loserId: 'c1',
    );
    (backend.remote['divisions'] as List).first['data']['matchRecords'] = [record.toMap()];
    backend.remote['revision'] = (backend.remote['revision'] as int) + 1;
    final session = await result.openDivisionExecution('Tatami 1', 'one');
    expect(session.division.matchRecords.single.winnerId, 'c0');
    await session.saveInProgress(const DivisionInProgressMatch(matchId: 'match_1'));
    await session.saveInProgress(const DivisionInProgressMatch(matchId: 'match_1', competitorAPoints: 1));
    await result.saveDivisionExecutionState('Tatami 1', 'one', matchRecords: [], placements: []);
    await expectLater(session.saveResults([record], []), throwsStateError);
  });

  test('stale execution writes cannot replace newer results', () async {
    final backend = FakeBackend(initialSnapshot());
    final result = await repository(backend, MemoryStore());
    await result.startDivisionOnTatami('Tatami 1', 'one');
    final stale = (await result.watchDivisions().first).first;
    const record = DivisionMatchRecord(
      matchId: 'match_1',
      roundLabel: 'Final',
      competitorAId: 'c0',
      competitorBId: 'c1',
      winnerId: 'c0',
      loserId: 'c1',
    );
    await result.saveDivisionExecutionState(
      'Tatami 1', 'one', matchRecords: [record], placements: [],
    );
    await expectLater(
      result.saveDivisionExecutionState(
        'Tatami 1', 'one', matchRecords: [], placements: [],
        expectedDivision: stale,
      ),
      throwsStateError,
    );
    expect((await result.watchDivisions().first).first.matchRecords, [record]);
  });

  test('tournament passwords distinguish admin and user access', () {
    final tournament = TournamentRegistration(
      id: 'test',
      password: 'admin-secret',
      userPassword: 'user-secret',
      createdAt: DateTime.utc(2026),
    );

    expect(
      tournamentAccessRoleForPassword(tournament, 'admin-secret'),
      TournamentAccessRole.admin,
    );
    expect(
      tournamentAccessRoleForPassword(tournament, 'user-secret'),
      TournamentAccessRole.user,
    );
    expect(tournamentAccessRoleForPassword(tournament, 'wrong'), isNull);
  });

  test(
    'deleting a tournament clears remote, local and in-memory data',
    () async {
      final backend = FakeBackend(initialSnapshot());
      final store = MemoryStore();
      final result = await repository(backend, store);

      await result.deleteTournament();

      expect(backend.deleted, isTrue);
      expect(backend.remote, isEmpty);
      expect(store.value, isNull);
      expect(await result.watchDivisions().first, isEmpty);
    },
  );

  test('local deletion preserves data for other tournaments', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = TournamentLocalStore();
    await store.saveSnapshot(<String, Object?>{
      'value': 'first',
    }, tournamentId: 'first');
    await store.saveSnapshot(<String, Object?>{
      'value': 'second',
    }, tournamentId: 'second');
    await store.prependDrawSheetSnapshot(<String, Object?>{
      'id': 'first-draw',
    }, tournamentId: 'first');
    await store.prependDrawSheetSnapshot(<String, Object?>{
      'id': 'second-draw',
    }, tournamentId: 'second');
    await store.setActiveTournamentId('first');

    await store.clearTournamentData(tournamentId: 'first');

    expect(await store.loadSnapshot(tournamentId: 'first'), isNull);
    expect(await store.loadDrawSheetSnapshots(tournamentId: 'first'), isEmpty);
    expect(await store.loadSnapshot(tournamentId: 'second'), {
      'value': 'second',
    });
    expect(
      await store.loadDrawSheetSnapshots(tournamentId: 'second'),
      hasLength(1),
    );
    expect(await store.loadActiveTournamentId(), isNull);
  });

  test(
    'process logs use stable IDs, normalized activities and tatami names',
    () {
      final bytes = encodeDivisionProcessLogWorkbook(
        divisions: [
          division('one', 'Tatami 1', ['c0', 'c1']),
          division('two', 'Tatami 2', ['c2', 'c3']),
        ],
        tatamiLogsByTatami: {
          'Tatami 1': [
            const TatamiLogEntry(
              id: 'first',
              tatamiName: 'Tatami 1',
              divisionId: 'one',
              message: 'Started: division',
              activity: 'Started',
              competitorCount: 2,
              timestamp: 1000,
            ),
            const TatamiLogEntry(
              id: 'second',
              tatamiName: 'Tatami 2',
              divisionId: 'two',
              message: 'Moved Tatami 1 -> Tatami 2',
              activity: 'Moved Tatami 1 -> Tatami 2',
              timestamp: 2000,
            ),
            const TatamiLogEntry(
              id: 'match',
              tatamiName: 'Tatami 1',
              divisionId: 'one',
              message: 'Competitor A defeated B',
              timestamp: 3000,
            ),
          ],
        },
      );
      final rows = Excel.decodeBytes(bytes).tables.values.single.rows;
      expect(rows, hasLength(3));
      expect(
        rows.first.map((cell) => cell!.value.toString()),
        contains('Tatami'),
      );
      expect(rows[1][0]!.value.toString(), 'one');
      expect(rows[2][0]!.value.toString(), 'two');
      expect(rows[2][1]!.value.toString(), 'Moved');
      expect(rows[2][4]!.value.toString(), 'Tatami 2');
    },
  );
  test('timer recovery preserves expired, paused and running states', () {
    final now = DateTime.utc(2026, 10, 5, 12);
    const expired = DivisionInProgressMatch(matchId: 'match_1');
    expect(expired.remainingAt(now), Duration.zero);
    const paused = DivisionInProgressMatch(
      matchId: 'match_1',
      timerRemainingSeconds: 10,
      timerRemainingMilliseconds: 10500,
    );
    expect(paused.remainingAt(now), const Duration(milliseconds: 10500));
    final running = DivisionInProgressMatch(
      matchId: 'match_1',
      timerRunning: true,
      timerEndsAtMillis: now
          .add(const Duration(seconds: 20))
          .millisecondsSinceEpoch,
    );
    final restored = DivisionInProgressMatch.fromMap(
      Map<String, dynamic>.from(running.toMap()),
    );
    expect(restored.remainingAt(now), const Duration(seconds: 20));
    expect(
      restored.remainingAt(now.add(const Duration(seconds: 30))),
      Duration.zero,
    );
  });
  test('independent division edits merge without losing results', () {
    final result = mergeTournamentSnapshots(
      base: snapshot({'one': 0, 'two': 0}),
      local: snapshot({'one': 1, 'two': 0}),
      remote: snapshot({'one': 0, 'two': 2}),
    );
    expect(result['divisions'], snapshot({'one': 1, 'two': 2})['divisions']);
  });

  test('conflicting division edits are rejected rather than overwritten', () {
    expect(
      () => mergeTournamentSnapshots(
        base: snapshot({'one': 0}),
        local: snapshot({'one': 1}),
        remote: snapshot({'one': 2}),
      ),
      throwsA(isA<TournamentSyncConflict>()),
    );
  });

  test('remote additions and local deletions both survive a merge', () {
    final result = mergeTournamentSnapshots(
      base: snapshot({'one': 0}),
      local: snapshot({}),
      remote: snapshot({'one': 0, 'two': 2}),
    );
    expect(result['divisions'], snapshot({'two': 2})['divisions']);
  });

  test(
    'two offline operators synchronize independent division starts',
    () async {
      final backend = FakeBackend(initialSnapshot());
      final first = await repository(backend, MemoryStore());
      final second = await repository(backend, MemoryStore());
      backend.offline = true;
      await first.startDivisionOnTatami('Tatami 1', 'one');
      await first.synchronize();
      await second.startDivisionOnTatami('Tatami 2', 'two');
      await second.synchronize();
      backend.offline = false;
      await first.synchronize();
      await second.synchronize();
      final rows = backend.remote['divisions'] as List;
      expect(rows.every((row) => row['data']['progress'] == 'running'), isTrue);
      expect((backend.remote['tatamiLogs'] as List).length, 2);
    },
  );

  test('failed writes survive restart and synchronize on reconnect', () async {
    final backend = FakeBackend(initialSnapshot());
    final store = MemoryStore();
    final first = await repository(backend, store);
    backend.offline = true;
    await first.startDivisionOnTatami('Tatami 1', 'one');
    await first.synchronize();
    expect(store.value!['_syncPending'], isTrue);
    await first.dispose();
    final restarted = await repository(backend, store);
    expect(
      (await restarted.watchDivisions().first).first.progress,
      DivisionProgress.running,
    );
    backend.offline = false;
    await restarted.synchronize();
    expect(store.value!['_syncPending'], isFalse);
    expect(
      (backend.remote['divisions'] as List).first['data']['progress'],
      'running',
    );
  });

  test('same-division conflicts retain pending local changes', () async {
    final backend = FakeBackend(initialSnapshot());
    final first = await repository(backend, MemoryStore());
    final store = MemoryStore();
    final second = await repository(backend, store);
    backend.offline = true;
    await first.startDivisionOnTatami('Tatami 1', 'one');
    await first.synchronize();
    await second.assignDivisionToTatami('Tatami 2', 'one');
    await second.synchronize();
    backend.offline = false;
    await first.synchronize();
    await second.synchronize();
    expect(
      (await second.watchSyncStatus().first).state,
      TournamentSyncState.conflict,
    );
    expect(store.value!['_syncPending'], isTrue);
    expect(
      (await second.watchDivisions().first).first.assignedTatamiName,
      'Tatami 2',
    );
  });

  test('revision races retry without overwriting newer server state', () async {
    final backend = FakeBackend(initialSnapshot());
    final result = await repository(backend, MemoryStore());
    backend.offline = true;
    await result.startDivisionOnTatami('Tatami 1', 'one');
    await result.synchronize();
    backend.offline = false;
    backend.competingWrites = 1;
    await result.synchronize();
    expect(
      (await result.watchSyncStatus().first).state,
      TournamentSyncState.synced,
    );
    expect(backend.remote['revision'], 3);
  });

  test(
    'a second running division and moves into occupied tatamis are rejected',
    () async {
      final backend = FakeBackend(initialSnapshot(sameTatami: true));
      final result = await repository(backend, MemoryStore());
      await result.startDivisionOnTatami('Tatami 1', 'one');
      await expectLater(
        result.startDivisionOnTatami('Tatami 1', 'two'),
        throwsStateError,
      );
      await result.assignDivisionToTatami('Tatami 2', 'two');
      await result.startDivisionOnTatami('Tatami 2', 'two');
      await expectLater(
        result.assignDivisionToTatami('Tatami 1', 'two'),
        throwsStateError,
      );
    },
  );

  test(
    'concurrent starts on the same tatami cannot both synchronize',
    () async {
      final backend = FakeBackend(initialSnapshot(sameTatami: true));
      final first = await repository(backend, MemoryStore());
      final store = MemoryStore();
      final second = await repository(backend, store);
      backend.offline = true;
      await first.startDivisionOnTatami('Tatami 1', 'one');
      await first.synchronize();
      await second.startDivisionOnTatami('Tatami 1', 'two');
      await second.synchronize();
      backend.offline = false;
      await first.synchronize();
      await second.synchronize();
      expect(
        (await second.watchSyncStatus().first).state,
        TournamentSyncState.conflict,
      );
      expect(store.value!['_syncPending'], isTrue);
      expect(
        (backend.remote['divisions'] as List).where(
          (row) => row['data']['progress'] == 'running',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'started entrants cannot be edited, deleted, or removed by import',
    () async {
      final backend = FakeBackend(initialSnapshot());
      final result = await repository(backend, MemoryStore());
      await result.startDivisionOnTatami('Tatami 1', 'one');
      await expectLater(
        result.saveCompetitor(entrants().first.copyWith(age: 11)),
        throwsStateError,
      );
      await expectLater(result.deleteCompetitor('c0'), throwsStateError);
      await expectLater(
        result.replaceCompetitors(entrants().skip(1).toList()),
        throwsStateError,
      );
      expect(await result.watchCompetitors().first, hasLength(4));
    },
  );

  test('bracket edits are rejected and stale saves preserve authoritative progress', () async {
    final backend = FakeBackend(initialSnapshot());
    final result = await repository(backend, MemoryStore());
    final original = (await result.watchDivisions().first).first;
    await result.startDivisionOnTatami('Tatami 1', 'one');
    await expectLater(
      result.saveDivision(original.copyWith(competitorIds: ['c1', 'c0'])),
      throwsStateError,
    );
    await result.saveDivision(original);
    expect(
      (await result.watchDivisions().first).first.progress,
      DivisionProgress.running,
    );
  });

  test(
    'start and finish are idempotent and completion requires a start',
    () async {
      final backend = FakeBackend(initialSnapshot());
      final result = await repository(backend, MemoryStore());
      await expectLater(
        result.completeDivisionOnTatami('Tatami 1', 'one'),
        throwsStateError,
      );
      await result.startDivisionOnTatami('Tatami 1', 'one');
      await result.startDivisionOnTatami('Tatami 1', 'one');
      await result.completeDivisionOnTatami('Tatami 1', 'one');
      await result.completeDivisionOnTatami('Tatami 1', 'one');
      expect((await result.watchTatamiLogs().first)['Tatami 1'], hasLength(2));
      await expectLater(
        result.startDivisionOnTatami('Tatami 1', 'one'),
        throwsStateError,
      );
    },
  );

  test(
    'explicit redo clears unfinished state and permits bracket edits',
    () async {
      final backend = FakeBackend(initialSnapshot());
      final result = await repository(backend, MemoryStore());
      await result.startDivisionOnTatami('Tatami 1', 'one');
      await result.saveDivisionInProgressMatch(
        'Tatami 1',
        'one',
        const DivisionInProgressMatch(matchId: 'match_1', competitorAPoints: 2),
      );
      await result.redoDivisionOnTatami('Tatami 1', 'one');
      final reset = (await result.watchDivisions().first).singleWhere(
        (item) => item.id == 'one',
      );
      expect(reset.inProgressMatch, isNull);
      await result.saveDivision(reset.copyWith(competitorIds: ['c1', 'c0']));
      expect(
        (await result.watchDivisions().first)
            .singleWhere((item) => item.id == 'one')
            .competitorIds,
        ['c1', 'c0'],
      );
    },
  );

  test(
    'an online stale operator refreshes occupancy before starting',
    () async {
      final backend = FakeBackend(initialSnapshot(sameTatami: true));
      final first = await repository(backend, MemoryStore());
      final second = await repository(backend, MemoryStore());
      await first.startDivisionOnTatami('Tatami 1', 'one');
      await expectLater(
        second.startDivisionOnTatami('Tatami 1', 'two'),
        throwsStateError,
      );
      expect(
        (await second.watchDivisions().first)
            .singleWhere((item) => item.id == 'two')
            .progress,
        DivisionProgress.queued,
      );
    },
  );

  test(
    'legacy local caches are retained instead of overwritten on startup',
    () async {
      final backend = FakeBackend(initialSnapshot());
      final store = MemoryStore();
      store.value = initialSnapshot();
      (store.value!['divisions'] as List).first['data']['progress'] = 'running';
      final result = await repository(backend, store);
      expect(
        (await result.watchSyncStatus().first).state,
        TournamentSyncState.conflict,
      );
      expect(
        (await result.watchDivisions().first).first.progress,
        DivisionProgress.running,
      );
    },
  );

  test('moved divisions reject stale execution writes', () async {
    final backend = FakeBackend(initialSnapshot());
    final result = await repository(backend, MemoryStore());
    await result.startDivisionOnTatami('Tatami 1', 'one');
    await result.assignDivisionToTatami('Tatami 2', 'one');
    await expectLater(
      result.saveDivisionExecutionState(
        'Tatami 1',
        'one',
        matchRecords: [],
        placements: [],
      ),
      throwsStateError,
    );
    await result.saveDivisionInProgressMatch(
      'Tatami 1',
      'one',
      const DivisionInProgressMatch(matchId: 'match_1', competitorAPoints: 5),
    );
    expect((await result.watchDivisions().first).first.inProgressMatch, isNull);
  });

  test(
    'lost acknowledgements retry without duplicate lifecycle events',
    () async {
      final backend = FakeBackend(initialSnapshot());
      final store = MemoryStore();
      final result = await repository(backend, store);
      backend.loseNextAcknowledgement = true;
      await result.startDivisionOnTatami('Tatami 1', 'one');
      expect(store.value!['_syncPending'], isTrue);
      await result.synchronize();
      expect(store.value!['_syncPending'], isFalse);
      final groups = backend.remote['tatamiLogs'] as List;
      expect(groups.single['entries'], hasLength(1));
    },
  );

  test('in-flight conflicts retain the baseline and local edits', () async {
    final backend = FakeBackend(initialSnapshot());
    final store = MemoryStore();
    final result = await repository(backend, store);
    backend.offline = true;
    await result.saveCompetitor(entrants().first.copyWith(name: 'Local edit'));
    await result.synchronize();
    backend.offline = false;
    backend.remote['revision'] = 2;
    (backend.remote['divisions'] as List)[1]['data']['competitorIds'] = [
      'c3',
      'c2',
    ];
    backend.saveStarted = Completer<void>();
    backend.continueSave = Completer<void>();
    final syncing = result.synchronize();
    await backend.saveStarted!.future;
    final second = (await result.watchDivisions().first).singleWhere(
      (item) => item.id == 'two',
    );
    await result.saveDivision(second.copyWith(maxAge: 11));
    backend.continueSave!.complete();
    await syncing;
    expect(
      (await result.watchSyncStatus().first).state,
      TournamentSyncState.conflict,
    );
    expect(store.value!['_syncPending'], isTrue);
    expect((store.value!['_syncBase'] as Map)['revision'], 1);
    await result.synchronize();
    expect((backend.remote['divisions'] as List)[1]['data']['maxAge'], 10);
    expect(
      (await result.watchDivisions().first)
          .singleWhere((item) => item.id == 'two')
          .maxAge,
      11,
    );
  });
}
