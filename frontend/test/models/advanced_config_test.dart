import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/models.dart';

const int _seed = 0xA0010001;

void main() {
  test('Property 1: AudioStreamConfig JSON round-trip', () {
    final Random random = Random(_seed);
    for (var i = 0; i < 200; i++) {
      final AudioStreamConfig config = AudioStreamConfig(
        encoder: _pick(random, const <String>[
          'copy',
          'aac',
          'libfdk_aac',
          'libopus',
          'flac',
          'ac3',
          'eac3',
        ]),
        mode: _pick(random, const <String>['CBR', 'VBR']),
        bitrate: '${64 + random.nextInt(8) * 32}k',
        vbrQuality: 1 + random.nextInt(5),
        vbrModeOpus: _pick(random, const <String>['off', 'on', 'constrained']),
        sampleRate: _pick(random, const <String>[
          '保持源',
          '44100',
          '48000',
          '88200',
          '96000',
        ]),
        channelLayout: _pick(random, const <String>[
          '保持源',
          'mono',
          'stereo',
          '5.1',
          '7.1',
        ]),
        downmixAlgo: _pick(random, const <String>['默认', 'dpl2']),
        profile: _pick(random, const <String>[
          'aac_low',
          'aac_he',
          'aac_he_v2',
          'aac_ld',
          'aac_eld',
        ]),
        compressionLevel: random.nextInt(13),
        loudnormEnabled: random.nextBool(),
        loudnormI: -24 + random.nextInt(12).toDouble(),
        loudnormTp: -3 + random.nextDouble() * 2,
        loudnormLra: 5 + random.nextInt(12).toDouble(),
        drcEnabled: random.nextBool(),
        drcThreshold: -30 + random.nextInt(20).toDouble(),
        drcRatio: 1 + random.nextInt(8).toDouble(),
        drcAttack: 1 + random.nextInt(100).toDouble(),
        drcRelease: 50 + random.nextInt(500).toDouble(),
        customFilter: random.nextBool()
            ? 'volume=${random.nextInt(3) + 1}'
            : '',
      );
      expect(
        AudioStreamConfig.fromJson(config.toJson()),
        config,
        reason: 'seed=$_seed i=$i config=${config.toJson()}',
      );
    }
  });

  test('Property 2: VideoEncodingConfig JSON round-trip', () {
    final Random random = Random(_seed ^ 0x02000000);
    for (var i = 0; i < 200; i++) {
      final String encoder = _pick(random, kSupportedRcModes.keys.toList());
      final VideoEncodingConfig config = VideoEncodingConfig(
        mode: _pick(random, kSupportedRcModes[encoder]!),
        userOverridden: random.nextBool(),
        crf: random.nextInt(52),
        bitrate: '${1 + random.nextInt(20)}M',
        maxrate: '${1 + random.nextInt(24)}M',
        minrate: '${1 + random.nextInt(12)}M',
        bufsize: '${2 + random.nextInt(48)}M',
        qpI: random.nextInt(52),
        qpP: random.nextInt(52),
        qpB: random.nextInt(52),
      );
      expect(
        VideoEncodingConfig.fromJson(config.toJson(), encoderKey: encoder),
        config,
        reason: 'seed=$_seed i=$i encoder=$encoder config=${config.toJson()}',
      );
    }
  });

  test('Property 3: ToneMappingConfig JSON round-trip', () {
    final Random random = Random(_seed ^ 0x03000000);
    for (var i = 0; i < 200; i++) {
      final ToneMappingConfig config = ToneMappingConfig(
        outputPrimaries: _pick(random, const <String>[
          'bt709',
          'bt2020',
          'p3d65',
          'source',
        ]),
        outputTransfer: _pick(random, const <String>[
          'bt709',
          'smpte2084',
          'arib-std-b67',
          'source',
        ]),
        outputRange: _pick(random, const <String>['tv', 'pc', 'source']),
        tonemapMode: _pick(random, const <String>['auto', 'on', 'off']),
        tonemapAlgo: _pick(random, const <String>[
          'hable',
          'mobius',
          'reinhard',
          'bt2390',
          'linear',
        ]),
        peak: random.nextBool() ? 'auto' : '${100 + random.nextInt(1000)}',
        desat: random.nextDouble() * 2,
      );
      expect(
        ToneMappingConfig.fromJson(config.toJson()),
        config,
        reason: 'seed=$_seed i=$i config=${config.toJson()}',
      );
    }
  });

  test('Property 4: EncodingSettingsSnapshot v2 round-trip', () {
    final Random random = Random(_seed ^ 0x04000000);
    for (var i = 0; i < 100; i++) {
      final String inputPath = 'C:/media/source_${random.nextInt(8)}.mkv';
      final String encoder = _pick(random, kSupportedRcModes.keys.toList());
      final AudioStreamConfig audio = AudioStreamConfig(
        encoder: _pick(random, const <String>['aac', 'libopus', 'flac']),
        mode: _pick(random, const <String>['CBR', 'VBR']),
        bitrate: '${96 + random.nextInt(8) * 32}k',
        vbrQuality: 1 + random.nextInt(5),
        vbrModeOpus: 'on',
        sampleRate: _pick(random, const <String>['保持源', '48000', '96000']),
        channelLayout: _pick(random, const <String>['保持源', 'stereo']),
        downmixAlgo: '默认',
        profile: 'aac_low',
        compressionLevel: random.nextInt(10),
        loudnormEnabled: random.nextBool(),
        loudnormI: -16,
        loudnormTp: -1.5,
        loudnormLra: 11,
        drcEnabled: random.nextBool(),
        drcThreshold: -18,
        drcRatio: 3,
        drcAttack: 20,
        drcRelease: 250,
        customFilter: random.nextBool() ? 'volume=1.25' : '',
      );
      final EncodingSettingsSnapshot snapshot = EncodingSettingsSnapshot(
        compressionMode: _pick(random, CompressionMode.values),
        hardwareMode: _pick(random, HardwareMode.values),
        outputFileNameOverride: 'out_$i',
        releaseGroup: 'RG',
        titleOverride: 'Title $i',
        seasonNumber: 'S${random.nextInt(4) + 1}',
        episodeNumber: '${random.nextInt(24) + 1}',
        sourceLabel: 'WEB',
        episodicNamingTemplate: '{title}.{ext}',
        outputResolution: '1920x1080',
        outputFps: '23.976',
        outputDirectory: 'C:/out',
        avcBitrate: '${2 + random.nextInt(6)}000k',
        avcMaxrate: '${3 + random.nextInt(8)}000k',
        hevcBitrate: '${1 + random.nextInt(5)}000k',
        hevcMaxrate: '${2 + random.nextInt(7)}000k',
        encoderTunings: <String, EncoderTuningSelection>{
          encoder: const EncoderTuningSelection(preset: 'slow', tune: '默认'),
        },
        audioStreamConfigs: <String, AudioStreamConfig>{
          '$inputPath#${random.nextInt(3)}': audio,
        },
        audioDefaultProfile: audio.copyWith(bitrate: '256k'),
        videoEncodingConfigs: <String, VideoEncodingConfig>{
          encoder: VideoEncodingConfig.defaultsFor(encoder).copyWith(
            userOverridden: true,
            mode: _pick(random, kSupportedRcModes[encoder]!),
            crf: random.nextInt(52),
          ),
        },
        toneMappingConfig: ToneMappingConfig(
          outputPrimaries: 'bt709',
          outputTransfer: 'bt709',
          outputRange: 'tv',
          tonemapMode: _pick(random, const <String>['auto', 'on', 'off']),
          tonemapAlgo: 'hable',
          peak: random.nextBool() ? 'auto' : '${100 + random.nextInt(900)}',
          desat: random.nextDouble() * 2,
        ),
        continueOnMissingFont: random.nextBool(),
        fontSubsettingEnabled: random.nextBool(),
        sourceHanEllipsisFix: random.nextBool(),
      );
      final EncodingSettingsSnapshot decoded =
          EncodingSettingsSnapshot.fromJson(snapshot.toJson());
      expect(decoded.compressionMode, snapshot.compressionMode);
      expect(decoded.hardwareMode, snapshot.hardwareMode);
      expect(decoded.outputFileNameOverride, snapshot.outputFileNameOverride);
      expect(decoded.encoderTunings.keys, snapshot.encoderTunings.keys);
      for (final String key in snapshot.encoderTunings.keys) {
        expect(
          decoded.encoderTunings[key]!.preset,
          snapshot.encoderTunings[key]!.preset,
        );
        expect(
          decoded.encoderTunings[key]!.tune,
          snapshot.encoderTunings[key]!.tune,
        );
      }
      expect(decoded.audioStreamConfigs, snapshot.audioStreamConfigs);
      expect(decoded.audioDefaultProfile, snapshot.audioDefaultProfile);
      expect(decoded.videoEncodingConfigs, snapshot.videoEncodingConfigs);
      expect(decoded.toneMappingConfig, snapshot.toneMappingConfig);
      expect(decoded.continueOnMissingFont, snapshot.continueOnMissingFont);
      expect(decoded.fontSubsettingEnabled, snapshot.fontSubsettingEnabled);
      expect(decoded.sourceHanEllipsisFix, snapshot.sourceHanEllipsisFix);
    }
  });

  test('Property 16: Source color classification is total and pure', () {
    final Random random = Random(_seed ^ 0x16000000);
    for (var i = 0; i < 300; i++) {
      final VideoStreamInfo info = VideoStreamInfo(
        colorPrimaries: _pick(random, const <String>[
          'bt709',
          'bt2020',
          'smpte432',
          'smpte431',
          'unknown',
          'undefined',
        ]),
        colorTransfer: _pick(random, const <String>[
          'bt709',
          'smpte2084',
          'arib-std-b67',
          'unknown',
        ]),
        bitsPerRawSample: random.nextInt(16),
        dolbyVision: random.nextBool() && i % 7 == 0,
      );
      final VideoStreamInfo copy = VideoStreamInfo.fromJson(info.toJson());
      expect(
        detectSourceColorClass(info),
        detectSourceColorClass(copy),
        reason: 'seed=$_seed i=$i info=${info.toJson()}',
      );
      expect(info, copy, reason: 'detectSourceColorClass mutated input');
    }
  });

  test('fromJson defaults, legacy tone mode, and type errors', () {
    expect(
      AudioStreamConfig.fromJson(<String, dynamic>{}),
      const AudioStreamConfig.defaultAac(),
    );
    expect(
      ToneMappingConfig.fromJson(<String, dynamic>{
        'tonemapMode': 'manual',
      }).tonemapMode,
      'on',
    );
    expect(
      () => AudioStreamConfig.fromJson(<String, dynamic>{'bitrate': true}),
      throwsA(
        isA<FormatException>().having(
          (FormatException e) => e.message,
          'message',
          contains('bitrate'),
        ),
      ),
    );
    expect(
      () => VideoEncodingConfig.fromJson(<String, dynamic>{'crf': '23'}),
      throwsA(
        isA<FormatException>().having(
          (FormatException e) => e.message,
          'message',
          contains('crf'),
        ),
      ),
    );
    expect(
      () => ToneMappingConfig.fromJson(<String, dynamic>{'peak': <String>[]}),
      throwsA(
        isA<FormatException>().having(
          (FormatException e) => e.message,
          'message',
          contains('peak'),
        ),
      ),
    );
    expect(
      () => EncodingSettingsSnapshot.fromJson(<String, dynamic>{
        'type': 'aemt.encoding-settings',
        'version': 3,
      }),
      throwsA(
        isA<FormatException>().having(
          (FormatException e) => e.message,
          'message',
          '不支持的编码参数配置版本: 3',
        ),
      ),
    );
  });
}

T _pick<T>(Random random, List<T> values) {
  return values[random.nextInt(values.length)];
}
