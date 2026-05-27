import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/controller.dart';
import 'package:frontend/src/models.dart';
import 'package:frontend/src/widgets/encoding_panel.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1280, 1200);
    view.devicePixelRatio = 1;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });

  testWidgets('Audio_Settings_Tab shows empty-media placeholder', (
    WidgetTester tester,
  ) async {
    final AemtController controller = _controller();
    await _pumpPanel(tester, controller, null);

    await _tapTab(tester, '音频参数');

    expect(find.text('请先导入视频。'), findsWidgets);
    controller.dispose();
  });

  testWidgets('Audio_Settings_Tab disables controls for disabled streams', (
    WidgetTester tester,
  ) async {
    final AemtController controller = _controller();
    final MediaInfo media = _mediaInfo(audioEnabled: false);
    controller.debugSetMediaInfo(media);

    await _pumpPanel(tester, controller, media);
    await _tapTab(tester, '音频参数');

    expect(find.text('已禁用'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey<String>('audio-encoder-dropdown')).first,
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey<String>('audio-bitrate-field')).first,
          )
          .enabled,
      isFalse,
    );
    controller.dispose();
  });

  testWidgets('Audio_Settings_Tab commits CBR bitrate on blur', (
    WidgetTester tester,
  ) async {
    final AemtController controller = _controller();
    final MediaInfo media = _mediaInfo();
    controller.debugSetMediaInfo(media);

    await _pumpPanel(tester, controller, media);
    await _tapTab(tester, '音频参数');
    final Finder field = find
        .byKey(const ValueKey<String>('audio-bitrate-field'))
        .first;

    await tester.enterText(field, '256K');
    await tester.pump();
    expect(
      controller.audioStreamConfigs['C:/media/input.mkv#1']?.bitrate,
      '320k',
    );

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(
      controller.audioStreamConfigs['C:/media/input.mkv#1']?.bitrate,
      '256K',
    );
    controller.dispose();
  });

  testWidgets('Basic_Settings_Tab commits text fields on blur', (
    WidgetTester tester,
  ) async {
    final AemtController controller = _controller();
    final MediaInfo media = _mediaInfo();

    await _pumpPanel(tester, controller, media);
    final Finder field = find.widgetWithText(TextFormField, '输出分辨率').first;

    await tester.enterText(field, '1280x720');
    await tester.pump();
    expect(controller.outputResolution, isEmpty);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(controller.outputResolution, '1280x720');
    controller.dispose();
  });

  testWidgets('Audio_Settings_Tab switches encoder-specific fields', (
    WidgetTester tester,
  ) async {
    final AemtController controller = _controller();
    final MediaInfo media = _mediaInfo();
    controller.debugSetMediaInfo(media);

    await _pumpPanel(tester, controller, media);
    await _tapTab(tester, '音频参数');
    expect(find.text('profile'), findsOneWidget);
    expect(find.text('响度归一化'), findsOneWidget);

    controller.setAudioStreamConfig(
      'C:/media/input.mkv#1',
      const AudioStreamConfig.defaultAac().copyWith(encoder: 'copy'),
    );
    await tester.pumpAndSettle();
    expect(find.text('profile'), findsNothing);
    expect(find.text('响度归一化'), findsNothing);

    controller.setAudioStreamConfig(
      'C:/media/input.mkv#1',
      const AudioStreamConfig.defaultAac().copyWith(
        encoder: 'libopus',
        mode: 'VBR',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('VBR 模式'), findsOneWidget);
    expect(find.text('compression_level'), findsOneWidget);

    controller.setAudioStreamConfig(
      'C:/media/input.mkv#1',
      const AudioStreamConfig.defaultAac().copyWith(encoder: 'flac'),
    );
    await tester.pumpAndSettle();
    expect(find.text('码率'), findsNothing);
    expect(find.text('compression_level'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('Video rate-control UI renders mode fields and validation', (
    WidgetTester tester,
  ) async {
    final AemtController controller = _controller();
    final MediaInfo media = _mediaInfo();

    controller.setVideoEncodingMode('h264_nvenc', 'VBR');
    controller.setVideoEncodingField(
      'h264_nvenc',
      bitrate: 'bad',
      maxrate: '5M',
      minrate: '3000k',
      bufsize: '10000k',
    );
    await _pumpPanel(tester, controller, media);
    await _tapTab(tester, '高级编码参数');
    await tester.drag(find.byType(GridView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('video-rc-mode-h264_nvenc')),
      findsOneWidget,
    );
    expect(find.text('minrate'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey<String>('video-bitrate')).first,
      'bad',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(find.text('码率格式应为如 8000k 或 5M'), findsWidgets);
    controller.dispose();
  });

  testWidgets('Video rate-control text fields commit on blur', (
    WidgetTester tester,
  ) async {
    final AemtController controller = _controller();
    final MediaInfo media = _mediaInfo();
    controller.setVideoEncodingMode('h264_nvenc', 'VBR');
    controller.setVideoEncodingField('h264_nvenc', bitrate: '3000k');

    await _pumpPanel(tester, controller, media);
    await _tapTab(tester, '高级编码参数');
    await tester.drag(find.byType(GridView), const Offset(0, -700));
    await tester.pumpAndSettle();
    final Finder field = find
        .byKey(const ValueKey<String>('video-bitrate'))
        .first;

    await tester.enterText(field, '5000k');
    await tester.pump();
    expect(controller.videoEncodingConfigs['h264_nvenc']?.bitrate, '3000k');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(controller.videoEncodingConfigs['h264_nvenc']?.bitrate, '5000k');
    controller.dispose();
  });

  testWidgets('Font_Settings_Tab toggles values and snapshots them', (
    WidgetTester tester,
  ) async {
    final AemtController controller = _controller();
    final MediaInfo media = _mediaInfo();

    await _pumpPanel(tester, controller, media);
    await _tapTab(tester, '字体处理');

    expect(controller.continueOnMissingFont, isFalse);
    expect(controller.fontSubsettingEnabled, isTrue);
    expect(controller.sourceHanEllipsisFix, isTrue);

    await tester.tap(find.text('缺失字体时仍继续导出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('启用字体子集化'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('思源黑/宋字体省略号居中对齐'));
    await tester.pumpAndSettle();

    final EncodingSettingsSnapshot snapshot = controller
        .debugBuildEncodingSettingsSnapshot();
    expect(snapshot.continueOnMissingFont, isTrue);
    expect(snapshot.fontSubsettingEnabled, isFalse);
    expect(snapshot.sourceHanEllipsisFix, isFalse);
    controller.dispose();
  });

  testWidgets('Tone_Mapping_Tab shows HDR recommendation and manual override', (
    WidgetTester tester,
  ) async {
    final AemtController controller = _controller(hasZscale: true);
    final MediaInfo media = _mediaInfo(
      primaryVideo: const VideoStreamInfo(
        colorPrimaries: 'bt2020',
        colorTransfer: 'smpte2084',
        colorSpace: 'bt2020nc',
        bitsPerRawSample: 10,
      ),
    );

    await _pumpPanel(tester, controller, media);
    await _tapTab(tester, '色调映射');

    expect(find.text('HDR_PQ'), findsOneWidget);
    expect(find.text('推荐输出配置'), findsOneWidget);
    expect(find.textContaining('滤镜链:'), findsOneWidget);
    expect(find.text('输出色域'), findsNothing);

    await tester.tap(find.text('我自己来'));
    await tester.pumpAndSettle();

    expect(find.text('输出色域'), findsOneWidget);
    expect(find.text('tonemap 算法'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('Tone_Mapping_Tab shows SDR passthrough hint', (
    WidgetTester tester,
  ) async {
    final AemtController controller = _controller(hasZscale: true);
    final MediaInfo media = _mediaInfo(
      primaryVideo: const VideoStreamInfo(
        colorPrimaries: 'bt709',
        colorTransfer: 'bt709',
        colorSpace: 'bt709',
        bitsPerRawSample: 8,
      ),
    );

    await _pumpPanel(tester, controller, media);
    await _tapTab(tester, '色调映射');

    expect(find.text('SDR_BT709'), findsOneWidget);
    expect(find.text('源已是 BT.709 SDR，无需色调映射'), findsOneWidget);
    expect(find.text('推荐输出配置'), findsNothing);
    controller.dispose();
  });

  testWidgets('Tone_Mapping_Tab disables controls when zscale is missing', (
    WidgetTester tester,
  ) async {
    final AemtController controller = _controller(hasZscale: false);
    final MediaInfo media = _mediaInfo(
      primaryVideo: const VideoStreamInfo(
        colorPrimaries: 'bt2020',
        colorTransfer: 'smpte2084',
        colorSpace: 'bt2020nc',
        bitsPerRawSample: 10,
      ),
    );

    await _pumpPanel(tester, controller, media);
    await _tapTab(tester, '色调映射');
    await tester.tap(find.text('我自己来'));
    await tester.pumpAndSettle();

    expect(
      find.text('当前 ffmpeg 未启用 libzimg，色调映射不可用，导出将按源色彩直通'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.widgetWithText(DropdownButtonFormField<String>, 'tonemap 模式'),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey<String>('number-peak')).first,
          )
          .enabled,
      isFalse,
    );
    controller.dispose();
  });

  testWidgets('Tone_Mapping_Tab number fields commit on blur', (
    WidgetTester tester,
  ) async {
    final AemtController controller = _controller(hasZscale: true);
    final MediaInfo media = _mediaInfo(
      primaryVideo: const VideoStreamInfo(
        colorPrimaries: 'bt2020',
        colorTransfer: 'smpte2084',
        colorSpace: 'bt2020nc',
        bitsPerRawSample: 10,
      ),
    );

    await _pumpPanel(tester, controller, media);
    await _tapTab(tester, '色调映射');
    await tester.tap(find.text('我自己来'));
    await tester.pumpAndSettle();
    final Finder field = find
        .byKey(const ValueKey<String>('number-peak'))
        .first;

    await tester.enterText(field, '400');
    await tester.pump();
    expect(controller.toneMappingConfig.peak, 'auto');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(controller.toneMappingConfig.peak, '400');
    controller.dispose();
  });
}

AemtController _controller({bool hasZscale = true}) {
  final AemtController controller = AemtController(initializePlayer: false);
  controller.diagnostics = RuntimeDiagnostics(
    ffmpeg: const RuntimeToolInfo(
      name: 'ffmpeg',
      path: 'C:/bin/ffmpeg.exe',
      required: true,
    ),
    ffprobe: RuntimeDiagnostics.empty.ffprobe,
    mkvpropedit: RuntimeDiagnostics.empty.mkvpropedit,
    sevenZip: RuntimeDiagnostics.empty.sevenZip,
    hwaccels: const <String>[],
    videoEncoders: const <String>{'h264_nvenc', 'hevc_nvenc'},
    hasZscale: hasZscale,
    audioEncoders: const <String>{'aac', 'libopus', 'flac', 'ac3', 'eac3'},
  );
  return controller;
}

Future<void> _pumpPanel(
  WidgetTester tester,
  AemtController controller,
  MediaInfo? media,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AnimatedBuilder(
          animation: controller,
          builder: (BuildContext context, _) {
            return EncodingPanel(controller: controller, media: media);
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapTab(WidgetTester tester, String tabText) async {
  await tester.tap(find.text(tabText));
  await tester.pumpAndSettle();
}

MediaInfo _mediaInfo({
  bool audioEnabled = true,
  VideoStreamInfo primaryVideo = const VideoStreamInfo(
    colorPrimaries: 'bt709',
    colorTransfer: 'bt709',
    colorSpace: 'bt709',
    bitsPerRawSample: 8,
  ),
}) {
  return MediaInfo(
    inputPath: 'C:/media/input.mkv',
    displayName: 'input.mkv',
    duration: const Duration(minutes: 1),
    width: 1920,
    height: 1080,
    fps: 23.976,
    primaryVideo: primaryVideo,
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
        videoInfo: primaryVideo,
      ),
      MediaStreamEntry(
        index: 1,
        kind: StreamKind.audio,
        codec: 'aac',
        title: 'Main',
        language: 'ja',
        regionCode: '',
        enabled: audioEnabled,
        isDefault: true,
        isForced: false,
        origin: StreamOrigin.input,
        sourceLabel: '',
        channels: 6,
        channelLayout: '5.1',
      ),
    ],
    chapters: const <ChapterEntry>[],
  );
}
