import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/models.dart';
import 'package:frontend/src/services/font_asset_service.dart';

const int _seed = 0xF0010001;

void main() {
  test('Property 9: Subtitle character index covers visible text', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'aemt_font_index_',
    );
    final String assPath = '${root.path}/sample.ass';
    await File(assPath).writeAsString('''
[Script Info]
Title: sample

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour
Style: Default,Example Font,36,&H00FFFFFF
Style: Vertical,@Vertical Font,36,&H00FFFFFF

[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,0:00:00.00,0:00:01.00,Default,{\\fnAlt Font}Hello{\\b1}世界
Dialogue: 0,0:00:00.00,0:00:01.00,Vertical,、……
''');
    final SubtitleCharIndex index = await const FontAssetService(
      ffmpegPath: null,
      sevenZipPath: null,
    ).indexSubtitleCharacters(<String>[assPath]);

    for (final int codepoint in 'Hello世界'.runes.toSet()) {
      expect(index.codepointsByFontname['alt font'], contains(codepoint));
    }
    expect(index.codepointsByFontname['vertical font'], contains(0xFE11));
    expect(index.codepointsByFontname['vertical font'], contains(0xFE19));
    expect(index.codepointsByFontname['alt font'], contains(0xFF1F));
    expect(index.codepointsByFontname['alt font'], contains(0xFF20));
  });

  test(
    'Property 10: Font matching is case-insensitive and source-prioritized',
    () {
      final FontMatchResult result =
          const FontAssetService(
            ffmpegPath: null,
            sevenZipPath: null,
          ).matchFonts(
            const SubtitleCharIndex(<String, Set<int>>{
              'Example Font': <int>{0x41},
            }),
            const <ResolvedFontFile>[
              ResolvedFontFile(
                path: 'C:/fonts/imported.ttf',
                fileName: 'imported.ttf',
                mimeType: 'font/ttf',
                source: FontSourceKind.imported,
                importOrder: 0,
                familyNames: <String>{'example font'},
                maxpNumGlyphs: 10,
              ),
              ResolvedFontFile(
                path: 'C:/fonts/attached.ttf',
                fileName: 'attached.ttf',
                mimeType: 'font/ttf',
                source: FontSourceKind.attachment,
                importOrder: 1,
                fullNames: <String>{'EXAMPLE FONT'},
                maxpNumGlyphs: 20,
              ),
            ],
          );

      expect(result.missing, isEmpty);
      expect(result.matched['example font']!.fileName, 'attached.ttf');
    },
  );

  test('Source Han regional aliases match common ASS font names', () {
    final FontMatchResult result =
        const FontAssetService(ffmpegPath: null, sevenZipPath: null).matchFonts(
          const SubtitleCharIndex(<String, Set<int>>{
            'source han sans jp': <int>{0x41},
            'Source Han Sans SC Medium': <int>{0x4E00},
          }),
          const <ResolvedFontFile>[
            ResolvedFontFile(
              path: 'C:/fonts/SourceHanSans-Bold.otf',
              fileName: 'SourceHanSans-Bold.otf',
              mimeType: 'font/otf',
              familyNames: <String>{'Source Han Sans'},
              fullNames: <String>{'Source Han Sans Bold'},
              bold: true,
              weight: 700,
              maxpNumGlyphs: 100,
            ),
            ResolvedFontFile(
              path: 'C:/fonts/SourceHanSans-Regular.otf',
              fileName: 'SourceHanSans-Regular.otf',
              mimeType: 'font/otf',
              familyNames: <String>{'Source Han Sans'},
              fullNames: <String>{'Source Han Sans'},
              weight: 400,
              maxpNumGlyphs: 100,
            ),
            ResolvedFontFile(
              path: 'C:/fonts/SourceHanSansSC-Medium.otf',
              fileName: 'SourceHanSansSC-Medium.otf',
              mimeType: 'font/otf',
              familyNames: <String>{'Source Han Sans SC Medium'},
              fullNames: <String>{'Source Han Sans SC Medium'},
              weight: 500,
              maxpNumGlyphs: 100,
            ),
          ],
        );

    expect(result.missing, isEmpty);
    expect(
      result.matched['source han sans jp']!.fileName,
      'SourceHanSans-Regular.otf',
    );
    expect(
      result.matched['source han sans sc medium']!.fileName,
      'SourceHanSansSC-Medium.otf',
    );
  });

  test('subtitle parser error includes path and seed', () async {
    final String missingPath = 'C:/missing/subtitle-$_seed.ass';
    expect(
      () => const FontAssetService(
        ffmpegPath: null,
        sevenZipPath: null,
      ).indexSubtitleCharacters(<String>[missingPath]),
      throwsA(
        isA<Exception>().having(
          (Exception e) => e.toString(),
          'message',
          contains(missingPath),
        ),
      ),
    );
  });
}
