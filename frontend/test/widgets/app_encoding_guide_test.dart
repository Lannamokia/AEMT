import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/app.dart';

void main() {
  testWidgets('encoding parameter guide opens as plain text card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return TextButton(
              onPressed: () => showEncodingParameterGuide(context),
              child: const Text('编码参数设置指引'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('编码参数设置指引'));
    await tester.pumpAndSettle();

    expect(find.text('编码参数设置指引'), findsWidgets);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.textContaining('面对字幕组场景的成片压制'), findsOneWidget);
    expect(find.textContaining('AAC，码率 256k'), findsOneWidget);
  });
}
