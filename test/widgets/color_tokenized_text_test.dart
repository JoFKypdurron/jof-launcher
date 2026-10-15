import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joflauncher/widgets/color_tokenized_text.dart';

void main() {
  testWidgets('ColorTokenizedText parses colors correctly', (WidgetTester tester) async {
    const text = '^1Red ^2Green ^3Yellow';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ColorTokenizedText(text: text),
      ),
    ));

    // Text.rich uses RichText internally
    final richTextFinder = find.byType(RichText);
    expect(richTextFinder, findsOneWidget);

    final RichText richText = tester.widget(richTextFinder);
    final TextSpan textSpan = richText.text as TextSpan;

    // When using Text.rich, the provided TextSpan is wrapped in another TextSpan that applies the style
    expect(textSpan.children?.length, 1);
    final innerSpan = textSpan.children![0] as TextSpan;
    expect(innerSpan.children?.length, 3);
    
    final span1 = innerSpan.children![0] as TextSpan;
    expect(span1.text, 'Red ');
    expect(span1.style?.color, const Color(0xFFFF5C5C));

    final span2 = innerSpan.children![1] as TextSpan;
    expect(span2.text, 'Green ');
    expect(span2.style?.color, const Color(0xFF3EE05A));

    final span3 = innerSpan.children![2] as TextSpan;
    expect(span3.text, 'Yellow');
    expect(span3.style?.color, const Color(0xFFFFD400));
  });

  testWidgets('ColorTokenizedText handles no tokens', (WidgetTester tester) async {
    const text = 'No tokens here';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ColorTokenizedText(text: text),
      ),
    ));

    expect(find.text('No tokens here'), findsOneWidget);
  });
}
