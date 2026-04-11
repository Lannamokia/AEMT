import 'package:path/path.dart' as p;

import '../models.dart';
import '../utils/export_utils.dart';

MediaInfo parseMediaInfo(String inputPath, Map<String, dynamic> json) {
  final List<dynamic> streamJson =
      json['streams'] as List<dynamic>? ?? <dynamic>[];
  final List<dynamic> chapterJson =
      json['chapters'] as List<dynamic>? ?? <dynamic>[];
  final Map<String, dynamic> formatJson =
      json['format'] as Map<String, dynamic>? ?? <String, dynamic>{};
  final List<MediaStreamEntry> streams = <MediaStreamEntry>[];
  var width = 0;
  var height = 0;
  var fps = 0.0;
  for (final dynamic raw in streamJson) {
    final Map<String, dynamic> item = raw as Map<String, dynamic>;
    final StreamKind kind = _parseStreamKind(
      (item['codec_type'] ?? '').toString(),
    );
    final Map<String, dynamic> tags =
        item['tags'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final Map<String, dynamic> disposition =
        item['disposition'] as Map<String, dynamic>? ?? <String, dynamic>{};
    if (kind == StreamKind.video && width == 0) {
      width = (item['width'] as num?)?.toInt() ?? 0;
      height = (item['height'] as num?)?.toInt() ?? 0;
      fps = _parseRate((item['avg_frame_rate'] ?? '0/1').toString());
    }
    streams.add(
      MediaStreamEntry(
        index: (item['index'] as num?)?.toInt() ?? 0,
        kind: kind,
        codec: (item['codec_name'] ?? '').toString(),
        title: (tags['title'] ?? '').toString(),
        language: (tags['language'] ?? '').toString(),
        regionCode: '',
        enabled: kind != StreamKind.subtitle,
        isDefault: (disposition['default'] as num?)?.toInt() == 1,
        isForced: (disposition['forced'] as num?)?.toInt() == 1,
        origin: StreamOrigin.input,
        sourceLabel: '源文件',
        attachmentFileName: (tags['filename'] ?? '').toString(),
        attachmentMimeType: (tags['mimetype'] ?? '').toString(),
      ),
    );
  }
  final List<ChapterEntry> chapters = chapterJson.map((dynamic raw) {
    final Map<String, dynamic> item = raw as Map<String, dynamic>;
    final Map<String, dynamic> tags =
        item['tags'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return ChapterEntry(
      title: (tags['title'] ?? 'Episode').toString(),
      start: parseSeconds((item['start_time'] ?? '0').toString()),
      end: parseSeconds((item['end_time'] ?? '0').toString()),
    );
  }).toList();
  return MediaInfo(
    inputPath: inputPath,
    displayName: p.basename(inputPath),
    duration: parseSeconds((formatJson['duration'] ?? '0').toString()),
    width: width,
    height: height,
    fps: fps,
    streams: streams,
    chapters: chapters,
  );
}

StreamKind _parseStreamKind(String codecType) {
  switch (codecType) {
    case 'video':
      return StreamKind.video;
    case 'audio':
      return StreamKind.audio;
    case 'subtitle':
      return StreamKind.subtitle;
    case 'attachment':
      return StreamKind.attachment;
    case 'data':
      return StreamKind.data;
    default:
      return StreamKind.unknown;
  }
}

double _parseRate(String value) {
  if (!value.contains('/')) {
    return double.tryParse(value) ?? 0;
  }
  final List<String> parts = value.split('/');
  final num numerator = num.tryParse(parts.first) ?? 0;
  final num denominator = num.tryParse(parts.last) ?? 1;
  if (denominator == 0) {
    return 0;
  }
  return numerator / denominator;
}
