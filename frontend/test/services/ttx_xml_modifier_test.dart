import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/services/font_asset_service_internal/ttx_xml_modifier.dart';

void main() {
  test('Property 24: TTX_Pipeline produces a uniquely renamed font', () {
    const String xml = '''
<ttFont>
  <name>
    <namerecord nameID="1" platformID="3" platEncID="1" langID="0x409">Source Han Sans</namerecord>
    <namerecord nameID="3" platformID="3" platEncID="1" langID="0x409">Unique</namerecord>
    <namerecord nameID="4" platformID="3" platEncID="1" langID="0x409">Source Han Sans Regular</namerecord>
    <namerecord nameID="6" platformID="3" platEncID="1" langID="0x409">SourceHanSans-Regular</namerecord>
    <namerecord nameID="13" platformID="3" platEncID="1" langID="0x409">License</namerecord>
  </name>
  <cmap>
    <map code="0x2026" name="cid12345"/>
  </cmap>
  <GSUB>
    <Substitution in="cid12345" out="cid60001"/>
    <Substitution in="cid12345" out="cid50001"/>
  </GSUB>
</ttFont>
''';

    final TtxModifyResult result = modifyTtxXml(
      '$xml\x00',
      randomName: 'ABCDEFGH',
      aemtVersion: 'test',
      fontToolsVersion: '4.55.0',
      originalFontPath: 'C:/font/source.otf',
    );

    expect(result.isSourceHan, isTrue);
    expect(result.renamedNameRecordCount, 4);
    expect(result.removedEllipsisSubstitutions, 1);
    expect(result.xmlText, contains('ABCDEFGH'));
    expect(result.xmlText, contains('License'));
    expect(
      result.xmlText,
      contains('Processed by AEMT vtest; pyFontTools 4.55.0'),
    );
    expect(result.xmlText, isNot(contains('cid60001')));
    expect(result.xmlText, contains('cid50001'));
    expect(result.xmlText, isNot(contains('\x00')));
  });

  test('Font_Random_Rename produces unique uppercase names', () {
    final Set<String> used = <String>{};
    for (var i = 0; i < 64; i++) {
      final String value = generateRandomName(used);
      expect(value, matches(RegExp(r'^[A-Z0-9]{8}$')));
    }
    expect(used.length, 64);
  });

  test('empty cmap gains compile-safe subtables', () {
    const String xml = '''
<ttFont>
  <name>
    <namerecord nameID="1" platformID="3" platEncID="1" langID="0x409">Example</namerecord>
    <namerecord nameID="4" platformID="3" platEncID="1" langID="0x409">Example Regular</namerecord>
  </name>
  <cmap>
    <tableVersion version="0"/>
  </cmap>
</ttFont>
''';

    final TtxModifyResult result = modifyTtxXml(
      xml,
      randomName: 'ABCDEFGH',
      aemtVersion: 'test',
      fontToolsVersion: '4.61.0',
      originalFontPath: 'C:/font/example.ttf',
    );

    expect(result.xmlText, contains('cmap_format_4'));
    expect(result.xmlText, contains('platformID="0"'));
    expect(result.xmlText, contains('platformID="3"'));
  });
}
