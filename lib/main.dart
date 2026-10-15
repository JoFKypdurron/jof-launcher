import 'package:flutter/material.dart';
import 'theme/jof_theme.dart';
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
          theme: buildJofTheme(),
          home: const HomeView(),
        );
      },
    );
  }
}
