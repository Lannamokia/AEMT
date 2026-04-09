import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

class AemtController extends ChangeNotifier {
  AemtController() {
    videoController = VideoController(player);
  }

  final Player player = Player(
    configuration: const PlayerConfiguration(libass: true),
  );
  late final VideoController videoController;

  RuntimeDiagnostics diagnostics = RuntimeDiagnostics.empty;
  MediaInfo? mediaInfo;
  SubtitleBinding simplifiedBinding = const SubtitleBinding(
    key: 'chs',
    label: 'CHS 字幕',
    languageCode: 'zh',
    regionCode: 'CN',
    trackName: 'JPSC',
  );
  SubtitleBinding traditionalBinding = const SubtitleBinding(
    key: 'cht',
    label: 'CHT 字幕',
    languageCode: 'zh',
    regionCode: 'TW',
    trackName: 'JPTC',
  );
  final List<SubtitleBinding> customBindings = <SubtitleBinding>[];
  final Set<String> selectedHardsubBindingKeys = <String>{'chs', 'cht'};
  final Set<String> selectedMuxBindingKeys = <String>{'chs', 'cht'};
  List<String> importedFontSources = <String>[];
  CompressionMode compressionMode = CompressionMode.generic;
  HardwareMode hardwareMode = HardwareMode.auto;
  bool initializing = false;
  bool analyzing = false;
  bool queueRunning = false;
  bool stopQueueRequested = false;
  bool showStartupDialog = false;
  String startupMessage = '';
  String? statusMessage;
  String outputDirectory = '';
  String? customRuntimeDirectory;
  String? customRuntimeExecutable;
  String outputFileNameOverride = '';
  String releaseGroup = '';
  String titleOverride = '';
  String episodeNumber = '';
  String sourceLabel = '';
  String outputResolution = '';
  String outputFps = '';
  String avcBitrate = '2500k';
  String avcMaxrate = '3750k';
  String hevcBitrate = '2000k';
  String hevcMaxrate = '3000k';
  String previewSubtitleKey = 'off';
  bool streamExtractionRunning = false;
  String? streamExtractionMessage;
  Process? _activeProcess;
  final Set<int> removedEmbeddedSubtitleIndexes = <int>{};
  final Set<String> selectedStreamExtractionKeys = <String>{};
  final Map<int, String> _previewSubtitleCache = <int, String>{};
  Directory? _previewSubtitleTempDirectory;
  final List<ExportTask> tasks = <ExportTask>[];
  final Map<String, List<String>> importedFontEntries =
      <String, List<String>>{};
  final Map<String, EncoderTuning> encoderTunings = <String, EncoderTuning>{
    'libx264': const EncoderTuning(
      key: 'libx264',
      title: '软件 AVC / libx264',
      preset: 'slow',
      tune: '默认',
      presets: <String>[
        'ultrafast',
        'superfast',
        'veryfast',
        'faster',
        'fast',
        'medium',
        'slow',
        'slower',
        'veryslow',
      ],
      tunes: <String>['默认', 'film', 'animation', 'grain', 'fastdecode'],
    ),
    'libx265': const EncoderTuning(
      key: 'libx265',
      title: '软件 HEVC / libx265',
      preset: 'slow',
      tune: '默认',
      presets: <String>[
        'ultrafast',
        'superfast',
        'veryfast',
        'faster',
        'fast',
        'medium',
        'slow',
        'slower',
        'veryslow',
      ],
      tunes: <String>['默认', 'psnr', 'ssim', 'grain', 'fastdecode'],
    ),
    'h264_nvenc': const EncoderTuning(
      key: 'h264_nvenc',
      title: 'NVENC AVC / h264_nvenc',
      preset: 'p5',
      tune: '默认',
      presets: <String>['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'],
      tunes: <String>['默认', 'hq', 'll', 'ull', 'lossless'],
    ),
    'hevc_nvenc': const EncoderTuning(
      key: 'hevc_nvenc',
      title: 'NVENC HEVC / hevc_nvenc',
      preset: 'p5',
      tune: '默认',
      presets: <String>['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'],
      tunes: <String>['默认', 'hq', 'll', 'ull', 'lossless'],
    ),
    'h264_qsv': const EncoderTuning(
      key: 'h264_qsv',
      title: 'QSV AVC / h264_qsv',
      preset: 'medium',
      tune: '默认',
      presets: <String>['veryfast', 'faster', 'fast', 'medium', 'slow'],
      tunes: <String>['默认', 'balanced', 'quality', 'speed'],
    ),
    'hevc_qsv': const EncoderTuning(
      key: 'hevc_qsv',
      title: 'QSV HEVC / hevc_qsv',
      preset: 'medium',
      tune: '默认',
      presets: <String>['veryfast', 'faster', 'fast', 'medium', 'slow'],
      tunes: <String>['默认', 'balanced', 'quality', 'speed'],
    ),
    'h264_amf': const EncoderTuning(
      key: 'h264_amf',
      title: 'AMF AVC / h264_amf',
      preset: 'quality',
      tune: '默认',
      presets: <String>['speed', 'balanced', 'quality'],
      tunes: <String>['默认', 'high_quality', 'lowlatency'],
    ),
    'hevc_amf': const EncoderTuning(
      key: 'hevc_amf',
      title: 'AMF HEVC / hevc_amf',
      preset: 'quality',
      tune: '默认',
      presets: <String>['speed', 'balanced', 'quality'],
      tunes: <String>['默认', 'high_quality', 'lowlatency'],
    ),
  };

  List<SubtitleBinding> get allBindings => <SubtitleBinding>[
    simplifiedBinding,
    traditionalBinding,
    ...customBindings,
  ];

  Future<void> initialize() async {
    if (initializing) {
      return;
    }
    initializing = true;
    notifyListeners();
    await refreshRuntime(showDialog: true);
    initializing = false;
    notifyListeners();
  }

  Future<void> refreshRuntime({bool showDialog = false}) async {
    diagnostics = await _detectRuntime();
    if (showDialog) {
      showStartupDialog = true;
      startupMessage = _buildStartupMessage(diagnostics);
    }
    notifyListeners();
  }

  Future<void> dismissStartupDialog() async {
    showStartupDialog = false;
    notifyListeners();
  }

  Future<void> pickVideo() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>[
        'mkv',
        'mp4',
        'ts',
        'm2ts',
        'mov',
        'avi',
        'webm',
      ],
    );
    final String? path = result?.files.single.path;
    if (path == null) {
      return;
    }
    await analyzeVideo(path);
  }

  Future<void> analyzeVideo(String path) async {
    if (!diagnostics.ffprobe.available) {
      statusMessage = '缺少 ffprobe，无法解析媒体。';
      notifyListeners();
      return;
    }
    analyzing = true;
    statusMessage = '正在解析媒体信息...';
    notifyListeners();
    try {
      await _resetPreviewSubtitleArtifacts();
      selectedStreamExtractionKeys.clear();
      streamExtractionMessage = null;
      final ProcessResult result = await Process.run(
        diagnostics.ffprobe.path!,
        <String>[
          '-v',
          'error',
          '-show_streams',
          '-show_chapters',
          '-show_format',
          '-print_format',
          'json',
          path,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        throw Exception(result.stderr.toString());
      }
      mediaInfo = _parseMediaInfo(
        path,
        jsonDecode(result.stdout.toString()) as Map<String, dynamic>,
      );
      titleOverride = p.basenameWithoutExtension(path);
      outputFileNameOverride = p.basenameWithoutExtension(path);
      outputResolution = mediaInfo!.width == 0 || mediaInfo!.height == 0
          ? ''
          : '${mediaInfo!.width}x${mediaInfo!.height}';
      outputFps = mediaInfo!.fps <= 0 ? '' : mediaInfo!.fps.toStringAsFixed(3);
      removedEmbeddedSubtitleIndexes.clear();
      outputDirectory = outputDirectory.isEmpty
          ? p.join(p.dirname(path), 'outputs')
          : outputDirectory;
      statusMessage = '已解析 ${mediaInfo!.streams.length} 条流。';
      await player.open(Media(path), play: false);
      await player.setSubtitleTrack(SubtitleTrack.no());
      previewSubtitleKey = 'off';
      _syncExternalSubtitleStreams();
    } catch (error) {
      statusMessage = '解析失败: $error';
    } finally {
      analyzing = false;
      notifyListeners();
    }
  }

  Future<void> pickSubtitle(bool simplified) async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['ass', 'ssa', 'srt'],
    );
    final String? path = result?.files.single.path;
    if (path == null) {
      return;
    }
    _replaceBinding(
      simplified ? 'chs' : 'cht',
      (SubtitleBinding binding) => binding.copyWith(filePath: path),
    );
  }

  Future<void> addCustomSubtitleBinding() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['ass', 'ssa', 'srt'],
    );
    final String? path = result?.files.single.path;
    if (path == null) {
      return;
    }
    final int nextIndex = customBindings.length + 1;
    final String key = 'custom_$nextIndex';
    customBindings.add(
      SubtitleBinding(
        key: key,
        label: '自定义字幕 $nextIndex',
        languageCode: '',
        regionCode: '',
        trackName: '',
        filePath: path,
      ),
    );
    selectedHardsubBindingKeys.add(key);
    selectedMuxBindingKeys.add(key);
    _syncExternalSubtitleStreams();
    notifyListeners();
  }

  Future<void> importFonts() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: <String>['ttf', 'otf', 'ttc', 'zip', '7z', 'rar'],
    );
    if (result == null) {
      return;
    }
    for (final PlatformFile file in result.files) {
      if (file.path != null && !importedFontSources.contains(file.path)) {
        importedFontSources.add(file.path!);
        importedFontEntries[file.path!] = await _inspectFontSource(file.path!);
      }
    }
    notifyListeners();
  }

  Future<void> pickOutputDirectory() async {
    final String? path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.isEmpty) {
      return;
    }
    outputDirectory = path;
    notifyListeners();
  }

  Future<void> pickRuntimeDirectory() async {
    final String? directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath == null || directoryPath.isEmpty) {
      return;
    }
    customRuntimeDirectory = directoryPath;
    await refreshRuntime();
  }

  Future<void> pickRuntimeExecutable() async {
    final FilePickerResult? fileResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['exe'],
    );
    final String? filePath = fileResult?.files.single.path;
    if (filePath == null || filePath.isEmpty) {
      return;
    }
    customRuntimeExecutable = filePath;
    await refreshRuntime();
  }

  Future<void> togglePlayback() async {
    if (player.state.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> seekRelative(Duration delta) async {
    final Duration target = player.state.position + delta;
    await player.seek(target < Duration.zero ? Duration.zero : target);
  }

  Future<void> seekTo(Duration position) async {
    await player.seek(position < Duration.zero ? Duration.zero : position);
  }

  void setCompressionMode(CompressionMode value) {
    compressionMode = value;
    if (mediaInfo != null && value == CompressionMode.generic) {
      outputFileNameOverride = p.basenameWithoutExtension(
        mediaInfo!.displayName,
      );
    }
    notifyListeners();
  }

  void setHardwareMode(HardwareMode value) {
    hardwareMode = value;
    notifyListeners();
  }

  void setReleaseGroup(String value) {
    releaseGroup = value;
    notifyListeners();
  }

  void setTitleOverride(String value) {
    titleOverride = value;
    notifyListeners();
  }

  void setEpisodeNumber(String value) {
    episodeNumber = value;
    notifyListeners();
  }

  void setSourceLabel(String value) {
    sourceLabel = value;
    notifyListeners();
  }

  void setOutputDirectory(String value) {
    outputDirectory = value;
    notifyListeners();
  }

  void setOutputResolution(String value) {
    outputResolution = value;
    notifyListeners();
  }

  void setOutputFps(String value) {
    outputFps = value;
    notifyListeners();
  }

  void setOutputFileNameOverride(String value) {
    outputFileNameOverride = value;
    notifyListeners();
  }

  void setAvcBitrate(String value) {
    avcBitrate = value;
    notifyListeners();
  }

  void setAvcMaxrate(String value) {
    avcMaxrate = value;
    notifyListeners();
  }

  void setHevcBitrate(String value) {
    hevcBitrate = value;
    notifyListeners();
  }

  void setHevcMaxrate(String value) {
    hevcMaxrate = value;
    notifyListeners();
  }

  void updateBindingMeta({
    required String key,
    String? languageCode,
    String? regionCode,
    String? trackName,
  }) {
    _replaceBinding(
      key,
      (SubtitleBinding binding) => binding.copyWith(
        languageCode: languageCode,
        regionCode: regionCode,
        trackName: trackName,
      ),
    );
  }

  void removeFontSource(String path) {
    importedFontSources.remove(path);
    importedFontEntries.remove(path);
    notifyListeners();
  }

  void removeCustomBinding(String key) {
    customBindings.removeWhere((SubtitleBinding binding) => binding.key == key);
    selectedHardsubBindingKeys.remove(key);
    selectedMuxBindingKeys.remove(key);
    _syncExternalSubtitleStreams();
    notifyListeners();
  }

  void toggleHardsubBindingSelection(String key, bool value) {
    if (value) {
      selectedHardsubBindingKeys.add(key);
    } else {
      selectedHardsubBindingKeys.remove(key);
    }
    notifyListeners();
  }

  void toggleMuxBindingSelection(String key, bool value) {
    if (value) {
      selectedMuxBindingKeys.add(key);
    } else {
      selectedMuxBindingKeys.remove(key);
    }
    notifyListeners();
  }

  void removeAllEmbeddedSubtitles() {
    if (mediaInfo == null) {
      return;
    }
    removedEmbeddedSubtitleIndexes.addAll(
      mediaInfo!.streams
          .where(
            (MediaStreamEntry stream) =>
                stream.origin == StreamOrigin.input &&
                stream.kind == StreamKind.subtitle,
          )
          .map((MediaStreamEntry stream) => stream.index),
    );
    mediaInfo = mediaInfo!.copyWith(
      streams: mediaInfo!.streams
          .where(
            (MediaStreamEntry stream) =>
                !(stream.origin == StreamOrigin.input &&
                    stream.kind == StreamKind.subtitle &&
                    removedEmbeddedSubtitleIndexes.contains(stream.index)),
          )
          .toList(),
    );
    notifyListeners();
  }

  Future<void> selectPreviewSubtitle(String value) async {
    final String previousValue = previewSubtitleKey;
    previewSubtitleKey = value;
    notifyListeners();
    try {
      if (value == 'off') {
        await player.setSubtitleTrack(SubtitleTrack.no());
        return;
      }
      if (value.startsWith('external:')) {
        final String key = value.substring('external:'.length);
        final SubtitleBinding? binding = _findBindingByKey(key);
        if (binding?.filePath != null) {
          await player.setSubtitleTrack(
            SubtitleTrack.uri(
              binding!.filePath!,
              title: binding.trackName,
              language: binding.languageCode,
            ),
          );
        }
        return;
      }
      if (value.startsWith('compat:')) {
        final int? streamIndex = int.tryParse(
          value.substring('compat:'.length),
        );
        if (streamIndex == null) {
          throw Exception('无效的兼容预览字幕索引。');
        }
        final MediaStreamEntry stream = _findInputStreamByIndex(streamIndex);
        final String subtitlePath = await _extractPreviewSubtitleToTemp(stream);
        await player.setSubtitleTrack(
          SubtitleTrack.uri(
            subtitlePath,
            title: stream.title.isNotEmpty
                ? stream.title
                : '内封字幕 ${stream.index}',
            language: stream.language,
          ),
        );
        return;
      }
      if (value.startsWith('embedded:')) {
        final String id = value.substring('embedded:'.length);
        final Iterable<SubtitleTrack> matches = player.state.tracks.subtitle
            .where((SubtitleTrack track) => track.id == id);
        if (matches.isNotEmpty) {
          final SubtitleTrack track = matches.first;
          await player.setSubtitleTrack(track);
          return;
        }
      }
      throw Exception('预览播放器未暴露该字幕轨。');
    } catch (error) {
      previewSubtitleKey = previousValue == value ? 'off' : previousValue;
      await player.setSubtitleTrack(SubtitleTrack.no());
      statusMessage = '字幕预览失败: $error';
      notifyListeners();
    }
  }

  void updateChapterTitle(int index, String value) {
    _updateChapter(
      index,
      (ChapterEntry chapter) => chapter.copyWith(title: value),
    );
  }

  void updateChapterStart(int index, String value) {
    final Duration? parsed = parseTimestamp(value);
    if (parsed != null) {
      _updateChapter(
        index,
        (ChapterEntry chapter) => chapter.copyWith(start: parsed),
      );
    }
  }

  void updateChapterEnd(int index, String value) {
    final Duration? parsed = parseTimestamp(value);
    if (parsed != null) {
      _updateChapter(
        index,
        (ChapterEntry chapter) => chapter.copyWith(end: parsed),
      );
    }
  }

  void addChapter() {
    if (mediaInfo == null) {
      return;
    }
    final List<ChapterEntry> next = List<ChapterEntry>.from(
      mediaInfo!.chapters,
    );
    next.add(
      ChapterEntry(
        title: 'Episode',
        start: next.isEmpty ? Duration.zero : next.last.end,
        end: mediaInfo!.duration,
      ),
    );
    mediaInfo = mediaInfo!.copyWith(chapters: next);
    notifyListeners();
  }

  void removeChapter(int index) {
    if (mediaInfo == null) {
      return;
    }
    final List<ChapterEntry> next = List<ChapterEntry>.from(mediaInfo!.chapters)
      ..removeAt(index);
    mediaInfo = mediaInfo!.copyWith(chapters: next);
    notifyListeners();
  }

  void updateStreamEnabled(int index, bool value) {
    _updateStream(
      index,
      (MediaStreamEntry stream) => stream.copyWith(enabled: value),
    );
  }

  void updateStreamTitle(int index, String value) {
    _updateStream(
      index,
      (MediaStreamEntry stream) => stream.copyWith(title: value),
    );
  }

  void updateStreamLanguage(int index, String value) {
    _updateStream(
      index,
      (MediaStreamEntry stream) => stream.copyWith(language: value),
    );
  }

  void updateStreamDefault(int index, bool value) {
    _updateStream(
      index,
      (MediaStreamEntry stream) => stream.copyWith(isDefault: value),
    );
  }

  void updateStreamForced(int index, bool value) {
    _updateStream(
      index,
      (MediaStreamEntry stream) => stream.copyWith(isForced: value),
    );
  }

  void removeStream(int index) {
    if (mediaInfo == null) {
      return;
    }
    final MediaStreamEntry target = mediaInfo!.streams[index];
    if (target.origin == StreamOrigin.input) {
      _updateStream(
        index,
        (MediaStreamEntry stream) => stream.copyWith(enabled: false),
      );
      return;
    }
    final List<MediaStreamEntry> inputStreams = mediaInfo!.streams
        .where((MediaStreamEntry stream) => stream.origin == StreamOrigin.input)
        .toList();
    final SubtitleBinding? binding = _findBindingByPath(target.externalPath);
    if (binding != null) {
      _clearBindingFile(binding.key);
    }
    mediaInfo = mediaInfo!.copyWith(streams: inputStreams);
    _syncExternalSubtitleStreams();
    notifyListeners();
  }

  bool isStreamExtractable(MediaStreamEntry stream) {
    return stream.origin == StreamOrigin.input &&
        stream.kind != StreamKind.data &&
        stream.kind != StreamKind.unknown;
  }

  bool isStreamSelectedForExtraction(MediaStreamEntry stream) {
    return selectedStreamExtractionKeys.contains(_streamSelectionKey(stream));
  }

  bool shouldUseCompatibleSubtitlePreview(MediaStreamEntry stream) {
    return _requiresCompatibleSubtitlePreview(stream);
  }

  bool supportsDirectEmbeddedSubtitlePreview(MediaStreamEntry stream) {
    return _supportsDirectEmbeddedSubtitlePreview(stream);
  }

  bool shouldFallbackToCompatibleSubtitlePreview(MediaStreamEntry stream) {
    return _requiresCompatibleSubtitlePreview(stream) ||
        (!_supportsDirectEmbeddedSubtitlePreview(stream) &&
            _canExtractSubtitleAsAss(stream));
  }

  bool canExtractSubtitleForPreview(MediaStreamEntry stream) {
    return _canExtractSubtitleAsAss(stream);
  }

  void toggleStreamExtractionSelection(MediaStreamEntry stream, bool value) {
    if (!isStreamExtractable(stream)) {
      return;
    }
    final String key = _streamSelectionKey(stream);
    if (value) {
      selectedStreamExtractionKeys.add(key);
    } else {
      selectedStreamExtractionKeys.remove(key);
    }
    notifyListeners();
  }

  void setAllExtractableStreamSelections(bool value) {
    if (mediaInfo == null) {
      return;
    }
    if (value) {
      selectedStreamExtractionKeys
        ..clear()
        ..addAll(
          mediaInfo!.streams
              .where(isStreamExtractable)
              .map(_streamSelectionKey),
        );
    } else {
      selectedStreamExtractionKeys.clear();
    }
    notifyListeners();
  }

  Future<void> extractSelectedStreams() async {
    final MediaInfo? info = mediaInfo;
    if (info == null || streamExtractionRunning) {
      return;
    }
    if (!diagnostics.ffmpeg.available) {
      statusMessage = '缺少 ffmpeg，无法抽取流。';
      notifyListeners();
      return;
    }
    final List<MediaStreamEntry> selectedStreams = info.streams
        .where(
          (MediaStreamEntry stream) =>
              isStreamExtractable(stream) &&
              selectedStreamExtractionKeys.contains(
                _streamSelectionKey(stream),
              ),
        )
        .toList();
    if (selectedStreams.isEmpty) {
      streamExtractionMessage = '请先在流面板选择要抽取的流。';
      notifyListeners();
      return;
    }
    streamExtractionRunning = true;
    streamExtractionMessage = '正在抽取 ${selectedStreams.length} 条流...';
    notifyListeners();
    try {
      final String outputDir = _defaultStreamExtractionDirectory(info);
      await Directory(outputDir).create(recursive: true);
      final List<String> outputs = <String>[];
      final List<MediaStreamEntry> attachmentStreams = selectedStreams
          .where(
            (MediaStreamEntry stream) => stream.kind == StreamKind.attachment,
          )
          .toList();
      if (attachmentStreams.isNotEmpty) {
        outputs.addAll(
          await _extractInputAttachmentStreams(
            info,
            attachmentStreams,
            outputDir,
          ),
        );
      }
      for (final MediaStreamEntry stream in selectedStreams.where(
        (MediaStreamEntry stream) => stream.kind != StreamKind.attachment,
      )) {
        outputs.add(await _extractSingleInputStream(info, stream, outputDir));
      }
      streamExtractionMessage = '流抽取完成，共生成 ${outputs.length} 个文件。';
      statusMessage = '已抽取到 $outputDir';
    } catch (error) {
      streamExtractionMessage = '流抽取失败: $error';
      statusMessage = streamExtractionMessage;
    } finally {
      streamExtractionRunning = false;
      notifyListeners();
    }
  }

  void updateEncoderPreset(String key, String value) {
    encoderTunings[key] = encoderTunings[key]!.copyWith(preset: value);
    notifyListeners();
  }

  void updateEncoderTune(String key, String value) {
    encoderTunings[key] = encoderTunings[key]!.copyWith(tune: value);
    notifyListeners();
  }

  Future<void> exportNow(
    ExportProfile profile,
    List<String> bindingKeys,
  ) async {
    tasks.add(await _createTask(profile, bindingKeys));
    notifyListeners();
    unawaited(runQueue());
  }

  Future<void> enqueueTask(
    ExportProfile profile,
    List<String> bindingKeys,
  ) async {
    tasks.add(await _createTask(profile, bindingKeys));
    notifyListeners();
  }

  Future<void> enqueueSelectedTasks() async {
    final List<String> hardsubKeys = _selectedExistingBindingKeys(
      selectedHardsubBindingKeys,
    );
    for (final String key in hardsubKeys) {
      await enqueueTask(ExportProfile.hardsubMp4, <String>[key]);
    }
    final List<String> muxKeys = _selectedExistingBindingKeys(
      selectedMuxBindingKeys,
    );
    if (muxKeys.isNotEmpty) {
      await enqueueTask(ExportProfile.muxMkv, muxKeys);
    }
  }

  Future<void> enqueueSelectedHardsubTasks() async {
    final List<String> hardsubKeys = _selectedExistingBindingKeys(
      selectedHardsubBindingKeys,
    );
    for (final String key in hardsubKeys) {
      await enqueueTask(ExportProfile.hardsubMp4, <String>[key]);
    }
  }

  Future<void> enqueueSelectedMuxTask() async {
    final List<String> muxKeys = _selectedExistingBindingKeys(
      selectedMuxBindingKeys,
    );
    if (muxKeys.isEmpty) {
      return;
    }
    await enqueueTask(ExportProfile.muxMkv, muxKeys);
  }

  Future<void> runQueue() async {
    if (queueRunning || _activeProcess != null) {
      return;
    }
    stopQueueRequested = false;
    queueRunning = true;
    notifyListeners();
    while (true) {
      if (stopQueueRequested) {
        break;
      }
      final int taskIndex = tasks.indexWhere(
        (ExportTask task) => task.status == TaskStatus.queued,
      );
      if (taskIndex == -1) {
        break;
      }
      tasks[taskIndex] = tasks[taskIndex].copyWith(
        status: TaskStatus.running,
        progress: 0,
        currentStep: '准备任务资源',
        commandPreview: '',
        log: '',
      );
      notifyListeners();
      TaskPlan? plan;
      try {
        plan = await _buildTaskPlan(tasks[taskIndex]);
        tasks[taskIndex] = tasks[taskIndex].copyWith(
          progress: 0,
          currentStep: plan.steps.first.description,
          commandPreview: plan.commandPreview,
          log: '',
        );
      } catch (error) {
        tasks[taskIndex] = tasks[taskIndex].copyWith(
          status: TaskStatus.failed,
          progress: 0,
          currentStep: '',
          error: error.toString(),
          log: error.toString(),
        );
        notifyListeners();
        continue;
      }
      notifyListeners();
      final TaskPlan resolvedPlan = plan;
      final StringBuffer buffer = StringBuffer();
      var exitCode = 0;
      try {
        for (
          var stepIndex = 0;
          stepIndex < resolvedPlan.steps.length;
          stepIndex++
        ) {
          final CommandStep step = resolvedPlan.steps[stepIndex];
          buffer.writeln('> ${step.description}');
          buffer.writeln(renderCommand(step.executable, step.arguments));
          tasks[taskIndex] = tasks[taskIndex].copyWith(
            currentStep: step.description,
            progress: stepIndex / resolvedPlan.steps.length,
            log: buffer.toString(),
          );
          notifyListeners();
          final Process process = await Process.start(
            step.executable,
            step.arguments,
            workingDirectory: resolvedPlan.workingDirectory,
            runInShell: false,
          );
          _activeProcess = process;
          final bool canTrackProgress = _isFfmpegProgressStep(step);
          final StreamSubscription<String> stdoutSub = process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((String line) {
                _handleTaskOutputLine(
                  taskIndex: taskIndex,
                  line: line,
                  buffer: buffer,
                  canTrackProgress: canTrackProgress,
                  stepIndex: stepIndex,
                  totalSteps: resolvedPlan.steps.length,
                  expectedDuration: resolvedPlan.expectedDuration,
                );
              });
          final StreamSubscription<String> stderrSub = process.stderr
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((String line) {
                _handleTaskOutputLine(
                  taskIndex: taskIndex,
                  line: line,
                  buffer: buffer,
                  canTrackProgress: canTrackProgress,
                  stepIndex: stepIndex,
                  totalSteps: resolvedPlan.steps.length,
                  expectedDuration: resolvedPlan.expectedDuration,
                );
              });
          exitCode = await process.exitCode;
          await stdoutSub.cancel();
          await stderrSub.cancel();
          if (exitCode == 0) {
            tasks[taskIndex] = tasks[taskIndex].copyWith(
              progress: (stepIndex + 1) / resolvedPlan.steps.length,
              log: buffer.toString(),
            );
            notifyListeners();
          }
          if (exitCode != 0) {
            break;
          }
          if (stopQueueRequested) {
            break;
          }
        }
      } finally {
        _activeProcess = null;
      }
      try {
        await Directory(resolvedPlan.workingDirectory).delete(recursive: true);
      } catch (_) {}
      tasks[taskIndex] = tasks[taskIndex].copyWith(
        status: stopQueueRequested
            ? TaskStatus.cancelled
            : (exitCode == 0 ? TaskStatus.success : TaskStatus.failed),
        progress: exitCode == 0 ? 1 : tasks[taskIndex].progress,
        currentStep: stopQueueRequested
            ? '已停止'
            : (exitCode == 0 ? '已完成' : tasks[taskIndex].currentStep),
        error: stopQueueRequested
            ? '任务已停止'
            : (exitCode == 0 ? null : '退出码 $exitCode'),
        log: buffer.toString(),
      );
      notifyListeners();
    }
    queueRunning = false;
    stopQueueRequested = false;
    notifyListeners();
  }

  Future<void> stopAllTasks() async {
    stopQueueRequested = true;
    _activeProcess?.kill(ProcessSignal.sigterm);
    notifyListeners();
  }

  void clearCompleted() {
    tasks.removeWhere((ExportTask task) => task.status == TaskStatus.success);
    notifyListeners();
  }

  void clearQueue() {
    tasks.removeWhere((ExportTask task) => task.status == TaskStatus.queued);
    notifyListeners();
  }

  Future<void> retryAll() async {
    var hasRetriedTask = false;
    for (var i = 0; i < tasks.length; i++) {
      final ExportTask task = tasks[i];
      if (task.status != TaskStatus.failed &&
          task.status != TaskStatus.cancelled) {
        continue;
      }
      hasRetriedTask = true;
      tasks[i] = task.copyWith(
        status: TaskStatus.queued,
        progress: 0,
        currentStep: '',
        commandPreview: '',
        log: '',
        error: null,
      );
    }
    notifyListeners();
    if (hasRetriedTask && !queueRunning) {
      await runQueue();
    }
  }

  @override
  void dispose() {
    unawaited(player.dispose());
    unawaited(_resetPreviewSubtitleArtifacts());
    super.dispose();
  }

  Future<ExportTask> _createTask(
    ExportProfile profile,
    List<String> bindingKeys,
  ) async {
    final List<String> resolvedBindingKeys = _selectedExistingBindingKeys(
      bindingKeys,
    );
    return ExportTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      profile: profile,
      bindingKeys: resolvedBindingKeys,
      label: _buildTaskLabel(profile, resolvedBindingKeys),
      outputPath: _buildOutputPath(profile, resolvedBindingKeys),
      status: TaskStatus.queued,
      progress: 0,
      currentStep: '',
      commandPreview: '',
      log: '',
    );
  }

  Future<TaskPlan> _buildTaskPlan(ExportTask task) async {
    final MediaInfo? info = mediaInfo;
    if (info == null) {
      throw Exception('请先导入视频。');
    }
    if (!diagnostics.ffmpeg.available) {
      throw Exception('缺少 ffmpeg，无法导出。');
    }
    if (outputDirectory.isEmpty) {
      throw Exception('请先设置输出目录。');
    }
    if (compressionMode == CompressionMode.episodic &&
        (releaseGroup.trim().isEmpty ||
            titleOverride.trim().isEmpty ||
            episodeNumber.trim().isEmpty ||
            sourceLabel.trim().isEmpty)) {
      throw Exception('请先填写组标、片名、正片编号和视频源。');
    }
    final ({int width, int height})? resolution = _parseResolution(
      outputResolution.trim(),
    );
    final double? fps = double.tryParse(outputFps.trim());
    if (resolution == null) {
      throw Exception('输出分辨率格式必须为例如 1920x1080。');
    }
    if (fps == null || fps <= 0) {
      throw Exception('输出帧率必须大于 0。');
    }
    final Directory workDir = await Directory.systemTemp.createTemp('aemt_');
    final String? chapterMetadataPath = await _writeChapterMetadata(
      workDir.path,
      info.chapters,
    );
    final List<ResolvedFontFile> fontFiles = await _resolveFontFiles(
      workDir.path,
    );
    final String outputPath = task.outputPath;
    await Directory(outputDirectory).create(recursive: true);
    final List<SubtitleBinding> bindings = _resolveBindings(task.bindingKeys);
    _validateTaskBindings(task.profile, bindings);
    if (task.profile == ExportProfile.muxMkv) {
      final List<ResolvedFontFile> extractedAttachments =
          await _extractEnabledInputAttachments(info, workDir.path);
      return _buildMuxPlan(
        info: info,
        bindings: bindings,
        extractedAttachments: extractedAttachments,
        outputPath: outputPath,
        workDir: workDir.path,
        chapterMetadataPath: chapterMetadataPath,
        fontFiles: fontFiles,
      );
    }
    return _buildHardsubPlan(
      info: info,
      binding: bindings.first,
      outputPath: outputPath,
      workDir: workDir.path,
      chapterMetadataPath: chapterMetadataPath,
      fontFiles: fontFiles,
    );
  }

  TaskPlan _buildHardsubPlan({
    required MediaInfo info,
    required SubtitleBinding binding,
    required String outputPath,
    required String workDir,
    required String? chapterMetadataPath,
    required List<ResolvedFontFile> fontFiles,
  }) {
    if (binding.filePath == null) {
      throw Exception('导出内嵌 MP4 前需要绑定对应字幕。');
    }
    if (!_isBindingEnabled(info, binding)) {
      throw Exception('对应外挂字幕流未启用，无法烧录。');
    }
    final List<MediaStreamEntry> enabledVideo = info.streams
        .where(
          (MediaStreamEntry stream) =>
              stream.kind == StreamKind.video && stream.enabled,
        )
        .toList();
    final List<MediaStreamEntry> enabledAudio = info.streams
        .where(
          (MediaStreamEntry stream) =>
              stream.kind == StreamKind.audio && stream.enabled,
        )
        .toList();
    if (enabledVideo.isEmpty) {
      throw Exception('至少需要启用一条视频流。');
    }
    final _EncoderSelection encoder = _resolveEncoder(enabledVideo.first.codec);
    final List<String> args = <String>[
      '-y',
      '-hide_banner',
      '-nostats',
      '-progress',
      'pipe:2',
      '-i',
      info.inputPath,
    ];
    if (chapterMetadataPath != null) {
      args.addAll(<String>['-i', chapterMetadataPath]);
    }
    args.addAll(<String>['-map', '0:${enabledVideo.first.index}']);
    for (final MediaStreamEntry audio in enabledAudio) {
      args.addAll(<String>['-map', '0:${audio.index}']);
    }
    if (chapterMetadataPath != null) {
      args.addAll(<String>['-map_metadata', '1', '-map_chapters', '1']);
    }
    args.addAll(<String>[
      '-vf',
      _buildSubtitleFilter(binding.filePath!, fontFiles),
      '-r',
      outputFps.trim(),
      '-c:v',
      encoder.encoder,
      ..._buildVideoCodecArguments(encoder),
      '-c:a',
      'aac',
      '-b:a',
      '320k',
      '-ar',
      '48000',
      '-movflags',
      '+faststart',
    ]);
    for (var i = 0; i < enabledAudio.length; i++) {
      _applyMetadataForMappedStream(
        args: args,
        streamSpecifier: 'a:$i',
        stream: enabledAudio[i],
      );
    }
    args.add(outputPath);
    return TaskPlan(
      outputPath: outputPath,
      commandPreview: renderCommand(diagnostics.ffmpeg.path!, args),
      steps: <CommandStep>[
        CommandStep(
          executable: diagnostics.ffmpeg.path!,
          arguments: args,
          description: '导出内嵌 MP4',
        ),
      ],
      workingDirectory: workDir,
      expectedDuration: info.duration,
    );
  }

  TaskPlan _buildMuxPlan({
    required MediaInfo info,
    required List<SubtitleBinding> bindings,
    required List<ResolvedFontFile> extractedAttachments,
    required String outputPath,
    required String workDir,
    required String? chapterMetadataPath,
    required List<ResolvedFontFile> fontFiles,
  }) {
    if (!diagnostics.mkvpropedit.available) {
      throw Exception('导出简繁内封 MKV 需要 mkvpropedit。');
    }
    final List<MediaStreamEntry> enabledVideo = info.streams
        .where(
          (MediaStreamEntry stream) =>
              stream.kind == StreamKind.video && stream.enabled,
        )
        .toList();
    final List<MediaStreamEntry> enabledAudio = info.streams
        .where(
          (MediaStreamEntry stream) =>
              stream.kind == StreamKind.audio && stream.enabled,
        )
        .toList();
    final List<MediaStreamEntry> enabledSubtitle = info.streams
        .where(
          (MediaStreamEntry stream) =>
              stream.kind == StreamKind.subtitle &&
              stream.enabled &&
              stream.origin == StreamOrigin.input,
        )
        .toList();
    final List<MediaStreamEntry> enabledExternalSubtitle = info.streams
        .where(
          (MediaStreamEntry stream) =>
              stream.kind == StreamKind.subtitle &&
              stream.enabled &&
              stream.origin == StreamOrigin.externalSubtitle &&
              stream.externalPath != null &&
              stream.externalPath!.isNotEmpty,
        )
        .toList();
    if (enabledVideo.isEmpty) {
      throw Exception('至少需要启用一条视频流。');
    }
    if (enabledExternalSubtitle.isEmpty) {
      throw Exception('至少需要启用一条外挂字幕流才能导出内封 MKV。');
    }
    final _EncoderSelection encoder = _resolveEncoder(
      enabledVideo.first.codec,
      preferredCodecFamily: 'hevc',
    );
    final List<String> args = <String>[
      '-y',
      '-hide_banner',
      '-nostats',
      '-progress',
      'pipe:2',
      '-i',
      info.inputPath,
    ];
    final List<MediaStreamEntry> selectedExternalSubtitle =
        enabledExternalSubtitle
            .where(
              (MediaStreamEntry stream) => bindings.any(
                (SubtitleBinding binding) =>
                    binding.filePath == stream.externalPath,
              ),
            )
            .toList();
    for (final MediaStreamEntry subtitle in selectedExternalSubtitle) {
      args.addAll(<String>['-i', subtitle.externalPath!]);
    }
    if (chapterMetadataPath != null) {
      args.addAll(<String>['-i', chapterMetadataPath]);
    }
    args.addAll(<String>['-map', '0:${enabledVideo.first.index}']);
    for (final MediaStreamEntry audio in enabledAudio) {
      args.addAll(<String>['-map', '0:${audio.index}']);
    }
    for (final MediaStreamEntry subtitle in enabledSubtitle) {
      args.addAll(<String>['-map', '0:${subtitle.index}']);
    }
    for (var i = 0; i < selectedExternalSubtitle.length; i++) {
      args.addAll(<String>['-map', '${i + 1}:0']);
    }
    if (chapterMetadataPath != null) {
      args.addAll(<String>[
        '-map_metadata',
        '${selectedExternalSubtitle.length + 1}',
        '-map_chapters',
        '${selectedExternalSubtitle.length + 1}',
      ]);
    }
    args.addAll(<String>[
      '-c:v',
      encoder.encoder,
      '-vf',
      _buildVideoScaleFilter(),
      '-r',
      outputFps.trim(),
      ..._buildVideoCodecArguments(encoder),
      ..._buildPixelFormatArguments(encoder),
      '-c:a',
      'aac',
      '-b:a',
      '320k',
      '-ar',
      '48000',
      '-c:s',
      'copy',
    ]);
    for (var i = 0; i < enabledAudio.length; i++) {
      _applyMetadataForMappedStream(
        args: args,
        streamSpecifier: 'a:$i',
        stream: enabledAudio[i],
      );
    }
    for (var i = 0; i < enabledSubtitle.length; i++) {
      _applyMetadataForMappedStream(
        args: args,
        streamSpecifier: 's:$i',
        stream: enabledSubtitle[i],
      );
    }
    for (var i = 0; i < selectedExternalSubtitle.length; i++) {
      final int mappedIndex = enabledSubtitle.length + i;
      final MediaStreamEntry stream = selectedExternalSubtitle[i];
      args.addAll(<String>['-c:s:$mappedIndex', 'ass']);
      _applyMetadataForMappedStream(
        args: args,
        streamSpecifier: 's:$mappedIndex',
        stream: stream,
      );
    }
    final List<ResolvedFontFile> attachmentFiles = <ResolvedFontFile>[
      ...extractedAttachments,
      ...fontFiles,
    ];
    for (var i = 0; i < attachmentFiles.length; i++) {
      final ResolvedFontFile attachment = attachmentFiles[i];
      final int attachmentIndex = i;
      args.addAll(<String>['-attach', attachment.path]);
      args.addAll(<String>[
        '-metadata:s:t:$attachmentIndex',
        'mimetype=${attachment.mimeType}',
      ]);
      args.addAll(<String>[
        '-metadata:s:t:$attachmentIndex',
        'filename=${attachment.fileName}',
      ]);
    }
    args.add(outputPath);
    return TaskPlan(
      outputPath: outputPath,
      commandPreview: <String>[
        renderCommand(diagnostics.ffmpeg.path!, args),
        renderCommand(
          diagnostics.mkvpropedit.path!,
          _buildMkvSubtitleMetadataArguments(outputPath, <MediaStreamEntry>[
            ...enabledSubtitle,
            ...selectedExternalSubtitle,
          ]),
        ),
      ].join('\n\n'),
      steps: <CommandStep>[
        CommandStep(
          executable: diagnostics.ffmpeg.path!,
          arguments: args,
          description: '导出简繁内封 MKV',
        ),
        CommandStep(
          executable: diagnostics.mkvpropedit.path!,
          arguments: _buildMkvSubtitleMetadataArguments(
            outputPath,
            <MediaStreamEntry>[...enabledSubtitle, ...selectedExternalSubtitle],
          ),
          description: '写入 MKV 字幕轨元数据',
        ),
      ],
      workingDirectory: workDir,
      expectedDuration: info.duration,
    );
  }

  List<String> _buildVideoCodecArguments(_EncoderSelection selection) {
    final EncoderTuning tuning = encoderTunings[selection.encoder]!;
    final List<String> args = <String>[
      '-b:v',
      selection.codecFamily == 'hevc' ? hevcBitrate : avcBitrate,
      '-maxrate',
      selection.codecFamily == 'hevc' ? hevcMaxrate : avcMaxrate,
    ];
    switch (selection.encoder) {
      case 'libx264':
      case 'libx265':
      case 'h264_nvenc':
      case 'hevc_nvenc':
      case 'h264_qsv':
      case 'hevc_qsv':
        args.addAll(<String>['-preset', tuning.preset]);
        break;
      case 'h264_amf':
      case 'hevc_amf':
        args.addAll(<String>['-quality', tuning.preset]);
        break;
    }
    if (tuning.tune != '默认') {
      switch (selection.encoder) {
        case 'h264_qsv':
        case 'hevc_qsv':
          args.addAll(<String>['-scenario', tuning.tune]);
          break;
        case 'h264_amf':
        case 'hevc_amf':
          args.addAll(<String>['-usage', tuning.tune]);
          break;
        default:
          args.addAll(<String>['-tune', tuning.tune]);
      }
    }
    return args;
  }

  List<String> _buildPixelFormatArguments(_EncoderSelection selection) {
    if (selection.codecFamily != 'hevc') {
      return const <String>[];
    }
    switch (selection.encoder) {
      case 'hevc_nvenc':
        return const <String>['-pix_fmt', 'p010le', '-profile:v', 'main10'];
      case 'hevc_qsv':
        return const <String>['-pix_fmt', 'p010le', '-profile:v', 'main10'];
      case 'hevc_amf':
        return const <String>['-pix_fmt', 'p010le', '-profile:v', 'main10'];
      case 'libx265':
        return const <String>[
          '-pix_fmt',
          'yuv420p10le',
          '-profile:v',
          'main10',
        ];
      default:
        return const <String>[];
    }
  }

  void _handleTaskOutputLine({
    required int taskIndex,
    required String line,
    required StringBuffer buffer,
    required bool canTrackProgress,
    required int stepIndex,
    required int totalSteps,
    required Duration expectedDuration,
  }) {
    buffer.writeln(line);
    double? progress;
    if (canTrackProgress) {
      progress = _extractTaskProgress(
        line: line,
        stepIndex: stepIndex,
        totalSteps: totalSteps,
        expectedDuration: expectedDuration,
      );
    }
    tasks[taskIndex] = tasks[taskIndex].copyWith(
      progress: progress ?? tasks[taskIndex].progress,
      log: buffer.toString(),
    );
    notifyListeners();
  }

  double? _extractTaskProgress({
    required String line,
    required int stepIndex,
    required int totalSteps,
    required Duration expectedDuration,
  }) {
    if (expectedDuration <= Duration.zero || totalSteps <= 0) {
      return null;
    }
    final String trimmed = line.trim();
    int? outTimeUs;
    if (trimmed.startsWith('out_time_us=')) {
      outTimeUs = int.tryParse(trimmed.substring('out_time_us='.length));
    } else if (trimmed.startsWith('out_time_ms=')) {
      outTimeUs = int.tryParse(
        trimmed.substring('out_time_ms='.length),
      )?.toInt();
    } else if (trimmed == 'progress=end') {
      return (stepIndex + 1) / totalSteps;
    }
    if (outTimeUs == null) {
      return null;
    }
    final double stepProgress = (outTimeUs / expectedDuration.inMicroseconds)
        .clamp(0, 1)
        .toDouble();
    return ((stepIndex + stepProgress) / totalSteps).clamp(0, 1).toDouble();
  }

  bool _isFfmpegProgressStep(CommandStep step) {
    return p.basename(step.executable).toLowerCase() == 'ffmpeg.exe';
  }

  String _buildSubtitleFilter(
    String subtitlePath,
    List<ResolvedFontFile> fontFiles,
  ) {
    final String scale = _buildVideoScaleFilter();
    final String normalizedSubtitlePath = subtitlePath
        .replaceAll(r'\', '/')
        .replaceAll(':', r'\:');
    final StringBuffer buffer = StringBuffer();
    if (scale.isNotEmpty) {
      buffer.write('$scale,');
    }
    buffer
      ..write("subtitles='")
      ..write(normalizedSubtitlePath)
      ..write("'");
    if (fontFiles.isNotEmpty) {
      final String fontsDir = p
          .dirname(fontFiles.first.path)
          .replaceAll(r'\', '/')
          .replaceAll(':', r'\:');
      buffer.write(":fontsdir='");
      buffer.write(fontsDir);
      buffer.write("'");
    }
    return buffer.toString();
  }

  String _buildVideoScaleFilter() {
    final ({int width, int height})? resolution = _parseResolution(
      outputResolution.trim(),
    );
    if (resolution == null) {
      return '';
    }
    return 'scale=${resolution.width}:${resolution.height}';
  }

  Future<List<ResolvedFontFile>> _resolveFontFiles(String tempDir) async {
    final List<ResolvedFontFile> result = <ResolvedFontFile>[];
    for (final String source in importedFontSources) {
      final String extension = p.extension(source).toLowerCase();
      if (<String>{'.ttf', '.otf', '.ttc'}.contains(extension)) {
        result.add(
          ResolvedFontFile(
            path: source,
            fileName: p.basename(source),
            mimeType: _mimeTypeForFont(source),
          ),
        );
        continue;
      }
      if (extension == '.zip') {
        final InputFileStream input = InputFileStream(source);
        final Archive archive = ZipDecoder().decodeStream(input);
        for (final ArchiveFile file in archive) {
          if (!file.isFile || !_isFontFile(file.name)) {
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
              mimeType: _mimeTypeForFont(outPath),
            ),
          );
        }
        input.close();
        continue;
      }
      if (<String>{'.7z', '.rar'}.contains(extension) &&
          diagnostics.sevenZip.available) {
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
          if (_isFontFile(file.path)) {
            result.add(
              ResolvedFontFile(
                path: file.path,
                fileName: p.basename(file.path),
                mimeType: _mimeTypeForFont(file.path),
              ),
            );
          }
        }
      }
    }
    return result;
  }

  Future<List<ResolvedFontFile>> _extractEnabledInputAttachments(
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
              : _mimeTypeForAttachment(attachment),
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
      diagnostics.ffmpeg.path!,
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

  Future<List<String>> _extractInputAttachmentStreams(
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
      diagnostics.ffmpeg.path!,
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

  Future<String> _extractSingleInputStream(
    MediaInfo info,
    MediaStreamEntry stream,
    String outputDir,
  ) async {
    final String outputPath = _buildStreamExtractionOutputPath(
      info,
      stream,
      outputDir,
    );
    await Directory(p.dirname(outputPath)).create(recursive: true);
    final List<String> arguments = _buildSingleStreamExtractionArguments(
      info: info,
      stream: stream,
      outputPath: outputPath,
    );
    final ProcessResult extraction = await Process.run(
      diagnostics.ffmpeg.path!,
      arguments,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (extraction.exitCode != 0) {
      throw Exception('抽取流 ${stream.index} 失败: ${extraction.stderr}');
    }
    if (!File(outputPath).existsSync()) {
      throw Exception('抽取流 ${stream.index} 失败: 未生成 ${p.basename(outputPath)}');
    }
    return outputPath;
  }

  Future<List<String>> _inspectFontSource(String source) async {
    final String extension = p.extension(source).toLowerCase();
    if (_isFontFile(source)) {
      return <String>[p.basename(source)];
    }
    if (extension == '.zip') {
      final InputFileStream input = InputFileStream(source);
      try {
        final Archive archive = ZipDecoder().decodeStream(input);
        return archive.files
            .where((ArchiveFile file) => file.isFile && _isFontFile(file.name))
            .map((ArchiveFile file) => file.name)
            .toList();
      } finally {
        input.close();
      }
    }
    if (<String>{'.7z', '.rar'}.contains(extension) &&
        diagnostics.sevenZip.available) {
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
        if (_isFontFile(value)) {
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
          diagnostics.sevenZip.path!,
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

  Future<String?> _writeChapterMetadata(
    String tempDir,
    List<ChapterEntry> chapters,
  ) async {
    if (chapters.isEmpty) {
      return null;
    }
    final String metadataPath = p.join(tempDir, 'chapters.ffmeta');
    final StringBuffer buffer = StringBuffer(';FFMETADATA1\n');
    for (final ChapterEntry chapter in chapters) {
      buffer.writeln('[CHAPTER]');
      buffer.writeln('TIMEBASE=1/1000');
      buffer.writeln('START=${chapter.start.inMilliseconds}');
      buffer.writeln('END=${chapter.end.inMilliseconds}');
      buffer.writeln('title=${_escapeMetadata(chapter.title)}');
    }
    await File(metadataPath).writeAsString(buffer.toString());
    return metadataPath;
  }

  void _applyMetadataForMappedStream({
    required List<String> args,
    required String streamSpecifier,
    required MediaStreamEntry stream,
  }) {
    if (stream.title.isNotEmpty) {
      args.addAll(<String>[
        '-metadata:s:$streamSpecifier',
        'title=${stream.title}',
      ]);
    }
    if (stream.language.isNotEmpty) {
      args.addAll(<String>[
        '-metadata:s:$streamSpecifier',
        'language=${stream.language}',
      ]);
    }
    final List<String> flags = <String>[
      if (stream.isDefault) 'default',
      if (stream.isForced) 'forced',
    ];
    args.addAll(<String>[
      '-disposition:$streamSpecifier',
      flags.isEmpty ? '0' : flags.join('+'),
    ]);
  }

  List<String> _buildMkvSubtitleMetadataArguments(
    String outputPath,
    List<MediaStreamEntry> subtitleStreams,
  ) {
    final List<String> args = <String>[outputPath];
    for (var i = 0; i < subtitleStreams.length; i++) {
      final MediaStreamEntry stream = subtitleStreams[i];
      args.addAll(<String>['--edit', 'track:s${i + 1}']);
      if (stream.title.isNotEmpty) {
        args.addAll(<String>['--set', 'name=${stream.title}']);
      }
      final String languageTag = _buildLanguageTag(stream);
      if (languageTag.isNotEmpty) {
        args.addAll(<String>['--set', 'language=$languageTag']);
      }
      args.addAll(<String>[
        '--set',
        'flag-default=${stream.isDefault ? 1 : 0}',
      ]);
      args.addAll(<String>['--set', 'flag-forced=${stream.isForced ? 1 : 0}']);
    }
    return args;
  }

  MediaInfo _parseMediaInfo(String inputPath, Map<String, dynamic> json) {
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

  Future<RuntimeDiagnostics> _detectRuntime() async {
    final String currentDir = Directory.current.path;
    final String parentDir = p.dirname(currentDir);
    final List<String> preferredBinDirs = <String>[
      p.join(currentDir, 'bin'),
      p.join(parentDir, 'bin'),
    ];
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
    final String? customFfmpeg = _resolveCustomRuntime('ffmpeg.exe');
    final String? customFfprobe = _resolveCustomRuntime('ffprobe.exe');
    final String? customMkvpropedit = _resolveCustomRuntime('mkvpropedit.exe');
    final String? custom7z = _resolveCustomRuntime('7z.exe');
    final String? resolvedFfmpeg = customFfmpeg ?? ffmpeg;
    final String? resolvedFfprobe = customFfprobe ?? ffprobe;
    final String? resolvedMkvpropedit = customMkvpropedit ?? mkvpropedit;
    final String? resolved7z = custom7z ?? sevenZip;
    List<String> hwaccels = <String>[];
    Set<String> encoders = <String>{};
    if (resolvedFfmpeg != null) {
      hwaccels = await _readFfmpegOutput(resolvedFfmpeg, <String>[
        '-hide_banner',
        '-hwaccels',
      ]);
      encoders = await _probeHardwareVideoEncoders(resolvedFfmpeg);
    }
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
      hwaccels: hwaccels,
      videoEncoders: encoders,
    );
  }

  Future<List<String>> _readFfmpegOutput(
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

  Future<Set<String>> _probeHardwareVideoEncoders(String ffmpegPath) async {
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

  String _buildOutputPath(ExportProfile profile, List<String> bindingKeys) {
    final MediaInfo? info = mediaInfo;
    if (info == null) {
      return '';
    }
    if (compressionMode == CompressionMode.episodic) {
      return p.join(
        outputDirectory,
        _buildEpisodicFileName(info, profile, bindingKeys),
      );
    }
    final String baseName = outputFileNameOverride.isEmpty
        ? p.basenameWithoutExtension(info.displayName)
        : outputFileNameOverride;
    switch (profile) {
      case ExportProfile.hardsubMp4:
        final String bindingLabel = _buildBindingSuffix(bindingKeys);
        return p.join(outputDirectory, '$baseName [$bindingLabel Hardsub].mp4');
      case ExportProfile.muxMkv:
        final String bindingLabel = _buildBindingSuffix(bindingKeys);
        return p.join(outputDirectory, '$baseName [$bindingLabel Mux].mkv');
    }
  }

  String _buildTaskLabel(ExportProfile profile, List<String> bindingKeys) {
    final String suffix = profile == ExportProfile.muxMkv
        ? '字幕内封'
        : '${_buildBindingSuffix(bindingKeys)} 内嵌';
    if (compressionMode == CompressionMode.episodic) {
      final String title = titleOverride.trim().isEmpty
          ? '未命名'
          : titleOverride.trim();
      final String episode = episodeNumber.trim().isEmpty
          ? '?'
          : episodeNumber.trim();
      return '$title-第$episode话-$suffix';
    }
    final String baseName = outputFileNameOverride.trim().isEmpty
        ? '未命名'
        : outputFileNameOverride.trim();
    return '$baseName-$suffix';
  }

  String _buildEpisodicFileName(
    MediaInfo info,
    ExportProfile profile,
    List<String> bindingKeys,
  ) {
    final String group = '[${releaseGroup.trim()}]';
    final String title = titleOverride.trim();
    final String episode = '[${episodeNumber.trim()}]';
    final String resolutionTag = _buildOutputResolutionTag(
      outputResolution,
      profile,
    );
    final _EncoderSelection encoder = _resolveEncoder(
      info.streams
          .where((MediaStreamEntry stream) => stream.kind == StreamKind.video)
          .first
          .codec,
    );
    final String videoTag = _buildVideoNamingTag(encoder.encoder);
    switch (profile) {
      case ExportProfile.muxMkv:
        final String source = '[${sourceLabel.trim()}]';
        final String encodeAndAudio =
            '[$videoTag ${resolutionTag.toLowerCase()} ${_buildAudioCodecTag(info)}]';
        final String subtitleTag =
            '[${_buildMuxSubtitleTag(info, bindingKeys)}]';
        return '$group$title$episode$source$encodeAndAudio$subtitleTag.mkv';
      case ExportProfile.hardsubMp4:
        return '$group$title$episode[${_buildBindingSuffix(bindingKeys)}][$resolutionTag][$videoTag].mp4';
    }
  }

  String _buildOutputResolutionTag(String resolution, ExportProfile profile) {
    final ({int width, int height})? parsed = _parseResolution(resolution);
    if (parsed == null) {
      return resolution.trim();
    }
    final String suffix = profile == ExportProfile.muxMkv ? 'p' : 'P';
    return '${parsed.height}$suffix';
  }

  String _buildVideoNamingTag(String encoder) {
    if (encoder.contains('265') || encoder.contains('hevc')) {
      return 'HEVC-10bit';
    }
    return 'AVC 8bit';
  }

  String _buildAudioCodecTag(MediaInfo info) {
    final Iterable<MediaStreamEntry> audioStreams = info.streams.where(
      (MediaStreamEntry stream) =>
          stream.kind == StreamKind.audio && stream.enabled,
    );
    if (audioStreams.isEmpty) {
      return 'AUDIO';
    }
    final String codec = audioStreams.first.codec.trim();
    if (codec.isEmpty) {
      return 'AUDIO';
    }
    return codec.toUpperCase().replaceAll('-', '');
  }

  String _buildMuxSubtitleTag(MediaInfo info, List<String> bindingKeys) {
    final String audioLanguage = _buildPrimaryAudioLanguageTag(info);
    return bindingKeys
        .map(
          (String key) =>
              '${_buildBindingSuffix(<String>[key])}_$audioLanguage',
        )
        .join('&');
  }

  String _buildBindingSuffix(List<String> bindingKeys) {
    final List<String> labels = bindingKeys
        .map(_findBindingByKey)
        .whereType<SubtitleBinding>()
        .map((SubtitleBinding binding) => _bindingTag(binding))
        .toList();
    return labels.isEmpty ? 'SUB' : labels.join('&');
  }

  String _bindingTag(SubtitleBinding binding) {
    if (binding.key == 'chs') {
      return 'CHS';
    }
    if (binding.key == 'cht') {
      return 'CHT';
    }
    if (binding.languageCode.trim().isNotEmpty) {
      return binding.languageCode.trim().toUpperCase();
    }
    return binding.label.replaceAll(' 字幕', '').replaceAll('自定义字幕 ', 'SUB');
  }

  String _buildPrimaryAudioLanguageTag(MediaInfo info) {
    final Iterable<MediaStreamEntry> audioStreams = info.streams.where(
      (MediaStreamEntry stream) =>
          stream.kind == StreamKind.audio && stream.enabled,
    );
    if (audioStreams.isEmpty) {
      return 'UND';
    }
    final String language = audioStreams.first.language.trim().toLowerCase();
    switch (language) {
      case 'ja':
      case 'jpn':
      case 'jp':
        return 'JP';
      case 'en':
      case 'eng':
        return 'EN';
      case 'zh':
      case 'zho':
      case 'chi':
        return 'ZH';
      default:
        return language.isEmpty ? 'UND' : language.toUpperCase();
    }
  }

  _EncoderSelection _resolveEncoder(
    String videoCodec, {
    String? preferredCodecFamily,
  }) {
    final String codecFamily =
        preferredCodecFamily ??
        (videoCodec.contains('265') || videoCodec.contains('hevc')
            ? 'hevc'
            : 'avc');
    if (hardwareMode == HardwareMode.software) {
      return _EncoderSelection(
        encoder: codecFamily == 'hevc' ? 'libx265' : 'libx264',
        codecFamily: codecFamily,
      );
    }
    if (hardwareMode == HardwareMode.nvenc && diagnostics.hasNvenc) {
      return _EncoderSelection(
        encoder: codecFamily == 'hevc' ? 'hevc_nvenc' : 'h264_nvenc',
        codecFamily: codecFamily,
      );
    }
    if (hardwareMode == HardwareMode.qsv && diagnostics.hasQsv) {
      return _EncoderSelection(
        encoder: codecFamily == 'hevc' ? 'hevc_qsv' : 'h264_qsv',
        codecFamily: codecFamily,
      );
    }
    if (hardwareMode == HardwareMode.amf && diagnostics.hasAmf) {
      return _EncoderSelection(
        encoder: codecFamily == 'hevc' ? 'hevc_amf' : 'h264_amf',
        codecFamily: codecFamily,
      );
    }
    if (diagnostics.hasNvenc) {
      return _EncoderSelection(
        encoder: codecFamily == 'hevc' ? 'hevc_nvenc' : 'h264_nvenc',
        codecFamily: codecFamily,
      );
    }
    if (diagnostics.hasQsv) {
      return _EncoderSelection(
        encoder: codecFamily == 'hevc' ? 'hevc_qsv' : 'h264_qsv',
        codecFamily: codecFamily,
      );
    }
    if (diagnostics.hasAmf) {
      return _EncoderSelection(
        encoder: codecFamily == 'hevc' ? 'hevc_amf' : 'h264_amf',
        codecFamily: codecFamily,
      );
    }
    return _EncoderSelection(
      encoder: codecFamily == 'hevc' ? 'libx265' : 'libx264',
      codecFamily: codecFamily,
    );
  }

  String? _findExecutable({
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

  String? _resolveCustomRuntime(String executableName) {
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

  String? _resolveFromPath(String executable) {
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

  SubtitleBinding? _findBindingByKey(String key) {
    for (final SubtitleBinding binding in allBindings) {
      if (binding.key == key) {
        return binding;
      }
    }
    return null;
  }

  SubtitleBinding? _findBindingByPath(String? path) {
    if (path == null) {
      return null;
    }
    for (final SubtitleBinding binding in allBindings) {
      if (binding.filePath == path) {
        return binding;
      }
    }
    return null;
  }

  List<String> _selectedExistingBindingKeys(Iterable<String> keys) {
    return keys
        .where((String key) => _findBindingByKey(key)?.filePath != null)
        .toList();
  }

  List<SubtitleBinding> _resolveBindings(List<String> keys) {
    return keys
        .map(_findBindingByKey)
        .whereType<SubtitleBinding>()
        .where((SubtitleBinding binding) => binding.filePath != null)
        .toList();
  }

  void _replaceBinding(
    String key,
    SubtitleBinding Function(SubtitleBinding binding) transform,
  ) {
    if (key == 'chs') {
      simplifiedBinding = transform(simplifiedBinding);
    } else if (key == 'cht') {
      traditionalBinding = transform(traditionalBinding);
    } else {
      final int index = customBindings.indexWhere(
        (SubtitleBinding binding) => binding.key == key,
      );
      if (index == -1) {
        return;
      }
      customBindings[index] = transform(customBindings[index]);
    }
    _syncExternalSubtitleStreams();
    notifyListeners();
  }

  void _clearBindingFile(String key) {
    if (key == 'chs') {
      simplifiedBinding = simplifiedBinding.copyWith(clearFile: true);
    } else if (key == 'cht') {
      traditionalBinding = traditionalBinding.copyWith(clearFile: true);
    } else {
      customBindings.removeWhere(
        (SubtitleBinding binding) => binding.key == key,
      );
      selectedHardsubBindingKeys.remove(key);
      selectedMuxBindingKeys.remove(key);
    }
  }

  void _validateTaskBindings(
    ExportProfile profile,
    List<SubtitleBinding> bindings,
  ) {
    if (bindings.isEmpty) {
      throw Exception('请至少选择一条外挂字幕。');
    }
    if (profile == ExportProfile.hardsubMp4 && bindings.length != 1) {
      throw Exception('内嵌任务一次只能使用一条外挂字幕。');
    }
    for (final SubtitleBinding binding in bindings.where(
      (SubtitleBinding binding) => binding.key.startsWith('custom_'),
    )) {
      if (binding.languageCode.trim().isEmpty ||
          binding.regionCode.trim().isEmpty ||
          binding.trackName.trim().isEmpty) {
        throw Exception('自定义字幕需要填写语言代码、地区代码和轨道名。');
      }
    }
    for (final SubtitleBinding binding in bindings) {
      if (!_isBindingEnabled(mediaInfo!, binding)) {
        throw Exception('所选字幕中存在未启用项。');
      }
    }
  }

  void _syncExternalSubtitleStreams() {
    if (mediaInfo == null) {
      return;
    }
    final List<MediaStreamEntry> existingExternalStreams = mediaInfo!.streams
        .where(
          (MediaStreamEntry stream) =>
              stream.origin == StreamOrigin.externalSubtitle,
        )
        .toList();
    MediaStreamEntry? findExisting(String? path) {
      if (path == null) {
        return null;
      }
      for (final MediaStreamEntry stream in existingExternalStreams) {
        if (stream.externalPath == path) {
          return stream;
        }
      }
      return null;
    }

    final List<MediaStreamEntry> inputStreams = mediaInfo!.streams
        .where((MediaStreamEntry stream) => stream.origin == StreamOrigin.input)
        .toList();
    final List<SubtitleBinding> fileBindings = allBindings
        .where((SubtitleBinding binding) => binding.filePath != null)
        .toList();
    final List<MediaStreamEntry> externalStreams = <MediaStreamEntry>[
      for (var i = 0; i < fileBindings.length; i++)
        (() {
          final SubtitleBinding binding = fileBindings[i];
          final MediaStreamEntry? existing = findExisting(binding.filePath);
          return MediaStreamEntry(
            index: inputStreams.length + i,
            kind: StreamKind.subtitle,
            codec: p.extension(binding.filePath!).replaceFirst('.', ''),
            title: binding.trackName,
            language: binding.languageCode,
            regionCode: binding.regionCode,
            enabled: existing?.enabled ?? true,
            isDefault: existing?.isDefault ?? (binding.key == 'chs'),
            isForced: existing?.isForced ?? false,
            origin: StreamOrigin.externalSubtitle,
            sourceLabel: '${binding.label.replaceAll(" 字幕", "")} 外挂字幕',
            externalPath: binding.filePath,
          );
        })(),
    ];
    mediaInfo = mediaInfo!.copyWith(
      streams: <MediaStreamEntry>[...inputStreams, ...externalStreams],
    );
  }

  String _streamSelectionKey(MediaStreamEntry stream) {
    return '${stream.origin.index}:${stream.index}:${stream.externalPath ?? ''}';
  }

  String _defaultStreamExtractionDirectory(MediaInfo info) {
    final String configured = outputDirectory.trim();
    if (configured.isNotEmpty) {
      return configured;
    }
    return p.join(p.dirname(info.inputPath), 'extracted_streams');
  }

  MediaStreamEntry _findInputStreamByIndex(int streamIndex) {
    final MediaInfo? info = mediaInfo;
    if (info == null) {
      throw Exception('当前没有已载入的视频。');
    }
    for (final MediaStreamEntry stream in info.streams) {
      if (stream.origin == StreamOrigin.input && stream.index == streamIndex) {
        return stream;
      }
    }
    throw Exception('未找到索引为 $streamIndex 的源流。');
  }

  bool _requiresCompatibleSubtitlePreview(MediaStreamEntry stream) {
    if (stream.kind != StreamKind.subtitle ||
        stream.origin != StreamOrigin.input) {
      return false;
    }
    return <String>{'arib_caption'}.contains(stream.codec.trim().toLowerCase());
  }

  bool _supportsDirectEmbeddedSubtitlePreview(MediaStreamEntry stream) {
    if (stream.kind != StreamKind.subtitle ||
        stream.origin != StreamOrigin.input) {
      return false;
    }
    return <String>{
      'ass',
      'ssa',
      'subrip',
      'srt',
      'mov_text',
      'webvtt',
      'text',
      'subviewer',
      'subviewer1',
      'microdvd',
      'mpl2',
      'sami',
      'realtext',
      'jacosub',
      'pjs',
      'ttml',
      'stl',
      'dvd_subtitle',
      'dvb_subtitle',
      'dvb_teletext',
      'hdmv_pgs_subtitle',
      'pgssub',
      'xsub',
      'eia_608',
      'eia_708',
    }.contains(stream.codec.trim().toLowerCase());
  }

  bool _canExtractSubtitleAsAss(MediaStreamEntry stream) {
    if (stream.kind != StreamKind.subtitle ||
        stream.origin != StreamOrigin.input) {
      return false;
    }
    return <String>{
      'arib_caption',
      'ass',
      'ssa',
      'subrip',
      'srt',
      'mov_text',
      'webvtt',
      'text',
    }.contains(stream.codec.trim().toLowerCase());
  }

  Future<String> _extractPreviewSubtitleToTemp(MediaStreamEntry stream) async {
    if (!_canExtractSubtitleAsAss(stream)) {
      throw Exception('该字幕轨暂不支持转换为 ASS 预览。');
    }
    final String? cachedPath = _previewSubtitleCache[stream.index];
    if (cachedPath != null && File(cachedPath).existsSync()) {
      return cachedPath;
    }
    final MediaInfo info = mediaInfo!;
    final Directory tempDir = await _ensurePreviewSubtitleTempDirectory();
    final String outputPath = p.join(
      tempDir.path,
      'preview_sub_${stream.index}.ass',
    );
    statusMessage = '正在转换内封字幕 ${stream.index} 为兼容预览格式...';
    notifyListeners();
    final ProcessResult extraction = await Process.run(
      diagnostics.ffmpeg.path!,
      _buildSingleStreamExtractionArguments(
        info: info,
        stream: stream,
        outputPath: outputPath,
        preferAssSubtitleOutput: true,
      ),
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (extraction.exitCode != 0 || !File(outputPath).existsSync()) {
      throw Exception(
        extraction.stderr.toString().trim().isEmpty
            ? 'ffmpeg 未生成预览字幕文件。'
            : extraction.stderr.toString().trim(),
      );
    }
    _previewSubtitleCache[stream.index] = outputPath;
    statusMessage = '已生成兼容预览字幕。';
    notifyListeners();
    return outputPath;
  }

  Future<Directory> _ensurePreviewSubtitleTempDirectory() async {
    final Directory? existing = _previewSubtitleTempDirectory;
    if (existing != null && existing.existsSync()) {
      return existing;
    }
    final Directory created = await Directory.systemTemp.createTemp(
      'aemt_preview_',
    );
    _previewSubtitleTempDirectory = created;
    return created;
  }

  Future<void> _resetPreviewSubtitleArtifacts() async {
    _previewSubtitleCache.clear();
    final Directory? directory = _previewSubtitleTempDirectory;
    _previewSubtitleTempDirectory = null;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  String _buildStreamExtractionOutputPath(
    MediaInfo info,
    MediaStreamEntry stream,
    String outputDir,
  ) {
    final String baseName = _sanitizeFileNameComponent(
      p.basenameWithoutExtension(info.displayName),
    );
    switch (stream.kind) {
      case StreamKind.video:
        return p.join(outputDir, '$baseName.video${stream.index}.mkv');
      case StreamKind.audio:
        return p.join(outputDir, '$baseName.audio${stream.index}.mka');
      case StreamKind.subtitle:
        final String extension = _canExtractSubtitleAsAss(stream)
            ? 'ass'
            : 'mks';
        return p.join(
          outputDir,
          '$baseName.subtitle${stream.index}.$extension',
        );
      case StreamKind.attachment:
        final String fileName =
            stream.attachmentFileName?.trim().isNotEmpty == true
            ? stream.attachmentFileName!.trim()
            : 'attachment_${stream.index}.${stream.codec.trim().isEmpty ? 'bin' : stream.codec}';
        return p.join(
          outputDir,
          '$baseName.attachment${stream.index}_${_sanitizeFileNameComponent(fileName)}',
        );
      case StreamKind.data:
      case StreamKind.unknown:
        return p.join(outputDir, '$baseName.stream${stream.index}.bin');
    }
  }

  List<String> _buildSingleStreamExtractionArguments({
    required MediaInfo info,
    required MediaStreamEntry stream,
    required String outputPath,
    bool preferAssSubtitleOutput = false,
  }) {
    final bool transcodeSubtitleToAss =
        stream.kind == StreamKind.subtitle &&
        (preferAssSubtitleOutput || _canExtractSubtitleAsAss(stream));
    final List<String> arguments = <String>[
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
    ];
    if (transcodeSubtitleToAss) {
      arguments.add('-fix_sub_duration');
    }
    if (stream.kind == StreamKind.subtitle &&
        stream.codec.trim().toLowerCase() == 'arib_caption') {
      arguments.addAll(<String>['-sub_type', 'ass', '-ass_single_rect', '1']);
    }
    arguments.addAll(<String>[
      '-i',
      info.inputPath,
      '-map',
      '0:${stream.index}',
      '-map_metadata',
      '-1',
      '-map_chapters',
      '-1',
    ]);
    if (transcodeSubtitleToAss) {
      arguments.addAll(<String>['-c:s', 'ass']);
    } else {
      arguments.addAll(<String>['-c', 'copy']);
    }
    arguments.add(outputPath);
    return arguments;
  }

  String _sanitizeFileNameComponent(String value) {
    final String sanitized = value
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim();
    return sanitized.isEmpty ? 'stream' : sanitized;
  }

  void _updateChapter(
    int index,
    ChapterEntry Function(ChapterEntry chapter) transform,
  ) {
    if (mediaInfo == null) {
      return;
    }
    final List<ChapterEntry> chapters = List<ChapterEntry>.from(
      mediaInfo!.chapters,
    );
    chapters[index] = transform(chapters[index]);
    mediaInfo = mediaInfo!.copyWith(chapters: chapters);
    notifyListeners();
  }

  void _updateStream(
    int index,
    MediaStreamEntry Function(MediaStreamEntry stream) transform,
  ) {
    if (mediaInfo == null) {
      return;
    }
    final List<MediaStreamEntry> streams = List<MediaStreamEntry>.from(
      mediaInfo!.streams,
    );
    streams[index] = transform(streams[index]);
    mediaInfo = mediaInfo!.copyWith(streams: streams);
    notifyListeners();
  }

  String _buildStartupMessage(RuntimeDiagnostics runtime) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('硬件编码探测已完成。')
      ..writeln('自动模式回退顺序: NVENC -> QSV -> AMF -> SOFTWARE')
      ..writeln()
      ..writeln('FFmpeg: ${runtime.ffmpeg.path ?? '未找到'}')
      ..writeln('FFprobe: ${runtime.ffprobe.path ?? '未找到'}')
      ..writeln('MKVToolNix: ${runtime.mkvpropedit.path ?? '未找到'}')
      ..writeln('7-Zip: ${runtime.sevenZip.path ?? '未找到'}')
      ..writeln()
      ..writeln(
        '可用硬件加速视频编码探测结果: ${runtime.hardwareVideoEncoderLabels.isEmpty ? '无' : runtime.hardwareVideoEncoderLabels.join(', ')}',
      );
    return buffer.toString();
  }

  bool _isBindingEnabled(MediaInfo info, SubtitleBinding binding) {
    if (binding.filePath == null) {
      return false;
    }
    return info.streams.any(
      (MediaStreamEntry stream) =>
          stream.origin == StreamOrigin.externalSubtitle &&
          stream.externalPath == binding.filePath &&
          stream.enabled,
    );
  }
}

String _buildLanguageTag(MediaStreamEntry stream) {
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

class _EncoderSelection {
  const _EncoderSelection({required this.encoder, required this.codecFamily});

  final String encoder;
  final String codecFamily;
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

({int width, int height})? _parseResolution(String value) {
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

bool _isFontFile(String path) {
  return <String>{
    '.ttf',
    '.otf',
    '.ttc',
  }.contains(p.extension(path).toLowerCase());
}

String _mimeTypeForFont(String path) {
  switch (p.extension(path).toLowerCase()) {
    case '.otf':
      return 'application/vnd.ms-opentype';
    case '.ttc':
      return 'application/x-truetype-collection';
    default:
      return 'application/x-truetype-font';
  }
}

String _mimeTypeForAttachment(MediaStreamEntry stream) {
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

String _escapeMetadata(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('=', r'\=')
      .replaceAll(';', r'\;')
      .replaceAll('#', r'\#')
      .replaceAll('\n', r'\n');
}
