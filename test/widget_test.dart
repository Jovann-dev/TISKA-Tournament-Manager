// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tiska_tournament_manager/competitor_registration_screen.dart';
import 'package:tiska_tournament_manager/competitor_spreadsheet_codec.dart';
import 'package:tiska_tournament_manager/competition_execution_screen.dart';
import 'package:tiska_tournament_manager/division_registration_screen.dart';
import 'package:tiska_tournament_manager/main.dart';
import 'package:tiska_tournament_manager/draw_sheet_screen.dart';
import 'package:tiska_tournament_manager/home_screen.dart';
import 'package:tiska_tournament_manager/tournament_backend.dart';
import 'package:tiska_tournament_manager/tournament_models.dart';

List<Competitor> _competitors(int count) {
  return List<Competitor>.generate(
    count,
    (index) => Competitor(
      id: 'competitor-${index + 1}',
      number: '${index + 1}',
      name: 'Competitor ${index + 1}',
      belt: 'White',
      beltRank: 1,
      gender: Gender.male,
      age: 10,
    ),
  );
}

Division _divisionFor(List<Competitor> competitors) {
  return Division(
    id: 'test-division',
    competitionType: CompetitionType.kata,
    minBeltRank: 1,
    maxBeltRank: 1,
    minAge: 10,
    maxAge: 10,
    gender: DivisionGender.maleOnly,
    assignedTatamiName: 'Tatami 1',
    createdAt: 0,
    competitorIds: competitors.map((competitor) => competitor.id).toList(),
  );
}

Division _executionDivision(List<Competitor> competitors) {
  return Division(
    id: 'execution-division',
    competitionType: CompetitionType.kata,
    minBeltRank: 1,
    maxBeltRank: 1,
    minAge: 10,
    maxAge: 10,
    gender: DivisionGender.maleOnly,
    assignedTatamiName: 'Tatami 1',
    createdAt: 0,
    competitorIds: competitors.map((competitor) => competitor.id).toList(),
  );
}

DivisionMatchRecord _matchRecord(
  String matchId,
  String roundLabel,
  Competitor winner,
  Competitor loser,
) {
  return DivisionMatchRecord(
    matchId: matchId,
    roundLabel: roundLabel,
    competitorAId: winner.id,
    competitorBId: loser.id,
    winnerId: winner.id,
    loserId: loser.id,
  );
}

Widget _drawSheet(List<Competitor> competitors) {
  return MaterialApp(
    home: Scaffold(
      body: DrawSheetContent(
        division: _divisionFor(competitors),
        competitors: competitors,
      ),
    ),
  );
}

Widget _competitionExecution(
  List<Competitor> competitors,
  void Function(
    List<DivisionMatchRecord> matchRecords,
    List<DivisionPlacement> placements,
  )
  onSaved, {
  Division? division,
}) {
  return MaterialApp(
    home: CompetitionExecutionScreen(
      tatamiName: 'Tatami 1',
      division: division ?? _executionDivision(competitors),
      competitors: competitors,
      judgesCount: 5,
      onJudgeCountChanged: (_, _) async {},
      onStartDivision: (_, _) async {},
      onCompleteDivision: (_, _) async {},
      onSaveExecutionState:
          (
            _,
            _, {
            required matchRecords,
            required placements,
            logMessage,
          }) async {
            onSaved(matchRecords, placements);
          },
      onPublishLiveState: (_) {},
      onSaveInProgressMatch: (_, _, _) async {},
    ),
  );
}

void main() {
  testWidgets('an expired kumite timer reopens at zero', (tester) async {
    final competitors = _competitors(2);
    await tester.pumpWidget(_competitionExecution(
      competitors, (_, _) {},
      division: _executionDivision(competitors).copyWith(
        competitionType: CompetitionType.jiyuKumite,
        inProgressMatch: const DivisionInProgressMatch(matchId: 'match_1'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Timer: 00:00'), findsOneWidget);
    expect(find.text('Overtime'), findsOneWidget);
    expect(find.text('Timer: 01:00'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  test('draw-sheet ZIP contains only Tatami-grouped PNG images', () async {
    final zipBytes = await compute(
      encodeDrawSheetImageArchive,
      <String, Uint8List>{
        'Tatami 1/Division_A.png': Uint8List.fromList(<int>[1, 2, 3]),
        'Tatami 2/Division_B.png': Uint8List.fromList(<int>[4, 5, 6]),
      },
    );
    final archive = ZipDecoder().decodeBytes(zipBytes);

    expect(archive.files.map((file) => file.name).toSet(), <String>{
      'Tatami 1/Division_A.png',
      'Tatami 2/Division_B.png',
    });
    expect(
      archive.files.every((file) => file.name.toLowerCase().endsWith('.png')),
      isTrue,
    );
  });

  test('recent tournament list uses its creation time and 3-day cutoff', () {
    final now = DateTime.utc(2026, 10, 1, 12);
    final recent = tournamentsCreatedWithinLastThreeDays(
      <TournamentRegistration>[
        TournamentRegistration(
          id: 'older',
          password: 'p',
          createdAt: now.subtract(const Duration(days: 4)),
        ),
        TournamentRegistration(
          id: 'boundary',
          password: 'p',
          createdAt: now.subtract(const Duration(days: 3)),
        ),
        TournamentRegistration(
          id: 'recent',
          password: 'p',
          createdAt: now.subtract(const Duration(hours: 12)),
        ),
        TournamentRegistration(
          id: 'future',
          password: 'p',
          createdAt: now.add(const Duration(hours: 1)),
        ),
      ],
      now: now,
    );

    expect(recent.map((tournament) => tournament.id), <String>[
      'recent',
      'boundary',
    ]);
  });

  test('competitor XLSX codec round-trips all registration fields', () {
    final source = Competitor(
      id: 'stable-competitor-id',
      number: '017',
      name: 'Jordan Example',
      belt: 'Kiddies - Purple',
      beltRank: beltToRank('Kiddies - Purple'),
      gender: Gender.female,
      age: 17,
      birthDate: DateTime(2009, 4, 12),
      club: 'North Dojo',
    );

    final bytes = CompetitorSpreadsheetCodec.encode(<Competitor>[source]);
    final imported = CompetitorSpreadsheetCodec.decode(
      Uint8List.fromList(bytes),
      referenceDate: DateTime(2026, 1, 1),
    );

    expect(imported, hasLength(1));
    final roundTripped = imported.single;
    expect(roundTripped.id, source.id);
    expect(roundTripped.number, source.number);
    expect(roundTripped.name, source.name);
    expect(roundTripped.belt, source.belt);
    expect(roundTripped.beltRank, source.beltRank);
    expect(roundTripped.gender, source.gender);
    expect(roundTripped.age, source.age);
    expect(roundTripped.birthDate, source.birthDate);
    expect(roundTripped.club, source.club);
  });

  test('competitor XLSX codec works through isolate execution', () async {
    final source = _competitors(1).single.copyWith(
      gender: Gender.female,
      birthDate: DateTime(2010, 7, 9),
      age: 16,
      club: 'South Dojo',
    );
    final referenceDate = DateTime(2026, 1, 1);
    final bytes = await Isolate.run(
      () => CompetitorSpreadsheetCodec.encode(<Competitor>[source]),
    );
    final imported = await Isolate.run(
      () => CompetitorSpreadsheetCodec.decode(
        Uint8List.fromList(bytes),
        referenceDate: referenceDate,
      ),
    );

    expect(imported.single.id, source.id);
    expect(imported.single.gender, Gender.female);
    expect(imported.single.birthDate, DateTime(2010, 7, 9));
    expect(imported.single.club, 'South Dojo');
  });

  test(
    'competitor XLSX codec workers are compatible with Flutter compute',
    () async {
      final source = _competitors(1).single;
      final bytes = await compute(
        CompetitorSpreadsheetCodec.encode,
        <Competitor>[source],
      );
      final imported = await compute(
        CompetitorSpreadsheetCodec.decode,
        Uint8List.fromList(bytes),
      );

      expect(imported.single.id, source.id);
      expect(imported.single.number, source.number);
    },
  );

  test('legacy competitor XLSX rows remain importable', () {
    final imported = CompetitorSpreadsheetCodec.decodeRows(<List<String>>[
      <String>['number', 'name', 'belt', 'birth_year', 'club'],
      <String>['42', 'Legacy Competitor', 'Kiddies - Black', '2012', 'West'],
    ], referenceDate: DateTime(2026, 1, 1));

    expect(imported, hasLength(1));
    expect(imported.single.number, '42');
    expect(imported.single.gender, Gender.male);
    expect(imported.single.beltRank, beltToRank('Kiddies'));
    expect(imported.single.birthDate, DateTime(2012, 1, 1));
    expect(imported.single.club, 'West');
    expect(imported.single.id, isNotEmpty);

    final existing = _competitors(1).single.copyWith(number: '42');
    final reconciled = CompetitorSpreadsheetCodec.retainExistingIdsByNumber(
      imported: imported,
      existing: <Competitor>[existing],
    );
    expect(reconciled.single.id, existing.id);
  });

  testWidgets('App starts with tournament access gate', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Tournament Access'), findsOneWidget);
    expect(find.text('Tournament ID'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('three-person draw sheet shows loser feed between semifinals', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_drawSheet(_competitors(3)));

    expect(find.text('Semi-Finals'), findsOneWidget);
    expect(find.text('Finals'), findsOneWidget);
    expect(find.text('Loser'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
  });

  testWidgets('five-person draw sheet pre-fills three BYE advances', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_drawSheet(_competitors(5)));

    expect(find.text('Quarterfinal'), findsOneWidget);
    expect(find.text('BYE advance'), findsNWidgets(3));
    expect(find.text('BYE'), findsNWidgets(3));
  });

  testWidgets('four entrants start directly in semifinals', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_drawSheet(_competitors(4)));

    expect(find.text('Semi-Finals'), findsOneWidget);
    expect(find.text('Quarterfinal'), findsNothing);
    expect(find.text('BYE advance'), findsNothing);
  });

  testWidgets('eight entrants use the larger bracket under strict m > n', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_drawSheet(_competitors(8)));

    expect(find.text('Round of 16'), findsOneWidget);
    expect(find.text('BYE advance'), findsNWidgets(8));
  });

  testWidgets('repechage draw sheet includes mini-list BYEs, not a final', (
    WidgetTester tester,
  ) async {
    final competitors = _competitors(9);
    final division = _divisionFor(competitors).copyWith(
      matchRecords: <DivisionMatchRecord>[
        _matchRecord('match_1', 'Round of 16', competitors[0], competitors[1]),
        _matchRecord('match_2', 'Quarterfinal', competitors[0], competitors[2]),
        _matchRecord('match_3', 'Quarterfinal', competitors[3], competitors[4]),
        _matchRecord('match_4', 'Quarterfinal', competitors[5], competitors[6]),
        _matchRecord('match_5', 'Quarterfinal', competitors[7], competitors[8]),
        _matchRecord('match_6', 'Semifinal', competitors[0], competitors[3]),
        _matchRecord('match_7', 'Semifinal', competitors[7], competitors[5]),
        _matchRecord(
          'repechage_1',
          'Repechage Round 1',
          competitors[3],
          competitors[2],
        ),
        _matchRecord(
          'repechage_2',
          'Repechage Round 2',
          competitors[3],
          competitors[1],
        ),
        _matchRecord(
          'repechage_3',
          'Repechage Round 2',
          competitors[5],
          competitors[8],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawSheetContent(division: division, competitors: competitors),
        ),
      ),
    );

    final repechagePanel = find
        .ancestor(of: find.text('Repechage'), matching: find.byType(Card))
        .first;
    final mainDrawPanel = find
        .ancestor(of: find.text('Main Draw'), matching: find.byType(Card))
        .first;
    expect(
      tester.getSize(repechagePanel).width,
      tester.getSize(mainDrawPanel).width,
    );
    expect(
      find.descendant(of: repechagePanel, matching: find.text('BYE advance')),
      findsNWidgets(3),
    );
    final finalistsHeading = find.descendant(
      of: repechagePanel,
      matching: find.text('Finalists'),
    );
    expect(finalistsHeading, findsOneWidget);
    final finalistsColumn = find
        .ancestor(of: finalistsHeading, matching: find.byType(Column))
        .first;
    expect(
      find.descendant(of: finalistsColumn, matching: find.text('4')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: finalistsColumn, matching: find.text('6')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: finalistsColumn,
        matching: find.textContaining('Flags'),
      ),
      findsNothing,
    );
    expect(find.textContaining('Repechage Final'), findsNothing);
  });

  testWidgets('draw sheet shows Year and Floor once in the header', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_drawSheet(_competitors(2)));

    expect(find.text('Year: ${DateTime.now().year - 10}'), findsOneWidget);
    expect(find.text('Floor: Tatami 1'), findsOneWidget);
    expect(find.text('Tatami: Tatami 1'), findsNothing);
  });

  testWidgets('two-person division starts directly with its final', (
    WidgetTester tester,
  ) async {
    final competitors = _competitors(2);
    await tester.pumpWidget(_competitionExecution(competitors, (_, _) {}));
    await tester.pumpAndSettle();

    expect(find.text('Final'), findsOneWidget);
    expect(find.text('Round of 6'), findsNothing);
    expect(find.text('1 - Competitor 1'), findsOneWidget);
    expect(find.text('2 - Competitor 2'), findsOneWidget);
  });

  testWidgets('three-person execution assigns third entrant to Aka/top', (
    WidgetTester tester,
  ) async {
    final competitors = _competitors(3);
    var savedMatches = <DivisionMatchRecord>[];
    var savedPlacements = <DivisionPlacement>[];
    await tester.pumpWidget(
      _competitionExecution(competitors, (matches, placements) {
        savedMatches = matches;
        savedPlacements = placements;
      }),
    );
    await tester.pumpAndSettle();

    for (var matchIndex = 0; matchIndex < 2; matchIndex++) {
      final akaField = find.byKey(const ValueKey('Aka flags'));
      await tester.ensureVisible(akaField);
      await tester.enterText(akaField, '3');
      await tester.pump();
      expect(find.text('Shiro: 2   Aka: 3'), findsOneWidget);
      final nextMatchButton = find.text('Next Match');
      await tester.ensureVisible(nextMatchButton);
      await tester.tap(nextMatchButton);
      await tester.pumpAndSettle();
    }

    final secondMatch = savedMatches.singleWhere(
      (record) => record.matchId == 'match_2',
    );
    expect(secondMatch.competitorAId, competitors[2].id);
    expect(secondMatch.competitorBId, competitors[1].id);
    expect(secondMatch.competitorAFlags, 3);
    expect(secondMatch.competitorBFlags, 2);
    expect(find.textContaining('3rd Place'), findsNothing);

    final finalAkaField = find.byKey(const ValueKey('Aka flags'));
    await tester.ensureVisible(finalAkaField);
    await tester.enterText(finalAkaField, '3');
    final recordFinalButton = find.text('Record Final Result');
    await tester.ensureVisible(recordFinalButton);
    await tester.tap(recordFinalButton);
    await tester.pumpAndSettle();

    expect(
      savedPlacements.any(
        (placement) =>
            placement.placeLabel == '3rd Place' &&
            placement.competitorIds.single == competitors[1].id,
      ),
      isTrue,
    );
  });

  testWidgets('four-person execution records joint third place', (
    WidgetTester tester,
  ) async {
    final competitors = _competitors(4);
    var savedPlacements = <DivisionPlacement>[];
    var savedMatches = <DivisionMatchRecord>[];
    await tester.pumpWidget(
      _competitionExecution(competitors, (matches, placements) {
        savedMatches = matches;
        savedPlacements = placements;
      }),
    );
    await tester.pumpAndSettle();

    for (var matchIndex = 0; matchIndex < 2; matchIndex++) {
      final akaField = find.byKey(const ValueKey('Aka flags'));
      await tester.ensureVisible(akaField);
      await tester.enterText(akaField, '3');
      await tester.pump();
      expect(find.text('Shiro: 2   Aka: 3'), findsOneWidget);
      final nextMatchButton = find.text('Next Match');
      await tester.ensureVisible(nextMatchButton);
      await tester.tap(nextMatchButton);
      await tester.pumpAndSettle();
    }

    final finalAkaField = find.byKey(const ValueKey('Aka flags'));
    await tester.ensureVisible(finalAkaField);
    await tester.enterText(finalAkaField, '3');
    final recordFinalButton = find.text('Record Final Result');
    await tester.ensureVisible(recordFinalButton);
    await tester.tap(recordFinalButton);
    await tester.pumpAndSettle();

    final firstSemifinal = savedMatches.singleWhere(
      (record) => record.matchId == 'match_1',
    );
    final secondSemifinal = savedMatches.singleWhere(
      (record) => record.matchId == 'match_2',
    );
    expect(firstSemifinal.competitorAId, competitors[0].id);
    expect(firstSemifinal.competitorBId, competitors[1].id);
    expect(firstSemifinal.competitorAFlags, 3);
    expect(firstSemifinal.competitorBFlags, 2);
    expect(secondSemifinal.competitorAId, competitors[2].id);
    expect(secondSemifinal.competitorBId, competitors[3].id);
    expect(secondSemifinal.competitorAFlags, 3);
    expect(secondSemifinal.competitorBFlags, 2);

    expect(
      savedPlacements.any(
        (placement) =>
            placement.placeLabel == '3rd Place (Joint)' &&
            placement.competitorIds.toSet().containsAll(<String>[
              competitors[1].id,
              competitors[3].id,
            ]),
      ),
      isTrue,
    );
  });

  testWidgets('three-person repechage draws the loser-feed match', (
    WidgetTester tester,
  ) async {
    final competitors = _competitors(5);
    final division = _divisionFor(competitors).copyWith(
      matchRecords: <DivisionMatchRecord>[
        _matchRecord('match_1', 'Quarterfinal', competitors[0], competitors[1]),
        _matchRecord('match_2', 'Semifinal', competitors[0], competitors[2]),
        _matchRecord('match_3', 'Semifinal', competitors[3], competitors[4]),
        _matchRecord('match_4', 'Final', competitors[0], competitors[3]),
        _matchRecord(
          'repechage_1',
          'Repechage Round 1',
          competitors[2],
          competitors[1],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawSheetContent(division: division, competitors: competitors),
        ),
      ),
    );

    final repechagePanel = find
        .ancestor(of: find.text('Repechage'), matching: find.byType(Card))
        .first;
    expect(
      find.descendant(
        of: repechagePanel,
        matching: find.byIcon(Icons.arrow_downward),
      ),
      findsOneWidget,
    );
    final thirdEntrant = find.descendant(
      of: repechagePanel,
      matching: find.text('5'),
    );
    final advancingLoser = find
        .descendant(of: repechagePanel, matching: find.text('2'))
        .last;
    expect(
      tester.getTopLeft(thirdEntrant).dy,
      lessThan(tester.getTopLeft(advancingLoser).dy),
    );
  });

  testWidgets('three-person repechage execution preserves Aka/Shiro order', (
    WidgetTester tester,
  ) async {
    final competitors = _competitors(5);
    var savedMatches = <DivisionMatchRecord>[];
    final division = _executionDivision(competitors).copyWith(
      matchRecords: <DivisionMatchRecord>[
        _matchRecord('match_1', 'Quarterfinal', competitors[0], competitors[1]),
        _matchRecord('match_2', 'Semifinal', competitors[0], competitors[2]),
        _matchRecord('match_3', 'Semifinal', competitors[3], competitors[4]),
      ],
    );
    await tester.pumpWidget(
      _competitionExecution(competitors, (matches, _) {
        savedMatches = matches;
      }, division: division),
    );
    await tester.pumpAndSettle();

    expect(find.text('Repechage Round 1'), findsOneWidget);
    for (var matchIndex = 0; matchIndex < 2; matchIndex++) {
      final akaField = find.byKey(const ValueKey('Aka flags'));
      await tester.ensureVisible(akaField);
      await tester.enterText(akaField, '3');
      await tester.pump();
      final nextMatchButton = find.text('Next Match');
      await tester.ensureVisible(nextMatchButton);
      await tester.tap(nextMatchButton);
      await tester.pumpAndSettle();
    }

    final secondRepechageMatch = savedMatches.singleWhere(
      (record) => record.matchId == 'repechage_2',
    );
    expect(secondRepechageMatch.competitorAId, competitors[4].id);
    expect(secondRepechageMatch.competitorBId, competitors[1].id);
    expect(secondRepechageMatch.competitorAFlags, 3);
    expect(secondRepechageMatch.competitorBFlags, 2);
  });

  testWidgets('selecting Kiddies reveals a color belt selector', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompetitorRegistrationScreen(
          competitors: const <Competitor>[],
          onSave: (_) async {},
          onDelete: (_) async {},
          onReplaceCompetitors: (_) async {},
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kiddies').last);
    await tester.pumpAndSettle();

    expect(find.text('Kiddies Belt Color'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
  });

  test('Kiddies color belts keep the Kiddies division rank', () {
    expect(beltToRank('Kiddies - White'), beltToRank('Kiddies'));
    expect(beltToRank('Kiddies - Black'), beltToRank('Kiddies'));
  });

  testWidgets('division draw order can be changed before saving', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DivisionRegistrationScreen(
          competitors: _competitors(3),
          divisions: const <Division>[],
          tatamiNames: const <String>['Tatami 1'],
          onSave: (_) async {},
          onDelete: (_) async {},
        ),
      ),
    );

    for (final number in <String>['1', '2', '3']) {
      await tester.enterText(find.byType(TextField).first, number);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    final firstHandle = find.byType(ReorderableDragStartListener).first;
    await tester.ensureVisible(firstHandle);
    await tester.drag(firstHandle, const Offset(0, 140));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('3 - Competitor 3')).dy,
      lessThan(tester.getTopLeft(find.text('1 - Competitor 1')).dy),
    );
  });

  testWidgets('seven-person repechage follows both semifinals before final', (
    WidgetTester tester,
  ) async {
    final competitors = _competitors(7);
    final savedPlacements = <DivisionPlacement>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CompetitionExecutionScreen(
          tatamiName: 'Tatami 1',
          division: _executionDivision(competitors),
          competitors: competitors,
          judgesCount: 5,
          onJudgeCountChanged: (_, _) async {},
          onStartDivision: (_, _) async {},
          onCompleteDivision: (_, _) async {},
          onSaveExecutionState:
              (
                _,
                _, {
                required matchRecords,
                required placements,
                logMessage,
              }) async {
                savedPlacements
                  ..clear()
                  ..addAll(placements);
              },
          onPublishLiveState: (_) {},
          onSaveInProgressMatch: (_, _, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var matchIndex = 0; matchIndex < 5; matchIndex++) {
      final akaField = find.byType(TextField).last;
      await tester.ensureVisible(akaField);
      await tester.enterText(akaField, '3');
      final nextMatchButton = find.text('Next Match');
      await tester.ensureVisible(nextMatchButton);
      await tester.tap(nextMatchButton);
      await tester.pumpAndSettle();
    }

    expect(find.text('Repechage Round 1'), findsOneWidget);
    expect(find.text('Final'), findsNothing);

    for (var repechageMatch = 0; repechageMatch < 2; repechageMatch++) {
      final akaField = find.byType(TextField).last;
      await tester.ensureVisible(akaField);
      await tester.enterText(akaField, '3');
      final nextMatchButton = find.text('Next Match');
      await tester.ensureVisible(nextMatchButton);
      await tester.tap(nextMatchButton);
      await tester.pumpAndSettle();
    }

    expect(find.text('Final'), findsOneWidget);
    expect(find.textContaining('Repechage Final'), findsNothing);

    final finalAkaField = find.byType(TextField).last;
    await tester.ensureVisible(finalAkaField);
    await tester.enterText(finalAkaField, '3');
    final recordFinalButton = find.text('Record Final Result');
    await tester.ensureVisible(recordFinalButton);
    await tester.tap(recordFinalButton);
    await tester.pumpAndSettle();

    expect(
      savedPlacements.any(
        (placement) => placement.placeLabel == '4th Place (Joint)',
      ),
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.textContaining('4th Place (Joint)'),
      -300,
    );
    expect(find.textContaining('4th Place (Joint)'), findsOneWidget);
  });
}
