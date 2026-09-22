// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:tiska_tournament_manager/main.dart';

void main() {
  testWidgets('App starts with tournament access gate', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Tournament Access'), findsOneWidget);
    expect(find.text('Tournament ID'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
