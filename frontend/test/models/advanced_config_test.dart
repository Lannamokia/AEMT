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
        vbrModeOpus: _pick(random, const <String>[
          'off',
          'on',
          'constrained',
        ]),
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
        customFilter: random.nextBool() ? 'volume=${random.nextInt(3) + 1}' : '',
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
    expect(AudioStreamConfig.fromJson(<String, dynamic>{}),
        const AudioStreamConfig.defaultAac());
    expect(
      ToneMappingConfig.fromJson(<String, dynamic>{
        'tonemapMode': 'manual',
      }).tonemapMode,
      'on',
    );
    expect(
      () => AudioStreamConfig.fromJson(<String, dynamic>{'bitrate': true}),
      throwsA(isA<FormatException>().having(
        (FormatException e) => e.message,
        'message',
        contains('bitrate'),
      )),
    );
    expect(
      () => VideoEncodingConfig.fromJson(<String, dynamic>{'crf': '23'}),
      throwsA(isA<FormatException>().having(
        (FormatException e) => e.message,
        'message',
        contains('crf'),
      )),
    );
    expect(
      () => ToneMappingConfig.fromJson(<String, dynamic>{'peak': <String>[]}),
      throwsA(isA<FormatException>().having(
        (FormatException e) => e.message,
        'message',
        contains('peak'),
      )),
    );
  });
}

T _pick<T>(Random random, List<T> values) {
  return values[random.nextInt(values.length)];
}
