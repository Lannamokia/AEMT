import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../models.dart';
import '../utils/export_utils.dart';
import 'font_asset_service_internal/sfnt_name_reader.dart';
import 'font_asset_service_internal/ttx_xml_modifier.dart';
import 'font_asset_service_internal/vert_mapping.dart';

class FontAssetService {
  const FontAssetService({
    required this.ffmpegPath,
    required this.sevenZipPath,
  });

  final String? ffmpegPath;
  final String? sevenZipPath;

  static String normalizeFontName(String value) {
    final String trimmed = value.trim();
    return (trimmed.startsWith('@') ? trimmed.substring(1) : trimmed)
        .trim()
        .toLowerCase();
  }

  static Set<String> _candidateMatchNames(ResolvedFontFile candidate) {
    return <String>{
      ...candidate.familyNames,
      ...candidate.fullNames,
      ..._sourceHanRegionAliases(candidate),
    }.map(normalizeFontName).toSet();
  }

  static Set<String> _sourceHanRegionAliases(ResolvedFontFile candidate) {
    final String stem = p.basenameWithoutExtension(candidate.fileName);
    final RegExpMatch? match = RegExp(
      r'^SourceHan(Sans|Serif)(HW)?(SC|TC|HC|K)?(?:[-_]?(.+))?$',
      caseSensitive: false,
    ).firstMatch(stem);
    if (match == null) {
      return const <String>{};
    }
    final String family = match.group(1)!.toLowerCase() == 'serif'
        ? 'Source Han Serif'
        : 'Source Han Sans';
    final String? halfWidth = match.group(2);
    final String region = switch (match.group(3)?.toUpperCase()) {
      'SC' => 'SC',
      'TC' => 'TC',
      'HC' => 'HK',
      'K' => 'KR',
      _ => 'JP',
    };
    final String? style = _sourceHanStyleName(match.group(4));
    final String base = halfWidth == null ? family : '$family HW';
    final Set<String> aliases = <String>{};
    if (style != null) {
      aliases.add('$base $region $style');
    }
    if (_isRegularSourceHanFace(candidate, style)) {
      aliases.add('$base $region');
    }
    return aliases;
  }

  static String? _sourceHanStyleName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value
        .replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ')
        .replaceAll(RegExp(r'[-_]+'), ' ')
        .trim();
  }

  static bool _isRegularSourceHanFace(
    ResolvedFontFile candidate,
    String? style,
  ) {
    final String normalizedStyle = (style ?? '')
        .replaceAll(' ', '')
        .toLowerCase();
    if (normalizedStyle.isNotEmpty &&
        normalizedStyle != 'regular' &&
        normalizedStyle != 'normal') {
      return false;
    }
    return !candidate.bold && !candidate.italic && candidate.weight <= 450;
  }

  Future<List<ResolvedFontFile>> resolveFontFiles(
    List<String> importedFontSources,
    String tempDir,
  ) async {
    final List<ResolvedFontFile> result = <ResolvedFontFile>[];
    for (final String source in importedFontSources) {
      final String extension = p.extension(source).toLowerCase();
      if (<String>{'.ttf', '.otf', '.ttc'}.contains(extension)) {
        result.addAll(
          await _enrichFont(
            ResolvedFontFile(
              path: source,
              fileName: p.basename(source),
              mimeType: mimeTypeForFont(source),
              source: FontSourceKind.imported,
              importOrder: result.length,
            ),
          ),
        );
        continue;
      }
      if (extension == '.zip') {
        final InputFileStream input = InputFileStream(source);
        final Archive archive = ZipDecoder().decodeStream(input);
        for (final ArchiveFile file in archive) {
          if (!file.isFile || !isFontFile(file.name)) {
            continue;
          }
          final String outPath = p.join(tempDir, p.basename(file.name));
          final OutputFileStream output = OutputFileStream(outPath);
          file.writeContent(output);
          output.close();
          result.addAll(
            await _enrichFont(
              ResolvedFontFile(
                path: outPath,
                fileName: p.basename(outPath),
                mimeType: mimeTypeForFont(outPath),
                source: FontSourceKind.imported,
                importOrder: result.length,
              ),
            ),
          );
        }
        input.close();
        continue;
      }
      if (<String>{'.7z', '.rar'}.contains(extension) &&
          sevenZipPath != null &&
          sevenZipPath!.isNotEmpty) {
        final String outDir = p.join(
          tempDir,
          p.basenameWithoutExtension(source),
        );
        await Directory(outDir).create(recursive: true);
        final ProcessResult extraction = await _runSevenZipWithAdaptiveEncoding(
          <String>['x', source, '-aoa', '-y', '-o$outDir'],
        );
        if (extraction.exitCode != 0) {
          continue;
        }
        final List<FileSystemEntity> entries = Directory(
          outDir,
        ).listSync(recursive: true);
        for (final File file in entries.whereType<File>()) {
          if (isFontFile(file.path)) {
            result.addAll(
              await _enrichFont(
                ResolvedFontFile(
                  path: file.path,
                  fileName: p.basename(file.path),
                  mimeType: mimeTypeForFont(file.path),
                  source: FontSourceKind.imported,
                  importOrder: result.length,
                ),
              ),
            );
          }
        }
      }
    }
    return result;
  }

  Future<List<ResolvedFontFile>> extractEnabledInputAttachments(
    MediaInfo info,
    String tempDir,
  ) async {
    final List<MediaStreamEntry> allInputAttachments = info.streams
        .where(
          (MediaStreamEntry stream) =>
              stream.origin == StreamOrigin.input &&
              stream.kind == StreamKind.attachment,
        )
        .toList();
    final List<MediaStreamEntry> enabledAttachments = allInputAttachments
        .where((MediaStreamEntry stream) => stream.enabled)
        .toList();
    if (enabledAttachments.isEmpty) {
      return <ResolvedFontFile>[];
    }
    final String outDir = p.join(tempDir, 'input_attachments');
    await Directory(outDir).create(recursive: true);
    final List<ResolvedFontFile> result = <ResolvedFontFile>[];
    final List<String> args = <String>[
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
    ];
    for (final MediaStreamEntry attachment in enabledAttachments) {
      final int attachmentStreamIndex = allInputAttachments.indexWhere(
        (MediaStreamEntry stream) => stream.index == attachment.index,
      );
      if (attachmentStreamIndex == -1) {
        continue;
      }
      final String fileName =
          attachment.attachmentFileName?.trim().isNotEmpty == true
          ? attachment.attachmentFileName!.trim()
          : 'attachment_$attachmentStreamIndex.${attachment.codec}';
      final String outPath = p.join(
        outDir,
        '${attachmentStreamIndex}_$fileName',
      );
      final List<ResolvedFontFile> enriched = await _enrichFont(
        ResolvedFontFile(
          path: outPath,
          fileName: fileName,
          mimeType: attachment.attachmentMimeType?.trim().isNotEmpty == true
              ? attachment.attachmentMimeType!.trim()
              : mimeTypeForAttachment(attachment),
          source: FontSourceKind.attachment,
          importOrder: result.length,
        ),
      );
      result.addAll(enriched);
      args.addAll(<String>[
        '-dump_attachment:t:$attachmentStreamIndex',
        outPath,
      ]);
    }
    if (result.isEmpty) {
      return result;
    }
    final ProcessResult extraction = await Process.run(
      ffmpegPath!,
      <String>[...args, '-i', info.inputPath, '-f', 'null', '-'],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (extraction.exitCode != 0) {
      throw Exception('提取原始附件失败: ${extraction.stderr}');
    }
    for (final ResolvedFontFile file in result) {
      if (!File(file.path).existsSync()) {
        throw Exception('提取原始附件失败: 未生成 ${file.fileName}');
      }
    }
    return result;
  }

  Future<SubtitleCharIndex> indexSubtitleCharacters(
    List<String> subtitlePaths,
  ) async {
    final Map<String, Set<int>> aggregate = <String, Set<int>>{};
    final Map<String, Set<int>> nextAggregate = <String, Set<int>>{};
    for (final String subtitlePath in subtitlePaths) {
      try {
        final Map<String, Set<int>> parsed = await _indexOneSubtitle(
          subtitlePath,
        );
        nextAggregate
          ..clear()
          ..addAll({
            for (final MapEntry<String, Set<int>> entry in aggregate.entries)
              entry.key: <int>{...entry.value},
          });
        for (final MapEntry<String, Set<int>> entry in parsed.entries) {
          nextAggregate
              .putIfAbsent(entry.key, () => <int>{})
              .addAll(entry.value);
        }
        aggregate
          ..clear()
          ..addAll({
            for (final MapEntry<String, Set<int>> entry
                in nextAggregate.entries)
              entry.key: entry.value,
          });
      } catch (error) {
        throw Exception('无法解析字幕: $subtitlePath: $error');
      }
    }
    for (final Set<int> codepoints in aggregate.values) {
      _appendNecessaryCodepoints(codepoints);
    }
    return SubtitleCharIndex(aggregate);
  }

  FontMatchResult matchFonts(
    SubtitleCharIndex index,
    List<ResolvedFontFile> candidates,
  ) {
    _throwOnDuplicateFonts(candidates);
    final Map<String, ResolvedFontFile> matched = <String, ResolvedFontFile>{};
    final Set<String> missing = <String>{};
    final List<ResolvedFontFile> ordered = <ResolvedFontFile>[...candidates]
      ..sort((ResolvedFontFile a, ResolvedFontFile b) {
        if (a.source != b.source) {
          return a.source == FontSourceKind.attachment ? -1 : 1;
        }
        return a.importOrder.compareTo(b.importOrder);
      });
    for (final String fontName in index.codepointsByFontname.keys) {
      final String key = normalizeFontName(fontName);
      ResolvedFontFile? selected;
      for (final ResolvedFontFile candidate in ordered) {
        final Set<String> names = _candidateMatchNames(candidate);
        if (names.contains(key)) {
          selected = candidate;
          break;
        }
      }
      if (selected == null) {
        missing.add(fontName);
      } else {
        matched[key] = selected;
      }
    }
    return FontMatchResult(matched: matched, missing: missing);
  }

  List<FontSubsetStepPlan> planSubsetFontSteps(
    SubtitleCharIndex index,
    Map<String, ResolvedFontFile> matchedFontsByNormalizedFontname,
    String workDir, {
    required String pyftsubsetPath,
    required String ttxPath,
    required String aemtVersion,
    required String? fontToolsVersion,
    bool sourceHanEllipsisFix = true,
    bool verifyAfterSubset = true,
  }) {
    final Set<String> usedNames = <String>{};
    final String subsetDir = p.join(workDir, 'subsetted');
    return <FontSubsetStepPlan>[
      for (final MapEntry<String, ResolvedFontFile> entry
          in matchedFontsByNormalizedFontname.entries)
        _buildSubsetStepPlan(
          normalizedKey: entry.key,
          originalFont: entry.value,
          codepoints: index.codepointsByFontname[entry.key] ?? <int>{},
          subsetDir: subsetDir,
          pyftsubsetPath: pyftsubsetPath,
          ttxPath: ttxPath,
          aemtVersion: aemtVersion,
          fontToolsVersion: fontToolsVersion,
          sourceHanEllipsisFix: sourceHanEllipsisFix,
          verifyAfterSubset: verifyAfterSubset,
          usedNames: usedNames,
        ),
    ];
  }

  Future<SubsetResult> subsetFonts(
    SubtitleCharIndex index,
    Map<String, ResolvedFontFile> matchedFontsByNormalizedFontname,
    String workDir, {
    required String pyftsubsetPath,
    required String ttxPath,
    required Stream<void> cancelSignal,
    required String aemtVersion,
    required String? fontToolsVersion,
    bool sourceHanEllipsisFix = true,
    bool verifyAfterSubset = true,
  }) async {
    final List<FontSubsetStepPlan> steps = planSubsetFontSteps(
      index,
      matchedFontsByNormalizedFontname,
      workDir,
      pyftsubsetPath: pyftsubsetPath,
      ttxPath: ttxPath,
      aemtVersion: aemtVersion,
      fontToolsVersion: fontToolsVersion,
      sourceHanEllipsisFix: sourceHanEllipsisFix,
      verifyAfterSubset: verifyAfterSubset,
    );
    final List<ResolvedFontFile> fonts = <ResolvedFontFile>[];
    final Map<String, String> renameMap = <String, String>{};
    for (final FontSubsetStepPlan step in steps) {
      await executeSubsetFontStep(step, cancelSignal: cancelSignal);
      fonts.add(step.outputFont);
      renameMap[step.normalizedKey] = step.randomName;
    }
    return SubsetResult(fonts: fonts, renameMap: renameMap);
  }

  Future<({String verifyLogLine, String? fsTypeWarning})> executeSubsetFontStep(
    FontSubsetStepPlan plan, {
    required Stream<void> cancelSignal,
  }) async {
    await Directory(plan.subsetDir).create(recursive: true);
    await _appendLicenseSidecar(plan);
    await File(
      plan.codepointsFilePath,
    ).writeAsString(_formatUnicodeFile(plan.codepoints), encoding: utf8);
    await _runProcessOrThrow(
      plan.pyftsubsetPath,
      plan.pyftsubsetArguments,
      plan.originalFont.path,
      cancelSignal,
    );
    await _runProcessOrThrow(
      plan.ttxPath,
      plan.ttxDumpArguments,
      plan.originalFont.path,
      cancelSignal,
    );
    final File ttxFile = File(plan.ttxXmlPath);
    if (!ttxFile.existsSync()) {
      throw Exception('${plan.originalFont.path}: $kFontForgeAdvice');
    }
    final String xmlText = await ttxFile.readAsString();
    final TtxModifyResult modified = modifyTtxXml(
      xmlText,
      randomName: plan.randomName,
      aemtVersion: plan.aemtVersion,
      fontToolsVersion: plan.fontToolsVersion,
      originalFontPath: plan.originalFont.path,
      sourceHanEllipsisFix: plan.sourceHanEllipsisFix,
    );
    await ttxFile.writeAsString(modified.xmlText);
    await _runProcessOrThrow(
      plan.ttxPath,
      plan.ttxCompileArguments,
      plan.originalFont.path,
      cancelSignal,
    );
    if (!File(plan.outputFont.path).existsSync()) {
      throw Exception('${plan.originalFont.path}: $kFontForgeAdvice');
    }
    if (plan.verifyAfterSubset) {
      final Set<int> cmap = await readSfntFontFaces(plan.outputFont.path).then(
        (List<SfntFontFace> faces) =>
            faces.expand((SfntFontFace face) => face.cmapCodepoints).toSet(),
      );
      final Set<int> missing = plan.codepoints
          .where((int codepoint) => !_isNonRenderingCodepoint(codepoint))
          .where((int codepoint) => !cmap.contains(codepoint))
          .toSet();
      if (missing.isNotEmpty) {
        throw Exception(
          '${plan.originalFont.path}: subset FAIL: missing ${missing.length} codepoints',
        );
      }
    }
    return (
      verifyLogLine: plan.verifyAfterSubset
          ? 'subset OK: ${plan.originalFont.fileName} (${plan.codepoints.length})'
          : '子集化校验已跳过',
      fsTypeWarning: plan.fsTypeRestricted
          ? '字体 ${plan.originalFont.fileName} 标记为受限嵌入...'
          : null,
    );
  }

  bool _isNonRenderingCodepoint(int codepoint) {
    if (codepoint == 0x09 || codepoint == 0x0A || codepoint == 0x0D) {
      return true;
    }
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

  String _formatUnicodeFile(List<int> codepoints) {
    return codepoints
        .map(
          (int codepoint) =>
              'U+${codepoint.toRadixString(16).toUpperCase().padLeft(4, '0')}',
        )
        .join('\n');
  }

  Future<void> _appendLicenseSidecar(FontSubsetStepPlan plan) async {
    final String text = plan.originalFont.licenseDescription.trim().isEmpty
        ? '原字体未提供许可信息，仅做字符子集化处理。'
        : plan.originalFont.licenseDescription.trim();
    final File file = File(p.join(plan.subsetDir, 'LICENSE.txt'));
    final String entry = [
      'Font: ${plan.originalFont.fileName}',
      text,
      '',
    ].join('\n');
    await file.writeAsString(entry, mode: FileMode.append, encoding: utf8);
  }

  FontSubsetStepPlan _buildSubsetStepPlan({
    required String normalizedKey,
    required ResolvedFontFile originalFont,
    required Set<int> codepoints,
    required String subsetDir,
    required String pyftsubsetPath,
    required String ttxPath,
    required String aemtVersion,
    required String? fontToolsVersion,
    required bool sourceHanEllipsisFix,
    required bool verifyAfterSubset,
    required Set<String> usedNames,
  }) {
    final String randomName = generateRandomName(usedNames);
    final String baseName = p.basenameWithoutExtension(originalFont.fileName);
    final String extension = p.extension(originalFont.fileName);
    final String subsetTempPath = p.join(
      subsetDir,
      '$baseName.subset_tmp_$extension',
    );
    final String ttxXmlPath = p.join(subsetDir, '$baseName.ttx');
    final String outputPath = p.join(subsetDir, '$baseName.subset$extension');
    return FontSubsetStepPlan(
      originalFont: originalFont,
      outputFont: originalFont.copyWith(
        path: outputPath,
        source: FontSourceKind.subsetted,
      ),
      normalizedKey: normalizedKey,
      randomName: randomName,
      codepoints: (codepoints.toList()..sort()),
      pyftsubsetPath: pyftsubsetPath,
      ttxPath: ttxPath,
      aemtVersion: aemtVersion,
      fontToolsVersion: fontToolsVersion,
      sourceHanEllipsisFix: sourceHanEllipsisFix,
      verifyAfterSubset: verifyAfterSubset,
      fsTypeRestricted: (originalFont.fsType & 0x0002) != 0,
      subsetDir: subsetDir,
      codepointsFilePath: p.join(subsetDir, '$baseName.unicodes.txt'),
      subsetTempPath: subsetTempPath,
      ttxXmlPath: ttxXmlPath,
    );
  }

  Future<void> _runProcessOrThrow(
    String executable,
    List<String> arguments,
    String originalFontPath,
    Stream<void> cancelSignal,
  ) async {
    final Process process = await Process.start(
      executable,
      arguments,
      runInShell: false,
      environment: const <String, String>{'PYTHONIOENCODING': 'utf-8'},
    );
    final StreamSubscription<void> cancelSub = cancelSignal.listen((_) {
      process.kill(ProcessSignal.sigterm);
    });
    final List<int> stderrBytes = <int>[];
    final StreamSubscription<List<int>> stderrSub = process.stderr.listen(
      stderrBytes.addAll,
    );
    final StreamSubscription<List<int>> stdoutSub = process.stdout.listen(
      (_) {},
    );
    final int exitCode = await process.exitCode;
    await cancelSub.cancel();
    await stdoutSub.cancel();
    await stderrSub.cancel();
    if (exitCode != 0) {
      final String stderr = utf8.decode(
        stderrBytes.length > 4096
            ? stderrBytes.sublist(stderrBytes.length - 4096)
            : stderrBytes,
        allowMalformed: true,
      );
      throw Exception('$originalFontPath: $stderr\n$kFontForgeAdvice');
    }
  }

  Future<List<ResolvedFontFile>> _enrichFont(ResolvedFontFile file) async {
    if (p.basename(file.path).toLowerCase().contains('misans')) {
      assert(false, 'MiSans must never enter subtitle font candidates.');
      return <ResolvedFontFile>[];
    }
    try {
      return await enrichResolvedFontFile(file);
    } catch (_) {
      return <ResolvedFontFile>[file];
    }
  }

  Future<Map<String, Set<int>>> _indexOneSubtitle(String path) async {
    final Uint8List bytes = await File(path).readAsBytes();
    final String text = _decodeSubtitleBytes(bytes);
    final String extension = p.extension(path).toLowerCase();
    if (extension == '.ass' || extension == '.ssa') {
      return _indexAssText(text);
    }
    return <String, Set<int>>{'__default__': _visibleCodepoints(text)};
  }

  Map<String, Set<int>> _indexAssText(String text) {
    final List<String> lines = text.split(RegExp(r'\r\n|\n'));
    final Map<String, String> styleFonts = <String, String>{};
    final Map<String, Set<int>> result = <String, Set<int>>{};
    var section = '';
    List<String> styleFormat = <String>[];
    List<String> eventFormat = <String>[];
    for (final String line in lines) {
      final String trimmed = line.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        section = trimmed.toLowerCase();
        continue;
      }
      if ((section == '[v4+ styles]' || section == '[v4 styles]') &&
          trimmed.toLowerCase().startsWith('format:')) {
        styleFormat = _parseFormat(line);
        continue;
      }
      if ((section == '[v4+ styles]' || section == '[v4 styles]') &&
          trimmed.toLowerCase().startsWith('style:')) {
        final List<String> fields = _splitAssLine(line, styleFormat.length);
        final int nameIndex = styleFormat.indexOf('name');
        final int fontIndex = styleFormat.indexOf('fontname');
        if (nameIndex != -1 &&
            fontIndex != -1 &&
            nameIndex < fields.length &&
            fontIndex < fields.length) {
          styleFonts[fields[nameIndex].trim()] = fields[fontIndex].trim();
        }
        continue;
      }
      if (section == '[events]' &&
          trimmed.toLowerCase().startsWith('format:')) {
        eventFormat = _parseFormat(line);
        continue;
      }
      if (section == '[events]' &&
          trimmed.toLowerCase().startsWith('dialogue:')) {
        final List<String> fields = _splitAssLine(line, eventFormat.length);
        final int styleIndex = eventFormat.indexOf('style');
        final int textIndex = eventFormat.indexOf('text');
        if (styleIndex == -1 ||
            textIndex == -1 ||
            styleIndex >= fields.length ||
            textIndex >= fields.length) {
          continue;
        }
        final String defaultFont =
            styleFonts[fields[styleIndex].trim()] ?? '__default__';
        _indexAssDialogueText(fields[textIndex], defaultFont, result);
      }
    }
    return result;
  }

  void _indexAssDialogueText(
    String text,
    String defaultFont,
    Map<String, Set<int>> result,
  ) {
    String currentFont = defaultFont;
    var index = 0;
    while (index < text.length) {
      final int open = text.indexOf('{', index);
      if (open == -1) {
        _addTextCodepoints(result, currentFont, text.substring(index));
        break;
      }
      _addTextCodepoints(result, currentFont, text.substring(index, open));
      final int close = text.indexOf('}', open + 1);
      if (close == -1) {
        break;
      }
      final String? overrideFont = _extractLastFontOverride(
        text.substring(open + 1, close),
      );
      if (overrideFont != null) {
        currentFont = overrideFont;
      }
      index = close + 1;
    }
  }

  String? _extractLastFontOverride(String block) {
    String? result;
    var index = 0;
    while (index < block.length) {
      final int tag = block.indexOf(r'\fn', index);
      if (tag == -1) {
        break;
      }
      final int start = tag + 3;
      var end = start;
      while (end < block.length && block[end] != r'\') {
        end++;
      }
      result = block.substring(start, end).trim();
      index = end;
    }
    return result == null || result.isEmpty ? null : result;
  }

  void _addTextCodepoints(
    Map<String, Set<int>> result,
    String fontName,
    String text,
  ) {
    final String normalized = normalizeFontName(fontName);
    final bool vertical = fontName.trimLeft().startsWith('@');
    final Set<int> target = result.putIfAbsent(normalized, () => <int>{});
    for (final int codepoint in text.runes) {
      target.add(codepoint);
      if (vertical) {
        final int? mapped = kVertMappingTable[codepoint];
        if (mapped != null) {
          target.add(mapped);
        }
      }
    }
  }

  Set<int> _visibleCodepoints(String text) {
    return text.runes.toSet();
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

  void _appendNecessaryCodepoints(Set<int> codepoints) {
    for (var cp = 0x20; cp <= 0x7E; cp++) {
      codepoints.add(cp);
    }
    codepoints
      ..add(0x0A)
      ..add(0x0D)
      ..add(0x09)
      ..add(0xFF1F)
      ..add(0xFF20);
    for (var cp = 0x41; cp <= 0x5A; cp++) {
      codepoints
        ..add(cp)
        ..add(cp + 65248);
    }
    for (var cp = 0x61; cp <= 0x7A; cp++) {
      codepoints
        ..add(cp)
        ..add(cp + 65248);
    }
    for (var cp = 0x30; cp <= 0x39; cp++) {
      codepoints
        ..add(cp)
        ..add(cp + 65248);
    }
  }

  void _throwOnDuplicateFonts(List<ResolvedFontFile> candidates) {
    final Map<String, List<ResolvedFontFile>> buckets =
        <String, List<ResolvedFontFile>>{};
    for (final ResolvedFontFile font in candidates) {
      for (final String familyName in font.familyNames) {
        final String key = <Object>[
          normalizeFontName(familyName),
          font.bold,
          font.italic,
          font.weight,
          font.trackIndex,
          font.maxpNumGlyphs,
        ].join('|');
        buckets.putIfAbsent(key, () => <ResolvedFontFile>[]).add(font);
      }
    }
    for (final List<ResolvedFontFile> bucket in buckets.values) {
      if (bucket.length >= 2) {
        throw Exception(
          '字体源中存在重复字体: ${bucket.map((ResolvedFontFile f) => f.fileName).join(', ')}',
        );
      }
    }
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
    return utf8.decode(raw);
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

  Future<List<String>> extractInputAttachmentStreams(
    MediaInfo info,
    List<MediaStreamEntry> attachments,
    String outputDir,
  ) async {
    final List<MediaStreamEntry> allInputAttachments = info.streams
        .where(
          (MediaStreamEntry stream) =>
              stream.origin == StreamOrigin.input &&
              stream.kind == StreamKind.attachment,
        )
        .toList();
    final List<String> args = <String>[
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
    ];
    final List<String> outputs = <String>[];
    for (final MediaStreamEntry attachment in attachments) {
      final int attachmentStreamIndex = allInputAttachments.indexWhere(
        (MediaStreamEntry stream) => stream.index == attachment.index,
      );
      if (attachmentStreamIndex == -1) {
        continue;
      }
      final String rawFileName =
          attachment.attachmentFileName?.trim().isNotEmpty == true
          ? attachment.attachmentFileName!.trim()
          : 'attachment_${attachment.index}.${attachment.codec.trim().isEmpty ? 'bin' : attachment.codec}';
      final String outputPath = p.join(
        outputDir,
        '${_sanitizeFileNameComponent(p.basenameWithoutExtension(info.displayName))}.attachment${attachment.index}_${_sanitizeFileNameComponent(rawFileName)}',
      );
      outputs.add(outputPath);
      args.addAll(<String>[
        '-dump_attachment:t:$attachmentStreamIndex',
        outputPath,
      ]);
    }
    if (outputs.isEmpty) {
      return outputs;
    }
    final ProcessResult extraction = await Process.run(
      ffmpegPath!,
      <String>[...args, '-i', info.inputPath, '-f', 'null', '-'],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (extraction.exitCode != 0) {
      throw Exception('抽取附件失败: ${extraction.stderr}');
    }
    for (final String output in outputs) {
      if (!File(output).existsSync()) {
        throw Exception('抽取附件失败: 未生成 ${p.basename(output)}');
      }
    }
    return outputs;
  }

  Future<List<String>> inspectSource(String source) async {
    final String extension = p.extension(source).toLowerCase();
    if (isFontFile(source)) {
      return <String>[p.basename(source)];
    }
    if (extension == '.zip') {
      final InputFileStream input = InputFileStream(source);
      try {
        final Archive archive = ZipDecoder().decodeStream(input);
        return archive.files
            .where((ArchiveFile file) => file.isFile && isFontFile(file.name))
            .map((ArchiveFile file) => file.name)
            .toList();
      } finally {
        input.close();
      }
    }
    if (<String>{'.7z', '.rar'}.contains(extension) &&
        sevenZipPath != null &&
        sevenZipPath!.isNotEmpty) {
      final ProcessResult listing = await _runSevenZipWithAdaptiveEncoding(
        <String>['l', '-slt', source],
      );
      if (listing.exitCode != 0) {
        return <String>[];
      }
      final List<String> entries = <String>[];
      for (final String line in listing.stdout.toString().split(
        RegExp(r'\r?\n'),
      )) {
        final String trimmed = line.trim();
        if (!trimmed.startsWith('Path = ')) {
          continue;
        }
        final String value = trimmed.substring('Path = '.length).trim();
        if (value.isEmpty || value == source || value == p.basename(source)) {
          continue;
        }
        if (isFontFile(value)) {
          entries.add(value);
        }
      }
      return entries;
    }
    return <String>[];
  }

  Future<ProcessResult> _runSevenZipWithAdaptiveEncoding(
    List<String> args,
  ) async {
    final List<({String switchValue, Encoding encoding})> candidates =
        <({String switchValue, Encoding encoding})>[
          (switchValue: '-sccUTF-8', encoding: utf8),
          (switchValue: '-sccWIN', encoding: systemEncoding),
          (switchValue: '-sccDOS', encoding: systemEncoding),
        ];
    ProcessResult? lastResult;
    Object? lastError;
    for (final ({String switchValue, Encoding encoding}) candidate
        in candidates) {
      try {
        final ProcessResult result = await Process.run(
          sevenZipPath!,
          <String>[...args, candidate.switchValue],
          stdoutEncoding: candidate.encoding,
          stderrEncoding: candidate.encoding,
        );
        if (result.exitCode == 0) {
          return result;
        }
        lastResult = result;
        final String stderrText = result.stderr.toString();
        if (!stderrText.contains('Incorrect command line') &&
            !stderrText.contains('Unsupported command')) {
          return result;
        }
      } catch (error) {
        lastError = error;
      }
    }
    if (lastResult != null) {
      return lastResult;
    }
    throw lastError ?? Exception('7z 执行失败');
  }

  String _sanitizeFileNameComponent(String value) {
    final String sanitized = value
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim();
    return sanitized.isEmpty ? 'stream' : sanitized;
  }
}
