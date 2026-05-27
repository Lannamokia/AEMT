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
    'subtitle character index ignores non-rendering format controls',
    () async {
      final Directory root = await Directory.systemTemp.createTemp(
        'aemt_font_index_controls_',
      );
      final String assPath = '${root.path}/sample.ass';
      await File(assPath).writeAsString('''
[Script Info]

[V4+ Styles]
Format: Name, Fontname, Fontsize
Style: Default,Example Font,36

[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,0:00:00.00,0:00:01.00,Default,\u200Eおはよう
''');
      final SubtitleCharIndex index = await const FontAssetService(
        ffmpegPath: null,
        sevenZipPath: null,
      ).indexSubtitleCharacters(<String>[assPath]);

      expect(
        index.codepointsByFontname['example font'],
        isNot(contains(0x200E)),
      );
      expect(index.codepointsByFontname['example font'], contains(0x304A));
    },
  );

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

  test('system fonts are fallback candidates after imported fonts', () {
    final FontMatchResult result =
        const FontAssetService(ffmpegPath: null, sevenZipPath: null).matchFonts(
          const SubtitleCharIndex(<String, Set<int>>{
            'Example Font': <int>{0x41},
            'System Font': <int>{0x42},
          }),
          const <ResolvedFontFile>[
            ResolvedFontFile(
              path: 'C:/fonts/system-example.ttf',
              fileName: 'system-example.ttf',
              mimeType: 'font/ttf',
              source: FontSourceKind.system,
              importOrder: 0,
              familyNames: <String>{'Example Font'},
              maxpNumGlyphs: 10,
            ),
            ResolvedFontFile(
              path: 'C:/fonts/imported-example.ttf',
              fileName: 'imported-example.ttf',
              mimeType: 'font/ttf',
              source: FontSourceKind.imported,
              importOrder: 1,
              familyNames: <String>{'Example Font'},
              maxpNumGlyphs: 10,
            ),
            ResolvedFontFile(
              path: 'C:/fonts/system-only.ttf',
              fileName: 'system-only.ttf',
              mimeType: 'font/ttf',
              source: FontSourceKind.system,
              importOrder: 2,
              familyNames: <String>{'System Font'},
              maxpNumGlyphs: 10,
            ),
          ],
        );

    expect(result.missing, isEmpty);
    expect(result.matched['example font']!.fileName, 'imported-example.ttf');
    expect(result.matched['system font']!.fileName, 'system-only.ttf');
  });

  test('Source Han regional aliases match common ASS font names', () {
    final FontMatchResult result =
        const FontAssetService(ffmpegPath: null, sevenZipPath: null).matchFonts(
          const SubtitleCharIndex(<String, Set<int>>{
            'source han sans jp': <int>{0x41},
            'Source Han Sans SC Medium': <int>{0x4E00},
            'Source Han Sans CN': <int>{0x4E8C},
            'Source Han Sans TW': <int>{0x4E09},
            'Source Han Sans HK': <int>{0x56DB},
            'Source Han Sans KR': <int>{0x4E94},
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
            ResolvedFontFile(
              path: 'C:/fonts/SourceHanSansSC-Regular.otf',
              fileName: 'SourceHanSansSC-Regular.otf',
              mimeType: 'font/otf',
              familyNames: <String>{'Source Han Sans SC Regular'},
              fullNames: <String>{'Source Han Sans SC Regular'},
              weight: 400,
              maxpNumGlyphs: 100,
            ),
            ResolvedFontFile(
              path: 'C:/fonts/SourceHanSansTC-Normal.otf',
              fileName: 'SourceHanSansTC-Normal.otf',
              mimeType: 'font/otf',
              familyNames: <String>{'Source Han Sans TC Normal'},
              fullNames: <String>{'Source Han Sans TC Normal'},
              weight: 400,
              maxpNumGlyphs: 100,
            ),
            ResolvedFontFile(
              path: 'C:/fonts/SourceHanSansHC-Normal.otf',
              fileName: 'SourceHanSansHC-Normal.otf',
              mimeType: 'font/otf',
              familyNames: <String>{'Source Han Sans HC Normal'},
              fullNames: <String>{'Source Han Sans HC Normal'},
              weight: 400,
              maxpNumGlyphs: 100,
            ),
            ResolvedFontFile(
              path: 'C:/fonts/SourceHanSansK-Normal.otf',
              fileName: 'SourceHanSansK-Normal.otf',
              mimeType: 'font/otf',
              familyNames: <String>{'Source Han Sans K Normal'},
              fullNames: <String>{'Source Han Sans K Normal'},
              weight: 400,
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
    expect(
      result.matched['source han sans cn']!.fileName,
      'SourceHanSansSC-Regular.otf',
    );
    expect(
      result.matched['source han sans tw']!.fileName,
      'SourceHanSansTC-Normal.otf',
    );
    expect(
      result.matched['source han sans hk']!.fileName,
      'SourceHanSansHC-Normal.otf',
    );
    expect(
      result.matched['source han sans kr']!.fileName,
      'SourceHanSansK-Normal.otf',
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
