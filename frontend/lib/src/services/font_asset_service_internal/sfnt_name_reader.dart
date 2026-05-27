import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models.dart';

class SfntFontFace {
  const SfntFontFace({
    required this.trackIndex,
    required this.familyNames,
    required this.fullNames,
    required this.postScriptNames,
    required this.licenseDescriptions,
    required this.maxpNumGlyphs,
    required this.fsType,
    required this.bold,
    required this.italic,
    required this.weight,
    required this.cmapCodepoints,
  });

  final int trackIndex;
  final Set<String> familyNames;
  final Set<String> fullNames;
  final Set<String> postScriptNames;
  final Set<String> licenseDescriptions;
  final int maxpNumGlyphs;
  final int fsType;
  final bool bold;
  final bool italic;
  final int weight;
  final Set<int> cmapCodepoints;
}

class _TableRecord {
  const _TableRecord({required this.offset, required this.length});

  final int offset;
  final int length;
}

Future<List<SfntFontFace>> readSfntFontFaces(String path) async {
  final Uint8List bytes = await File(path).readAsBytes();
  final ByteData data = ByteData.sublistView(bytes);
  if (bytes.length < 12) {
    throw FormatException('字体文件过短: $path');
  }
  if (_tagAt(bytes, 0) == 'ttcf') {
    final int count = data.getUint32(8);
    final List<SfntFontFace> faces = <SfntFontFace>[];
    for (var i = 0; i < count; i++) {
      faces.add(_readFace(bytes, data.getUint32(12 + i * 4), i, path));
    }
    return faces;
  }
  return <SfntFontFace>[_readFace(bytes, 0, 0, path)];
}

Future<List<ResolvedFontFile>> enrichResolvedFontFile(
  ResolvedFontFile file,
) async {
  final List<SfntFontFace> faces = await readSfntFontFaces(file.path);
  return <ResolvedFontFile>[
    for (final SfntFontFace face in faces)
      file.copyWith(
        trackIndex: face.trackIndex,
        familyNames: face.familyNames,
        fullNames: <String>{...face.fullNames, ...face.postScriptNames},
        maxpNumGlyphs: face.maxpNumGlyphs,
        fsType: face.fsType,
        bold: face.bold,
        italic: face.italic,
        weight: face.weight,
        licenseDescription: face.licenseDescriptions.isEmpty
            ? '原字体未提供许可信息，仅做字符子集化处理。'
            : face.licenseDescriptions.join('\n\n'),
      ),
  ];
}

SfntFontFace _readFace(
  Uint8List bytes,
  int offset,
  int trackIndex,
  String path,
) {
  final ByteData data = ByteData.sublistView(bytes);
  if (offset < 0 || offset + 12 > bytes.length) {
    throw FormatException('字体 face 偏移非法: ${p.basename(path)}');
  }
  final int tableCount = data.getUint16(offset + 4);
  final Map<String, _TableRecord> tables = <String, _TableRecord>{};
  for (var i = 0; i < tableCount; i++) {
    final int recordOffset = offset + 12 + i * 16;
    if (recordOffset + 16 > bytes.length) {
      break;
    }
    tables[_tagAt(bytes, recordOffset)] = _TableRecord(
      offset: data.getUint32(recordOffset + 8),
      length: data.getUint32(recordOffset + 12),
    );
  }
  final ({
    Set<String> familyNames,
    Set<String> fullNames,
    Set<String> postScriptNames,
    Set<String> licenseDescriptions,
  }) names = _readNames(bytes, tables['name']);
  final ({int fsType, bool bold, bool italic, int weight}) os2 =
      _readOs2(bytes, tables['OS/2']);
  return SfntFontFace(
    trackIndex: trackIndex,
    familyNames: names.familyNames,
    fullNames: names.fullNames,
    postScriptNames: names.postScriptNames,
    licenseDescriptions: names.licenseDescriptions,
    maxpNumGlyphs: _readMaxpNumGlyphs(bytes, tables['maxp']),
    fsType: os2.fsType,
    bold: os2.bold,
    italic: os2.italic,
    weight: os2.weight,
    cmapCodepoints: _readCmapCodepoints(bytes, tables['cmap']),
  );
}

({
  Set<String> familyNames,
  Set<String> fullNames,
  Set<String> postScriptNames,
  Set<String> licenseDescriptions,
}) _readNames(Uint8List bytes, _TableRecord? table) {
  final Set<String> familyNames = <String>{};
  final Set<String> fullNames = <String>{};
  final Set<String> postScriptNames = <String>{};
  final Set<String> licenseDescriptions = <String>{};
  if (table == null || table.offset + 6 > bytes.length) {
    return (
      familyNames: familyNames,
      fullNames: fullNames,
      postScriptNames: postScriptNames,
      licenseDescriptions: licenseDescriptions,
    );
  }
  final ByteData data = ByteData.sublistView(bytes);
  final int count = data.getUint16(table.offset + 2);
  final int stringOffset = table.offset + data.getUint16(table.offset + 4);
  for (var i = 0; i < count; i++) {
    final int recordOffset = table.offset + 6 + i * 12;
    if (recordOffset + 12 > bytes.length) {
      break;
    }
    final int platformId = data.getUint16(recordOffset);
    final int encodingId = data.getUint16(recordOffset + 2);
    final int nameId = data.getUint16(recordOffset + 6);
    final int length = data.getUint16(recordOffset + 8);
    final int valueOffset = stringOffset + data.getUint16(recordOffset + 10);
    if (valueOffset < 0 || valueOffset + length > bytes.length) {
      continue;
    }
    final String value = _decodeName(
      bytes.sublist(valueOffset, valueOffset + length),
      platformId: platformId,
      encodingId: encodingId,
    ).trim();
    if (value.isEmpty) {
      continue;
    }
    switch (nameId) {
      case 1:
        familyNames.add(value);
        break;
      case 4:
        fullNames.add(value);
        break;
      case 6:
        postScriptNames.add(value);
        break;
      case 13:
        licenseDescriptions.add(value);
        break;
    }
  }
  return (
    familyNames: familyNames,
    fullNames: fullNames,
    postScriptNames: postScriptNames,
    licenseDescriptions: licenseDescriptions,
  );
}

({int fsType, bool bold, bool italic, int weight}) _readOs2(
  Uint8List bytes,
  _TableRecord? table,
) {
  if (table == null || table.offset + 64 > bytes.length) {
    return (fsType: 0, bold: false, italic: false, weight: 400);
  }
  final ByteData data = ByteData.sublistView(bytes);
  final int weight = data.getUint16(table.offset + 4);
  final int fsType = data.getUint16(table.offset + 8);
  final int fsSelection = data.getUint16(table.offset + 62);
  return (
    fsType: fsType,
    bold: (fsSelection & 0x20) != 0,
    italic: (fsSelection & 0x01) != 0,
    weight: weight,
  );
}

int _readMaxpNumGlyphs(Uint8List bytes, _TableRecord? table) {
  if (table == null || table.offset + 6 > bytes.length) {
    return 0;
  }
  return ByteData.sublistView(bytes).getUint16(table.offset + 4);
}

Set<int> _readCmapCodepoints(Uint8List bytes, _TableRecord? table) {
  final Set<int> result = <int>{};
  if (table == null || table.offset + 4 > bytes.length) {
    return result;
  }
  final ByteData data = ByteData.sublistView(bytes);
  final int count = data.getUint16(table.offset + 2);
  for (var i = 0; i < count; i++) {
    final int recordOffset = table.offset + 4 + i * 8;
    if (recordOffset + 8 > bytes.length) {
      break;
    }
    final int subtableOffset = table.offset + data.getUint32(recordOffset + 4);
    if (subtableOffset + 2 > bytes.length) {
      continue;
    }
    final int format = data.getUint16(subtableOffset);
    if (format == 4) {
      result.addAll(_readCmapFormat4(bytes, subtableOffset));
    } else if (format == 12) {
      result.addAll(_readCmapFormat12(bytes, subtableOffset));
    }
  }
  return result;
}

Set<int> _readCmapFormat4(Uint8List bytes, int offset) {
  final Set<int> result = <int>{};
  final ByteData data = ByteData.sublistView(bytes);
  if (offset + 16 > bytes.length) {
    return result;
  }
  final int segCount = data.getUint16(offset + 6) ~/ 2;
  final int endCodeOffset = offset + 14;
  final int startCodeOffset = endCodeOffset + segCount * 2 + 2;
  final int idDeltaOffset = startCodeOffset + segCount * 2;
  for (var i = 0; i < segCount; i++) {
    final int end = data.getUint16(endCodeOffset + i * 2);
    final int start = data.getUint16(startCodeOffset + i * 2);
    final int delta = data.getInt16(idDeltaOffset + i * 2);
    if (start == 0xFFFF && end == 0xFFFF) {
      continue;
    }
    if (delta == 0 && start == 0 && end == 0) {
      continue;
    }
    for (var cp = start; cp <= end && cp <= 0x10FFFF; cp++) {
      result.add(cp);
    }
  }
  return result;
}

Set<int> _readCmapFormat12(Uint8List bytes, int offset) {
  final Set<int> result = <int>{};
  final ByteData data = ByteData.sublistView(bytes);
  if (offset + 16 > bytes.length) {
    return result;
  }
  final int groupCount = data.getUint32(offset + 12);
  for (var i = 0; i < groupCount; i++) {
    final int groupOffset = offset + 16 + i * 12;
    if (groupOffset + 12 > bytes.length) {
      break;
    }
    final int start = data.getUint32(groupOffset);
    final int end = data.getUint32(groupOffset + 4);
    for (var cp = start; cp <= end && cp <= 0x10FFFF; cp++) {
      result.add(cp);
    }
  }
  return result;
}

String _decodeName(
  List<int> bytes, {
  required int platformId,
  required int encodingId,
}) {
  if (platformId == 0 || platformId == 3) {
    return _decodeUtf16Be(bytes);
  }
  if (platformId == 1 && encodingId == 0) {
    return latin1.decode(bytes, allowInvalid: true);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String _decodeUtf16Be(List<int> bytes) {
  final List<int> codeUnits = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    codeUnits.add((bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(codeUnits);
}

String _tagAt(Uint8List bytes, int offset) {
  return ascii.decode(bytes.sublist(offset, offset + 4));
}
