import 'package:flutter/material.dart';

class ColorTokenizedText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const ColorTokenizedText({super.key, required this.text, this.style});

  static const Map<String, Color> colorMap = {
    '0': Color(0xFF000000), // BLACK
    '1': Color(0xFFFF0000), // RED
    '2': Color(0xFF00AA00), // GREEN
    '3': Color(0xFFFFFF00), // YELLOW
    '4': Color(0xFF0000FF), // BLUE
    '5': Color(0xFF00FFFF), // CYAN
    '6': Color(0xFFFF00FF), // MAGENTA
    '7': Color(0xFFFFFFFF), // WHITE
    '8': Color(0xFFFFA500), // ORANGE
    '9': Color(0xFF808080), // GREY
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
