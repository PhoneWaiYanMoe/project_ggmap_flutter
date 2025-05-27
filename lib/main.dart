import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:project_ggmap_flutter/src/features/map/map_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'src/features/auth/login_screen.dart';
import 'src/features/map/map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Required for async initialization
  await dotenv.load(fileName: ".env"); // Load environment variables
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token'); // Check if user is logged in
  runApp(MyApp(isLoggedIn: token != null));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;

  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Map App',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4285F4), // Google Maps blue
          brightness: Brightness.light,
          primary: const Color(0xFF4285F4),
          secondary: const Color(0xFF34A853), // Google Maps green
          surface: Colors.white,
          background: const Color(0xFFF8F9FA),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 2,
          centerTitle: false,
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1A73E8),
          titleTextStyle: TextStyle(
            color: Color(0xFF1A73E8),
            fontSize: 22,
            fontWeight: FontWeight.w500,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: const Color(0xFF4285F4),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          color: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF4285F4), width: 2),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4285F4),
          brightness: Brightness.dark,
          primary: const Color(0xFF4285F4),
          secondary: const Color(0xFF34A853),
          surface: const Color(0xFF242F3E), // Google Maps dark mode color
          background: const Color(0xFF242F3E),
        ),
        scaffoldBackgroundColor: const Color(0xFF242F3E),
        appBarTheme: const AppBarTheme(
          elevation: 2,
          centerTitle: false,
          backgroundColor: Color(0xFF242F3E),
          foregroundColor: Colors.white,
        ),
      ),
      home: MapScreen(),
    );
  }
}