import 'package:flutter/material.dart';
import 'views/home_view.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double textScaleFactor = constraints.maxWidth < 600 ? 0.85 : 1.0;
        
        return MaterialApp(
          title: 'JoF Launcher',
          builder: (context, child) {
            final MediaQueryData data = MediaQuery.of(context);
            return MediaQuery(
              data: data.copyWith(
                textScaler: TextScaler.linear(textScaleFactor),
              ),
              child: child!,
            );
          },
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF051720),
            fontFamily: 'Rajdhani',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF051720),
              brightness: Brightness.dark,
              primary: const Color(0xFFA5D8FF),
              secondary: const Color(0xFFA5D8FF),
              surface: const Color(0xFF03273C),
              onSurface: Colors.white,
            ),
            cardTheme: const CardThemeData(
              color: Color(0xFF03273C),
              margin: EdgeInsets.zero,
            ),
            expansionTileTheme: const ExpansionTileThemeData(
              backgroundColor: Color(0xFF03273C),
              collapsedBackgroundColor: Color(0xFF03273C),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF051720),
              foregroundColor: Colors.white,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003554),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: Color(0xFF003554),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
            useMaterial3: true,
          ),
          home: const HomeView(),
        );
      },
    );
  }
}
