import 'package:flutter/material.dart';

class ColorTokenizedText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const ColorTokenizedText({super.key, required this.text, this.style});

  /// Quake 3 colour codes (`^0`–`^9`).
  ///
  /// Tuned from the engine's pure RGB values to stay readable on the dark
  /// surfaces, matching the player list in the JoF design files: black is
  /// lifted to a mid grey and pure red and blue are lightened.
  static const Map<String, Color> colorMap = {
    '0': Color(0xFF7A7A7A), // BLACK
    '1': Color(0xFFFF5C5C), // RED
    '2': Color(0xFF3EE05A), // GREEN
    '3': Color(0xFFFFD400), // YELLOW
    '4': Color(0xFF7D93FF), // BLUE
    '5': Color(0xFF00E5FF), // CYAN
    '6': Color(0xFFFF66FF), // MAGENTA
    '7': Color(0xFFFFFFFF), // WHITE
    '8': Color(0xFFFFA500), // ORANGE
    '9': Color(0xFF9B9B9B), // GREY
  };

  @override
  Widget build(BuildContext context) {
    List<TextSpan> spans = [];
    final RegExp regExp = RegExp(r'\^(\d)');

    int lastMatchEnd = 0;
    Color currentColor = style?.color ?? Colors.white;

    final matches = regExp.allMatches(text);

    if (matches.isEmpty) {
      return Text(text, style: style);
    }

    for (var match in matches) {
      // Add text before the match
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastMatchEnd, match.start),
            style: (style ?? const TextStyle()).copyWith(color: currentColor),
          ),
        );
      }

      // Update current color
      String colorCode = match.group(1)!;
      currentColor = colorMap[colorCode] ?? currentColor;

      lastMatchEnd = match.end;
    }

    // Add remaining text
    if (lastMatchEnd < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastMatchEnd),
          style: (style ?? const TextStyle()).copyWith(color: currentColor),
        ),
      );
    }

    return Text.rich(TextSpan(children: spans), style: style);
  }
}
