import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/controller.dart';
import 'package:frontend/src/models.dart';

const int _seed = 0x71DE0007;

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('Property 7: Video rate-control command construction', () {
    final Random random = Random(_seed);
    final AemtController controller = AemtController(initializePlayer: false);

    for (var i = 0; i < 240; i++) {
      final String encoder = _pick(random, kSupportedRcModes.keys.toList());
      final String mode = _pick(random, kSupportedRcModes[encoder]!);
      final VideoEncodingConfig config =
          VideoEncodingConfig.defaultsFor(encoder).copyWith(
            userOverridden: true,
            mode: mode,
            crf: random.nextInt(52),
            bitrate: '${1 + random.nextInt(12)}M',
            maxrate: '${2 + random.nextInt(16)}M',
            bufsize: '${4 + random.nextInt(32)}M',
            qpI: random.nextInt(52),
            qpP: random.nextInt(52),
            qpB: random.nextInt(52),
          );

      final List<String> args = controller.debugBuildVideoRateControlArguments(
        encoder,
        encoder.contains('265') || encoder.contains('hevc') ? 'hevc' : 'avc',
        config,
      );

      if (mode == 'CRF') {
        expect(
          args,
          containsAllInOrder(<String>['-crf', config.crf.toString()]),
        );
        expect(args, isNot(contains('-b:v')));
        expect(
          args,
          containsAllInOrder(<String>[
            '-maxrate',
            config.maxrate,
            '-bufsize',
            config.bufsize,
          ]),
        );
      } else if (mode == 'CBR') {
        expect(
          args,
          containsAllInOrder(<String>[
            '-b:v',
            config.bitrate,
            '-maxrate',
            config.maxrate,
            '-minrate',
            config.bitrate,
            '-bufsize',
            config.bufsize,
          ]),
        );
        _expectRateSwitch(args, encoder, cbr: true);
      } else if (mode == 'VBR') {
        expect(args, containsAllInOrder(<String>['-b:v', config.bitrate]));
        expect(
          args,
          containsAllInOrder(<String>[
            '-maxrate',
            config.maxrate,
            '-bufsize',
            config.bufsize,
          ]),
        );
        _expectRateSwitch(args, encoder, cbr: false);
      } else if (mode == 'CQP') {
        _expectCqp(args, encoder, config);
      }
    }

    controller.dispose();
  });

  test('default video config uses advanced encoder settings', () {
    final AemtController controller = AemtController(initializePlayer: false);

    final List<String> args = controller.debugBuildVideoRateControlArguments(
      'libx264',
      'avc',
      VideoEncodingConfig.defaultsFor('libx264'),
    );

    expect(
      args,
      containsAllInOrder(<String>[
        '-crf',
        '23',
        '-maxrate',
        '3750k',
        '-bufsize',
        '7500k',
        '-preset',
        'slow',
      ]),
    );
    expect(args, isNot(contains('-b:v')));

    controller.dispose();
  });

  test('video rate-control validation rejects malformed input', () {
    final AemtController controller = AemtController(initializePlayer: false);

    expect(
      () => controller.debugBuildVideoRateControlArguments(
        'libx264',
        'avc',
        VideoEncodingConfig.defaultsFor(
          'libx264',
        ).copyWith(userOverridden: true, mode: 'CBR', bitrate: '8000kbps'),
      ),
      throwsA(
        isA<Exception>().having(
          (Exception e) => e.toString(),
          'message',
          contains('视频码率格式非法'),
        ),
      ),
    );
    expect(
      () => controller.debugBuildVideoRateControlArguments(
        'libx264',
        'avc',
        VideoEncodingConfig.defaultsFor(
          'libx264',
        ).copyWith(userOverridden: true, mode: 'CRF', crf: 52),
      ),
      throwsA(
        isA<Exception>().having(
          (Exception e) => e.toString(),
          'message',
          contains('crf 范围应为 0-51'),
        ),
      ),
    );
    expect(
      () => controller.debugBuildVideoRateControlArguments(
        'libx264',
        'avc',
        VideoEncodingConfig.defaultsFor(
          'libx264',
        ).copyWith(userOverridden: true, mode: 'CQP'),
      ),
      throwsA(
        isA<Exception>().having(
          (Exception e) => e.toString(),
          'message',
          contains('当前编码器 libx264 不支持模式 CQP'),
        ),
      ),
    );

    controller.dispose();
  });
}

void _expectRateSwitch(List<String> args, String encoder, {required bool cbr}) {
  if (encoder.contains('nvenc')) {
    expect(args, containsAllInOrder(<String>['-rc', cbr ? 'cbr' : 'vbr']));
  } else if (encoder.contains('qsv')) {
    expect(args, containsAllInOrder(<String>['-rc:v', cbr ? 'cbr' : 'vbr']));
  } else if (encoder.contains('amf')) {
    expect(
      args,
      containsAllInOrder(<String>['-rc_mode', cbr ? 'cbr' : 'vbr_peak']),
    );
  } else {
    expect(args, isNot(contains('-rc')));
    expect(args, isNot(contains('-rc:v')));
    expect(args, isNot(contains('-rc_mode')));
  }
}

void _expectCqp(List<String> args, String encoder, VideoEncodingConfig config) {
  if (encoder.contains('nvenc')) {
    expect(
      args,
      containsAllInOrder(<String>[
        '-rc',
        'constqp',
        '-qp',
        config.qpI.toString(),
        '-init_qpP',
        config.qpP.toString(),
        '-init_qpB',
        config.qpB.toString(),
      ]),
    );
  } else if (encoder.contains('qsv')) {
    expect(
      args,
      containsAllInOrder(<String>[
        '-rc:v',
        'cqp',
        '-q',
        config.qpI.toString(),
        '-global_quality',
        config.qpI.toString(),
      ]),
    );
  } else if (encoder.contains('amf')) {
    expect(
      args,
      containsAllInOrder(<String>[
        '-rc_mode',
        'cqp',
        '-qp_i',
        config.qpI.toString(),
        '-qp_p',
        config.qpP.toString(),
        '-qp_b',
        config.qpB.toString(),
      ]),
    );
  }
}

T _pick<T>(Random random, List<T> values) {
  return values[random.nextInt(values.length)];
}
