import 'dart:math';

import 'package:xml/xml.dart';

const String kFontForgeAdvice =
    '请尝试使用 FontForge 重新生成字体（File - Generate Font），然后用新字体再次子集化。';

class TtxModifyResult {
  const TtxModifyResult({
    required this.xmlText,
    required this.isSourceHan,
    required this.renamedNameRecordCount,
    required this.removedEllipsisSubstitutions,
  });

  final String xmlText;
  final bool isSourceHan;
  final int renamedNameRecordCount;
  final int removedEllipsisSubstitutions;
}

String generateRandomName(Set<String> usedNames) {
  const String alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final Random random = Random.secure();
  for (var attempt = 0; attempt < 32; attempt++) {
    final String value = String.fromCharCodes(<int>[
      for (var i = 0; i < 8; i++)
        alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ]);
    if (usedNames.add(value)) {
      return value;
    }
  }
  throw Exception('无法生成唯一字体随机名（碰撞超过 32 次）');
}

TtxModifyResult modifyTtxXml(
  String xmlText, {
  required String randomName,
  required String aemtVersion,
  required String? fontToolsVersion,
  required String originalFontPath,
  bool sourceHanEllipsisFix = true,
}) {
  final XmlDocument document = XmlDocument.parse(xmlText.replaceAll('\x00', ''));
  final Iterable<XmlElement> nameRecords = document
      .findAllElements('namerecord');
  var renamedCount = 0;
  var isSourceHan = false;
  for (final XmlElement record in nameRecords) {
    final String? nameId = record.getAttribute('nameID')?.trim();
    if (nameId == '1' || nameId == '3' || nameId == '4' || nameId == '6') {
      if (record.innerText.contains('Source Han')) {
        isSourceHan = true;
      }
    }
  }
  for (final XmlElement record in nameRecords) {
    final String? nameId = record.getAttribute('nameID')?.trim();
    if (nameId == '0') {
      _replaceText(
        record,
        'Processed by AEMT v$aemtVersion; pyFontTools ${fontToolsVersion ?? 'unknown'}',
      );
    } else if (nameId == '1' ||
        nameId == '3' ||
        nameId == '4' ||
        nameId == '6') {
      _replaceText(record, randomName);
      renamedCount++;
    }
  }
  _appendNameId0IfMissing(document, aemtVersion, fontToolsVersion);
  if (renamedCount == 0) {
    throw Exception('$originalFontPath: $kFontForgeAdvice');
  }
  final int removed = sourceHanEllipsisFix && isSourceHan
      ? _applySourceHanEllipsisFix(document)
      : 0;
  return TtxModifyResult(
    xmlText: document.toXmlString(pretty: true).replaceAll('\x00', ''),
    isSourceHan: isSourceHan,
    renamedNameRecordCount: renamedCount,
    removedEllipsisSubstitutions: removed,
  );
}

void _replaceText(XmlElement element, String text) {
  element.children.clear();
  element.children.add(XmlText(text));
}

void _appendNameId0IfMissing(
  XmlDocument document,
  String aemtVersion,
  String? fontToolsVersion,
) {
  final XmlElement? nameElement = _firstOrNull(document.findAllElements('name'));
  if (nameElement == null) {
    return;
  }
  final bool hasNameId0 = nameElement
      .findElements('namerecord')
      .any((XmlElement record) => record.getAttribute('nameID') == '0');
  if (hasNameId0) {
    return;
  }
  nameElement.children.add(
    XmlElement(
      XmlName('namerecord'),
      <XmlAttribute>[
        XmlAttribute(XmlName('nameID'), '0'),
        XmlAttribute(XmlName('platformID'), '3'),
        XmlAttribute(XmlName('platEncID'), '1'),
        XmlAttribute(XmlName('langID'), '0x409'),
      ],
      <XmlNode>[
        XmlText(
          'Processed by AEMT v$aemtVersion; pyFontTools ${fontToolsVersion ?? 'unknown'}',
        ),
      ],
    ),
  );
}

int _applySourceHanEllipsisFix(XmlDocument document) {
  final XmlElement? ellipsisMap = _firstOrNull(
    document
        .findAllElements('map')
        .where((XmlElement element) => element.getAttribute('code') == '0x2026'),
  );
  final String? ellipsisCid = ellipsisMap?.getAttribute('name');
  if (ellipsisCid == null || ellipsisCid.isEmpty) {
    return 0;
  }
  final List<XmlElement> removeTargets = document
      .findAllElements('Substitution')
      .where(
        (XmlElement element) =>
            element.getAttribute('in') == ellipsisCid &&
            (element.getAttribute('out') ?? '').startsWith('cid6'),
      )
      .toList();
  for (final XmlElement target in removeTargets) {
    target.parent?.children.remove(target);
  }
  return removeTargets.length;
}

T? _firstOrNull<T>(Iterable<T> values) {
  for (final T value in values) {
    return value;
  }
  return null;
}
