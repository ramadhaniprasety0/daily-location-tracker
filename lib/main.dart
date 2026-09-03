import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workmanager/workmanager.dart';
import 'services/location_service.dart';
import 'home_page.dart';
import 'auth_page.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Supabase.initialize(
        url: 'https://gskjwngdpgjttdukncki.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdza2p3bmdkcGdqdHRkdWtuY2tpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgzODQwNzIsImV4cCI6MjEwMzk2MDA3Mn0.yyRNEDWjCzNK-ReFCxrEnMPfydwx9nafzgcNPkycCCE',
      );
      await initializeDateFormatting('id_ID', null);
      await LocationService.recordLocation(isManual: false);
      return Future.value(true);
    } catch (e) {
      print(e);
      return Future.value(false);
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await initializeDateFormatting('id_ID', null);
  
  await Supabase.initialize(
    url: 'https://gskjwngdpgjttdukncki.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdza2p3bmdkcGdqdHRkdWtuY2tpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgzODQwNzIsImV4cCI6MjEwMzk2MDA3Mn0.yyRNEDWjCzNK-ReFCxrEnMPfydwx9nafzgcNPkycCCE',
  );

  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true, // Ubah ke false untuk production
  );

  runApp(const DailyLocationTrackerApp());
}

class DailyLocationTrackerApp extends StatelessWidget {
  const DailyLocationTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Location Tracker',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E40AF),
          primary: const Color(0xFF1E40AF),
          background: const Color(0xFFF8FAFC),
          surface: const Color(0xFFFFFFFF),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF0F172A)),
          bodyMedium: TextStyle(color: Color(0xFF64748B)),
        ),
      ),
      home: const SplashAuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SplashAuthWrapper extends StatefulWidget {
  const SplashAuthWrapper({Key? key}) : super(key: key);

  @override
  State<SplashAuthWrapper> createState() => _SplashAuthWrapperState();
}

class _SplashAuthWrapperState extends State<SplashAuthWrapper> {
  @override
  void initState() {
    super.initState();
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      final session = data.session;
      if (session != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const AuthPage()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
