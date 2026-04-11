import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../models.dart';
import '../utils/export_utils.dart';

class FontAssetService {
  const FontAssetService({
    required this.ffmpegPath,
    required this.sevenZipPath,
  });

  final String? ffmpegPath;
  final String? sevenZipPath;

  Future<List<ResolvedFontFile>> resolveFontFiles(
    List<String> importedFontSources,
    String tempDir,
  ) async {
    final List<ResolvedFontFile> result = <ResolvedFontFile>[];
    for (final String source in importedFontSources) {
      final String extension = p.extension(source).toLowerCase();
      if (<String>{'.ttf', '.otf', '.ttc'}.contains(extension)) {
        result.add(
          ResolvedFontFile(
            path: source,
            fileName: p.basename(source),
            mimeType: mimeTypeForFont(source),
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
          result.add(
            ResolvedFontFile(
              path: outPath,
              fileName: p.basename(outPath),
              mimeType: mimeTypeForFont(outPath),
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
            result.add(
              ResolvedFontFile(
                path: file.path,
                fileName: p.basename(file.path),
                mimeType: mimeTypeForFont(file.path),
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
      result.add(
        ResolvedFontFile(
          path: outPath,
          fileName: fileName,
          mimeType: attachment.attachmentMimeType?.trim().isNotEmpty == true
              ? attachment.attachmentMimeType!.trim()
              : mimeTypeForAttachment(attachment),
        ),
      );
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
