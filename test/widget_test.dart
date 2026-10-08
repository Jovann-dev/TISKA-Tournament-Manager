// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';
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
import 'package:tiska_tournament_manager/competition_categories_screen.dart';
import 'package:tiska_tournament_manager/competition_results_screen.dart';
import 'package:tiska_tournament_manager/live_match_state.dart';
import 'package:tiska_tournament_manager/tatami_display_screen.dart';
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
  testWidgets('points warning counts fit a narrow mobile screen', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final competitors = _competitors(2);
    final division = _executionDivision(competitors).copyWith(
      competitionType: CompetitionType.jiyuKumite,
      inProgressMatch: DivisionInProgressMatch(matchId: 'match_1', timerRemainingSeconds: 60,
        competitorAWarningStage: 3, events: [DivisionMatchEventRecord(
          competitorId: competitors.first.id, kind: KumiteEventKind.warning,
          warningType: KumiteWarningType.contact, warningStage: KumiteWarningStage.third,
          timestamp: 1,
        )]),
    );
    await tester.pumpWidget(_competitionExecution(competitors, (_, _) {}, division: division));
    await tester.pumpAndSettle();
    final block = find.byKey(ValueKey('points-editor-${competitors.first.id}'));
    await tester.scrollUntilVisible(block, 300);
    await tester.pumpAndSettle();
    expect(find.text('Warnings: 1 (Hansoku)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restored warning counts and undo preserve the confirmation threshold', (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final competitors = _competitors(2);
    final warned = competitors.first;
    final division = _executionDivision(competitors).copyWith(
      competitionType: CompetitionType.jiyuKumite,
      inProgressMatch: DivisionInProgressMatch(matchId: 'match_1',
        timerRemainingSeconds: 60, competitorAWarningStage: 3,
        events: [for (var timestamp = 1; timestamp <= 2; timestamp++) DivisionMatchEventRecord(
          competitorId: warned.id, kind: KumiteEventKind.warning,
          warningType: KumiteWarningType.contact, warningStage: KumiteWarningStage.third,
          timestamp: timestamp,
        )],
      ),
    );
    await tester.pumpWidget(_competitionExecution(competitors, (_, _) {}, division: division));
    await tester.pumpAndSettle();
    final block = find.byKey(ValueKey('points-editor-${warned.id}'));
    Future<void> warn(String label) async {
      final button = find.descendant(of: block, matching: find.text(label));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    await warn('JK');
    expect(find.textContaining('has 3 warnings'), findsOneWidget);
    await tester.tap(find.text('Continue Match'));
    await tester.pumpAndSettle();
    final undo = find.text('Undo Last Event');
    await tester.ensureVisible(undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(find.text('Disqualify competitor?'), findsNothing);
    await warn('MK');
    expect(find.textContaining('has 3 warnings'), findsOneWidget);
    await tester.tap(find.text('Continue Match'));
    await tester.pumpAndSettle();
  });

  testWidgets('short repechage finalists are centered between the feeder matches', (tester) async {
    for (final entrantCount in [5, 6]) {
      final competitors = _competitors(entrantCount);
      final records = entrantCount == 5 ? [
        _matchRecord('match_1', 'Quarterfinal', competitors[0], competitors[1]),
        _matchRecord('match_2', 'Semifinal', competitors[0], competitors[2]),
        _matchRecord('match_3', 'Semifinal', competitors[3], competitors[4]),
        _matchRecord('match_4', 'Final', competitors[0], competitors[3]),
        _matchRecord('repechage_1', 'Repechage Round 1', competitors[2], competitors[1]),
        _matchRecord('repechage_2', 'Repechage Round 2', competitors[1], competitors[4]),
      ] : [
        _matchRecord('match_1', 'Quarterfinal', competitors[0], competitors[1]),
        _matchRecord('match_2', 'Quarterfinal', competitors[2], competitors[3]),
        _matchRecord('match_3', 'Semifinal', competitors[0], competitors[4]),
        _matchRecord('match_4', 'Semifinal', competitors[2], competitors[5]),
        _matchRecord('match_5', 'Final', competitors[0], competitors[2]),
        _matchRecord('repechage_1', 'Repechage Round 1', competitors[4], competitors[1]),
        _matchRecord('repechage_2', 'Repechage Round 1', competitors[5], competitors[3]),
      ];
      final division = _divisionFor(competitors).copyWith(matchRecords: records.map((record) =>
        DivisionMatchRecord.fromMap({...record.toMap(), 'competitorAFlags': 3, 'competitorBFlags': 2})).toList());
      for (final printFriendly in [false, true]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: DrawSheetContent(
        division: division, competitors: competitors, printFriendly: printFriendly,
      ))));
      await tester.pumpAndSettle();
      final feeder = find.byKey(const ValueKey('Repechage-round-0'));
      final finalColumn = find.byKey(const ValueKey('Repechage-round-1'));
      final first = find.descendant(of: feeder, matching: find.byKey(const ValueKey('round-match-0')));
      final second = find.descendant(of: feeder, matching: find.byKey(const ValueKey('round-match-1')));
      final finalMatch = find.descendant(of: finalColumn, matching: find.byKey(const ValueKey('round-match-0')));
      final midpoint = (tester.getCenter(first).dy + tester.getCenter(second).dy) / 2;
      expect(tester.getCenter(finalMatch).dy, closeTo(midpoint, 0.5), reason: '$entrantCount entrants');
      expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('all point warnings are enabled and disqualification requires confirmation', (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final competitors = _competitors(2);
    var saved = <DivisionMatchRecord>[];
    await tester.pumpWidget(_competitionExecution(competitors, (matches, _) => saved = matches,
      division: _executionDivision(competitors).copyWith(competitionType: CompetitionType.jiyuKumite)));
    await tester.pumpAndSettle();
    final warned = find.byKey(ValueKey('points-editor-${competitors[0].id}'));
    for (final label in ['JK', 'MK', 'CK', 'JC', 'MC', 'CC', 'JH', 'MH', 'CH']) {
      final button = find.descendant(of: warned, matching: find.widgetWithText(OutlinedButton, label));
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    }
    for (final label in ['CH', 'JK', 'MC']) {
      final button = find.descendant(of: warned, matching: find.text(label));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    expect(find.text('Disqualify competitor?'), findsOneWidget);
    expect(saved, isEmpty);
    await tester.tap(find.text('Continue Match'));
    await tester.pumpAndSettle();
    final point = find.descendant(of: warned, matching: find.text('Waza-ari'));
    await tester.ensureVisible(point);
    await tester.tap(point);
    await tester.pumpAndSettle();
    expect(find.text('Disqualify competitor?'), findsNothing);
    final fourth = find.descendant(of: warned, matching: find.text('JH'));
    await tester.ensureVisible(fourth);
    await tester.tap(fourth);
    await tester.pumpAndSettle();
    expect(find.textContaining('has 4 warnings'), findsOneWidget);
    await tester.tap(find.text('Disqualify'));
    await tester.pumpAndSettle();
    expect(saved.single.winnerId, competitors[1].id);
    expect(saved.single.finishReason, KumiteFinishReason.warning);
    expect(saved.single.events.where((event) => event.kind == KumiteEventKind.warning), hasLength(4));
    expect(saved.single.events.first.shortLabel, 'CH');
  });

  test('legacy joint fourth placements display and serialize as joint third', () {
    final placement = DivisionPlacement.fromMap({
      'placeLabel': '4th Place (Joint)', 'competitorIds': ['one', 'two'],
    });
    expect(placement.placeLabel, '3rd Place (Joint)');
    expect(placement.toMap()['placeLabel'], '3rd Place (Joint)');
    expect(const DivisionPlacement(placeLabel: 'Joint 4th Place', competitorIds: []).placeLabel, '3rd Place (Joint)');
  });

  testWidgets('team spectator rosters fit mobile width', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final competitors = _competitors(5);
    final division = _divisionFor(competitors).copyWith(
      competitionTemplate: CompetitionTemplate.flagTeams, progress: DivisionProgress.running,
      teams: [
        DivisionTeam(id: 'team-1', number: 1, memberIds: competitors.take(4).map((item) => item.id).toList()),
        DivisionTeam(id: 'team-2', number: 2, memberIds: [competitors.last.id]),
      ],
    );
    final teams = division.bracketEntrants(competitors);
    await tester.pumpWidget(MaterialApp(home: TatamiDisplayScreen(
      watchTatamiDefinitions: () => Stream.value([const TatamiDefinition(name: 'Tatami 1', judgesCount: 5)]),
      watchDivisions: () => Stream.value([division]), watchCompetitors: () => Stream.value(competitors),
      watchLiveMatchState: (_) => Stream.value(LiveMatchState(
        tatamiName: 'Tatami 1', divisionId: division.id, divisionTitle: 'Team Kata',
        competitionType: CompetitionType.kata, executionMode: CompetitionExecutionMode.flagVoting,
        updatedAt: 1, competitorA: teams[0], competitorB: teams[1],
      )),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('team-member-count-team-1')), findsOneWidget);
    expect(find.text('5 - Competitor 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('team registration and results fit a narrow mobile screen', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final competitors = _competitors(5);
    final division = _divisionFor(competitors).copyWith(
      competitionTemplate: CompetitionTemplate.flagTeams,
      teams: [
        DivisionTeam(id: 'team-1', number: 1, memberIds: competitors.take(4).map((item) => item.id).toList()),
        DivisionTeam(id: 'team-2', number: 2, memberIds: [competitors.last.id]),
      ],
      placements: const [DivisionPlacement(placeLabel: '1st Place', competitorIds: ['team-1'])],
    );
    await tester.pumpWidget(MaterialApp(home: CompetitionResultsScreen(division: division, competitors: competitors)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(home: DivisionRegistrationScreen(
      competitors: competitors, divisions: [], tatamiNames: ['Tatami 1'],
      watchCompetitionCategories: () => Stream.value([
        const CompetitionCategory(id: 'team-kata', name: 'Team Kata', template: CompetitionTemplate.flagTeams),
      ]), onSave: (_) async {}, onDelete: (_) async {},
    )));
    await tester.pumpAndSettle();
    final add = find.byKey(const ValueKey('add-division-team'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('Team 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('team draw results show short names and long roster references below repechage', (tester) async {
    final competitors = _competitors(7);
    final division = _divisionFor(competitors).copyWith(
      competitionTemplate: CompetitionTemplate.flagTeams,
      teams: [
        DivisionTeam(id: 'team-1', number: 1, memberIds: competitors.take(3).map((item) => item.id).toList()),
        DivisionTeam(id: 'team-2', number: 2, memberIds: competitors.skip(3).map((item) => item.id).toList()),
      ],
      placements: const [
        DivisionPlacement(placeLabel: '1st Place', competitorIds: ['team-1']),
        DivisionPlacement(placeLabel: '2nd Place', competitorIds: ['team-2']),
      ],
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DrawSheetContent(
      division: division, competitors: competitors, printFriendly: true,
    ))));
    final result = find.byKey(const ValueKey('draw-results'));
    expect(find.descendant(of: result, matching: find.text('1 - Competitor 1')), findsOneWidget);
    expect(find.descendant(of: result, matching: find.byKey(const ValueKey('team-member-count-team-2'))), findsOneWidget);
    expect(find.descendant(of: result, matching: find.text('4 - Competitor 4')), findsNothing);
    expect(find.descendant(of: result, matching: find.text('See draw sheet roster')), findsOneWidget);
    expect(tester.getTopLeft(find.text('Team Rosters')).dy, greaterThan(tester.getTopLeft(find.text('Repechage')).dy));
    expect(find.textContaining('7 - Competitor 7'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: CompetitionResultsScreen(
      division: division, competitors: competitors,
    )));
    expect(find.text('1 - Competitor 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('team-member-count-team-2')), findsOneWidget);
  });

  testWidgets('three-team flag advancement ignores shared individual membership', (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final competitors = _competitors(2);
    var placements = <DivisionPlacement>[];
    final division = _executionDivision(competitors).copyWith(
      competitionTemplate: CompetitionTemplate.flagTeams,
      teams: [
        DivisionTeam(id: 'team-1', number: 1, memberIds: [competitors[0].id]),
        DivisionTeam(id: 'team-2', number: 2, memberIds: [competitors[0].id]),
        DivisionTeam(id: 'team-3', number: 3, memberIds: [competitors[1].id]),
      ],
    );
    await tester.pumpWidget(_competitionExecution(competitors, (_, saved) => placements = saved, division: division));
    await tester.pumpAndSettle();
    expect(find.text('Shared team members: Competitor 1'), findsOneWidget);
    for (var match = 0; match < 3; match++) {
      final flags = find.byKey(const ValueKey('Aka flags'));
      await tester.ensureVisible(flags);
      await tester.enterText(flags, '3');
      await tester.pump();
      final next = find.text(match == 2 ? 'Record Final Result' : 'Next Match');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
    expect(placements.first.competitorIds, ['team-1']);
    expect(placements[1].competitorIds, ['team-3']);
    expect(placements.last.competitorIds, ['team-2']);
  });

  testWidgets('team execution advances teams without limiting individual roster count', (tester) async {
    final competitors = _competitors(18);
    var savedMatches = <DivisionMatchRecord>[];
    var savedPlacements = <DivisionPlacement>[];
    final division = _executionDivision(competitors).copyWith(
      competitionTemplate: CompetitionTemplate.flagTeams,
      teams: [
        DivisionTeam(id: 'team-1', number: 1, memberIds: competitors.take(17).map((item) => item.id).toList()),
        DivisionTeam(id: 'team-2', number: 2, memberIds: [competitors.last.id]),
      ],
    );
    await tester.pumpWidget(_competitionExecution(competitors, (matches, placements) {
      savedMatches = matches; savedPlacements = placements;
    }, division: division));
    await tester.pumpAndSettle();
    expect(find.text('Final'), findsOneWidget);
    expect(find.textContaining('2 teams'), findsOneWidget);
    final flags = find.byKey(const ValueKey('Aka flags'));
    await tester.ensureVisible(flags);
    await tester.enterText(flags, '3');
    final record = find.text('Record Final Result');
    await tester.ensureVisible(record);
    await tester.tap(record);
    await tester.pumpAndSettle();
    expect(savedMatches.single.winnerId, 'team-1');
    expect(savedPlacements.first.competitorIds, ['team-1']);
    expect(savedPlacements[1].competitorIds, ['team-2']);
  });

  testWidgets('team builder saves two numbered teams with shared membership', (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final competitors = _competitors(2);
    Division? saved;
    const category = CompetitionCategory(id: 'team-kata', name: 'Team Kata', template: CompetitionTemplate.flagTeams);
    await tester.pumpWidget(MaterialApp(home: DivisionRegistrationScreen(
      competitors: competitors, divisions: [], tatamiNames: ['Tatami 1'],
      watchCompetitionCategories: () => Stream.value([category]),
      onSave: (division) async => saved = division, onDelete: (_) async {},
    )));
    await tester.pumpAndSettle();
    for (var teamNumber = 1; teamNumber <= 2; teamNumber++) {
      final addTeam = find.byKey(const ValueKey('add-division-team'));
      await tester.ensureVisible(addTeam);
      await tester.tap(addTeam);
      await tester.pumpAndSettle();
      final search = find.byKey(ValueKey('team-search-$teamNumber-0'));
      await tester.ensureVisible(search);
      await tester.enterText(search, '1');
      await tester.pumpAndSettle();
      final addMember = find.byTooltip('Add 1 to Team $teamNumber');
      await tester.ensureVisible(addMember);
      await tester.tap(addMember);
      await tester.pumpAndSettle();
    }
    final save = find.text('Add Division');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved!.teams.map((team) => team.number), [1, 2]);
    expect(saved!.teams.every((team) => team.memberIds.single == competitors.first.id), isTrue);
    expect(saved!.competitorIds, [competitors.first.id]);
    expect(saved!.teamRules.maximumMembers, isNull);
    expect(saved!.teamRules.allowNames, isFalse);
  });

  testWidgets('admin team template defaults and rule controls are saved', (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CompetitionCategory? saved;
    await tester.pumpWidget(MaterialApp(home: CompetitionCategoriesScreen(
      watchCategories: () => Stream.value([]), onSave: (category) async => saved = category,
      onDelete: (_) async {},
    )));
    final template = find.byType(DropdownButton<CompetitionTemplate>);
    await tester.ensureVisible(template);
    await tester.tap(template);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flag-Based Team Scoring').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('competition-category-name')), 'Team Kata');
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('team-shared-members'))).value, isTrue);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('team-allow-names'))).value, isFalse);
    final create = find.byKey(const ValueKey('add-competition-category'));
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(saved!.template, CompetitionTemplate.flagTeams);
    expect(saved!.teamRules, const TeamRules());
    await tester.ensureVisible(find.byKey(const ValueKey('team-minimum')));
    await tester.enterText(find.byKey(const ValueKey('team-minimum')), '2');
    final shared = find.byKey(const ValueKey('team-shared-members'));
    await tester.ensureVisible(shared);
    await tester.tap(shared);
    await tester.pumpAndSettle();
    final names = find.byKey(const ValueKey('team-allow-names'));
    await tester.ensureVisible(names);
    await tester.tap(names);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('competition-category-name')));
    await tester.enterText(find.byKey(const ValueKey('competition-category-name')), 'Named Team Kata');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(saved!.teamRules.minimumMembers, 2);
    expect(saved!.teamRules.allowSharedMembers, isFalse);
    expect(saved!.teamRules.allowNames, isTrue);
  });

  testWidgets('category management fits mobile width with long names', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final category = CompetitionCategory(
      id: 'long-name', name: List.filled(80, 'X').join(), template: CompetitionTemplate.points,
    );
    await tester.pumpWidget(MaterialApp(home: CompetitionCategoriesScreen(
      watchCategories: () => Stream.value([category]),
      onSave: (_) async {}, onDelete: (_) async {},
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('category-enabled-long-name')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom categories use their saved scoring template', (tester) async {
    final competitors = _competitors(2);
    final custom = _executionDivision(competitors).copyWith(
      competitionCategoryId: 'custom', competitionCategoryName: 'Open Kumite',
      competitionTemplate: CompetitionTemplate.points,
    );
    await tester.pumpWidget(_competitionExecution(competitors, (_, _) {}, division: custom));
    await tester.pumpAndSettle();
    expect(find.text('Timer: 01:00'), findsOneWidget);
    expect(find.byKey(const ValueKey('Aka flags')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_competitionExecution(competitors, (_, _) {},
      division: custom.copyWith(competitionTemplate: CompetitionTemplate.flagVoting)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('Aka flags')), findsOneWidget);
    expect(find.text('Timer: 01:00'), findsNothing);
  });

  testWidgets('division categories follow live availability changes', (tester) async {
    final updates = StreamController<List<CompetitionCategory>>.broadcast();
    addTearDown(updates.close);
    await tester.pumpWidget(MaterialApp(home: DivisionRegistrationScreen(
      competitors: [], divisions: [], tatamiNames: ['Tatami 1'],
      watchCompetitionCategories: () => updates.stream,
      onSave: (_) async {}, onDelete: (_) async {},
    )));
    const custom = CompetitionCategory(id: 'custom', name: 'Open Kata', template: CompetitionTemplate.flagVoting);
    updates.add([custom]);
    await tester.pumpAndSettle();
    final finder = find.byWidgetPredicate((widget) => widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == 'Competition Category');
    final dropdown = find.descendant(of: finder, matching: find.byType(DropdownButton<String>));
    final selector = tester.widget<DropdownButton<String>>(dropdown);
    expect(selector.items!.map((item) => item.value), ['custom']);
    updates.add([custom.copyWith(enabled: false)]);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<String>>(dropdown).items, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom points draw sheet preserves category and event symbols', (tester) async {
    final competitors = _competitors(2);
    final division = _divisionFor(competitors).copyWith(
      competitionCategoryId: 'custom', competitionCategoryName: 'Open Kumite',
      competitionTemplate: CompetitionTemplate.points,
      matchRecords: [DivisionMatchRecord(
        matchId: 'match_1', roundLabel: 'Final',
        competitorAId: competitors[0].id, competitorBId: competitors[1].id,
        winnerId: competitors[0].id, loserId: competitors[1].id,
        events: [DivisionMatchEventRecord(competitorId: competitors[0].id,
          kind: KumiteEventKind.ippon, timestamp: 1, pointsAwarded: 2)],
      )],
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DrawSheetContent(
      division: division, competitors: competitors,
    ))));
    expect(find.text('Open Kumite'), findsOneWidget);
    expect(find.text('●'), findsOneWidget);
  });

  testWidgets('admin creates a category and toggles its availability', (tester) async {
    final updates = StreamController<List<CompetitionCategory>>.broadcast();
    addTearDown(updates.close);
    final categories = <CompetitionCategory>[];
    await tester.pumpWidget(MaterialApp(home: CompetitionCategoriesScreen(
      watchCategories: () => updates.stream,
      onSave: (category) async {
        categories.removeWhere((item) => item.id == category.id);
        categories.add(category);
        updates.add(List.of(categories));
      },
      onDelete: (_) async {},
    )));
    await tester.enterText(find.byKey(const ValueKey('competition-category-name')), 'Open Kata');
    await tester.tap(find.byKey(const ValueKey('add-competition-category')));
    await tester.pumpAndSettle();
    expect(categories.single.name, 'Open Kata');
    expect(categories.single.template, CompetitionTemplate.flagVoting);
    final availability = find.byKey(ValueKey('category-enabled-${categories.single.id}'));
    await tester.ensureVisible(availability);
    await tester.tap(availability);
    await tester.pumpAndSettle();
    expect(categories.single.enabled, isFalse);
  });

  test('spreadsheet import defaults missing Kiddies color and gender', () {
    final imported = CompetitorSpreadsheetCodec.decodeRows([
      ['number', 'name', 'belt', 'age'],
      ['001', 'Unspecified entrant', 'Kiddies', '10'],
    ]);
    expect(imported.single.belt, 'Kiddies - None');
    expect(imported.single.gender, Gender.notSpecified);
    expect(imported.single.beltRank, beltToRank('Kiddies'));
    final restored = CompetitorSpreadsheetCodec.decode(
      Uint8List.fromList(CompetitorSpreadsheetCodec.encode(imported)),
    );
    expect(restored.single.belt, 'Kiddies - None');
    expect(restored.single.gender, Gender.notSpecified);
  });

  test('spreadsheet Kiddies color column round trips and supports legacy belts', () {
    final imported = CompetitorSpreadsheetCodec.decodeRows([
      ['number', 'name', 'belt', 'age', 'kiddies_belt_color', 'gender'],
      ['001', 'Color entrant', 'Kiddies', '10', 'Purple', 'Female'],
      ['002', 'Legacy entrant', 'Kiddies - Black', '10', '', 'Male'],
    ]);
    final restored = CompetitorSpreadsheetCodec.decode(
      Uint8List.fromList(CompetitorSpreadsheetCodec.encode(imported)),
    );
    expect(restored.map((item) => item.belt), ['Kiddies - Purple', 'Kiddies - Black']);
    expect(restored.map((item) => item.gender), [Gender.female, Gender.male]);
  });

  testWidgets('spectator display clears expired live scores', (tester) async {
    final competitors = _competitors(2);
    final live = StreamController<LiveMatchState?>.broadcast();
    addTearDown(live.close);
    final division = _divisionFor(competitors).copyWith(progress: DivisionProgress.running);
    await tester.pumpWidget(MaterialApp(
      home: TatamiDisplayScreen(
        watchTatamiDefinitions: () => Stream.value([
          const TatamiDefinition(name: 'Tatami 1', judgesCount: 5),
        ]),
        watchDivisions: () => Stream.value([division]),
        watchCompetitors: () => Stream.value(competitors),
        watchLiveMatchState: (_) => live.stream,
      ),
    ));
    await tester.pumpAndSettle();
    live.add(LiveMatchState(
      tatamiName: 'Tatami 1', divisionId: division.id, divisionTitle: division.title,
      competitionType: CompetitionType.kata,
      executionMode: CompetitionExecutionMode.flagVoting,
      updatedAt: 1, competitorA: competitors[0], competitorB: competitors[1],
    ));
    await tester.pumpAndSettle();
    expect(find.text('VS'), findsOneWidget);
    live.add(null);
    await tester.pumpAndSettle();
    expect(find.text('VS'), findsNothing);
    expect(find.text('Waiting for live updates...'), findsOneWidget);
  });

  testWidgets('spectator display selects an existing tatami after remote removal', (tester) async {
    final definitions = StreamController<List<TatamiDefinition>>.broadcast();
    addTearDown(definitions.close);
    await tester.pumpWidget(MaterialApp(
      home: TatamiDisplayScreen(
        watchTatamiDefinitions: () => definitions.stream,
        watchDivisions: () => Stream.value([]),
        watchCompetitors: () => Stream.value([]),
        watchLiveMatchState: (_) => Stream.value(null),
      ),
    ));
    definitions.add(const [
      TatamiDefinition(name: 'Tatami 1', judgesCount: 5),
      TatamiDefinition(name: 'Tatami 2', judgesCount: 5),
    ]);
    await tester.pumpAndSettle();
    definitions.add(const [TatamiDefinition(name: 'Tatami 2', judgesCount: 5)]);
    await tester.pumpAndSettle();
    final selector = tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
    expect(selector.value, 'Tatami 2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('reused kumite results follow competitor IDs when sides reverse', (tester) async {
    final competitors = _competitors(3);
    var saved = <DivisionMatchRecord>[];
    final division = _executionDivision(competitors).copyWith(
      competitionType: CompetitionType.jiyuKumite,
      matchRecords: [
        DivisionMatchRecord(
          matchId: 'match_1', roundLabel: 'Semifinal',
          competitorAId: competitors[0].id, competitorBId: competitors[1].id,
          winnerId: competitors[1].id, loserId: competitors[0].id,
          competitorAPoints: 1, competitorBPoints: 2,
          competitorAWarningStage: 2, competitorBWarningStage: 1,
          events: [DivisionMatchEventRecord(
            competitorId: competitors[1].id, kind: KumiteEventKind.ippon,
            timestamp: 1, pointsAwarded: 2,
          )],
        ),
        DivisionMatchRecord(
          matchId: 'match_2', roundLabel: 'Semifinal',
          competitorAId: competitors[2].id, competitorBId: competitors[0].id,
          winnerId: competitors[0].id, loserId: competitors[2].id,
        ),
      ],
    );
    await tester.pumpWidget(_competitionExecution(
      competitors, (records, _) => saved = records, division: division,
    ));
    await tester.pumpAndSettle();
    final reused = saved.singleWhere((record) => record.reusedPreviousResult);
    expect(reused.competitorAId, competitors[1].id);
    expect(reused.competitorAPoints, 2);
    expect(reused.competitorBPoints, 1);
    expect(reused.competitorAWarningStage, 1);
    expect(reused.competitorBWarningStage, 2);
    expect(reused.events.single.competitorId, competitors[1].id);
    await tester.pumpWidget(const SizedBox());
  });

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
    expect(imported.single.gender, Gender.notSpecified);
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
        (placement) => placement.placeLabel == '3rd Place (Joint)',
      ),
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.textContaining('3rd Place (Joint)'),
      -300,
    );
    expect(find.textContaining('3rd Place (Joint)'), findsOneWidget);
  });
}
