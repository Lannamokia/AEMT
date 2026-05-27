import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/widgets/common_widgets.dart';
import 'package:frontend/src/models.dart';

void main() {
  testWidgets('runtime details include font subsetting tools', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Wrap(
          children: <Widget>[
            toolChip(
              const RuntimeToolInfo(
                name: 'pyftsubset',
                path: 'C:/Python/Scripts/pyftsubset.exe',
                required: false,
              ),
            ),
            toolChip(
              const RuntimeToolInfo(
                name: 'ttx',
                path: 'C:/Python/Scripts/ttx.exe',
                required: false,
              ),
            ),
            statusChip(label: 'fonttools', status: '4.61.0', ok: true),
          ],
        ),
      ),
    );

    expect(find.text('pyftsubset: 已就绪'), findsOneWidget);
    expect(find.text('ttx: 已就绪'), findsOneWidget);
    expect(find.text('fonttools: 4.61.0'), findsOneWidget);
  });
}
