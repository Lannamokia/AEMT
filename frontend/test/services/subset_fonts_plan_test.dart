import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/models.dart';
import 'package:frontend/src/services/font_asset_service.dart';

void main() {
  test('Property 12: pyftsubset command construction', () {
    final List<FontSubsetStepPlan> steps = const FontAssetService(
      ffmpegPath: null,
      sevenZipPath: null,
    ).planSubsetFontSteps(
      const SubtitleCharIndex(<String, Set<int>>{
        'example font': <int>{0x41, 0x4E16},
      }),
      const <String, ResolvedFontFile>{
        'example font': ResolvedFontFile(
          path: 'C:/fonts/Example.ttf',
          fileName: 'Example.ttf',
          mimeType: 'font/ttf',
          trackIndex: 0,
          fsType: 0,
        ),
      },
      'C:/work',
      pyftsubsetPath: 'C:/bin/pyftsubset.exe',
      ttxPath: 'C:/bin/ttx.exe',
      aemtVersion: 'test',
      fontToolsVersion: '4.61.0',
    );

    expect(steps, hasLength(1));
    final FontSubsetStepPlan plan = steps.single;
    expect(plan.pyftsubsetArguments, contains('--unicodes-file=C:/work\\subsetted\\Example.unicodes.txt'));
    expect(plan.pyftsubsetArguments, contains('--output-file=C:/work\\subsetted\\Example.subset_tmp_.ttf'));
    expect(plan.pyftsubsetArguments, contains('--no-hinting'));
    expect(plan.pyftsubsetArguments, contains('--retain-gids'));
    expect(plan.pyftsubsetArguments, contains('--layout-features=vert,vrtr,vrt2,vkna'));
    expect(plan.pyftsubsetArguments, contains('--name-IDs=*'));
    expect(plan.pyftsubsetArguments, contains('--name-languages=*'));
    expect(plan.pyftsubsetArguments, contains('--drop-tables='));
    expect(plan.pyftsubsetArguments, contains('--no-prune-codepage-ranges'));
    expect(plan.pyftsubsetArguments, contains('--drop-tables+=BASE'));
    expect(plan.ttxDumpArguments, <String>[
      '-f',
      '-o',
      'C:/work\\subsetted\\Example.ttx',
      'C:/work\\subsetted\\Example.subset_tmp_.ttf',
    ]);
    expect(plan.ttxCompileArguments, <String>[
      '-f',
      '-b',
      'C:/work\\subsetted\\Example.ttx',
    ]);
    expect(plan.outputFont.fileName, 'Example.ttf');
    expect(plan.outputFont.mimeType, 'font/ttf');
  });

  test('fonttools compatibility flags follow version thresholds', () {
    expect(fontToolsCompatibilityFlags('4.44.0'), isEmpty);
    expect(fontToolsCompatibilityFlags('4.44.1'), contains('--no-prune-codepage-ranges'));
    expect(fontToolsCompatibilityFlags('4.60.1'), contains('--drop-tables+=BASE'));
    expect(fontToolsCompatibilityFlags(null), containsAll(<String>{
      '--no-prune-codepage-ranges',
      '--drop-tables+=BASE',
    }));
  });

  test('Property 14: empty codepoint set still builds a full subset plan', () {
    final List<FontSubsetStepPlan> steps = const FontAssetService(
      ffmpegPath: null,
      sevenZipPath: null,
    ).planSubsetFontSteps(
      const SubtitleCharIndex(<String, Set<int>>{'empty': <int>{}}),
      const <String, ResolvedFontFile>{
        'empty': ResolvedFontFile(
          path: 'C:/fonts/Empty.otf',
          fileName: 'Empty.otf',
          mimeType: 'font/otf',
        ),
      },
      'C:/work',
      pyftsubsetPath: 'pyftsubset',
      ttxPath: 'ttx',
      aemtVersion: 'test',
      fontToolsVersion: null,
    );

    expect(steps.single.codepoints, isEmpty);
    expect(steps.single.pyftsubsetArguments, contains('--unicodes-file=C:/work\\subsetted\\Empty.unicodes.txt'));
    expect(steps.single.outputFont.path, 'C:/work\\subsetted\\Empty.subset.otf');
  });

  test('Property 22: license sidecar inputs and fsType warning are preserved', () {
    final List<FontSubsetStepPlan> steps = const FontAssetService(
      ffmpegPath: null,
      sevenZipPath: null,
    ).planSubsetFontSteps(
      const SubtitleCharIndex(<String, Set<int>>{
        'restricted': <int>{0x41},
      }),
      const <String, ResolvedFontFile>{
        'restricted': ResolvedFontFile(
          path: 'C:/fonts/Restricted.ttf',
          fileName: 'Restricted.ttf',
          mimeType: 'font/ttf',
          familyNames: <String>{'Restricted'},
          fsType: 0x0002,
          licenseDescription: 'License text',
        ),
      },
      'C:/work',
      pyftsubsetPath: 'pyftsubset',
      ttxPath: 'ttx',
      aemtVersion: 'test',
      fontToolsVersion: null,
    );

    expect(steps.single.fsTypeRestricted, isTrue);
    expect(steps.single.originalFont.licenseDescription, 'License text');
  });
}
