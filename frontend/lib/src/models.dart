enum StreamKind { video, audio, subtitle, attachment, data, unknown }

enum StreamOrigin { input, externalSubtitle }

enum ExportProfile { hardsubMp4, muxMkv }

enum TaskStatus { queued, running, success, failed, cancelled }

enum CompressionMode { generic, episodic }

enum HardwareMode { auto, software, nvenc, qsv, amf }

class RuntimeToolInfo {
  const RuntimeToolInfo({
    required this.name,
    required this.path,
    required this.required,
  });

  final String name;
  final String? path;
  final bool required;

  bool get available => path != null && path!.isNotEmpty;
}

class RuntimeDiagnostics {
  const RuntimeDiagnostics({
    required this.ffmpeg,
    required this.ffprobe,
    required this.mkvpropedit,
    required this.sevenZip,
    required this.hwaccels,
    required this.videoEncoders,
  });

  final RuntimeToolInfo ffmpeg;
  final RuntimeToolInfo ffprobe;
  final RuntimeToolInfo mkvpropedit;
  final RuntimeToolInfo sevenZip;
  final List<String> hwaccels;
  final Set<String> videoEncoders;

  List<String> get hardwareVideoEncoderLabels => <String>[
        if (videoEncoders.contains('h264_nvenc')) 'NVENC AVC',
        if (videoEncoders.contains('hevc_nvenc')) 'NVENC HEVC',
        if (videoEncoders.contains('h264_qsv')) 'QSV AVC',
        if (videoEncoders.contains('hevc_qsv')) 'QSV HEVC',
        if (videoEncoders.contains('h264_amf')) 'AMF AVC',
        if (videoEncoders.contains('hevc_amf')) 'AMF HEVC',
      ];

  bool get hasNvenc =>
      videoEncoders.contains('h264_nvenc') ||
      videoEncoders.contains('hevc_nvenc');

  bool get hasQsv =>
      videoEncoders.contains('h264_qsv') || videoEncoders.contains('hevc_qsv');

  bool get hasAmf =>
      videoEncoders.contains('h264_amf') || videoEncoders.contains('hevc_amf');

  static const empty = RuntimeDiagnostics(
    ffmpeg: RuntimeToolInfo(name: 'ffmpeg', path: null, required: true),
    ffprobe: RuntimeToolInfo(name: 'ffprobe', path: null, required: true),
    mkvpropedit: RuntimeToolInfo(name: 'mkvpropedit', path: null, required: false),
    sevenZip: RuntimeToolInfo(name: '7z', path: null, required: false),
    hwaccels: <String>[],
    videoEncoders: <String>{},
  );
}

class SubtitleBinding {
  const SubtitleBinding({
    required this.key,
    required this.label,
    required this.languageCode,
    required this.regionCode,
    required this.trackName,
    this.filePath,
  });

  final String key;
  final String label;
  final String languageCode;
  final String regionCode;
  final String trackName;
  final String? filePath;

  SubtitleBinding copyWith({
    String? languageCode,
    String? regionCode,
    String? trackName,
    String? filePath,
    bool clearFile = false,
  }) {
    return SubtitleBinding(
      key: key,
      label: label,
      languageCode: languageCode ?? this.languageCode,
      regionCode: regionCode ?? this.regionCode,
      trackName: trackName ?? this.trackName,
      filePath: clearFile ? null : filePath ?? this.filePath,
    );
  }
}

class ChapterEntry {
  const ChapterEntry({
    required this.title,
    required this.start,
    required this.end,
  });

  final String title;
  final Duration start;
  final Duration end;

  ChapterEntry copyWith({
    String? title,
    Duration? start,
    Duration? end,
  }) {
    return ChapterEntry(
      title: title ?? this.title,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}

class MediaStreamEntry {
  const MediaStreamEntry({
    required this.index,
    required this.kind,
    required this.codec,
    required this.title,
    required this.language,
    required this.regionCode,
    required this.enabled,
    required this.isDefault,
    required this.isForced,
    required this.origin,
    required this.sourceLabel,
    this.attachmentFileName,
    this.attachmentMimeType,
    this.externalPath,
  });

  final int index;
  final StreamKind kind;
  final String codec;
  final String title;
  final String language;
  final String regionCode;
  final bool enabled;
  final bool isDefault;
  final bool isForced;
  final StreamOrigin origin;
  final String sourceLabel;
  final String? attachmentFileName;
  final String? attachmentMimeType;
  final String? externalPath;

  MediaStreamEntry copyWith({
    String? codec,
    String? title,
    String? language,
    String? regionCode,
    bool? enabled,
    bool? isDefault,
    bool? isForced,
    String? sourceLabel,
    String? attachmentFileName,
    String? attachmentMimeType,
    String? externalPath,
  }) {
    return MediaStreamEntry(
      index: index,
      kind: kind,
      codec: codec ?? this.codec,
      title: title ?? this.title,
      language: language ?? this.language,
      regionCode: regionCode ?? this.regionCode,
      enabled: enabled ?? this.enabled,
      isDefault: isDefault ?? this.isDefault,
      isForced: isForced ?? this.isForced,
      origin: origin,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      attachmentFileName: attachmentFileName ?? this.attachmentFileName,
      attachmentMimeType: attachmentMimeType ?? this.attachmentMimeType,
      externalPath: externalPath ?? this.externalPath,
    );
  }
}

class MediaInfo {
  const MediaInfo({
    required this.inputPath,
    required this.displayName,
    required this.duration,
    required this.width,
    required this.height,
    required this.fps,
    required this.streams,
    required this.chapters,
  });

  final String inputPath;
  final String displayName;
  final Duration duration;
  final int width;
  final int height;
  final double fps;
  final List<MediaStreamEntry> streams;
  final List<ChapterEntry> chapters;

  MediaInfo copyWith({
    List<MediaStreamEntry>? streams,
    List<ChapterEntry>? chapters,
  }) {
    return MediaInfo(
      inputPath: inputPath,
      displayName: displayName,
      duration: duration,
      width: width,
      height: height,
      fps: fps,
      streams: streams ?? this.streams,
      chapters: chapters ?? this.chapters,
    );
  }
}

class EncoderTuning {
  const EncoderTuning({
    required this.key,
    required this.title,
    required this.preset,
    required this.tune,
    required this.presets,
    required this.tunes,
  });

  final String key;
  final String title;
  final String preset;
  final String tune;
  final List<String> presets;
  final List<String> tunes;

  EncoderTuning copyWith({
    String? preset,
    String? tune,
  }) {
    return EncoderTuning(
      key: key,
      title: title,
      preset: preset ?? this.preset,
      tune: tune ?? this.tune,
      presets: presets,
      tunes: tunes,
    );
  }
}

class ExportTask {
  const ExportTask({
    required this.id,
    required this.profile,
    required this.bindingKeys,
    required this.label,
    required this.outputPath,
    required this.status,
    required this.progress,
    required this.currentStep,
    required this.commandPreview,
    required this.log,
    this.error,
  });

  final String id;
  final ExportProfile profile;
  final List<String> bindingKeys;
  final String label;
  final String outputPath;
  final TaskStatus status;
  final double progress;
  final String currentStep;
  final String commandPreview;
  final String log;
  final String? error;

  ExportTask copyWith({
    TaskStatus? status,
    double? progress,
    String? currentStep,
    String? commandPreview,
    String? log,
    String? error,
  }) {
    return ExportTask(
      id: id,
      profile: profile,
      bindingKeys: bindingKeys,
      label: label,
      outputPath: outputPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      currentStep: currentStep ?? this.currentStep,
      commandPreview: commandPreview ?? this.commandPreview,
      log: log ?? this.log,
      error: error ?? this.error,
    );
  }
}

class ResolvedFontFile {
  const ResolvedFontFile({
    required this.path,
    required this.fileName,
    required this.mimeType,
  });

  final String path;
  final String fileName;
  final String mimeType;
}

class CommandStep {
  const CommandStep({
    required this.executable,
    required this.arguments,
    required this.description,
  });

  final String executable;
  final List<String> arguments;
  final String description;
}

class TaskPlan {
  const TaskPlan({
    required this.outputPath,
    required this.commandPreview,
    required this.steps,
    required this.workingDirectory,
    required this.expectedDuration,
  });

  final String outputPath;
  final String commandPreview;
  final List<CommandStep> steps;
  final String workingDirectory;
  final Duration expectedDuration;
}
