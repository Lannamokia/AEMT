import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/services/font_asset_service_internal/subset_ass_rewriter.dart';

void main() {
  test('Property 26: Subset_Rewrite_Ass faithfully applies renameMap', () {
    const String input = '''
[Script Info]
; keep me

[V4+ Styles]
Format: Name, Fontname, Fontsize
Style: Default,Example Font,36
Style: Vertical,@Example Font,36

[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,0:00:00.00,0:00:01.00,Default,{\\fnExample Font}hello{\\fn@Example Font}world
''';
    final String output = rewriteAssText(input, const <String, String>{
      'example font': 'ABCDEFGH',
    }, newline: '\n');

    expect(output, contains('; Font Subset: ABCDEFGH - example font'));
    expect(output, contains('Style: Default,ABCDEFGH,36'));
    expect(output, contains('Style: Vertical,@ABCDEFGH,36'));
    expect(output, contains(r'{\fnABCDEFGH}hello{\fn@ABCDEFGH}world'));
    expect(output, contains('; keep me'));
  });

  test(
    'Property 27: Subset_Rewrite_Ass skip-path leaves originals untouched',
    () {
      const String input = '[Events]\nDialogue: 0,0,0,Default,{\\fnA}x\n';
      expect(
        rewriteAssText(input, const <String, String>{}, newline: '\n'),
        input,
      );
    },
  );

  test('Subset_Rewrite_Ass strips non-rendering format controls', () {
    const String input = '''
[Script Info]

[V4+ Styles]
Format: Name, Fontname, Fontsize
Style: Default,Example Font,36

[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,0:00:00.00,0:00:01.00,Default,{\\fnExample Font}\u200Eおはよう
''';
    final String output = rewriteAssText(input, const <String, String>{
      'example font': 'ABCDEFGH',
    }, newline: '\n');

    expect(output, contains(r'{\fnABCDEFGH}おはよう'));
    expect(output.contains('\u200E'), isFalse);
  });
}
