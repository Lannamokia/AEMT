import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class AssRewriteResult {
  const AssRewriteResult({required this.outputPath, required this.changed});

  final String outputPath;
  final bool changed;
}

Future<AssRewriteResult> rewriteAssWithRenameMap({
  required String originalPath,
  required String outputPath,
  required Map<String, String> renameMap,
}) async {
  final Uint8List raw = await File(originalPath).readAsBytes();
  final String newline = _detectNewline(raw);
  final String text = _decodeSubtitleBytes(raw);
  final String rewritten = rewriteAssText(text, renameMap, newline: newline);
  await Directory(p.dirname(outputPath)).create(recursive: true);
  await File(
    outputPath,
  ).writeAsBytes(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(rewritten)]);
  return AssRewriteResult(outputPath: outputPath, changed: rewritten != text);
}

String rewriteAssText(
  String text,
  Map<String, String> renameMap, {
  required String newline,
}) {
  if (renameMap.isEmpty) {
    return text;
  }
  final List<String> lines = text.split(RegExp(r'\r\n|\n'));
  final List<String> output = <String>[];
  var section = '';
  List<String> format = <String>[];
  List<String> eventFormat = <String>[];
  var insertedComments = false;
  var changed = false;
  for (final String line in lines) {
    final String trimmed = line.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      section = trimmed.toLowerCase();
      format = <String>[];
      output.add(line);
      if (section == '[script info]' && !insertedComments) {
        for (final MapEntry<String, String> entry in renameMap.entries) {
          output.add('; Font Subset: ${entry.value} - ${entry.key}');
        }
        insertedComments = true;
      }
      continue;
    }
    if ((section == '[v4+ styles]' || section == '[v4 styles]') &&
        trimmed.toLowerCase().startsWith('format:')) {
      format = _parseFormat(line);
      output.add(line);
      continue;
    }
    if (section == '[events]' && trimmed.toLowerCase().startsWith('format:')) {
      eventFormat = _parseFormat(line);
      output.add(line);
      continue;
    }
    if ((section == '[v4+ styles]' || section == '[v4 styles]') &&
        trimmed.toLowerCase().startsWith('style:')) {
      final String rewritten = _rewriteStyleLine(line, format, renameMap);
      output.add(rewritten);
      changed = changed || rewritten != line;
      continue;
    }
    if (section == '[events]' &&
        trimmed.toLowerCase().startsWith('dialogue:')) {
      final String rewritten = _rewriteDialogueLine(
        line,
        eventFormat,
        renameMap,
      );
      output.add(rewritten);
      changed = changed || rewritten != line;
      continue;
    }
    output.add(line);
  }
  if (!insertedComments) {
    output.insertAll(0, <String>[
      '[Script Info]',
      for (final MapEntry<String, String> entry in renameMap.entries)
        '; Font Subset: ${entry.value} - ${entry.key}',
      '',
    ]);
    changed = true;
  }
  final String rewritten = output.join(newline);
  return changed ? rewritten : output.join(newline);
}

List<String> _parseFormat(String line) {
  final int colon = line.indexOf(':');
  if (colon == -1) {
    return <String>[];
  }
  return line
      .substring(colon + 1)
      .split(',')
      .map((String item) => item.trim().toLowerCase())
      .toList();
}

String _rewriteStyleLine(
  String line,
  List<String> format,
  Map<String, String> renameMap,
) {
  final int fontIndex = format.indexOf('fontname');
  if (fontIndex == -1) {
    return line;
  }
  final int colon = line.indexOf(':');
  if (colon == -1) {
    return line;
  }
  final List<String> fields = _splitAssCsv(line.substring(colon + 1));
  if (fontIndex >= fields.length) {
    return line;
  }
  fields[fontIndex] = _rewriteFontName(fields[fontIndex], renameMap);
  return '${line.substring(0, colon + 1)}${fields.join(',')}';
}

String _rewriteDialogueLine(
  String line,
  List<String> format,
  Map<String, String> renameMap,
) {
  final int colon = line.indexOf(':');
  if (colon == -1) {
    return line;
  }
  final int textIndex = format.indexOf('text');
  if (textIndex == -1) {
    return line;
  }
  final List<String> parts = _splitAssLine(line, format.length);
  if (textIndex >= parts.length) {
    return line;
  }
  parts[textIndex] = _stripUnicodeFormatControls(
    _rewriteOverrideBlocks(parts[textIndex], renameMap),
  );
  return '${line.substring(0, colon + 1)}${parts.join(',')}';
}

String _rewriteOverrideBlocks(String text, Map<String, String> renameMap) {
  final StringBuffer buffer = StringBuffer();
  var index = 0;
  while (index < text.length) {
    final int open = text.indexOf('{', index);
    if (open == -1) {
      buffer.write(text.substring(index));
      break;
    }
    final int close = text.indexOf('}', open + 1);
    if (close == -1) {
      buffer.write(text.substring(index));
      break;
    }
    buffer
      ..write(text.substring(index, open))
      ..write(_rewriteFontTags(text.substring(open, close + 1), renameMap));
    index = close + 1;
  }
  return buffer.toString();
}

String _rewriteFontTags(String block, Map<String, String> renameMap) {
  final List<String> keys = renameMap.keys.toList()
    ..sort((String a, String b) => b.length.compareTo(a.length));
  final StringBuffer buffer = StringBuffer();
  var index = 0;
  while (index < block.length) {
    final int tag = block.indexOf(r'\fn', index);
    if (tag == -1) {
      buffer.write(block.substring(index));
      break;
    }
    buffer
      ..write(block.substring(index, tag))
      ..write(r'\fn');
    var valueStart = tag + 3;
    var valueEnd = valueStart;
    while (valueEnd < block.length &&
        block[valueEnd] != r'\' &&
        block[valueEnd] != '}') {
      valueEnd++;
    }
    final String rawName = block.substring(valueStart, valueEnd);
    final String key = _normalizeFontName(rawName);
    final String? replacement = _lookupRename(key, renameMap, keys);
    if (replacement == null) {
      buffer.write(rawName);
    } else {
      buffer.write(
        rawName.trimLeft().startsWith('@') ? '@$replacement' : replacement,
      );
    }
    index = valueEnd;
  }
  return buffer.toString();
}

String _rewriteFontName(String value, Map<String, String> renameMap) {
  final String leftTrimmed = value.trimLeft();
  final bool vertical = leftTrimmed.startsWith('@');
  final String key = _normalizeFontName(value);
  final String? replacement = renameMap[key];
  if (replacement == null) {
    return value;
  }
  final int leadingWhitespace = value.length - leftTrimmed.length;
  return '${value.substring(0, leadingWhitespace)}${vertical ? '@' : ''}$replacement';
}

String? _lookupRename(
  String key,
  Map<String, String> renameMap,
  List<String> sortedKeys,
) {
  if (renameMap.containsKey(key)) {
    return renameMap[key];
  }
  for (final String candidate in sortedKeys) {
    if (key == candidate) {
      return renameMap[candidate];
    }
  }
  return null;
}

String _stripUnicodeFormatControls(String text) {
  final StringBuffer buffer = StringBuffer();
  for (final int codepoint in text.runes) {
    if (_isUnicodeFormatControl(codepoint)) {
      continue;
    }
    buffer.writeCharCode(codepoint);
  }
  return buffer.toString();
}

bool _isUnicodeFormatControl(int codepoint) {
  if (codepoint >= 0x200B && codepoint <= 0x200F) {
    return true;
  }
  if (codepoint >= 0x202A && codepoint <= 0x202E) {
    return true;
  }
  if (codepoint >= 0x2060 && codepoint <= 0x206F) {
    return true;
  }
  return codepoint >= 0xFE00 && codepoint <= 0xFE0F;
}

String _normalizeFontName(String value) {
  final String trimmed = value.trim();
  return (trimmed.startsWith('@') ? trimmed.substring(1) : trimmed)
      .trim()
      .toLowerCase();
}

List<String> _splitAssCsv(String text) {
  return text.split(',');
}

List<String> _splitAssLine(String line, int columnCount) {
  final int colon = line.indexOf(':');
  if (colon == -1) {
    return <String>[];
  }
  final int splitCount = columnCount <= 0 ? 0 : columnCount - 1;
  final List<String> result = <String>[];
  var rest = line.substring(colon + 1);
  for (var i = 0; i < splitCount; i++) {
    final int comma = rest.indexOf(',');
    if (comma == -1) {
      result.add(rest);
      return result;
    }
    result.add(rest.substring(0, comma));
    rest = rest.substring(comma + 1);
  }
  result.add(rest);
  return result;
}

String _detectNewline(Uint8List raw) {
  for (var i = 0; i + 1 < raw.length; i++) {
    if (raw[i] == 0x0D && raw[i + 1] == 0x0A) {
      return '\r\n';
    }
  }
  return '\n';
}

String _decodeSubtitleBytes(Uint8List raw) {
  if (raw.length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) {
    return utf8.decode(raw.sublist(3), allowMalformed: true);
  }
  if (raw.length >= 2 && raw[0] == 0xFF && raw[1] == 0xFE) {
    return _decodeUtf16(raw.sublist(2), littleEndian: true);
  }
  if (raw.length >= 2 && raw[0] == 0xFE && raw[1] == 0xFF) {
    return _decodeUtf16(raw.sublist(2), littleEndian: false);
  }
  return utf8.decode(raw, allowMalformed: true);
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final List<int> codeUnits = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    codeUnits.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(codeUnits);
}
