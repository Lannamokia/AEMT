import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/models.dart';
import 'package:frontend/src/services/font_asset_service.dart';
import 'package:frontend/src/services/font_asset_service_internal/sfnt_name_reader.dart';
import 'package:path/path.dart' as p;

const int _seed = 0xF07A7001;

void main() {
  test('Property 13: Subsetting preserves required codepoints', () async {
    final _FontToolsFixture? fixture = await _discoverFixture();
    if (fixture == null) {
      markTestSkipped(_skipReason);
      return;
    }

    final Set<int> codepoints = <int>{
      0x09,
      0x0A,
      0x0D,
      0x200E,
      0x41,
      0x42,
      0x43,
      0x61,
      0x62,
      0x63,
    };
    final Set<int> renderingCodepoints = <int>{
      0x41,
      0x42,
      0x43,
      0x61,
      0x62,
      0x63,
    };
    final Directory workDir = await Directory.systemTemp.createTemp(
      'aemt_subset_round_trip_$_seed',
    );
    final SubsetResult result =
        await const FontAssetService(
          ffmpegPath: null,
          sevenZipPath: null,
        ).subsetFonts(
          SubtitleCharIndex(<String, Set<int>>{'fixture font': codepoints}),
          <String, ResolvedFontFile>{'fixture font': fixture.font},
          workDir.path,
          pyftsubsetPath: fixture.pyftsubsetPath,
          ttxPath: fixture.ttxPath,
          cancelSignal: const Stream<void>.empty(),
          aemtVersion: 'test',
          fontToolsVersion: fixture.fontToolsVersion,
        );

    expect(result.fonts, hasLength(1));
    expect(result.renameMap['fixture font'], matches(RegExp(r'^[A-Z0-9]{8}$')));
    final Set<int> cmap = (await readSfntFontFaces(
      result.fonts.single.path,
    )).expand((SfntFontFace face) => face.cmapCodepoints).toSet();
    expect(
      cmap,
      containsAll(renderingCodepoints),
      reason: 'seed=$_seed output=${result.fonts.single.path}',
    );
  });

  test(
    'Property 14: Empty codepoint set still yields a valid subset file',
    () async {
      final _FontToolsFixture? fixture = await _discoverFixture();
      if (fixture == null) {
        markTestSkipped(_skipReason);
        return;
      }

      final Directory workDir = await Directory.systemTemp.createTemp(
        'aemt_empty_subset_$_seed',
      );
      final SubsetResult result =
          await const FontAssetService(
            ffmpegPath: null,
            sevenZipPath: null,
          ).subsetFonts(
            const SubtitleCharIndex(<String, Set<int>>{
              'fixture font': <int>{},
            }),
            <String, ResolvedFontFile>{'fixture font': fixture.font},
            workDir.path,
            pyftsubsetPath: fixture.pyftsubsetPath,
            ttxPath: fixture.ttxPath,
            cancelSignal: const Stream<void>.empty(),
            aemtVersion: 'test',
            fontToolsVersion: fixture.fontToolsVersion,
            verifyAfterSubset: false,
          );

      expect(result.fonts, hasLength(1));
      expect(File(result.fonts.single.path).existsSync(), isTrue);
      expect(await readSfntFontFaces(result.fonts.single.path), isNotEmpty);
    },
  );

  test(
    'system font scan enriches font files from configured directories',
    () async {
      final String? fontPath = _findFixtureFont();
      if (fontPath == null) {
        markTestSkipped(_skipReason);
        return;
      }
      final Directory root = await Directory.systemTemp.createTemp(
        'aemt_system_font_scan_$_seed',
      );
      final String copiedFontPath = p.join(root.path, p.basename(fontPath));
      await File(fontPath).copy(copiedFontPath);
      await File(p.join(root.path, 'not-a-font.txt')).writeAsString('ignored');

      final List<ResolvedFontFile> fonts = await const FontAssetService(
        ffmpegPath: null,
        sevenZipPath: null,
      ).resolveSystemFontFiles(fontDirectories: <String>[root.path]);

      expect(fonts, isNotEmpty);
      expect(
        fonts.every(
          (ResolvedFontFile font) => font.source == FontSourceKind.system,
        ),
        isTrue,
      );
      expect(
        fonts.map((ResolvedFontFile font) => font.fileName),
        isNot(contains('not-a-font.txt')),
      );
      expect(
        fonts.expand((ResolvedFontFile font) => font.familyNames),
        isNotEmpty,
      );
    },
  );
}

const String _skipReason =
    '真实 fonttools 集成测试需要 pyftsubset、ttx 和可读 TTF 字体；设置 FONTTOOLS_BIN_DIR 或 PATH 后会自动运行。';

class _FontToolsFixture {
  const _FontToolsFixture({
    required this.pyftsubsetPath,
    required this.ttxPath,
    required this.font,
    required this.fontToolsVersion,
  });

  final String pyftsubsetPath;
  final String ttxPath;
  final ResolvedFontFile font;
  final String? fontToolsVersion;
}

Future<_FontToolsFixture?> _discoverFixture() async {
  final String? pyftsubsetPath = _findExecutable('pyftsubset');
  final String? ttxPath = _findExecutable('ttx');
  final String? fontPath = _findFixtureFont();
  if (pyftsubsetPath == null || ttxPath == null || fontPath == null) {
    return null;
  }
  return _FontToolsFixture(
    pyftsubsetPath: pyftsubsetPath,
    ttxPath: ttxPath,
    font: ResolvedFontFile(
      path: fontPath,
      fileName: p.basename(fontPath),
      mimeType: 'font/ttf',
      familyNames: const <String>{'fixture font'},
    ),
    fontToolsVersion: await _probeTtxVersion(ttxPath),
  );
}

String? _findExecutable(String baseName) {
  final List<String> names = Platform.isWindows
      ? <String>['$baseName.exe', baseName]
      : <String>[baseName];
  final String? fontToolsBinDir = Platform.environment['FONTTOOLS_BIN_DIR'];
  final List<String> dirs = <String>[
    if (fontToolsBinDir != null && fontToolsBinDir.trim().isNotEmpty)
      fontToolsBinDir,
    ...Platform.environment['PATH']?.split(Platform.isWindows ? ';' : ':') ??
        const <String>[],
  ];
  for (final String dir in dirs) {
    for (final String name in names) {
      final String path = p.join(dir, name);
      if (File(path).existsSync()) {
        return path;
      }
    }
  }
  return null;
}

String? _findFixtureFont() {
  final String? explicit = Platform.environment['AEMT_FONTTOOLS_TEST_FONT'];
  final List<String> candidates = <String>[
    if (explicit != null && explicit.trim().isNotEmpty) explicit,
    if (Platform.isWindows) r'C:\Windows\Fonts\arial.ttf',
    if (Platform.isWindows) r'C:\Windows\Fonts\segoeui.ttf',
    p.join(Directory.current.path, 'assets', 'fonts', 'MiSans-Regular.ttf'),
  ];
  for (final String candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

Future<String?> _probeTtxVersion(String ttxPath) async {
  final ProcessResult result = await Process.run(
    ttxPath,
    const <String>['--version'],
    stdoutEncoding: systemEncoding,
    stderrEncoding: systemEncoding,
  );
  final String text = '${result.stdout}\n${result.stderr}';
  return RegExp(r'\d+\.\d+\.\d+').firstMatch(text)?.group(0);
}
