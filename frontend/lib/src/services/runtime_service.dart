import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../models.dart';

class RuntimeService {
  static Future<RuntimeDiagnostics> detect({
    required String? customRuntimeDirectory,
    required String? customRuntimeExecutable,
  }) async {
    final String currentDir = Directory.current.path;
    final String parentDir = p.dirname(currentDir);
    final List<String> preferredBinDirs = <String>[
      p.join(currentDir, 'bin'),
      p.join(parentDir, 'bin'),
    ];
    final List<String> customSearchDirs = _customRuntimeSearchDirectories(
      customRuntimeDirectory: customRuntimeDirectory,
      customRuntimeExecutable: customRuntimeExecutable,
    );
    final String? ffmpeg = _findExecutable(
      executableName: 'ffmpeg.exe',
      searchDirectories: preferredBinDirs,
      environmentVariable: 'FFMPEG_BIN_DIR',
    );
    final String? ffprobe = _findExecutable(
      executableName: 'ffprobe.exe',
      searchDirectories: preferredBinDirs,
      environmentVariable: 'FFMPEG_BIN_DIR',
    );
    final String? mkvpropedit = _findExecutable(
      executableName: 'mkvpropedit.exe',
      searchDirectories: <String>[
        ...preferredBinDirs,
        r'C:\Program Files\MKVToolNix',
        r'C:\Program Files (x86)\MKVToolNix',
      ],
      environmentVariable: 'MKVTOOLNIX_BIN_DIR',
    );
    final String? sevenZip = _findExecutable(
      executableName: '7z.exe',
      searchDirectories: <String>[
        ...preferredBinDirs,
        r'C:\Program Files\7-Zip',
        r'C:\Program Files (x86)\7-Zip',
      ],
      environmentVariable: null,
      pathFallbacks: <String>['7z.exe', '7za.exe', '7zz.exe'],
    );
    final String? customFfmpeg = _resolveCustomRuntime(
      executableName: 'ffmpeg.exe',
      customRuntimeDirectory: customRuntimeDirectory,
      customRuntimeExecutable: customRuntimeExecutable,
    );
    final String? customFfprobe = _resolveCustomRuntime(
      executableName: 'ffprobe.exe',
      customRuntimeDirectory: customRuntimeDirectory,
      customRuntimeExecutable: customRuntimeExecutable,
    );
    final String? customMkvpropedit = _resolveCustomRuntime(
      executableName: 'mkvpropedit.exe',
      customRuntimeDirectory: customRuntimeDirectory,
      customRuntimeExecutable: customRuntimeExecutable,
    );
    final String? custom7z = _resolveCustomRuntime(
      executableName: '7z.exe',
      customRuntimeDirectory: customRuntimeDirectory,
      customRuntimeExecutable: customRuntimeExecutable,
    );
    final String? pyftsubset = _findExecutable(
      executableName: 'pyftsubset.exe',
      searchDirectories: <String>[...customSearchDirs, ...preferredBinDirs],
      environmentVariable: 'FONTTOOLS_BIN_DIR',
      pathFallbacks: <String>['pyftsubset.exe', 'pyftsubset'],
    );
    final String? ttx = _findExecutable(
      executableName: 'ttx.exe',
      searchDirectories: <String>[...customSearchDirs, ...preferredBinDirs],
      environmentVariable: 'FONTTOOLS_BIN_DIR',
      pathFallbacks: <String>['ttx.exe', 'ttx'],
    );
    final String? resolvedFfmpeg = customFfmpeg ?? ffmpeg;
    final String? resolvedFfprobe = customFfprobe ?? ffprobe;
    final String? resolvedMkvpropedit = customMkvpropedit ?? mkvpropedit;
    final String? resolved7z = custom7z ?? sevenZip;
    List<String> hwaccels = <String>[];
    Set<String> encoders = <String>{};
    Set<String> audioEncoders = <String>{};
    bool hasZscale = false;
    if (resolvedFfmpeg != null) {
      hwaccels = await _readFfmpegOutput(resolvedFfmpeg, <String>[
        '-hide_banner',
        '-hwaccels',
      ]);
      encoders = await _probeHardwareVideoEncoders(resolvedFfmpeg);
      final List<String> filterLines = await _readFfmpegOutput(
        resolvedFfmpeg,
        <String>['-hide_banner', '-filters'],
      );
      hasZscale = _parseHasZscale(filterLines);
      final List<String> encoderLines = await _readFfmpegOutput(
        resolvedFfmpeg,
        <String>['-hide_banner', '-encoders'],
      );
      audioEncoders = _parseAudioEncoders(encoderLines);
    }
    final Version? fontToolsVersion = ttx == null
        ? null
        : await _probeFontToolsVersion(ttx);
    return RuntimeDiagnostics(
      ffmpeg: RuntimeToolInfo(
        name: 'ffmpeg',
        path: resolvedFfmpeg,
        required: true,
      ),
      ffprobe: RuntimeToolInfo(
        name: 'ffprobe',
        path: resolvedFfprobe,
        required: true,
      ),
      mkvpropedit: RuntimeToolInfo(
        name: 'mkvpropedit',
        path: resolvedMkvpropedit,
        required: false,
      ),
      sevenZip: RuntimeToolInfo(name: '7z', path: resolved7z, required: false),
      pyftsubset: RuntimeToolInfo(
        name: 'pyftsubset',
        path: pyftsubset,
        required: false,
      ),
      ttx: RuntimeToolInfo(name: 'ttx', path: ttx, required: false),
      fontToolsVersion: fontToolsVersion,
      hwaccels: hwaccels,
      videoEncoders: encoders,
      hasZscale: hasZscale,
      audioEncoders: audioEncoders,
    );
  }

  @visibleForTesting
  static bool parseHasZscaleForTesting(List<String> lines) {
    return _parseHasZscale(lines);
  }

  @visibleForTesting
  static Set<String> parseAudioEncodersForTesting(List<String> lines) {
    return _parseAudioEncoders(lines);
  }

  static Future<List<String>> _readFfmpegOutput(
    String executable,
    List<String> args,
  ) async {
    final ProcessResult result = await Process.run(
      executable,
      args,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      return <String>[];
    }
    return '${result.stdout}\n${result.stderr}'
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList();
  }

  static Future<Set<String>> _probeHardwareVideoEncoders(
    String ffmpegPath,
  ) async {
    final List<({String encoder, String size})> candidates =
        <({String encoder, String size})>[
          (encoder: 'h264_nvenc', size: '256x256'),
          (encoder: 'hevc_nvenc', size: '256x256'),
          (encoder: 'h264_qsv', size: '1280x720'),
          (encoder: 'hevc_qsv', size: '1280x720'),
          (encoder: 'h264_amf', size: '1280x720'),
          (encoder: 'hevc_amf', size: '1280x720'),
        ];
    final Set<String> result = <String>{};
    for (final ({String encoder, String size}) candidate in candidates) {
      final ProcessResult probe = await Process.run(
        ffmpegPath,
        <String>[
          '-hide_banner',
          '-loglevel',
          'error',
          '-f',
          'lavfi',
          '-i',
          'color=c=black:s=${candidate.size}:r=1',
          '-frames:v',
          '1',
          '-an',
          '-c:v',
          candidate.encoder,
          '-f',
          'null',
          '-',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (probe.exitCode == 0) {
        result.add(candidate.encoder);
      }
    }
    return result;
  }

  static bool _parseHasZscale(List<String> lines) {
    return lines.any((String line) => RegExp(r'\bzscale\b').hasMatch(line));
  }

  static Set<String> _parseAudioEncoders(List<String> lines) {
    const Set<String> supported = <String>{
      'aac',
      'libfdk_aac',
      'libopus',
      'flac',
      'ac3',
      'eac3',
    };
    final Set<String> result = <String>{};
    for (final String line in lines) {
      final Iterable<RegExpMatch> matches = RegExp(
        r'\b(aac|libfdk_aac|libopus|flac|ac3|eac3)\b',
      ).allMatches(line);
      for (final RegExpMatch match in matches) {
        final String encoder = match.group(1)!;
        if (supported.contains(encoder)) {
          result.add(encoder);
        }
      }
    }
    return result;
  }

  static Future<Version?> _probeFontToolsVersion(String ttxPath) async {
    final ProcessResult result = await Process.run(
      ttxPath,
      <String>['--version'],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      return null;
    }
    return Version.tryParse('${result.stdout}\n${result.stderr}');
  }

  static String? _findExecutable({
    required String executableName,
    required List<String> searchDirectories,
    required String? environmentVariable,
    List<String>? pathFallbacks,
  }) {
    final String? envDir = environmentVariable == null
        ? null
        : Platform.environment[environmentVariable];
    final List<String> candidates = <String>[
      if (envDir != null && envDir.isNotEmpty) p.join(envDir, executableName),
      ...searchDirectories.map((String dir) => p.join(dir, executableName)),
    ];
    for (final String candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    for (final String pathCandidate
        in pathFallbacks ?? <String>[executableName]) {
      final String? resolved = _resolveFromPath(pathCandidate);
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  static String? _resolveCustomRuntime({
    required String executableName,
    required String? customRuntimeDirectory,
    required String? customRuntimeExecutable,
  }) {
    final String? executablePath = customRuntimeExecutable;
    if (executablePath != null && executablePath.isNotEmpty) {
      if (p.basename(executablePath).toLowerCase() ==
          executableName.toLowerCase()) {
        return executablePath;
      }
    }
    final String? path = customRuntimeDirectory;
    if (path == null || path.isEmpty) {
      return null;
    }
    try {
      final Iterable<File> files = Directory(
        path,
      ).listSync(recursive: true).whereType<File>();
      for (final File file in files) {
        if (p.basename(file.path).toLowerCase() ==
            executableName.toLowerCase()) {
          return file.path;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static List<String> _customRuntimeSearchDirectories({
    required String? customRuntimeDirectory,
    required String? customRuntimeExecutable,
  }) {
    final List<String> result = <String>[];
    if (customRuntimeDirectory != null && customRuntimeDirectory.isNotEmpty) {
      result.add(customRuntimeDirectory);
      result.add(p.join(customRuntimeDirectory, 'bin'));
    }
    if (customRuntimeExecutable != null && customRuntimeExecutable.isNotEmpty) {
      result.add(p.dirname(customRuntimeExecutable));
    }
    return result;
  }

  static String? _resolveFromPath(String executable) {
    final List<String> entries = (Platform.environment['PATH'] ?? '')
        .split(';')
        .where((String item) => item.isNotEmpty)
        .toList();
    for (final String entry in entries) {
      final String candidate = p.join(entry, executable);
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }
}

String buildStartupMessage(RuntimeDiagnostics runtime) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('硬件编码/解码探测已完成。')
    ..writeln('自动模式回退顺序: NVENC -> QSV -> AMF -> SOFTWARE')
    ..writeln()
    ..writeln('FFmpeg: ${runtime.ffmpeg.path ?? '未找到'}')
    ..writeln('FFprobe: ${runtime.ffprobe.path ?? '未找到'}')
    ..writeln('MKVToolNix: ${runtime.mkvpropedit.path ?? '未找到'}')
    ..writeln('7-Zip: ${runtime.sevenZip.path ?? '未找到'}')
    ..writeln('pyftsubset: ${runtime.pyftsubset.path ?? '未找到'}')
    ..writeln('ttx: ${runtime.ttx.path ?? '未找到'}')
    ..writeln(
      'fonttools: ${runtime.fontToolsVersion?.toString() ?? '未知'}',
    )
    ..writeln(
      runtime.hasZscale ? 'zscale: 可用' : '当前 ffmpeg 未启用 libzimg，色调映射不可用',
    )
    ..writeln()
    ..writeln(
      '可用硬件加速视频编码探测结果: ${runtime.hardwareVideoEncoderLabels.isEmpty ? '无' : runtime.hardwareVideoEncoderLabels.join(', ')}',
    )
    ..writeln(
      '可用硬件加速视频解码后端: ${runtime.hardwareDecodeLabels.isEmpty ? '无' : runtime.hardwareDecodeLabels.join(', ')}',
    );
  return buffer.toString();
}
