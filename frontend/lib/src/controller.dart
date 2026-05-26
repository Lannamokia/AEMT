import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import 'models.dart';
import 'services/font_asset_service.dart';
import 'services/media_parser.dart';
import 'services/runtime_service.dart';
import 'utils/export_utils.dart';

part 'controller_media_ops.dart';
part 'controller_queue_runner.dart';
part 'controller_export_config.dart';
part 'controller_task_planner.dart';

class AemtController extends ChangeNotifier {
  AemtController({@visibleForTesting bool initializePlayer = true})
    : _playerInitialized = initializePlayer {
    if (initializePlayer) {
      player = Player(configuration: const PlayerConfiguration(libass: true));
      videoController = VideoController(player);
    }
    for (final String encoderKey in kSupportedRcModes.keys) {
      videoEncodingConfigs[encoderKey] = VideoEncodingConfig.defaultsFor(
        encoderKey,
      );
    }
  }

  static const String defaultEpisodicNamingTemplate =
      '{group}{title}{season}{episode}{source}{subtitle}{profile_tags}.{ext}';
  static final RegExp _templateVariablePattern = RegExp(r'\{([A-Za-z0-9_]+)\}');
  static const List<NamingTemplateVariable>
  _episodicNamingVariables = <NamingTemplateVariable>[
    NamingTemplateVariable(name: 'group', description: '组标，自动带 []'),
    NamingTemplateVariable(name: 'group_raw', description: '组标原文'),
    NamingTemplateVariable(name: 'title', description: '片名'),
    NamingTemplateVariable(name: 'season', description: '季，自动带 []'),
    NamingTemplateVariable(name: 'season_raw', description: '季原文'),
    NamingTemplateVariable(name: 'episode', description: '集，自动带 []'),
    NamingTemplateVariable(name: 'episode_raw', description: '集原文'),
    NamingTemplateVariable(name: 'source', description: '视频源，自动带 []'),
    NamingTemplateVariable(name: 'source_raw', description: '视频源原文'),
    NamingTemplateVariable(name: 'binding', description: '字幕标签，自动带 []'),
    NamingTemplateVariable(name: 'binding_raw', description: '字幕标签原文'),
    NamingTemplateVariable(name: 'subtitle', description: '字幕描述，自动带 []'),
    NamingTemplateVariable(name: 'subtitle_raw', description: '字幕描述原文'),
    NamingTemplateVariable(name: 'resolution', description: '分辨率标签，自动带 []'),
    NamingTemplateVariable(name: 'resolution_raw', description: '分辨率标签原文'),
    NamingTemplateVariable(name: 'video', description: '视频标签，自动带 []'),
    NamingTemplateVariable(name: 'video_raw', description: '视频标签原文'),
    NamingTemplateVariable(name: 'audio', description: '音频编码标签'),
    NamingTemplateVariable(name: 'encode_audio', description: '编码与音频组合，自动带 []'),
    NamingTemplateVariable(name: 'profile_tags', description: '除字幕外的默认编码标签组合'),
    NamingTemplateVariable(name: 'ext', description: '扩展名，如 mp4 / mkv'),
  ];

  late final Player player;
  late final VideoController videoController;
  final bool _playerInitialized;

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
  String seasonNumber = '';
  String episodeNumber = '';
  String sourceLabel = '';
  String episodicNamingTemplate = defaultEpisodicNamingTemplate;
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
  final Map<String, AudioStreamConfig> audioStreamConfigs =
      <String, AudioStreamConfig>{};
  AudioStreamConfig audioDefaultProfile = const AudioStreamConfig.defaultAac();
  final Map<String, VideoEncodingConfig> videoEncodingConfigs =
      <String, VideoEncodingConfig>{};
  ToneMappingConfig toneMappingConfig = const ToneMappingConfig.defaultBt709();
  bool continueOnMissingFont = false;
  bool sourceHanEllipsisFix = true;
  bool _hdrToneMappingNoticeShown = false;
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

  List<NamingTemplateVariable> get episodicNamingVariables =>
      _episodicNamingVariables;

  FontAssetService get _fontAssetService => FontAssetService(
    ffmpegPath: diagnostics.ffmpeg.path,
    sevenZipPath: diagnostics.sevenZip.path,
  );

  _MediaOps get _mediaOps => _MediaOps(this);

  _QueueRunner get _queueRunner => _QueueRunner(this);

  _ExportConfig get _exportConfig => _ExportConfig(this);

  _TaskPlanner get _taskPlanner => _TaskPlanner(this);

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
    diagnostics = await RuntimeService.detect(
      customRuntimeDirectory: customRuntimeDirectory,
      customRuntimeExecutable: customRuntimeExecutable,
    );
    if (showDialog) {
      showStartupDialog = true;
      startupMessage = buildStartupMessage(diagnostics);
    }
    notifyListeners();
  }

  Future<void> dismissStartupDialog() async {
    showStartupDialog = false;
    notifyListeners();
  }

  Future<void> pickVideo() async {
    await _mediaOps.pickVideo();
  }

  Future<void> analyzeVideo(String path) async {
    await _mediaOps.analyzeVideo(path);
  }

  Future<void> pickSubtitle(bool simplified) async {
    await _mediaOps.pickSubtitle(simplified);
  }

  Future<void> addCustomSubtitleBinding() async {
    await _mediaOps.addCustomSubtitleBinding();
  }

  Future<void> importFonts() async {
    await _mediaOps.importFonts();
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

  Future<void> exportEncodingSettings() async {
    try {
      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: '导出编码参数配置',
        fileName: 'aemt-encoding-settings.json',
        type: FileType.custom,
        allowedExtensions: <String>['json'],
      );
      if (path == null || path.isEmpty) {
        return;
      }
      final String resolvedPath = p.extension(path).toLowerCase() == '.json'
          ? path
          : '$path.json';
      final EncodingSettingsSnapshot snapshot = _exportConfig
          .buildEncodingSettingsSnapshot();
      final String jsonText = const JsonEncoder.withIndent(
        '  ',
      ).convert(snapshot.toJson());
      await File(resolvedPath).writeAsString('$jsonText\n');
      statusMessage = '编码参数配置已导出到 $resolvedPath';
    } catch (error) {
      statusMessage = '导出编码参数配置失败: $error';
    }
    notifyListeners();
  }

  Future<void> importEncodingSettings() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['json'],
        withData: true,
      );
      if (result == null) {
        return;
      }
      final PlatformFile file = result.files.single;
      final String content;
      if (file.path != null && file.path!.isNotEmpty) {
        content = await File(file.path!).readAsString();
      } else if (file.bytes != null) {
        content = utf8.decode(file.bytes!);
      } else {
        throw const FormatException('无法读取所选配置文件。');
      }
      final EncodingSettingsSnapshot snapshot =
          EncodingSettingsSnapshot.fromJson(
            jsonDecode(content) as Map<String, dynamic>,
          );
      _exportConfig.applyEncodingSettingsSnapshot(snapshot);
      statusMessage = '已导入编码参数配置: ${file.name}';
    } catch (error) {
      statusMessage = '导入编码参数配置失败: $error';
    }
    notifyListeners();
  }

  Future<void> togglePlayback() async {
    await _mediaOps.togglePlayback();
  }

  Future<void> seekRelative(Duration delta) async {
    await _mediaOps.seekRelative(delta);
  }

  Future<void> seekTo(Duration position) async {
    await _mediaOps.seekTo(position);
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

  void setAudioStreamConfig(String key, AudioStreamConfig value) {
    audioStreamConfigs[key] = value;
    notifyListeners();
  }

  void setAudioDefaultProfile(AudioStreamConfig value) {
    audioDefaultProfile = value;
    _syncAudioStreamConfigsWithMedia(resetExisting: true);
    notifyListeners();
  }

  void setVideoEncodingMode(String encoderKey, String mode) {
    final VideoEncodingConfig current = _videoEncodingConfigFor(encoderKey);
    videoEncodingConfigs[encoderKey] = current.copyWith(
      mode: mode,
      userOverridden: true,
    );
    notifyListeners();
  }

  void setVideoEncodingField(
    String encoderKey, {
    int? crf,
    String? bitrate,
    String? maxrate,
    String? minrate,
    String? bufsize,
    int? qpI,
    int? qpP,
    int? qpB,
  }) {
    final VideoEncodingConfig current = _videoEncodingConfigFor(encoderKey);
    videoEncodingConfigs[encoderKey] = current.copyWith(
      userOverridden: true,
      crf: crf,
      bitrate: bitrate,
      maxrate: maxrate,
      minrate: minrate,
      bufsize: bufsize,
      qpI: qpI,
      qpP: qpP,
      qpB: qpB,
    );
    notifyListeners();
  }

  void reconcileVideoEncodingMode(String encoderKey) {
    final List<String> supported =
        kSupportedRcModes[encoderKey] ?? const <String>[];
    final VideoEncodingConfig current = _videoEncodingConfigFor(encoderKey);
    if (supported.contains(current.mode)) {
      return;
    }
    videoEncodingConfigs[encoderKey] = VideoEncodingConfig.defaultsFor(
      encoderKey,
    );
    notifyListeners();
  }

  void setToneMappingConfig(ToneMappingConfig value) {
    toneMappingConfig = value;
    notifyListeners();
  }

  void setContinueOnMissingFont(bool value) {
    continueOnMissingFont = value;
    notifyListeners();
  }

  void setSourceHanEllipsisFix(bool value) {
    sourceHanEllipsisFix = value;
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

  void setSeasonNumber(String value) {
    seasonNumber = value;
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

  void setEpisodicNamingTemplate(String value) {
    episodicNamingTemplate = value;
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
    _mediaOps.updateBindingMeta(
      key: key,
      languageCode: languageCode,
      regionCode: regionCode,
      trackName: trackName,
    );
  }

  void removeFontSource(String path) {
    _mediaOps.removeFontSource(path);
  }

  void removeCustomBinding(String key) {
    _mediaOps.removeCustomBinding(key);
  }

  void toggleHardsubBindingSelection(String key, bool value) {
    _mediaOps.toggleHardsubBindingSelection(key, value);
  }

  void toggleMuxBindingSelection(String key, bool value) {
    _mediaOps.toggleMuxBindingSelection(key, value);
  }

  void removeAllEmbeddedSubtitles() {
    _mediaOps.removeAllEmbeddedSubtitles();
  }

  Future<void> selectPreviewSubtitle(String value) async {
    await _mediaOps.selectPreviewSubtitle(value);
  }

  void updateChapterTitle(int index, String value) {
    _mediaOps.updateChapterTitle(index, value);
  }

  void updateChapterStart(int index, String value) {
    _mediaOps.updateChapterStart(index, value);
  }

  void updateChapterEnd(int index, String value) {
    _mediaOps.updateChapterEnd(index, value);
  }

  void addChapter() {
    _mediaOps.addChapter();
  }

  void removeChapter(int index) {
    _mediaOps.removeChapter(index);
  }

  void updateStreamEnabled(int index, bool value) {
    _mediaOps.updateStreamEnabled(index, value);
  }

  void updateStreamTitle(int index, String value) {
    _mediaOps.updateStreamTitle(index, value);
  }

  void updateStreamLanguage(int index, String value) {
    _mediaOps.updateStreamLanguage(index, value);
  }

  void updateStreamDefault(int index, bool value) {
    _mediaOps.updateStreamDefault(index, value);
  }

  void updateStreamForced(int index, bool value) {
    _mediaOps.updateStreamForced(index, value);
  }

  void removeStream(int index) {
    _mediaOps.removeStream(index);
  }

  bool isStreamExtractable(MediaStreamEntry stream) {
    return _mediaOps.isStreamExtractable(stream);
  }

  bool isStreamSelectedForExtraction(MediaStreamEntry stream) {
    return _mediaOps.isStreamSelectedForExtraction(stream);
  }

  bool shouldUseCompatibleSubtitlePreview(MediaStreamEntry stream) {
    return _mediaOps.shouldUseCompatibleSubtitlePreview(stream);
  }

  bool supportsDirectEmbeddedSubtitlePreview(MediaStreamEntry stream) {
    return _mediaOps.supportsDirectEmbeddedSubtitlePreview(stream);
  }

  bool shouldFallbackToCompatibleSubtitlePreview(MediaStreamEntry stream) {
    return _mediaOps.shouldFallbackToCompatibleSubtitlePreview(stream);
  }

  bool canExtractSubtitleForPreview(MediaStreamEntry stream) {
    return _mediaOps.canExtractSubtitleForPreview(stream);
  }

  void toggleStreamExtractionSelection(MediaStreamEntry stream, bool value) {
    _mediaOps.toggleStreamExtractionSelection(stream, value);
  }

  void setAllExtractableStreamSelections(bool value) {
    _mediaOps.setAllExtractableStreamSelections(value);
  }

  Future<void> extractSelectedStreams() async {
    await _mediaOps.extractSelectedStreams();
  }

  void updateEncoderPreset(String key, String value) {
    encoderTunings[key] = encoderTunings[key]!.copyWith(preset: value);
    notifyListeners();
  }

  void updateEncoderTune(String key, String value) {
    encoderTunings[key] = encoderTunings[key]!.copyWith(tune: value);
    notifyListeners();
  }

  @visibleForTesting
  EncodingSettingsSnapshot debugBuildEncodingSettingsSnapshot() {
    return _exportConfig.buildEncodingSettingsSnapshot();
  }

  @visibleForTesting
  void debugApplyEncodingSettingsSnapshot(EncodingSettingsSnapshot snapshot) {
    _exportConfig.applyEncodingSettingsSnapshot(snapshot);
    if (snapshot.importStatusMessage != null) {
      statusMessage = snapshot.importStatusMessage;
    }
    notifyListeners();
  }

  @visibleForTesting
  void debugSetMediaInfo(MediaInfo? value) {
    mediaInfo = value;
    if (value != null) {
      _syncAudioStreamConfigsWithMedia(resetExisting: true);
      _appendHdrToneMappingNoticeIfNeeded();
    }
    notifyListeners();
  }

  void _markChanged() {
    notifyListeners();
  }

  Future<void> exportNow(
    ExportProfile profile,
    List<String> bindingKeys,
  ) async {
    await _queueRunner.exportNow(profile, bindingKeys);
  }

  Future<void> enqueueTask(
    ExportProfile profile,
    List<String> bindingKeys,
  ) async {
    await _queueRunner.enqueueTask(profile, bindingKeys);
  }

  Future<void> enqueueSelectedTasks() async {
    await _queueRunner.enqueueSelectedTasks();
  }

  Future<void> enqueueSelectedHardsubTasks() async {
    await _queueRunner.enqueueSelectedHardsubTasks();
  }

  Future<void> enqueueSelectedMuxTask() async {
    await _queueRunner.enqueueSelectedMuxTask();
  }

  Future<void> runQueue() async {
    await _queueRunner.runQueue();
  }

  Future<void> stopAllTasks() async {
    await _queueRunner.stopAllTasks();
  }

  void clearCompleted() {
    _queueRunner.clearCompleted();
  }

  void clearQueue() {
    _queueRunner.clearQueue();
  }

  Future<void> retryAll() async {
    await _queueRunner.retryAll();
  }

  @override
  void dispose() {
    if (_playerInitialized) {
      unawaited(player.dispose());
    }
    unawaited(_mediaOps.resetPreviewSubtitleArtifacts());
    super.dispose();
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
    _syncAudioStreamConfigsWithMedia();
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

  String _audioStreamConfigKey(String inputPath, int streamIndex) {
    return '$inputPath#$streamIndex';
  }

  VideoEncodingConfig _videoEncodingConfigFor(String encoderKey) {
    return videoEncodingConfigs.putIfAbsent(
      encoderKey,
      () => VideoEncodingConfig.defaultsFor(encoderKey),
    );
  }

  void _syncAudioStreamConfigsWithMedia({bool resetExisting = false}) {
    final MediaInfo? info = mediaInfo;
    if (info == null) {
      return;
    }
    final Set<String> activeKeys = <String>{};
    for (final MediaStreamEntry stream in info.streams.where(
      (MediaStreamEntry stream) =>
          stream.kind == StreamKind.audio &&
          stream.origin == StreamOrigin.input,
    )) {
      final String key = _audioStreamConfigKey(info.inputPath, stream.index);
      activeKeys.add(key);
      if (resetExisting || !audioStreamConfigs.containsKey(key)) {
        audioStreamConfigs[key] = audioDefaultProfile.copyWith();
      }
    }
    audioStreamConfigs.removeWhere(
      (String key, AudioStreamConfig _) =>
          key.startsWith('${info.inputPath}#') && !activeKeys.contains(key),
    );
  }

  void _appendHdrToneMappingNoticeIfNeeded() {
    final VideoStreamInfo? video = mediaInfo?.primaryVideo;
    if (video == null ||
        _hdrToneMappingNoticeShown ||
        toneMappingConfig.tonemapMode != 'auto') {
      return;
    }
    final SourceColorClass colorClass = detectSourceColorClass(video);
    if (colorClass != SourceColorClass.hdrPq &&
        colorClass != SourceColorClass.hdrHlg &&
        colorClass != SourceColorClass.dolbyVision) {
      return;
    }
    const String notice = '已自动启用色调映射 (HDR → BT.709)，可在 色调映射 选项卡中查看与覆盖。';
    statusMessage = statusMessage == null || statusMessage!.isEmpty
        ? notice
        : '${statusMessage!}\n$notice';
    _hdrToneMappingNoticeShown = true;
  }
}

class _EncoderSelection {
  const _EncoderSelection({required this.encoder, required this.codecFamily});

  final String encoder;
  final String codecFamily;
}
