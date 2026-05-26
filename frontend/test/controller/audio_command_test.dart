import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/controller.dart';
import 'package:frontend/src/models.dart';

const int _seed = 0xA0D10006;

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('Property 6: Audio command construction', () {
    final Random random = Random(_seed);
    final AemtController controller = AemtController(initializePlayer: false);
    controller.diagnostics = _diagnosticsWithAudioEncoders(const <String>{
      'aac',
      'libfdk_aac',
      'libopus',
      'flac',
      'ac3',
      'eac3',
    });
    final MediaStreamEntry sourceStream = _audioStream(
      channels: 6,
      channelLayout: '5.1(side)',
    );

    for (var i = 0; i < 240; i++) {
      final String encoder = _pick(random, const <String>[
        'copy',
        'aac',
        'libfdk_aac',
        'libopus',
        'flac',
        'ac3',
        'eac3',
      ]);
      final AudioStreamConfig config = _configFor(random, encoder);
      final List<String> args = controller.debugBuildAudioStreamArguments(
        i % 3,
        config,
        sourceStream: sourceStream,
      );
      final String suffix = ':${i % 3}';

      expect(args, containsAllInOrder(<String>['-c:a$suffix', encoder]));
      if (encoder == 'copy') {
        expect(args.where((String item) => item.startsWith('-af')), isEmpty);
        expect(args, hasLength(2), reason: 'seed=$_seed i=$i args=$args');
        continue;
      }
      if (config.mode == 'CBR' && encoder != 'flac') {
        expect(
          args,
          containsAllInOrder(<String>['-b:a$suffix', config.bitrate]),
        );
      }
      if (config.mode == 'VBR' && encoder == 'aac') {
        expect(
          args,
          containsAllInOrder(<String>[
            '-q:a$suffix',
            config.vbrQuality.toString(),
          ]),
        );
      }
      if (config.mode == 'VBR' && encoder == 'libfdk_aac') {
        expect(
          args,
          containsAllInOrder(<String>[
            '-vbr$suffix',
            config.vbrQuality.toString(),
          ]),
        );
      }
      if (config.mode == 'VBR' && encoder == 'libopus') {
        expect(
          args,
          containsAllInOrder(<String>['-vbr$suffix', config.vbrModeOpus]),
        );
      }
      if (config.sampleRate != '保持源') {
        expect(
          args,
          containsAllInOrder(<String>['-ar$suffix', config.sampleRate]),
        );
      }
      if (config.channelLayout == 'stereo' &&
          config.downmixAlgo == 'dpl2' &&
          encoder != 'copy') {
        final String filter = args[args.indexOf('-af$suffix') + 1];
        expect(filter, startsWith('pan=stereo'));
        expect(args, isNot(contains('-ac$suffix')));
      }
      if (config.loudnormEnabled ||
          config.drcEnabled ||
          config.customFilter.trim().isNotEmpty ||
          (config.channelLayout == 'stereo' && config.downmixAlgo == 'dpl2')) {
        final int filterIndex = args.indexOf('-af$suffix');
        expect(filterIndex, isNonNegative);
        final String filter = args[filterIndex + 1];
        final int loudnormIndex = filter.indexOf('loudnorm=');
        final int drcIndex = filter.indexOf('acompressor=');
        final int customIndex = filter.indexOf('volume=');
        if (loudnormIndex != -1 && drcIndex != -1) {
          expect(loudnormIndex < drcIndex, isTrue);
        }
        if (drcIndex != -1 && customIndex != -1) {
          expect(drcIndex < customIndex, isTrue);
        }
      }
    }

    controller.dispose();
  });

  test('legacy audio path requires all stream configs to be default', () {
    final AemtController controller = AemtController(initializePlayer: false);
    controller.debugSetMediaInfo(_mediaInfo());

    expect(
      controller.debugShouldUseLegacyAudioPath(
        _mediaInfo().streams
            .where((MediaStreamEntry stream) => stream.kind == StreamKind.audio)
            .toList(),
      ),
      isTrue,
    );

    controller.audioStreamConfigs['C:/input.mkv#1'] =
        const AudioStreamConfig.defaultAac().copyWith(bitrate: '192k');

    expect(
      controller.debugShouldUseLegacyAudioPath(
        _mediaInfo().streams
            .where((MediaStreamEntry stream) => stream.kind == StreamKind.audio)
            .toList(),
      ),
      isFalse,
    );

    controller.dispose();
  });

  test('audio validation rejects malformed bitrate and missing encoder', () {
    final AemtController controller = AemtController(initializePlayer: false);
    controller.diagnostics = _diagnosticsWithAudioEncoders(const <String>{
      'aac',
    });

    expect(
      () => controller.debugBuildAudioStreamArguments(
        0,
        const AudioStreamConfig.defaultAac().copyWith(bitrate: '192kbps'),
      ),
      throwsA(
        isA<Exception>().having(
          (Exception e) => e.toString(),
          'message',
          contains('码率格式应为如 192k'),
        ),
      ),
    );
    expect(
      () => controller.debugBuildAudioStreamArguments(
        0,
        const AudioStreamConfig.defaultAac().copyWith(encoder: 'libopus'),
      ),
      throwsA(
        isA<Exception>().having(
          (Exception e) => e.toString(),
          'message',
          contains('音频编码器 libopus 不可用'),
        ),
      ),
    );

    controller.dispose();
  });
}

AudioStreamConfig _configFor(Random random, String encoder) {
  return AudioStreamConfig(
    encoder: encoder,
    mode: _pick(random, const <String>['CBR', 'VBR']),
    bitrate: '${64 + random.nextInt(10) * 32}k',
    vbrQuality: 1 + random.nextInt(5),
    vbrModeOpus: _pick(random, const <String>['off', 'on', 'constrained']),
    sampleRate: _pick(random, const <String>['保持源', '44100', '48000']),
    channelLayout: _pick(random, const <String>[
      '保持源',
      'mono',
      'stereo',
      '5.1',
      '7.1',
    ]),
    downmixAlgo: _pick(random, const <String>['默认', 'dpl2']),
    profile: 'aac_low',
    compressionLevel: random.nextInt(11),
    loudnormEnabled: random.nextBool(),
    loudnormI: -16,
    loudnormTp: -1.5,
    loudnormLra: 11,
    drcEnabled: random.nextBool(),
    drcThreshold: -18,
    drcRatio: 3,
    drcAttack: 20,
    drcRelease: 250,
    customFilter: random.nextBool() ? 'volume=1.1' : '',
  );
}

RuntimeDiagnostics _diagnosticsWithAudioEncoders(Set<String> encoders) {
  return RuntimeDiagnostics(
    ffmpeg: const RuntimeToolInfo(
      name: 'ffmpeg',
      path: 'C:/fake/ffmpeg.exe',
      required: true,
    ),
    ffprobe: RuntimeDiagnostics.empty.ffprobe,
    mkvpropedit: RuntimeDiagnostics.empty.mkvpropedit,
    sevenZip: RuntimeDiagnostics.empty.sevenZip,
    hwaccels: const <String>[],
    videoEncoders: const <String>{},
    audioEncoders: encoders,
  );
}

MediaInfo _mediaInfo() {
  return MediaInfo(
    inputPath: 'C:/input.mkv',
    displayName: 'input.mkv',
    duration: const Duration(minutes: 1),
    width: 1920,
    height: 1080,
    fps: 23.976,
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
      _audioStream(),
    ],
    chapters: const <ChapterEntry>[],
  );
}

MediaStreamEntry _audioStream({
  int channels = 2,
  String channelLayout = 'stereo',
}) {
  return MediaStreamEntry(
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
    channels: channels,
    channelLayout: channelLayout,
  );
}

T _pick<T>(Random random, List<T> values) {
  return values[random.nextInt(values.length)];
}
