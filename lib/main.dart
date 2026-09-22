import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'tournament_access_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TISKA Tournament Manager',
      theme: AppTheme.light(),
      home: const TournamentAccessScreen(),
    );
  }
}
