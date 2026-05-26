import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/models.dart';
import 'package:frontend/src/services/media_parser.dart';

void main() {
  test('ffprobe color metadata populates primaryVideo', () {
    final MediaInfo info = parseMediaInfo('C:/video.mkv', <String, dynamic>{
      'format': <String, dynamic>{'duration': '10'},
      'streams': <dynamic>[
        <String, dynamic>{
          'index': 0,
          'codec_type': 'video',
          'codec_name': 'hevc',
          'width': 1920,
          'height': 1080,
          'avg_frame_rate': '24000/1001',
          'color_space': 'bt2020nc',
          'color_primaries': 'bt2020',
          'color_transfer': 'smpte2084',
          'color_range': 'tv',
          'bits_per_raw_sample': '10',
          'side_data_list': <dynamic>[
            <String, dynamic>{
              'side_data_type': 'Mastering display metadata',
              'red_x': '34000/50000',
            },
            <String, dynamic>{
              'side_data_type': 'Content light level metadata',
              'max_content': 0,
              'max_average': 0,
            },
          ],
        },
      ],
    });

    expect(info.primaryVideo, isNotNull);
    expect(info.primaryVideo!.colorSpace, 'bt2020nc');
    expect(info.primaryVideo!.colorPrimaries, 'bt2020');
    expect(info.primaryVideo!.colorTransfer, 'smpte2084');
    expect(info.primaryVideo!.colorRange, 'tv');
    expect(info.primaryVideo!.bitsPerRawSample, 10);
    expect(info.primaryVideo!.maxCll, 0);
    expect(info.primaryVideo!.maxFall, 0);
    expect(info.primaryVideo!.dolbyVision, isFalse);
    expect(detectSourceColorClass(info.primaryVideo!), SourceColorClass.hdrPq);
  });

  test('ffprobe DOVI side data wins color classification', () {
    final MediaInfo info = parseMediaInfo('C:/video.mkv', <String, dynamic>{
      'format': <String, dynamic>{'duration': '10'},
      'streams': <dynamic>[
        <String, dynamic>{
          'index': 0,
          'codec_type': 'video',
          'codec_name': 'hevc',
          'width': 1920,
          'height': 1080,
          'avg_frame_rate': '24/1',
          'side_data_list': <dynamic>[
            <String, dynamic>{
              'side_data_type': 'DOVI configuration record',
            },
          ],
        },
      ],
    });

    expect(info.primaryVideo!.dolbyVision, isTrue);
    expect(
      detectSourceColorClass(info.primaryVideo!),
      SourceColorClass.dolbyVision,
    );
  });
}
