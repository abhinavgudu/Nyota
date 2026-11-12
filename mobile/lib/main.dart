import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    // Fail loudly at startup instead of mysteriously later.
    runApp(const NyotaConfigErrorApp());
    return;
  }
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );
  runApp(const NyotaApp());
}

class NyotaApp extends StatelessWidget {
  const NyotaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nyota',
      debugShowCheckedModeBanner: false,
      theme: NyotaTheme.light(),
      home: const AuthGate(),
    );
  }
}

class NyotaConfigErrorApp extends StatelessWidget {
  const NyotaConfigErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nyota',
      debugShowCheckedModeBanner: false,
      theme: NyotaTheme.light(),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Missing Supabase configuration.\n\nRun the app with:\n'
              'flutter run \\\n'
              '  --dart-define=SUPABASE_URL=<your-url> \\\n'
              '  --dart-define=SUPABASE_ANON_KEY=<your-anon-key>',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}
