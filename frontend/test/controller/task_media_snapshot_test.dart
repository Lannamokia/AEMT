import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/controller.dart';
import 'package:frontend/src/models.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each task plans against the source media it was queued for', () async {
    final Directory workDir = await Directory.systemTemp.createTemp(
      'aemt_media_',
    );
    final String firstSubtitle = p.join(workDir.path, 'a.ass');
    final String secondSubtitle = p.join(workDir.path, 'b.ass');
    await File(firstSubtitle).writeAsString(_assText());
    await File(secondSubtitle).writeAsString(_assText());

    final AemtController controller = _planOnlyController();

    _loadMedia(controller, 'C:/in/a.mkv', firstSubtitle);
    await controller.enqueueTask(ExportProfile.hardsubMp4, <String>['chs']);

    _loadMedia(controller, 'C:/in/b.mkv', secondSubtitle);
    await controller.enqueueTask(ExportProfile.hardsubMp4, <String>['chs']);

    expect(controller.tasks, hasLength(2));
    final TaskPlan first = await controller.debugBuildTaskPlan(
      controller.tasks[0],
    );
    final TaskPlan second = await controller.debugBuildTaskPlan(
      controller.tasks[1],
    );

    expect(first.commandPreview, contains('-i C:/in/a.mkv'));
    expect(first.commandPreview, contains('a.ass'));
    expect(first.commandPreview, isNot(contains('b.ass')));
    expect(second.commandPreview, contains('-i C:/in/b.mkv'));
    expect(second.commandPreview, contains('b.ass'));
    expect(second.commandPreview, isNot(contains('a.ass')));
    controller.dispose();
  });

  test('queued tasks encode their own source videos', () async {
    final String? ffmpegPath = _repoTool('ffmpeg.exe');
    final String? ffprobePath = _repoTool('ffprobe.exe');
    if (ffmpegPath == null || ffprobePath == null) {
      markTestSkipped('未找到仓库内置 ffmpeg/ffprobe，跳过端到端压制验证。');
      return;
    }

    final Directory workDir = await Directory.systemTemp.createTemp(
      'aemt_task_media_',
    );
    final String firstMedia = p.join(workDir.path, 'a.mkv');
    final String secondMedia = p.join(workDir.path, 'b.mkv');
    await _renderSourceVideo(ffmpegPath, firstMedia, seconds: 1);
    await _renderSourceVideo(ffmpegPath, secondMedia, seconds: 3);
    final String firstSubtitle = p.join(workDir.path, 'a.ass');
    final String secondSubtitle = p.join(workDir.path, 'b.ass');
    await File(firstSubtitle).writeAsString(_assText());
    await File(secondSubtitle).writeAsString(_assText());

    final AemtController controller = _planOnlyController(
      diagnostics: _diagnostics(ffmpegPath: ffmpegPath),
      outputDirectory: p.join(workDir.path, 'out'),
      resolution: '320x240',
      fps: '25',
    );
    controller.setHardwareMode(HardwareMode.software);
    controller.debugFontResolver =
        (List<String> importedFontSources, String workDir) async =>
            const <ResolvedFontFile>[];
    controller.debugAttachmentExtractor =
        (MediaInfo info, String workDir) async => const <ResolvedFontFile>[];
    controller.debugSystemFontResolver = () async => const <ResolvedFontFile>[];

    _loadMedia(
      controller,
      firstMedia,
      firstSubtitle,
      duration: const Duration(seconds: 1),
    );
    await controller.enqueueTask(ExportProfile.hardsubMp4, <String>['chs']);
    _loadMedia(
      controller,
      secondMedia,
      secondSubtitle,
      duration: const Duration(seconds: 3),
    );
    await controller.enqueueTask(ExportProfile.hardsubMp4, <String>['chs']);

    await controller.runQueue();

    final ExportTask first = controller.tasks[0];
    final ExportTask second = controller.tasks[1];
    expect(first.status, TaskStatus.success, reason: first.log);
    expect(second.status, TaskStatus.success, reason: second.log);
    expect(
      await _durationSeconds(ffprobePath, first.outputPath),
      closeTo(1, 0.3),
      reason: '${first.outputPath} 应来自第一个视频',
    );
    expect(
      await _durationSeconds(ffprobePath, second.outputPath),
      closeTo(3, 0.3),
      reason: '${second.outputPath} 应来自第二个视频',
    );
    controller.dispose();
  });
}

AemtController _planOnlyController({
  RuntimeDiagnostics? diagnostics,
  String outputDirectory = 'C:/out',
  String resolution = '1920x1080',
  String fps = '23.976',
}) {
  return AemtController(initializePlayer: false)
    ..diagnostics = diagnostics ?? _diagnostics()
    ..setOutputDirectory(outputDirectory)
    ..setOutputResolution(resolution)
    ..setOutputFps(fps)
    ..setContinueOnMissingFont(true);
}

void _loadMedia(
  AemtController controller,
  String inputPath,
  String subtitle, {
  Duration duration = const Duration(minutes: 1),
}) {
  controller.debugResetSubtitleBindingsForNewMedia();
  controller.simplifiedBinding = controller.simplifiedBinding.copyWith(
    filePath: subtitle,
  );
  controller.debugSetMediaInfo(
    MediaInfo(
      inputPath: inputPath,
      displayName: p.basename(inputPath),
      duration: duration,
      width: 320,
      height: 240,
      fps: 25,
      primaryVideo: const VideoStreamInfo(
        colorPrimaries: 'bt709',
        bitsPerRawSample: 8,
      ),
      streams: <MediaStreamEntry>[
        const MediaStreamEntry(
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
          channels: 1,
          channelLayout: 'mono',
        ),
        MediaStreamEntry(
          index: 2,
          kind: StreamKind.subtitle,
          codec: 'ass',
          title: 'CHS',
          language: 'zh',
          regionCode: 'CN',
          enabled: true,
          isDefault: true,
          isForced: false,
          origin: StreamOrigin.externalSubtitle,
          sourceLabel: 'CHS 外挂字幕',
          externalPath: subtitle,
        ),
      ],
      chapters: const <ChapterEntry>[],
    ),
  );
}

RuntimeDiagnostics _diagnostics({String ffmpegPath = 'C:/bin/ffmpeg.exe'}) {
  return RuntimeDiagnostics(
    ffmpeg: RuntimeToolInfo(name: 'ffmpeg', path: ffmpegPath, required: true),
    ffprobe: RuntimeDiagnostics.empty.ffprobe,
    mkvpropedit: RuntimeDiagnostics.empty.mkvpropedit,
    sevenZip: RuntimeDiagnostics.empty.sevenZip,
    pyftsubset: RuntimeDiagnostics.empty.pyftsubset,
    ttx: RuntimeDiagnostics.empty.ttx,
    fontToolsVersion: null,
    hwaccels: const <String>[],
    videoEncoders: const <String>{},
    hasZscale: false,
    audioEncoders: const <String>{'aac'},
  );
}

String? _repoTool(String fileName) {
  final String path = p.normalize(
    p.join(Directory.current.path, '..', 'ffmpeg', fileName),
  );
  return File(path).existsSync() ? path : null;
}

Future<void> _renderSourceVideo(
  String ffmpegPath,
  String outputPath, {
  required int seconds,
}) async {
  final ProcessResult result = await Process.run(ffmpegPath, <String>[
    '-y',
    '-hide_banner',
    '-loglevel',
    'error',
    '-f',
    'lavfi',
    '-i',
    'testsrc=size=320x240:rate=25',
    '-f',
    'lavfi',
    '-i',
    'sine=frequency=440:sample_rate=48000',
    '-t',
    '$seconds',
    '-c:v',
    'libx264',
    '-pix_fmt',
    'yuv420p',
    '-preset',
    'ultrafast',
    '-c:a',
    'aac',
    '-b:a',
    '64k',
    '-shortest',
    outputPath,
  ]);
  expect(result.exitCode, 0, reason: '生成测试视频失败: ${result.stderr}');
}

Future<double> _durationSeconds(String ffprobePath, String path) async {
  final ProcessResult result = await Process.run(ffprobePath, <String>[
    '-v',
    'error',
    '-show_entries',
    'format=duration',
    '-of',
    'default=noprint_wrappers=1:nokey=1',
    path,
  ]);
  expect(result.exitCode, 0, reason: '读取 ${p.basename(path)} 时长失败');
  return double.parse(result.stdout.toString().trim());
}

String _assText() {
  return '''
[Script Info]
Title: test

[V4+ Styles]
Format: Name, Fontname, Fontsize
Style: Default, Example Font, 40

[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,0:00:00.00,0:00:01.00,Default,Hello
''';
}
