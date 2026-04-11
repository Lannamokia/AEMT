part of 'controller.dart';

class _TaskPlanner {
  _TaskPlanner(this._controller);

  final AemtController _controller;

  Future<TaskPlan> buildTaskPlan(ExportTask task) async {
    final MediaInfo? info = _controller.mediaInfo;
    if (info == null) {
      throw Exception('请先导入视频。');
    }
    if (!_controller.diagnostics.ffmpeg.available) {
      throw Exception('缺少 ffmpeg，无法导出。');
    }
    if (_controller.outputDirectory.isEmpty) {
      throw Exception('请先设置输出目录。');
    }
    if (_controller.compressionMode == CompressionMode.episodic) {
      final String template = _controller._exportConfig.resolvedEpisodicNamingTemplate;
      if (template.isEmpty) {
        throw Exception('请先填写命名格式。');
      }
      final List<String> unknownVariables = _controller._exportConfig
          .findUnknownTemplateVariables(template);
      if (unknownVariables.isNotEmpty) {
        throw Exception('命名格式包含未知变量: ${unknownVariables.join(', ')}');
      }
      final List<String> missingInputs = _controller._exportConfig
          .findMissingTemplateInputs(template);
      if (missingInputs.isNotEmpty) {
        throw Exception('命名格式依赖但尚未填写的字段: ${missingInputs.join('、')}');
      }
    }
    final ({int width, int height})? resolution = parseResolution(
      _controller.outputResolution.trim(),
    );
    final double? fps = double.tryParse(_controller.outputFps.trim());
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
    final List<ResolvedFontFile> fontFiles = await _controller._fontAssetService
        .resolveFontFiles(_controller.importedFontSources, workDir.path);
    final String outputPath = task.outputPath;
    await Directory(_controller.outputDirectory).create(recursive: true);
    final List<SubtitleBinding> bindings = _controller._resolveBindings(task.bindingKeys);
    _controller._validateTaskBindings(task.profile, bindings);
    if (task.profile == ExportProfile.muxMkv) {
      final List<ResolvedFontFile> extractedAttachments =
          await _controller._fontAssetService.extractEnabledInputAttachments(
            info,
            workDir.path,
          );
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
    if (!_controller._isBindingEnabled(info, binding)) {
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
    final _EncoderSelection encoder = resolveEncoder(enabledVideo.first.codec);
    final List<String> args = <String>[
      '-y',
      '-hide_banner',
      '-nostats',
      '-progress',
      'pipe:2',
      ..._buildPrimaryInputArguments(encoder, info.inputPath),
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
      _controller.outputFps.trim(),
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
      commandPreview: renderCommand(_controller.diagnostics.ffmpeg.path!, args),
      steps: <CommandStep>[
        CommandStep(
          executable: _controller.diagnostics.ffmpeg.path!,
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
    if (!_controller.diagnostics.mkvpropedit.available) {
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
    final _EncoderSelection encoder = resolveEncoder(
      enabledVideo.first.codec,
      preferredCodecFamily: 'hevc',
    );
    final List<String> args = <String>[
      '-y',
      '-hide_banner',
      '-nostats',
      '-progress',
      'pipe:2',
      ..._buildPrimaryInputArguments(encoder, info.inputPath),
    ];
    final List<MediaStreamEntry> selectedExternalSubtitle = enabledExternalSubtitle
        .where(
          (MediaStreamEntry stream) => bindings.any(
            (SubtitleBinding binding) => binding.filePath == stream.externalPath,
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
      _controller.outputFps.trim(),
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
        renderCommand(_controller.diagnostics.ffmpeg.path!, args),
        renderCommand(
          _controller.diagnostics.mkvpropedit.path!,
          _buildMkvSubtitleMetadataArguments(outputPath, <MediaStreamEntry>[
            ...enabledSubtitle,
            ...selectedExternalSubtitle,
          ]),
        ),
      ].join('\n\n'),
      steps: <CommandStep>[
        CommandStep(
          executable: _controller.diagnostics.ffmpeg.path!,
          arguments: args,
          description: '导出简繁内封 MKV',
        ),
        CommandStep(
          executable: _controller.diagnostics.mkvpropedit.path!,
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
    final EncoderTuning tuning = _controller.encoderTunings[selection.encoder]!;
    final List<String> args = <String>[
      '-b:v',
      selection.codecFamily == 'hevc'
          ? _controller.hevcBitrate
          : _controller.avcBitrate,
      '-maxrate',
      selection.codecFamily == 'hevc'
          ? _controller.hevcMaxrate
          : _controller.avcMaxrate,
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
      case 'hevc_qsv':
      case 'hevc_amf':
        return const <String>['-pix_fmt', 'p010le', '-profile:v', 'main10'];
      case 'libx265':
        return const <String>['-pix_fmt', 'yuv420p10le', '-profile:v', 'main10'];
      default:
        return const <String>[];
    }
  }

  List<String> _buildPrimaryInputArguments(
    _EncoderSelection selection,
    String inputPath,
  ) {
    final String? hwaccel = _resolveHardwareDecodeBackend(selection);
    if (hwaccel == null) {
      return <String>['-i', inputPath];
    }
    return <String>['-hwaccel', hwaccel, '-i', inputPath];
  }

  String? _resolveHardwareDecodeBackend(_EncoderSelection selection) {
    if (_controller.hardwareMode == HardwareMode.software) {
      return null;
    }
    final Set<String> availableHwaccels = _controller.diagnostics.hwaccels
        .map((String item) => item.trim().toLowerCase())
        .where((String item) => item.isNotEmpty)
        .toSet();
    if (availableHwaccels.isEmpty) {
      return null;
    }
    final List<String> preferredBackends = switch (_controller.hardwareMode) {
      HardwareMode.software => const <String>[],
      HardwareMode.nvenc => const <String>['cuda', 'd3d11va', 'dxva2'],
      HardwareMode.qsv => const <String>['d3d11va', 'dxva2', 'qsv'],
      HardwareMode.amf => const <String>['d3d11va', 'dxva2', 'amf'],
      HardwareMode.auto => _preferredAutoDecodeBackends(selection),
    };
    for (final String backend in preferredBackends) {
      if (availableHwaccels.contains(backend)) {
        return backend;
      }
    }
    return null;
  }

  List<String> _preferredAutoDecodeBackends(_EncoderSelection selection) {
    if (selection.encoder.contains('nvenc')) {
      return const <String>['cuda', 'd3d11va', 'dxva2'];
    }
    if (selection.encoder.contains('qsv')) {
      return const <String>['d3d11va', 'dxva2', 'qsv'];
    }
    if (selection.encoder.contains('amf')) {
      return const <String>['d3d11va', 'dxva2', 'amf'];
    }
    return const <String>['d3d11va', 'dxva2', 'cuda', 'qsv', 'amf'];
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
    final ({int width, int height})? resolution = parseResolution(
      _controller.outputResolution.trim(),
    );
    if (resolution == null) {
      return '';
    }
    return 'scale=${resolution.width}:${resolution.height}';
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
      buffer.writeln('title=${escapeMetadata(chapter.title)}');
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
      args.addAll(<String>['-metadata:s:$streamSpecifier', 'title=${stream.title}']);
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
    args.addAll(<String>['-disposition:$streamSpecifier', flags.isEmpty ? '0' : flags.join('+')]);
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
      final String languageTag = buildLanguageTag(stream);
      if (languageTag.isNotEmpty) {
        args.addAll(<String>['--set', 'language=$languageTag']);
      }
      args.addAll(<String>['--set', 'flag-default=${stream.isDefault ? 1 : 0}']);
      args.addAll(<String>['--set', 'flag-forced=${stream.isForced ? 1 : 0}']);
    }
    return args;
  }

  _EncoderSelection resolveEncoder(
    String videoCodec, {
    String? preferredCodecFamily,
  }) {
    final String codecFamily =
        preferredCodecFamily ??
        (videoCodec.contains('265') || videoCodec.contains('hevc') ? 'hevc' : 'avc');
    if (_controller.hardwareMode == HardwareMode.software) {
      return _EncoderSelection(
        encoder: codecFamily == 'hevc' ? 'libx265' : 'libx264',
        codecFamily: codecFamily,
      );
    }
    if (_controller.hardwareMode == HardwareMode.nvenc &&
        _controller.diagnostics.hasNvenc) {
      return _EncoderSelection(
        encoder: codecFamily == 'hevc' ? 'hevc_nvenc' : 'h264_nvenc',
        codecFamily: codecFamily,
      );
    }
    if (_controller.hardwareMode == HardwareMode.qsv &&
        _controller.diagnostics.hasQsv) {
      return _EncoderSelection(
        encoder: codecFamily == 'hevc' ? 'hevc_qsv' : 'h264_qsv',
        codecFamily: codecFamily,
      );
    }
    if (_controller.hardwareMode == HardwareMode.amf &&
        _controller.diagnostics.hasAmf) {
      return _EncoderSelection(
        encoder: codecFamily == 'hevc' ? 'hevc_amf' : 'h264_amf',
        codecFamily: codecFamily,
      );
    }
    if (_controller.diagnostics.hasNvenc) {
      return _EncoderSelection(
        encoder: codecFamily == 'hevc' ? 'hevc_nvenc' : 'h264_nvenc',
        codecFamily: codecFamily,
      );
    }
    if (_controller.diagnostics.hasQsv) {
      return _EncoderSelection(
        encoder: codecFamily == 'hevc' ? 'hevc_qsv' : 'h264_qsv',
        codecFamily: codecFamily,
      );
    }
    if (_controller.diagnostics.hasAmf) {
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
}