// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/material.dart';
import 'package:tiska_tournament_manager/main.dart';
import 'package:tiska_tournament_manager/draw_sheet_screen.dart';
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

void main() {
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

  testWidgets('eight entrants use the larger bracket under strict m > n', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_drawSheet(_competitors(8)));

    expect(find.text('Round of 16'), findsOneWidget);
    expect(find.text('BYE advance'), findsNWidgets(8));
  });
}
