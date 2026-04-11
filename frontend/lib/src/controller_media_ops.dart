// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

part of 'controller.dart';

class _MediaOps {
  _MediaOps(this._controller);

  final AemtController _controller;

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
    if (!_controller.diagnostics.ffprobe.available) {
      _controller.statusMessage = '缺少 ffprobe，无法解析媒体。';
      _controller.notifyListeners();
      return;
    }
    _controller.analyzing = true;
    _controller.statusMessage = '正在解析媒体信息...';
    _controller.notifyListeners();
    try {
      await resetPreviewSubtitleArtifacts();
      _controller.selectedStreamExtractionKeys.clear();
      _controller.streamExtractionMessage = null;
      final ProcessResult result = await Process.run(
        _controller.diagnostics.ffprobe.path!,
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
      _controller.mediaInfo = parseMediaInfo(
        path,
        jsonDecode(result.stdout.toString()) as Map<String, dynamic>,
      );
      _controller.titleOverride = p.basenameWithoutExtension(path);
      _controller.outputFileNameOverride = p.basenameWithoutExtension(path);
      _controller.outputResolution =
          _controller.mediaInfo!.width == 0 || _controller.mediaInfo!.height == 0
          ? ''
          : '${_controller.mediaInfo!.width}x${_controller.mediaInfo!.height}';
      _controller.outputFps = _controller.mediaInfo!.fps <= 0
          ? ''
          : _controller.mediaInfo!.fps.toStringAsFixed(3);
      _controller.removedEmbeddedSubtitleIndexes.clear();
      _controller.outputDirectory = _controller.outputDirectory.isEmpty
          ? p.join(p.dirname(path), 'outputs')
          : _controller.outputDirectory;
      _controller.statusMessage = '已解析 ${_controller.mediaInfo!.streams.length} 条流。';
      await _controller.player.open(Media(path), play: false);
      await _controller.player.setSubtitleTrack(SubtitleTrack.no());
      _controller.previewSubtitleKey = 'off';
      _controller._syncExternalSubtitleStreams();
    } catch (error) {
      _controller.statusMessage = '解析失败: $error';
    } finally {
      _controller.analyzing = false;
      _controller.notifyListeners();
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
    _controller._replaceBinding(
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
    final int nextIndex = _controller.customBindings.length + 1;
    final String key = 'custom_$nextIndex';
    _controller.customBindings.add(
      SubtitleBinding(
        key: key,
        label: '自定义字幕 $nextIndex',
        languageCode: '',
        regionCode: '',
        trackName: '',
        filePath: path,
      ),
    );
    _controller.selectedHardsubBindingKeys.add(key);
    _controller.selectedMuxBindingKeys.add(key);
    _controller._syncExternalSubtitleStreams();
    _controller.notifyListeners();
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
      if (file.path != null && !_controller.importedFontSources.contains(file.path)) {
        _controller.importedFontSources.add(file.path!);
        _controller.importedFontEntries[file.path!] =
            await _controller._fontAssetService.inspectSource(file.path!);
      }
    }
    _controller.notifyListeners();
  }

  Future<void> togglePlayback() async {
    if (_controller.player.state.playing) {
      await _controller.player.pause();
    } else {
      await _controller.player.play();
    }
  }

  Future<void> seekRelative(Duration delta) async {
    final Duration target = _controller.player.state.position + delta;
    await _controller.player.seek(target < Duration.zero ? Duration.zero : target);
  }

  Future<void> seekTo(Duration position) async {
    await _controller.player.seek(position < Duration.zero ? Duration.zero : position);
  }

  void updateBindingMeta({
    required String key,
    String? languageCode,
    String? regionCode,
    String? trackName,
  }) {
    _controller._replaceBinding(
      key,
      (SubtitleBinding binding) => binding.copyWith(
        languageCode: languageCode,
        regionCode: regionCode,
        trackName: trackName,
      ),
    );
  }

  void removeFontSource(String path) {
    _controller.importedFontSources.remove(path);
    _controller.importedFontEntries.remove(path);
    _controller.notifyListeners();
  }

  void removeCustomBinding(String key) {
    _controller.customBindings.removeWhere(
      (SubtitleBinding binding) => binding.key == key,
    );
    _controller.selectedHardsubBindingKeys.remove(key);
    _controller.selectedMuxBindingKeys.remove(key);
    _controller._syncExternalSubtitleStreams();
    _controller.notifyListeners();
  }

  void toggleHardsubBindingSelection(String key, bool value) {
    if (value) {
      _controller.selectedHardsubBindingKeys.add(key);
    } else {
      _controller.selectedHardsubBindingKeys.remove(key);
    }
    _controller.notifyListeners();
  }

  void toggleMuxBindingSelection(String key, bool value) {
    if (value) {
      _controller.selectedMuxBindingKeys.add(key);
    } else {
      _controller.selectedMuxBindingKeys.remove(key);
    }
    _controller.notifyListeners();
  }

  void removeAllEmbeddedSubtitles() {
    if (_controller.mediaInfo == null) {
      return;
    }
    _controller.removedEmbeddedSubtitleIndexes.addAll(
      _controller.mediaInfo!.streams
          .where(
            (MediaStreamEntry stream) =>
                stream.origin == StreamOrigin.input &&
                stream.kind == StreamKind.subtitle,
          )
          .map((MediaStreamEntry stream) => stream.index),
    );
    _controller.mediaInfo = _controller.mediaInfo!.copyWith(
      streams: _controller.mediaInfo!.streams
          .where(
            (MediaStreamEntry stream) =>
                !(stream.origin == StreamOrigin.input &&
                    stream.kind == StreamKind.subtitle &&
                    _controller.removedEmbeddedSubtitleIndexes.contains(stream.index)),
          )
          .toList(),
    );
    _controller.notifyListeners();
  }

  Future<void> selectPreviewSubtitle(String value) async {
    final String previousValue = _controller.previewSubtitleKey;
    _controller.previewSubtitleKey = value;
    _controller.notifyListeners();
    try {
      if (value == 'off') {
        await _controller.player.setSubtitleTrack(SubtitleTrack.no());
        return;
      }
      if (value.startsWith('external:')) {
        final String key = value.substring('external:'.length);
        final SubtitleBinding? binding = _controller._findBindingByKey(key);
        if (binding?.filePath != null) {
          await _controller.player.setSubtitleTrack(
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
        final int? streamIndex = int.tryParse(value.substring('compat:'.length));
        if (streamIndex == null) {
          throw Exception('无效的兼容预览字幕索引。');
        }
        final MediaStreamEntry stream = _findInputStreamByIndex(streamIndex);
        final String subtitlePath = await _extractPreviewSubtitleToTemp(stream);
        await _controller.player.setSubtitleTrack(
          SubtitleTrack.uri(
            subtitlePath,
            title: stream.title.isNotEmpty ? stream.title : '内封字幕 ${stream.index}',
            language: stream.language,
          ),
        );
        return;
      }
      if (value.startsWith('embedded:')) {
        final String id = value.substring('embedded:'.length);
        final Iterable<SubtitleTrack> matches = _controller.player.state.tracks.subtitle
            .where((SubtitleTrack track) => track.id == id);
        if (matches.isNotEmpty) {
          await _controller.player.setSubtitleTrack(matches.first);
          return;
        }
      }
      throw Exception('预览播放器未暴露该字幕轨。');
    } catch (error) {
      _controller.previewSubtitleKey = previousValue == value ? 'off' : previousValue;
      await _controller.player.setSubtitleTrack(SubtitleTrack.no());
      _controller.statusMessage = '字幕预览失败: $error';
      _controller.notifyListeners();
    }
  }

  void updateChapterTitle(int index, String value) {
    _updateChapter(index, (ChapterEntry chapter) => chapter.copyWith(title: value));
  }

  void updateChapterStart(int index, String value) {
    final Duration? parsed = parseTimestamp(value);
    if (parsed != null) {
      _updateChapter(index, (ChapterEntry chapter) => chapter.copyWith(start: parsed));
    }
  }

  void updateChapterEnd(int index, String value) {
    final Duration? parsed = parseTimestamp(value);
    if (parsed != null) {
      _updateChapter(index, (ChapterEntry chapter) => chapter.copyWith(end: parsed));
    }
  }

  void addChapter() {
    if (_controller.mediaInfo == null) {
      return;
    }
    final List<ChapterEntry> next = List<ChapterEntry>.from(_controller.mediaInfo!.chapters);
    next.add(
      ChapterEntry(
        title: 'Episode',
        start: next.isEmpty ? Duration.zero : next.last.end,
        end: _controller.mediaInfo!.duration,
      ),
    );
    _controller.mediaInfo = _controller.mediaInfo!.copyWith(chapters: next);
    _controller.notifyListeners();
  }

  void removeChapter(int index) {
    if (_controller.mediaInfo == null) {
      return;
    }
    final List<ChapterEntry> next = List<ChapterEntry>.from(_controller.mediaInfo!.chapters)
      ..removeAt(index);
    _controller.mediaInfo = _controller.mediaInfo!.copyWith(chapters: next);
    _controller.notifyListeners();
  }

  void updateStreamEnabled(int index, bool value) {
    _updateStream(index, (MediaStreamEntry stream) => stream.copyWith(enabled: value));
  }

  void updateStreamTitle(int index, String value) {
    _updateStream(index, (MediaStreamEntry stream) => stream.copyWith(title: value));
  }

  void updateStreamLanguage(int index, String value) {
    _updateStream(index, (MediaStreamEntry stream) => stream.copyWith(language: value));
  }

  void updateStreamDefault(int index, bool value) {
    _updateStream(index, (MediaStreamEntry stream) => stream.copyWith(isDefault: value));
  }

  void updateStreamForced(int index, bool value) {
    _updateStream(index, (MediaStreamEntry stream) => stream.copyWith(isForced: value));
  }

  void removeStream(int index) {
    if (_controller.mediaInfo == null) {
      return;
    }
    final MediaStreamEntry target = _controller.mediaInfo!.streams[index];
    if (target.origin == StreamOrigin.input) {
      _updateStream(index, (MediaStreamEntry stream) => stream.copyWith(enabled: false));
      return;
    }
    final List<MediaStreamEntry> inputStreams = _controller.mediaInfo!.streams
        .where((MediaStreamEntry stream) => stream.origin == StreamOrigin.input)
        .toList();
    final SubtitleBinding? binding = _controller._findBindingByPath(target.externalPath);
    if (binding != null) {
      _controller._clearBindingFile(binding.key);
    }
    _controller.mediaInfo = _controller.mediaInfo!.copyWith(streams: inputStreams);
    _controller._syncExternalSubtitleStreams();
    _controller.notifyListeners();
  }

  bool isStreamExtractable(MediaStreamEntry stream) {
    return stream.origin == StreamOrigin.input &&
        stream.kind != StreamKind.data &&
        stream.kind != StreamKind.unknown;
  }

  bool isStreamSelectedForExtraction(MediaStreamEntry stream) {
    return _controller.selectedStreamExtractionKeys.contains(_streamSelectionKey(stream));
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
      _controller.selectedStreamExtractionKeys.add(key);
    } else {
      _controller.selectedStreamExtractionKeys.remove(key);
    }
    _controller.notifyListeners();
  }

  void setAllExtractableStreamSelections(bool value) {
    if (_controller.mediaInfo == null) {
      return;
    }
    if (value) {
      _controller.selectedStreamExtractionKeys
        ..clear()
        ..addAll(_controller.mediaInfo!.streams.where(isStreamExtractable).map(_streamSelectionKey));
    } else {
      _controller.selectedStreamExtractionKeys.clear();
    }
    _controller.notifyListeners();
  }

  Future<void> extractSelectedStreams() async {
    final MediaInfo? info = _controller.mediaInfo;
    if (info == null || _controller.streamExtractionRunning) {
      return;
    }
    if (!_controller.diagnostics.ffmpeg.available) {
      _controller.statusMessage = '缺少 ffmpeg，无法抽取流。';
      _controller.notifyListeners();
      return;
    }
    final List<MediaStreamEntry> selectedStreams = info.streams
        .where(
          (MediaStreamEntry stream) =>
              isStreamExtractable(stream) &&
              _controller.selectedStreamExtractionKeys.contains(_streamSelectionKey(stream)),
        )
        .toList();
    if (selectedStreams.isEmpty) {
      _controller.streamExtractionMessage = '请先在流面板选择要抽取的流。';
      _controller.notifyListeners();
      return;
    }
    _controller.streamExtractionRunning = true;
    _controller.streamExtractionMessage = '正在抽取 ${selectedStreams.length} 条流...';
    _controller.notifyListeners();
    try {
      final String outputDir = _defaultStreamExtractionDirectory(info);
      await Directory(outputDir).create(recursive: true);
      final List<String> outputs = <String>[];
      final List<MediaStreamEntry> attachmentStreams = selectedStreams
          .where((MediaStreamEntry stream) => stream.kind == StreamKind.attachment)
          .toList();
      if (attachmentStreams.isNotEmpty) {
        outputs.addAll(
          await _controller._fontAssetService.extractInputAttachmentStreams(
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
      _controller.streamExtractionMessage = '流抽取完成，共生成 ${outputs.length} 个文件。';
      _controller.statusMessage = '已抽取到 $outputDir';
    } catch (error) {
      _controller.streamExtractionMessage = '流抽取失败: $error';
      _controller.statusMessage = _controller.streamExtractionMessage;
    } finally {
      _controller.streamExtractionRunning = false;
      _controller.notifyListeners();
    }
  }

  Future<void> resetPreviewSubtitleArtifacts() async {
    _controller._previewSubtitleCache.clear();
    final Directory? directory = _controller._previewSubtitleTempDirectory;
    _controller._previewSubtitleTempDirectory = null;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<String> _extractSingleInputStream(
    MediaInfo info,
    MediaStreamEntry stream,
    String outputDir,
  ) async {
    final String outputPath = _buildStreamExtractionOutputPath(info, stream, outputDir);
    await Directory(p.dirname(outputPath)).create(recursive: true);
    final List<String> arguments = _buildSingleStreamExtractionArguments(
      info: info,
      stream: stream,
      outputPath: outputPath,
    );
    final ProcessResult extraction = await Process.run(
      _controller.diagnostics.ffmpeg.path!,
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

  String _streamSelectionKey(MediaStreamEntry stream) {
    return '${stream.origin.index}:${stream.index}:${stream.externalPath ?? ''}';
  }

  String _defaultStreamExtractionDirectory(MediaInfo info) {
    final String configured = _controller.outputDirectory.trim();
    if (configured.isNotEmpty) {
      return configured;
    }
    return p.join(p.dirname(info.inputPath), 'extracted_streams');
  }

  MediaStreamEntry _findInputStreamByIndex(int streamIndex) {
    final MediaInfo? info = _controller.mediaInfo;
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
    if (stream.kind != StreamKind.subtitle || stream.origin != StreamOrigin.input) {
      return false;
    }
    return <String>{'arib_caption'}.contains(stream.codec.trim().toLowerCase());
  }

  bool _supportsDirectEmbeddedSubtitlePreview(MediaStreamEntry stream) {
    if (stream.kind != StreamKind.subtitle || stream.origin != StreamOrigin.input) {
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
    if (stream.kind != StreamKind.subtitle || stream.origin != StreamOrigin.input) {
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
    final String? cachedPath = _controller._previewSubtitleCache[stream.index];
    if (cachedPath != null && File(cachedPath).existsSync()) {
      return cachedPath;
    }
    final MediaInfo info = _controller.mediaInfo!;
    final Directory tempDir = await _ensurePreviewSubtitleTempDirectory();
    final String outputPath = p.join(tempDir.path, 'preview_sub_${stream.index}.ass');
    _controller.statusMessage = '正在转换内封字幕 ${stream.index} 为兼容预览格式...';
    _controller.notifyListeners();
    final ProcessResult extraction = await Process.run(
      _controller.diagnostics.ffmpeg.path!,
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
    _controller._previewSubtitleCache[stream.index] = outputPath;
    _controller.statusMessage = '已生成兼容预览字幕。';
    _controller.notifyListeners();
    return outputPath;
  }

  Future<Directory> _ensurePreviewSubtitleTempDirectory() async {
    final Directory? existing = _controller._previewSubtitleTempDirectory;
    if (existing != null && existing.existsSync()) {
      return existing;
    }
    final Directory created = await Directory.systemTemp.createTemp('aemt_preview_');
    _controller._previewSubtitleTempDirectory = created;
    return created;
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
        final String extension = _canExtractSubtitleAsAss(stream) ? 'ass' : 'mks';
        return p.join(outputDir, '$baseName.subtitle${stream.index}.$extension');
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
    final String sanitized = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return sanitized.isEmpty ? 'stream' : sanitized;
  }

  void _updateChapter(
    int index,
    ChapterEntry Function(ChapterEntry chapter) transform,
  ) {
    if (_controller.mediaInfo == null) {
      return;
    }
    final List<ChapterEntry> chapters = List<ChapterEntry>.from(
      _controller.mediaInfo!.chapters,
    );
    chapters[index] = transform(chapters[index]);
    _controller.mediaInfo = _controller.mediaInfo!.copyWith(chapters: chapters);
    _controller.notifyListeners();
  }

  void _updateStream(
    int index,
    MediaStreamEntry Function(MediaStreamEntry stream) transform,
  ) {
    if (_controller.mediaInfo == null) {
      return;
    }
    final List<MediaStreamEntry> streams = List<MediaStreamEntry>.from(
      _controller.mediaInfo!.streams,
    );
    streams[index] = transform(streams[index]);
    _controller.mediaInfo = _controller.mediaInfo!.copyWith(streams: streams);
    _controller.notifyListeners();
  }
}