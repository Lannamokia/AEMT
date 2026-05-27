import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/services/runtime_service.dart';

void main() {
  test('runtime parsers detect zscale and supported audio encoders', () {
    expect(
      RuntimeService.parseHasZscaleForTesting(const <String>[
        ' T.C zscale            V->V       Apply resizing, colorspace and bit depth conversion.',
      ]),
      isTrue,
    );
    expect(
      RuntimeService.parseHasZscaleForTesting(const <String>[
        ' ... scale             V->V       Scale the input video size.',
      ]),
      isFalse,
    );
    expect(
      RuntimeService.parseAudioEncodersForTesting(const <String>[
        ' A..... aac                  AAC (Advanced Audio Coding)',
        ' A..... libopus              libopus Opus',
        ' A..... flac                 FLAC',
        ' A..... eac3                 ATSC A/52 E-AC-3',
        ' V..... libx264              H.264',
      ]),
      containsAll(<String>{'aac', 'libopus', 'flac', 'eac3'}),
    );
  });
}
