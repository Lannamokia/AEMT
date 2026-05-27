import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/controller.dart';
import 'package:frontend/src/models.dart';

const int _seed = 0xC0117001;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('v1 import uses advanced-setting defaults and status message', () {
    final AemtController controller = AemtController(initializePlayer: false);

    final EncodingSettingsSnapshot snapshot =
        EncodingSettingsSnapshot.fromJson(<String, dynamic>{
          'type': 'aemt.encoding-settings',
          'version': 1,
          'compressionMode': 'episodic',
          'hardwareMode': 'software',
          'outputResolution': '1280x720',
        });
    controller.debugApplyEncodingSettingsSnapshot(snapshot);

    expect(controller.compressionMode, CompressionMode.episodic);
    expect(controller.hardwareMode, HardwareMode.software);
    expect(
      controller.audioDefaultProfile,
      const AudioStreamConfig.defaultAac(),
    );
    expect(controller.audioStreamConfigs, isEmpty);
    expect(
      controller.toneMappingConfig,
      const ToneMappingConfig.defaultBt709(),
    );
    expect(controller.continueOnMissingFont, isFalse);
    expect(controller.sourceHanEllipsisFix, isTrue);
    expect(controller.statusMessage, '已导入旧版本预设，音频高级参数、视频码控与色调映射沿用默认');

    controller.dispose();
  });

  test('v2 import maps audio configs by current stream index', () {
    final AemtController controller = AemtController(initializePlayer: false);
    controller.debugSetMediaInfo(
      _mediaInfo(
        inputPath: 'C:/current.mkv',
        primaryVideo: const VideoStreamInfo(),
      ),
    );
    final AudioStreamConfig importedAudio = const AudioStreamConfig.defaultAac()
        .copyWith(encoder: 'libopus', bitrate: '160k', sampleRate: '保持源');
    final AudioStreamConfig importedDefault =
        const AudioStreamConfig.defaultAac().copyWith(bitrate: '224k');
    final VideoEncodingConfig importedVideo = VideoEncodingConfig.defaultsFor(
      'libx265',
    ).copyWith(mode: 'CRF', crf: 19, userOverridden: true);
    final ToneMappingConfig importedTone =
        const ToneMappingConfig.defaultBt709().copyWith(tonemapMode: 'off');

    controller.debugApplyEncodingSettingsSnapshot(
      EncodingSettingsSnapshot(
        compressionMode: CompressionMode.generic,
        hardwareMode: HardwareMode.auto,
        outputFileNameOverride: '',
        releaseGroup: '',
        titleOverride: '',
        seasonNumber: '',
        episodeNumber: '',
        sourceLabel: '',
        episodicNamingTemplate: AemtController.defaultEpisodicNamingTemplate,
        outputResolution: '1920x1080',
        outputFps: '23.976',
        outputDirectory: 'C:/out',
        avcBitrate: '2500k',
        avcMaxrate: '3750k',
        hevcBitrate: '2000k',
        hevcMaxrate: '3000k',
        encoderTunings: const <String, EncoderTuningSelection>{},
        audioStreamConfigs: <String, AudioStreamConfig>{
          'C:/other.mkv#1': importedAudio,
        },
        audioDefaultProfile: importedDefault,
        videoEncodingConfigs: <String, VideoEncodingConfig>{
          'libx265': importedVideo,
        },
        toneMappingConfig: importedTone,
        continueOnMissingFont: true,
        sourceHanEllipsisFix: false,
      ),
    );

    expect(controller.audioDefaultProfile, importedDefault);
    expect(controller.audioStreamConfigs['C:/current.mkv#1'], importedAudio);
    expect(controller.videoEncodingConfigs['libx265'], importedVideo);
    expect(controller.toneMappingConfig, importedTone);
    expect(controller.continueOnMissingFont, isTrue);
    expect(controller.sourceHanEllipsisFix, isFalse);

    controller.dispose();
  });

  test('Property 8: Rate-control mode reconciliation', () {
    final Random random = Random(_seed ^ 0x08000000);
    final AemtController controller = AemtController(initializePlayer: false);

    for (var i = 0; i < 120; i++) {
      final String encoder = _pick(random, kSupportedRcModes.keys.toList());
      final String invalidMode = kSupportedRcModes[encoder]!.contains('CQP')
          ? 'CRF'
          : 'CQP';
      controller.videoEncodingConfigs[encoder] =
          VideoEncodingConfig.defaultsFor(
            encoder,
          ).copyWith(mode: invalidMode, userOverridden: true);

      controller.reconcileVideoEncodingMode(encoder);

      expect(
        controller.videoEncodingConfigs[encoder],
        VideoEncodingConfig.defaultsFor(encoder),
        reason: 'seed=$_seed i=$i encoder=$encoder invalidMode=$invalidMode',
      );
    }

    controller.dispose();
  });

  test('Property 18: First-time HDR notice is one-shot', () {
    final AemtController controller = AemtController(initializePlayer: false);
    final MediaInfo hdrInfo = _mediaInfo(
      inputPath: 'C:/hdr.mkv',
      primaryVideo: const VideoStreamInfo(
        colorTransfer: 'smpte2084',
        colorPrimaries: 'bt2020',
      ),
    );

    controller.debugSetMediaInfo(hdrInfo);
    controller.debugSetMediaInfo(hdrInfo.copyWith());

    const String notice = '已自动启用色调映射 (HDR → BT.709)，可在 色调映射 选项卡中查看与覆盖。';
    expect(_countOccurrences(controller.statusMessage ?? '', notice), 1);

    controller.dispose();
  });

  test('new media reset clears source-specific external subtitles', () {
    final AemtController controller = AemtController(initializePlayer: false);
    final MediaInfo oldMediaInfo = _mediaInfo(inputPath: 'C:/old.mkv');
    controller.debugSetMediaInfo(
      oldMediaInfo.copyWith(
        streams: <MediaStreamEntry>[
          ...oldMediaInfo.streams,
          const MediaStreamEntry(
            index: 2,
            kind: StreamKind.subtitle,
            codec: 'ass',
            title: 'Old external subtitle',
            language: 'zh',
            regionCode: 'CN',
            enabled: true,
            isDefault: true,
            isForced: false,
            origin: StreamOrigin.externalSubtitle,
            sourceLabel: 'CHS 外挂字幕',
            externalPath: 'C:/subs/old.chs.ass',
          ),
        ],
      ),
    );
    controller.simplifiedBinding = controller.simplifiedBinding.copyWith(
      filePath: 'C:/subs/old.chs.ass',
    );
    controller.traditionalBinding = controller.traditionalBinding.copyWith(
      filePath: 'C:/subs/old.cht.ass',
    );
    controller.customBindings.add(
      const SubtitleBinding(
        key: 'custom_1',
        label: '自定义字幕 1',
        languageCode: 'zh',
        regionCode: 'HK',
        trackName: 'Custom',
        filePath: 'C:/subs/old.custom.ass',
      ),
    );
    controller.selectedHardsubBindingKeys.add('custom_1');
    controller.selectedMuxBindingKeys.add('custom_1');
    controller.previewSubtitleKey = 'external:custom_1';

    controller.debugResetSubtitleBindingsForNewMedia();

    expect(controller.simplifiedBinding.filePath, isNull);
    expect(controller.traditionalBinding.filePath, isNull);
    expect(controller.customBindings, isEmpty);
    expect(controller.selectedHardsubBindingKeys, <String>{'chs', 'cht'});
    expect(controller.selectedMuxBindingKeys, <String>{'chs', 'cht'});
    expect(controller.previewSubtitleKey, 'off');
    expect(
      controller.mediaInfo!.streams.where(
        (MediaStreamEntry stream) =>
            stream.origin == StreamOrigin.externalSubtitle,
      ),
      isEmpty,
    );

    controller.dispose();
  });
}

MediaInfo _mediaInfo({
  required String inputPath,
  VideoStreamInfo primaryVideo = const VideoStreamInfo(),
}) {
  return MediaInfo(
    inputPath: inputPath,
    displayName: 'input.mkv',
    duration: const Duration(minutes: 1),
    width: 1920,
    height: 1080,
    fps: 23.976,
    streams: <MediaStreamEntry>[
      const MediaStreamEntry(
        index: 0,
        kind: StreamKind.video,
        codec: 'hevc',
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
      ),
    ],
    chapters: const <ChapterEntry>[],
    primaryVideo: primaryVideo,
  );
}

T _pick<T>(Random random, List<T> values) {
  return values[random.nextInt(values.length)];
}

int _countOccurrences(String haystack, String needle) {
  var count = 0;
  var index = 0;
  while (true) {
    index = haystack.indexOf(needle, index);
    if (index == -1) {
      return count;
    }
    count++;
    index += needle.length;
  }
}
