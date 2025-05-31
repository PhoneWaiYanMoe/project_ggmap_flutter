import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'src/features/map/map_screen.dart';
import 'src/services/language_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env', isOptional: true);
  } catch (e) {
    print('Failed to load .env file: $e');
  }
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');

  // Initialize language service
  final languageService = LanguageService();

  runApp(MyApp(
    isLoggedIn: token != null,
    languageService: languageService,
  ));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  final LanguageService languageService;

  const MyApp({
    super.key,
    required this.isLoggedIn,
    required this.languageService,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: languageService,
      builder: (context, _) {
        return MaterialApp(
          title: 'Flutter Map App',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4285F4),
              brightness: Brightness.light,
              primary: const Color(0xFF4285F4),
              secondary: const Color(0xFF34A853),
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
            cardTheme: CardThemeData(
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
              surface: const Color(0xFF242F3E),
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
          home: MapScreenWithLanguage(languageService: languageService),
        );
      },
    );
  }
}

// Keep the wrapper class as it's needed
class MapScreenWithLanguage extends StatelessWidget {
  final LanguageService languageService;

  const MapScreenWithLanguage({
    super.key,
    required this.languageService,
  });

  @override
  Widget build(BuildContext context) {
    return MapScreen(languageService: languageService);
  }
}