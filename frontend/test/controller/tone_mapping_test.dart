import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/controller.dart';
import 'package:frontend/src/models.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('Property 17: Tone mapping filter chain decision table', () {
    final AemtController controller = AemtController(initializePlayer: false);
    const ToneMappingConfig defaults = ToneMappingConfig.defaultBt709();

    final sdr = controller.debugBuildToneMappingFilter(
      const VideoStreamInfo(colorPrimaries: 'bt709', bitsPerRawSample: 8),
      defaults,
      hasZscale: true,
    );
    expect(sdr.filterChain, isEmpty);
    expect(sdr.metadataArgs, containsAll(<String>['bt709', 'tv']));

    final wide = controller.debugBuildToneMappingFilter(
      const VideoStreamInfo(colorPrimaries: 'bt2020', colorTransfer: 'bt709'),
      defaults,
      hasZscale: true,
    );
    expect(
      wide.filterChain,
      'zscale=p=bt709:t=bt709:m=bt709:r=tv,format=yuv420p',
    );
    expect(wide.tonemapAlgorithm, isNull);

    final hdr = controller.debugBuildToneMappingFilter(
      const VideoStreamInfo(
        colorPrimaries: 'bt2020',
        colorTransfer: 'smpte2084',
      ),
      defaults.copyWith(tonemapAlgo: 'mobius', peak: '400', desat: 1.25),
      hasZscale: true,
    );
    expect(hdr.filterChain, contains('zscale=t=linear:npl=100'));
    expect(
      hdr.filterChain,
      contains('tonemap=tonemap=mobius:desat=1.25:peak=400'),
    );
    expect(hdr.filterChain, contains('zscale=t=bt709:m=bt709:r=tv'));
    expect(hdr.tonemapAlgorithm, 'mobius');

    final dv = controller.debugBuildToneMappingFilter(
      const VideoStreamInfo(dolbyVision: true),
      defaults,
      hasZscale: true,
    );
    expect(dv.filterChain, contains('tonemap=tonemap=hable'));
    expect(dv.logLines, contains('WARN: 检测到 Dolby Vision，AEMT 仅按 PQ 基础层处理'));

    final unknown = controller.debugBuildToneMappingFilter(
      const VideoStreamInfo(colorPrimaries: 'film', colorTransfer: 'unknown'),
      defaults,
      hasZscale: true,
    );
    expect(unknown.filterChain, isEmpty);
    expect(unknown.logLines, contains('WARN: 无法识别源色彩特性，已按 BT.709 直通输出'));

    final forced = controller.debugBuildToneMappingFilter(
      const VideoStreamInfo(colorPrimaries: 'bt709', bitsPerRawSample: 8),
      defaults.copyWith(tonemapMode: 'on', peak: 'auto'),
      hasZscale: true,
    );
    expect(forced.filterChain, contains('tonemap=tonemap=hable:desat=0'));
    expect(forced.filterChain, isNot(contains(':peak=')));

    final manual = controller.debugBuildToneMappingFilter(
      const VideoStreamInfo(colorPrimaries: 'bt709', bitsPerRawSample: 8),
      defaults.copyWith(
        tonemapMode: 'off',
        outputPrimaries: 'bt2020',
        outputTransfer: 'source',
        outputRange: 'pc',
      ),
      hasZscale: true,
    );
    expect(manual.filterChain, 'zscale=p=bt2020:m=bt2020nc:r=pc');
    expect(
      manual.metadataArgs,
      containsAllInOrder(<String>[
        '-color_primaries',
        'bt2020',
        '-colorspace',
        'bt2020nc',
        '-color_range',
        'pc',
      ]),
    );
    expect(manual.metadataArgs, isNot(contains('-color_trc')));

    final passthrough = controller.debugBuildToneMappingFilter(
      const VideoStreamInfo(colorPrimaries: 'bt2020'),
      defaults.copyWith(
        tonemapMode: 'off',
        outputPrimaries: 'source',
        outputTransfer: 'source',
        outputRange: 'source',
      ),
      hasZscale: true,
    );
    expect(passthrough.filterChain, isEmpty);
    expect(passthrough.metadataArgs, isEmpty);

    final missingZscale = controller.debugBuildToneMappingFilter(
      const VideoStreamInfo(colorTransfer: 'smpte2084'),
      defaults,
      hasZscale: false,
    );
    expect(missingZscale.filterChain, isEmpty);
    expect(missingZscale.metadataArgs, isEmpty);
    expect(
      missingZscale.logLines,
      contains('WARN: ffmpeg 未启用 libzimg，色调映射已跳过'),
    );

    controller.dispose();
  });

  test('tone mapping validation rejects malformed input', () {
    final AemtController controller = AemtController(initializePlayer: false);
    const VideoStreamInfo hdr = VideoStreamInfo(colorTransfer: 'smpte2084');

    expect(
      () => controller.debugBuildToneMappingFilter(
        hdr,
        const ToneMappingConfig.defaultBt709().copyWith(desat: 2.1),
        hasZscale: true,
      ),
      throwsA(
        isA<Exception>().having(
          (Exception e) => e.toString(),
          'message',
          contains('色调映射参数非法: desat'),
        ),
      ),
    );
    expect(
      () => controller.debugBuildToneMappingFilter(
        hdr,
        const ToneMappingConfig.defaultBt709().copyWith(peak: '0'),
        hasZscale: true,
      ),
      throwsA(
        isA<Exception>().having(
          (Exception e) => e.toString(),
          'message',
          contains('色调映射参数非法: peak'),
        ),
      ),
    );

    controller.dispose();
  });
}
