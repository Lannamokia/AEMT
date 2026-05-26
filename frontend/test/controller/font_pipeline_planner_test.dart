import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/controller.dart';
import 'package:frontend/src/models.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Property 11: Missing-font failure policy', () async {
    final Directory workDir = await Directory.systemTemp.createTemp(
      'aemt_missing_font_',
    );
    final String assPath = p.join(workDir.path, 'missing.ass');
    await File(assPath).writeAsString(_assText('Missing Font'));

    final AemtController strict = _controllerForPlan(assPath);
    strict.debugFontResolver =
        (List<String> importedFontSources, String workDir) async =>
            const <ResolvedFontFile>[];
    strict.debugAttachmentExtractor = (MediaInfo info, String workDir) async =>
        const <ResolvedFontFile>[];

    await expectLater(
      strict.debugBuildTaskPlan(_task()),
      throwsA(
        isA<Exception>().having(
          (Exception e) => e.toString(),
          'message',
          contains('未找到字体: missing font'),
        ),
      ),
    );
    strict.dispose();

    final AemtController permissive = _controllerForPlan(assPath)
      ..setContinueOnMissingFont(true);
    permissive.debugFontResolver =
        (List<String> importedFontSources, String workDir) async =>
            const <ResolvedFontFile>[];
    permissive.debugAttachmentExtractor =
        (MediaInfo info, String workDir) async => const <ResolvedFontFile>[];

    final TaskPlan plan = await permissive.debugBuildTaskPlan(_task());

    expect(plan.commandPreview, isNot(contains('MiSans')));
    expect(plan.commandPreview, isNot(contains('-attach')));
    expect(plan.initialLogLines, contains('WARN: 字体 missing font 缺失'));
    expect(
      plan.steps.where((CommandStep s) => s.fontSubsetStep != null),
      isEmpty,
    );
    permissive.dispose();
  });

  test('Property 15: Subset-font pipeline injection', () async {
    final Directory workDir = await Directory.systemTemp.createTemp(
      'aemt_subset_inject_',
    );
    final String assPath = p.join(workDir.path, 'styled.ass');
    await File(assPath).writeAsString(_assText('Example Font'));
    final AemtController controller = _controllerForPlan(assPath);
    controller.debugFontResolver =
        (List<String> importedFontSources, String workDir) async =>
            const <ResolvedFontFile>[_exampleFont];
    controller.debugAttachmentExtractor =
        (MediaInfo info, String workDir) async => const <ResolvedFontFile>[];

    final TaskPlan hardsub = await controller.debugBuildTaskPlan(_task());

    final Iterable<CommandStep> subsetSteps = hardsub.steps.where(
      (CommandStep step) => step.fontSubsetStep != null,
    );
    expect(subsetSteps, hasLength(1));
    final FontSubsetStepPlan subsetPlan = subsetSteps.single.fontSubsetStep!;
    expect(hardsub.commandPreview, contains('<workDir>/subsetted'));
    expect(hardsub.commandPreview, contains('<workDir>/subtitles/styled.ass'));
    expect(hardsub.commandPreview, isNot(contains('MiSans')));
    expect(
      hardsub.commandPreview,
      isNot(contains("subtitles='${assPath.replaceAll(r'\', '/')}'")),
    );
    expect(subsetPlan.outputFont.path, endsWith('Example.subset.ttf'));

    controller.diagnostics = _diagnostics(
      hasMkvpropedit: true,
      hasFontTools: true,
    );
    final TaskPlan mux = await controller.debugBuildTaskPlan(
      _task(profile: ExportProfile.muxMkv),
    );

    expect(mux.commandPreview, contains('-attach'));
    expect(mux.commandPreview, contains('Example.subset.ttf'));
    expect(mux.commandPreview, contains('filename=Example.ttf'));
    expect(mux.commandPreview, contains('<workDir>/subtitles/styled.ass'));
    expect(
      mux.commandPreview,
      isNot(contains("-i ${assPath.replaceAll(r'\', '/')}")),
    );
    controller.dispose();
  });

  test('Property 19: Diagnostic comment-line preview', () async {
    final Directory workDir = await Directory.systemTemp.createTemp(
      'aemt_diagnostics_',
    );
    final String srtPath = p.join(workDir.path, 'plain.srt');
    await File(srtPath).writeAsString('1\n00:00:00,000 --> 00:00:01,000\nHi\n');
    final AemtController controller = _controllerForPlan(
      srtPath,
      videoInfo: const VideoStreamInfo(colorTransfer: 'smpte2084'),
    );
    controller.debugFontResolver =
        (List<String> importedFontSources, String workDir) async =>
            const <ResolvedFontFile>[];
    controller.debugAttachmentExtractor =
        (MediaInfo info, String workDir) async => const <ResolvedFontFile>[];
    controller.setVideoEncodingMode('libx264', 'CRF');
    controller.setVideoEncodingField('libx264', crf: 20);
    controller.setAudioStreamConfig(
      'C:/input.mkv#1',
      const AudioStreamConfig.defaultAac().copyWith(encoder: 'copy'),
    );

    final TaskPlan plan = await controller.debugBuildTaskPlan(_task());

    expect(plan.commandPreview, contains('# audio:0 copy'));
    expect(plan.commandPreview, contains('# video libx264 rc=CRF'));
    expect(
      plan.commandPreview,
      contains('# tonemap source=hdrPq -> bt709 algo=hable'),
    );
    controller.dispose();
  });

  test('Property 5: Legacy command equivalence without golden files', () async {
    final Directory workDir = await Directory.systemTemp.createTemp(
      'aemt_legacy_',
    );
    final String srtPath = p.join(workDir.path, 'legacy.srt');
    await File(srtPath).writeAsString('1\n00:00:00,000 --> 00:00:01,000\nHi\n');
    final AemtController controller = _controllerForPlan(
      srtPath,
      videoInfo: const VideoStreamInfo(
        colorPrimaries: 'bt709',
        bitsPerRawSample: 8,
      ),
    );
    controller.diagnostics = _diagnostics(hasZscale: false);
    controller.debugFontResolver =
        (List<String> importedFontSources, String workDir) async =>
            const <ResolvedFontFile>[];
    controller.debugAttachmentExtractor =
        (MediaInfo info, String workDir) async => const <ResolvedFontFile>[];

    final TaskPlan plan = await controller.debugBuildTaskPlan(_task());

    expect(plan.commandPreview, contains('-c:a aac -b:a 320k -ar 48000'));
    expect(plan.commandPreview, contains('-b:v 2500k -maxrate 3750k'));
    expect(plan.commandPreview, isNot(contains('-crf')));
    expect(plan.commandPreview, isNot(contains('# video')));
    expect(plan.commandPreview, isNot(contains('# tonemap')));
    expect(plan.commandPreview, isNot(contains('zscale')));
    expect(plan.commandPreview, isNot(contains('tonemap=')));
    controller.dispose();
  });

  test('Property 20: Validation rejects malformed input', () async {
    final Directory workDir = await Directory.systemTemp.createTemp(
      'aemt_validation_',
    );
    final String srtPath = p.join(workDir.path, 'validation.srt');
    await File(srtPath).writeAsString('1\n00:00:00,000 --> 00:00:01,000\nHi\n');

    final AemtController audioBad = _controllerForPlan(srtPath);
    audioBad.debugFontResolver =
        (List<String> importedFontSources, String workDir) async =>
            const <ResolvedFontFile>[];
    audioBad.debugAttachmentExtractor =
        (MediaInfo info, String workDir) async => const <ResolvedFontFile>[];
    audioBad.setAudioStreamConfig(
      'C:/input.mkv#1',
      const AudioStreamConfig.defaultAac().copyWith(bitrate: '192kbps'),
    );
    await expectLater(
      audioBad.debugBuildTaskPlan(_task()),
      throwsA(
        isA<Exception>().having(
          (Exception e) => e.toString(),
          'message',
          contains('码率格式应为如 192k'),
        ),
      ),
    );
    audioBad.dispose();

    final AemtController videoBad = _controllerForPlan(srtPath);
    videoBad.debugFontResolver =
        (List<String> importedFontSources, String workDir) async =>
            const <ResolvedFontFile>[];
    videoBad.debugAttachmentExtractor =
        (MediaInfo info, String workDir) async => const <ResolvedFontFile>[];
    videoBad.setVideoEncodingMode('libx264', 'CBR');
    videoBad.setVideoEncodingField('libx264', bitrate: '8000kbps');
    await expectLater(
      videoBad.debugBuildTaskPlan(_task()),
      throwsA(
        isA<Exception>().having(
          (Exception e) => e.toString(),
          'message',
          contains('视频码率格式非法'),
        ),
      ),
    );
    videoBad.dispose();

    final AemtController toneBad = _controllerForPlan(
      srtPath,
      videoInfo: const VideoStreamInfo(colorTransfer: 'smpte2084'),
    );
    toneBad.debugFontResolver =
        (List<String> importedFontSources, String workDir) async =>
            const <ResolvedFontFile>[];
    toneBad.debugAttachmentExtractor = (MediaInfo info, String workDir) async =>
        const <ResolvedFontFile>[];
    toneBad.setToneMappingConfig(
      const ToneMappingConfig.defaultBt709().copyWith(peak: '0'),
    );
    await expectLater(
      toneBad.debugBuildTaskPlan(_task()),
      throwsA(
        isA<Exception>().having(
          (Exception e) => e.toString(),
          'message',
          contains('色调映射参数非法: peak'),
        ),
      ),
    );
    toneBad.dispose();
  });
}

const ResolvedFontFile _exampleFont = ResolvedFontFile(
  path: 'C:/fonts/Example.ttf',
  fileName: 'Example.ttf',
  mimeType: 'font/ttf',
  familyNames: <String>{'Example Font'},
  fullNames: <String>{'Example Font Regular'},
);

AemtController _controllerForPlan(
  String subtitlePath, {
  VideoStreamInfo videoInfo = const VideoStreamInfo(
    colorPrimaries: 'bt709',
    bitsPerRawSample: 8,
  ),
}) {
  final AemtController controller = AemtController(initializePlayer: false);
  controller
    ..diagnostics = _diagnostics(hasFontTools: true)
    ..setOutputDirectory('C:/out')
    ..setOutputResolution('1920x1080')
    ..setOutputFps('23.976');
  controller.debugSetMediaInfo(_mediaInfo(subtitlePath, videoInfo));
  controller.simplifiedBinding = controller.simplifiedBinding.copyWith(
    filePath: subtitlePath,
  );
  controller.debugSetMediaInfo(_mediaInfo(subtitlePath, videoInfo));
  return controller;
}

RuntimeDiagnostics _diagnostics({
  bool hasMkvpropedit = false,
  bool hasFontTools = false,
  bool hasZscale = true,
}) {
  return RuntimeDiagnostics(
    ffmpeg: const RuntimeToolInfo(
      name: 'ffmpeg',
      path: 'C:/bin/ffmpeg.exe',
      required: true,
    ),
    ffprobe: RuntimeDiagnostics.empty.ffprobe,
    mkvpropedit: RuntimeToolInfo(
      name: 'mkvpropedit',
      path: hasMkvpropedit ? 'C:/bin/mkvpropedit.exe' : null,
      required: false,
    ),
    sevenZip: RuntimeDiagnostics.empty.sevenZip,
    pyftsubset: RuntimeToolInfo(
      name: 'pyftsubset',
      path: hasFontTools ? 'C:/bin/pyftsubset.exe' : null,
      required: false,
    ),
    ttx: RuntimeToolInfo(
      name: 'ttx',
      path: hasFontTools ? 'C:/bin/ttx.exe' : null,
      required: false,
    ),
    fontToolsVersion: hasFontTools ? const Version(4, 61, 0) : null,
    hwaccels: const <String>[],
    videoEncoders: const <String>{},
    hasZscale: hasZscale,
    audioEncoders: const <String>{
      'aac',
      'libfdk_aac',
      'libopus',
      'flac',
      'ac3',
      'eac3',
    },
  );
}

MediaInfo _mediaInfo(String subtitlePath, VideoStreamInfo videoInfo) {
  return MediaInfo(
    inputPath: 'C:/input.mkv',
    displayName: 'input.mkv',
    duration: const Duration(minutes: 1),
    width: 1920,
    height: 1080,
    fps: 23.976,
    primaryVideo: videoInfo,
    streams: <MediaStreamEntry>[
      MediaStreamEntry(
        index: 0,
        kind: StreamKind.video,
        codec: 'h264',
        title: '',
        language: '',
        regionCode: '',
        enabled: true,
        isDefault: true,
        isForced: false,
        origin: StreamOrigin.input,
        sourceLabel: '',
        videoInfo: videoInfo,
      ),
      const MediaStreamEntry(
        index: 1,
        kind: StreamKind.audio,
        codec: 'aac',
        title: '',
        language: 'ja',
        regionCode: '',
        enabled: true,
        isDefault: true,
        isForced: false,
        origin: StreamOrigin.input,
        sourceLabel: '',
        channels: 2,
        channelLayout: 'stereo',
      ),
      MediaStreamEntry(
        index: 2,
        kind: StreamKind.subtitle,
        codec: p.extension(subtitlePath).replaceFirst('.', ''),
        title: 'JPSC',
        language: 'zh',
        regionCode: 'CN',
        enabled: true,
        isDefault: true,
        isForced: false,
        origin: StreamOrigin.externalSubtitle,
        sourceLabel: 'CHS 外挂字幕',
        externalPath: subtitlePath,
      ),
    ],
    chapters: const <ChapterEntry>[],
  );
}

ExportTask _task({ExportProfile profile = ExportProfile.hardsubMp4}) {
  return ExportTask(
    id: 'task',
    profile: profile,
    bindingKeys: const <String>['chs'],
    label: 'task',
    outputPath: profile == ExportProfile.hardsubMp4
        ? 'C:/out/out.mp4'
        : 'C:/out/out.mkv',
    status: TaskStatus.queued,
    progress: 0,
    currentStep: '',
    commandPreview: '',
    log: '',
  );
}

String _assText(String fontName) {
  return '''
[Script Info]
Title: test

[V4+ Styles]
Format: Name, Fontname, Fontsize
Style: Default, $fontName, 40

[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,0:00:00.00,0:00:01.00,Default,Hello
''';
}
