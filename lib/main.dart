// Deployment / Git / Netlify reference:
// 1) Commit and push the latest app changes:
//    git add .
//    git commit -m "Describe the change"
//    git push origin main
//
// 2) Netlify deploys automatically when GitHub receives a push to main,
//    because the GitHub Actions workflow is configured in:
//    .github/workflows/netlify-deploy.yml
//
// 3) If the workflow or Netlify build needs rerunning, trigger a new push to main,
//    or use the Netlify dashboard to redeploy the latest successful build.
//
// 4) The app is configured for Supabase shared data access via:
//    lib/supabase_config.dart
//
// 5) Required GitHub secrets for Netlify deployment:
//    NETLIFY_AUTH_TOKEN
//    NETLIFY_SITE_ID
//
// This file is the app entry point for the tournament manager.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'supabase_config.dart';
import 'tournament_access_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

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
