import 'package:path/path.dart' as p;

import '../models.dart';

({int width, int height})? parseResolution(String value) {
  final RegExpMatch? match = RegExp(
    r'^(\d+)\s*[xX]\s*(\d+)$',
  ).firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  final int? width = int.tryParse(match.group(1)!);
  final int? height = int.tryParse(match.group(2)!);
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  return (width: width, height: height);
}

Duration parseSeconds(String value) {
  final double seconds = double.tryParse(value) ?? 0;
  return Duration(milliseconds: (seconds * 1000).round());
}

Duration? parseTimestamp(String value) {
  final RegExp regex = RegExp(r'^(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?$');
  final RegExpMatch? match = regex.firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  return Duration(
    hours: int.parse(match.group(1)!),
    minutes: int.parse(match.group(2)!),
    seconds: int.parse(match.group(3)!),
    milliseconds: int.parse((match.group(4) ?? '0').padRight(3, '0')),
  );
}

String formatDuration(Duration duration) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}.${duration.inMilliseconds.remainder(1000).toString().padLeft(3, '0')}';
}

String renderCommand(String executable, List<String> arguments) {
  return <String>[executable, ...arguments]
      .map((String item) {
        if (item.contains(' ')) {
          return '"$item"';
        }
        return item;
      })
      .join(' ');
}

bool isFontFile(String path) {
  return <String>{
    '.ttf',
    '.otf',
    '.ttc',
  }.contains(p.extension(path).toLowerCase());
}

String mimeTypeForFont(String path) {
  switch (p.extension(path).toLowerCase()) {
    case '.otf':
      return 'application/vnd.ms-opentype';
    case '.ttc':
      return 'application/x-truetype-collection';
    default:
      return 'application/x-truetype-font';
  }
}

String mimeTypeForAttachment(MediaStreamEntry stream) {
  final String extension = stream.attachmentFileName == null
      ? '.${stream.codec}'
      : p.extension(stream.attachmentFileName!).toLowerCase();
  switch (extension) {
    case '.otf':
      return 'application/vnd.ms-opentype';
    case '.ttc':
      return 'application/x-truetype-collection';
    case '.ttf':
      return 'application/x-truetype-font';
    default:
      return 'application/octet-stream';
  }
}

String escapeMetadata(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('=', r'\=')
      .replaceAll(';', r'\;')
      .replaceAll('#', r'\#')
      .replaceAll('\n', r'\n');
}

String buildLanguageTag(MediaStreamEntry stream) {
  final String language = stream.language.trim();
  final String regionCode = stream.regionCode.trim();
  if (language.isEmpty) {
    return '';
  }
  if (regionCode.isEmpty) {
    return language;
  }
  return '${language.toLowerCase()}-${regionCode.toUpperCase()}';
}
