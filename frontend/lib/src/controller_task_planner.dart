part of 'controller.dart';

typedef _FontPipelineResult = ({
  List<ResolvedFontFile> fonts,
  Map<String, String> renameMap,
  List<String> warnings,
  List<String> assSubtitlePaths,
  Map<String, String> rewrittenAssPaths,
  List<CommandStep> subsetSteps,
});

class _SharedFontPipelineUse {
  const _SharedFontPipelineUse({
    required this.key,
    required this.result,
    required this.includeSubsetSteps,
  });

  final String key;
  final _FontPipelineResult result;
  final bool includeSubsetSteps;
}

class _SharedFontPipelineContext {
  _SharedFontPipelineContext({
    required this.key,
    required this.workDir,
    required this.result,
    required this.pendingTaskIds,
  });

  final String key;
  final String workDir;
  final _FontPipelineResult result;
  final Set<String> pendingTaskIds;
  bool executorAssigned = false;
  bool subsetReady = false;
  bool failed = false;
}

class _TaskPlanner {
  _TaskPlanner(this._controller);

  final AemtController _controller;

  Future<TaskPlan> buildTaskPlan(
    ExportTask task, {
    _SharedFontPipelineUse? sharedFontPipeline,
  }) async {
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
      final String template =
          _controller._exportConfig.resolvedEpisodicNamingTemplate;
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
    try {
      final String? chapterMetadataPath = await _writeChapterMetadata(
        workDir.path,
        info.chapters,
      );
      final String outputPath = task.outputPath;
      await Directory(_controller.outputDirectory).create(recursive: true);
      final List<SubtitleBinding> bindings = _controller._resolveBindings(
        task.bindingKeys,
      );
      _controller._validateTaskBindings(task.profile, bindings);
      final _FontPipelineResult? sharedResult = sharedFontPipeline == null
          ? null
          : _fontPipelineWithSubsetSteps(
              sharedFontPipeline.result,
              includeSubsetSteps: sharedFontPipeline.includeSubsetSteps,
            );
      if (task.profile == ExportProfile.muxMkv) {
        final _FontPipelineResult fontPipeline =
            sharedResult ??
            await _runFontPipelineForBindings(bindings, workDir.path);
        return _buildMuxPlan(
          info: info,
          bindings: bindings,
          fontPipeline: fontPipeline,
          outputPath: outputPath,
          workDir: workDir.path,
          chapterMetadataPath: chapterMetadataPath,
          sharedFontPipelineKey: sharedFontPipeline?.key,
        );
      }
      final _FontPipelineResult fontPipeline =
          sharedResult ??
          await _runFontPipelineForBindings(bindings, workDir.path);
      return _buildHardsubPlan(
        info: info,
        binding: bindings.first,
        outputPath: outputPath,
        workDir: workDir.path,
        chapterMetadataPath: chapterMetadataPath,
        fontPipeline: fontPipeline,
        sharedFontPipelineKey: sharedFontPipeline?.key,
      );
    } catch (_) {
      await _controller._deleteOwnedTempDirectory(workDir.path);
      rethrow;
    }
  }

  Future<_FontPipelineResult> _runFontPipelineForBindings(
    List<SubtitleBinding> bindings,
    String workDir,
  ) async {
    final DebugFontResolver? debugFontResolver = _controller.debugFontResolver;
    final List<ResolvedFontFile> importedFonts = debugFontResolver == null
        ? await _controller._fontAssetService.resolveFontFiles(
            _controller.importedFontSources,
            workDir,
          )
        : await debugFontResolver(_controller.importedFontSources, workDir);
    final DebugAttachmentExtractor? debugAttachmentExtractor =
        _controller.debugAttachmentExtractor;
    final MediaInfo info = _controller.mediaInfo!;
    final List<ResolvedFontFile> extractedAttachments =
        debugAttachmentExtractor == null
        ? await _controller._fontAssetService.extractEnabledInputAttachments(
            info,
            workDir,
          )
        : await debugAttachmentExtractor(info, workDir);
    final DebugSystemFontResolver? debugSystemFontResolver =
        _controller.debugSystemFontResolver;
    final List<ResolvedFontFile> systemFonts = debugSystemFontResolver == null
        ? await _controller._fontAssetService.resolveSystemFontFiles()
        : await debugSystemFontResolver();
    return _runFontPipeline(
      bindings: bindings,
      importedFonts: importedFonts,
      extractedAttachments: extractedAttachments,
      systemFonts: systemFonts,
      workDir: workDir,
    );
  }

  _FontPipelineResult _fontPipelineWithSubsetSteps(
    _FontPipelineResult result, {
    required bool includeSubsetSteps,
  }) {
    if (includeSubsetSteps) {
      return result;
    }
    return (
      fonts: result.fonts,
      renameMap: result.renameMap,
      warnings: result.warnings,
      assSubtitlePaths: result.assSubtitlePaths,
      rewrittenAssPaths: result.rewrittenAssPaths,
      subsetSteps: <CommandStep>[],
    );
  }

  Future<_FontPipelineResult> _runFontPipeline({
    required List<SubtitleBinding> bindings,
    required List<ResolvedFontFile> importedFonts,
    required List<ResolvedFontFile> extractedAttachments,
    required List<ResolvedFontFile> systemFonts,
    required String workDir,
  }) async {
    final List<String> subtitlePaths = <String>[
      for (final SubtitleBinding binding in bindings)
        if (binding.filePath != null) binding.filePath!,
    ];
    final List<String> assSubtitlePaths = subtitlePaths
        .where(_isAssSubtitlePath)
        .toList();
    if (subtitlePaths.isEmpty) {
      return (
        fonts: <ResolvedFontFile>[],
        renameMap: <String, String>{},
        warnings: <String>[],
        assSubtitlePaths: assSubtitlePaths,
        rewrittenAssPaths: <String, String>{},
        subsetSteps: <CommandStep>[],
      );
    }
    final SubtitleCharIndex charIndex = await _controller._fontAssetService
        .indexSubtitleCharacters(subtitlePaths);
    final Map<String, Set<int>> matchableCodepoints = <String, Set<int>>{
      for (final MapEntry<String, Set<int>> entry
          in charIndex.codepointsByFontname.entries)
        if (entry.key != '__default__') entry.key: entry.value,
    };
    if (matchableCodepoints.isEmpty) {
      return (
        fonts: <ResolvedFontFile>[],
        renameMap: <String, String>{},
        warnings: <String>[],
        assSubtitlePaths: assSubtitlePaths,
        rewrittenAssPaths: <String, String>{},
        subsetSteps: <CommandStep>[],
      );
    }
    final SubtitleCharIndex matchableIndex = SubtitleCharIndex(
      matchableCodepoints,
    );
    final List<ResolvedFontFile> candidates = <ResolvedFontFile>[
      ...importedFonts,
      ...extractedAttachments,
      ...systemFonts,
    ];
    final FontMatchResult matchResult = _controller._fontAssetService
        .matchFonts(matchableIndex, candidates);
    if (matchResult.missing.isNotEmpty && !_controller.continueOnMissingFont) {
      throw Exception('未找到字体: ${matchResult.missing.first}');
    }
    final List<String> warnings = <String>[
      for (final String fontName in matchResult.missing)
        'WARN: 字体 $fontName 缺失',
    ];
    if (!_controller.fontSubsettingEnabled) {
      return (
        fonts: matchResult.matched.values.toList(),
        renameMap: <String, String>{},
        warnings: warnings,
        assSubtitlePaths: assSubtitlePaths,
        rewrittenAssPaths: <String, String>{},
        subsetSteps: <CommandStep>[],
      );
    }
    final RuntimeDiagnostics diagnostics = _controller.diagnostics;
    final String? pyftsubsetPath = diagnostics.pyftsubset.path;
    final String? ttxPath = diagnostics.ttx.path;
    if (matchResult.matched.isEmpty ||
        pyftsubsetPath == null ||
        pyftsubsetPath.isEmpty ||
        ttxPath == null ||
        ttxPath.isEmpty) {
      if (matchResult.matched.isNotEmpty) {
        warnings.add('未找到 pyftsubset/ttx，已跳过字体子集化与 ASS 重写');
      }
      return (
        fonts: matchResult.matched.values.toList(),
        renameMap: <String, String>{},
        warnings: warnings,
        assSubtitlePaths: assSubtitlePaths,
        rewrittenAssPaths: <String, String>{},
        subsetSteps: <CommandStep>[],
      );
    }
    final List<FontSubsetStepPlan> subsetPlans = _controller._fontAssetService
        .planSubsetFontSteps(
          matchableIndex,
          matchResult.matched,
          workDir,
          pyftsubsetPath: pyftsubsetPath,
          ttxPath: ttxPath,
          aemtVersion: '1.0.0',
          fontToolsVersion: diagnostics.fontToolsVersion?.toString(),
          sourceHanEllipsisFix: _controller.sourceHanEllipsisFix,
        );
    final Map<String, String> renameMap = <String, String>{
      for (final FontSubsetStepPlan plan in subsetPlans)
        plan.normalizedKey: plan.randomName,
    };
    final Map<String, String> rewrittenAssPaths = renameMap.isEmpty
        ? <String, String>{}
        : await _rewriteAssSubtitles(
            assSubtitlePaths: assSubtitlePaths,
            renameMap: renameMap,
            workDir: workDir,
          );
    return (
      fonts: subsetPlans
          .map((FontSubsetStepPlan plan) => plan.outputFont)
          .toList(),
      renameMap: renameMap,
      warnings: warnings,
      assSubtitlePaths: assSubtitlePaths,
      rewrittenAssPaths: rewrittenAssPaths,
      subsetSteps: <CommandStep>[
        for (final FontSubsetStepPlan plan in subsetPlans)
          CommandStep(
            executable: plan.pyftsubsetPath,
            arguments: plan.pyftsubsetArguments,
            description: '子集化字幕字体',
            fontSubsetStep: plan,
          ),
      ],
    );
  }

  Future<Map<String, String>> _rewriteAssSubtitles({
    required List<String> assSubtitlePaths,
    required Map<String, String> renameMap,
    required String workDir,
  }) async {
    final Map<String, String> rewritten = <String, String>{};
    if (assSubtitlePaths.isEmpty || renameMap.isEmpty) {
      return rewritten;
    }
    final String outputDir = p.join(workDir, 'subtitles');
    await Directory(outputDir).create(recursive: true);
    for (final String originalPath in assSubtitlePaths) {
      final String outputPath = p.join(outputDir, p.basename(originalPath));
      await rewriteAssWithRenameMap(
        originalPath: originalPath,
        outputPath: outputPath,
        renameMap: renameMap,
      );
      rewritten[originalPath] = outputPath;
    }
    return rewritten;
  }

  TaskPlan _buildHardsubPlan({
    required MediaInfo info,
    required SubtitleBinding binding,
    required String outputPath,
    required String workDir,
    required String? chapterMetadataPath,
    required _FontPipelineResult fontPipeline,
    required String? sharedFontPipelineKey,
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
    final _EncoderSelection encoder = resolveEncoder(
      enabledVideo.first.codec,
      preferredCodecFamily: codecFamilyForProfile(ExportProfile.hardsubMp4),
    );
    final bool useLegacyAudio = shouldUseLegacyAudioPath(enabledAudio);
    final toneMapping = _buildToneMappingFilter(
      enabledVideo.first.videoInfo ??
          info.primaryVideo ??
          const VideoStreamInfo(),
      _controller.toneMappingConfig,
      hasZscale: _controller.diagnostics.hasZscale,
    );
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
      _joinVideoFilters(<String>[
        toneMapping.filterChain,
        _buildSubtitleFilter(
          _subtitlePathForPlanner(binding.filePath!, fontPipeline),
          fontPipeline.fonts,
        ),
      ]),
      '-r',
      _controller.outputFps.trim(),
      '-c:v',
      encoder.encoder,
      ..._buildVideoRateControlArguments(
        encoder,
        _controller.videoEncodingConfigs[encoder.encoder] ??
            VideoEncodingConfig.defaultsFor(encoder.encoder),
      ),
      ..._buildAudioArgumentsForStreams(enabledAudio, useLegacyAudio),
      ...toneMapping.metadataArgs,
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
    final List<String> diagnosticComments = _buildDiagnosticComments(
      enabledAudio: enabledAudio,
      encoder: encoder,
      toneMapping: toneMapping,
    );
    final String commandPreview = _renderCommandPreview(
      diagnosticComments,
      renderCommand(_controller.diagnostics.ffmpeg.path!, args),
      workDir,
    );
    return TaskPlan(
      outputPath: outputPath,
      commandPreview: commandPreview,
      steps: <CommandStep>[
        ...fontPipeline.subsetSteps,
        CommandStep(
          executable: _controller.diagnostics.ffmpeg.path!,
          arguments: args,
          description: '导出内嵌 MP4',
        ),
      ],
      workingDirectory: workDir,
      expectedDuration: info.duration,
      initialLogLines: <String>[
        ...toneMapping.logLines,
        ..._hdrToneMappingUserChoiceLogLines(toneMapping.sourceClass),
        ...fontPipeline.warnings,
      ],
      sharedFontPipelineKey: sharedFontPipelineKey,
    );
  }

  TaskPlan _buildMuxPlan({
    required MediaInfo info,
    required List<SubtitleBinding> bindings,
    required _FontPipelineResult fontPipeline,
    required String outputPath,
    required String workDir,
    required String? chapterMetadataPath,
    required String? sharedFontPipelineKey,
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
      preferredCodecFamily: codecFamilyForProfile(ExportProfile.muxMkv),
    );
    final bool useLegacyAudio = shouldUseLegacyAudioPath(enabledAudio);
    final toneMapping = _buildToneMappingFilter(
      enabledVideo.first.videoInfo ??
          info.primaryVideo ??
          const VideoStreamInfo(),
      _controller.toneMappingConfig,
      hasZscale: _controller.diagnostics.hasZscale,
    );
    final List<String> args = <String>[
      '-y',
      '-hide_banner',
      '-nostats',
      '-progress',
      'pipe:2',
      ..._buildPrimaryInputArguments(encoder, info.inputPath),
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
      args.addAll(<String>[
        '-i',
        _subtitlePathForPlanner(subtitle.externalPath!, fontPipeline),
      ]);
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
      _joinVideoFilters(<String>[
        toneMapping.filterChain,
        _buildVideoScaleFilter(),
      ]),
      '-r',
      _controller.outputFps.trim(),
      ..._buildVideoRateControlArguments(
        encoder,
        _controller.videoEncodingConfigs[encoder.encoder] ??
            VideoEncodingConfig.defaultsFor(encoder.encoder),
      ),
      ..._buildPixelFormatArguments(encoder),
      ..._buildAudioArgumentsForStreams(enabledAudio, useLegacyAudio),
      ...toneMapping.metadataArgs,
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
    final List<ResolvedFontFile> attachmentFiles = fontPipeline.fonts;
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
    final List<String> diagnosticComments = _buildDiagnosticComments(
      enabledAudio: enabledAudio,
      encoder: encoder,
      toneMapping: toneMapping,
    );
    final String ffmpegPreview = _renderCommandPreview(
      diagnosticComments,
      renderCommand(_controller.diagnostics.ffmpeg.path!, args),
      workDir,
    );
    return TaskPlan(
      outputPath: outputPath,
      commandPreview: <String>[
        ffmpegPreview,
        _maskWorkDir(
          renderCommand(
            _controller.diagnostics.mkvpropedit.path!,
            _buildMkvSubtitleMetadataArguments(outputPath, <MediaStreamEntry>[
              ...enabledSubtitle,
              ...selectedExternalSubtitle,
            ]),
          ),
          workDir,
        ),
      ].join('\n\n'),
      steps: <CommandStep>[
        ...fontPipeline.subsetSteps,
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
      initialLogLines: <String>[
        ...toneMapping.logLines,
        ..._hdrToneMappingUserChoiceLogLines(toneMapping.sourceClass),
        ...fontPipeline.warnings,
      ],
      sharedFontPipelineKey: sharedFontPipelineKey,
    );
  }

  bool shouldUseLegacyAudioPath(List<MediaStreamEntry> streams) {
    if (_controller.audioDefaultProfile !=
        const AudioStreamConfig.defaultAac()) {
      return false;
    }
    for (final MediaStreamEntry stream in streams) {
      final String key = _controller._audioStreamConfigKey(
        _controller.mediaInfo?.inputPath ?? '',
        stream.index,
      );
      final AudioStreamConfig config =
          _controller.audioStreamConfigs[key] ??
          const AudioStreamConfig.defaultAac();
      if (config != const AudioStreamConfig.defaultAac()) {
        return false;
      }
    }
    return true;
  }

  List<String> _buildAudioArgumentsForStreams(
    List<MediaStreamEntry> streams,
    bool useLegacyAudio,
  ) {
    if (streams.isEmpty) {
      return const <String>[];
    }
    if (useLegacyAudio) {
      return const <String>['-c:a', 'aac', '-b:a', '320k', '-ar', '48000'];
    }
    final List<String> args = <String>[];
    for (var outIdx = 0; outIdx < streams.length; outIdx++) {
      final MediaStreamEntry stream = streams[outIdx];
      final String key = _controller._audioStreamConfigKey(
        _controller.mediaInfo?.inputPath ?? '',
        stream.index,
      );
      final AudioStreamConfig config =
          _controller.audioStreamConfigs[key] ??
          _controller.audioDefaultProfile;
      args.addAll(
        _buildAudioStreamArguments(outIdx, config, sourceStream: stream),
      );
    }
    return args;
  }

  List<String> _buildAudioStreamArguments(
    int outIdx,
    AudioStreamConfig config, {
    MediaStreamEntry? sourceStream,
  }) {
    final String suffix = ':$outIdx';
    final String encoder = config.encoder.trim();
    if (encoder.isEmpty) {
      throw Exception('音频编码器  不可用');
    }
    if (encoder == 'copy') {
      return <String>['-c:a$suffix', 'copy'];
    }
    if (!_isAudioEncoderAvailable(encoder)) {
      throw Exception('音频编码器 $encoder 不可用');
    }
    final List<String> args = <String>['-c:a$suffix', encoder];
    final List<String> filters = <String>[];
    switch (encoder) {
      case 'aac':
        _addAacArguments(args, suffix, config);
        if (config.profile.trim().isNotEmpty) {
          args.addAll(<String>['-profile:a$suffix', config.profile.trim()]);
        }
        break;
      case 'libfdk_aac':
        _addAacArguments(args, suffix, config);
        if (config.profile.trim().isNotEmpty) {
          args.addAll(<String>['-profile:a$suffix', config.profile.trim()]);
        }
        break;
      case 'libopus':
        _addBitrateOrOpusVbrArguments(args, suffix, config);
        args.addAll(<String>[
          '-compression_level$suffix',
          config.compressionLevel.toString(),
        ]);
        break;
      case 'flac':
        args.addAll(<String>[
          '-compression_level$suffix',
          config.compressionLevel.toString(),
        ]);
        break;
      case 'ac3':
      case 'eac3':
        _addCbrBitrateArgument(args, suffix, config);
        break;
      default:
        throw Exception('音频编码器 $encoder 不可用');
    }
    if (config.sampleRate != '保持源') {
      args.addAll(<String>['-ar$suffix', config.sampleRate]);
    }
    _addChannelArguments(
      args: args,
      filters: filters,
      suffix: suffix,
      config: config,
      sourceStream: sourceStream,
    );
    if (config.loudnormEnabled) {
      filters.add(
        'loudnorm=I=${_fmt(config.loudnormI)}:TP=${_fmt(config.loudnormTp)}:LRA=${_fmt(config.loudnormLra)}',
      );
    }
    if (config.drcEnabled) {
      filters.add(
        'acompressor=threshold=${_fmt(config.drcThreshold)}dB:ratio=${_fmt(config.drcRatio)}:attack=${_fmt(config.drcAttack)}:release=${_fmt(config.drcRelease)}',
      );
    }
    final String customFilter = config.customFilter.trim();
    if (customFilter.isNotEmpty) {
      filters.add(customFilter);
    }
    if (filters.isNotEmpty) {
      args.addAll(<String>['-af$suffix', filters.join(',')]);
    }
    return args;
  }

  void _addAacArguments(
    List<String> args,
    String suffix,
    AudioStreamConfig config,
  ) {
    if (config.mode == 'VBR') {
      if (config.encoder == 'libfdk_aac') {
        args.addAll(<String>['-vbr$suffix', config.vbrQuality.toString()]);
      } else {
        args.addAll(<String>['-q:a$suffix', config.vbrQuality.toString()]);
      }
      return;
    }
    _addCbrBitrateArgument(args, suffix, config);
  }

  void _addBitrateOrOpusVbrArguments(
    List<String> args,
    String suffix,
    AudioStreamConfig config,
  ) {
    if (config.mode == 'VBR') {
      args.addAll(<String>['-vbr$suffix', config.vbrModeOpus]);
      return;
    }
    _addCbrBitrateArgument(args, suffix, config);
  }

  void _addCbrBitrateArgument(
    List<String> args,
    String suffix,
    AudioStreamConfig config,
  ) {
    if (!RegExp(r'^\d+[kK]$').hasMatch(config.bitrate.trim())) {
      throw Exception('码率格式应为如 192k');
    }
    args.addAll(<String>['-b:a$suffix', config.bitrate.trim()]);
  }

  void _addChannelArguments({
    required List<String> args,
    required List<String> filters,
    required String suffix,
    required AudioStreamConfig config,
    required MediaStreamEntry? sourceStream,
  }) {
    final String layout = config.channelLayout.trim();
    if (layout.isEmpty || layout == '保持源') {
      return;
    }
    if (layout == 'stereo' &&
        config.downmixAlgo == 'dpl2' &&
        (sourceStream?.channels ?? 0) > 2) {
      filters.add(_buildDpl2PanFilter(sourceStream));
      return;
    }
    final int? channels = switch (layout) {
      'mono' => 1,
      'stereo' => 2,
      '5.1' => 6,
      '7.1' => 8,
      _ => null,
    };
    if (channels == null) {
      return;
    }
    args.addAll(<String>['-ac$suffix', channels.toString()]);
    if (layout != 'mono' && layout != 'stereo') {
      args.addAll(<String>['-channel_layout$suffix', layout]);
    }
  }

  String _buildDpl2PanFilter(MediaStreamEntry? sourceStream) {
    final String layout = sourceStream?.channelLayout.toLowerCase() ?? '';
    final bool hasBack = layout.contains('back') || layout.contains('7.1');
    final String surroundLeft = hasBack ? 'BL' : 'SL';
    final String surroundRight = hasBack ? 'BR' : 'SR';
    return 'pan=stereo|FL=FL+0.707*FC+0.707*$surroundLeft|FR=FR+0.707*FC+0.707*$surroundRight';
  }

  bool _isAudioEncoderAvailable(String encoder) {
    final Set<String> available = _controller.diagnostics.audioEncoders;
    return available.contains(encoder);
  }

  String _fmt(num value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  ({
    String filterChain,
    List<String> metadataArgs,
    List<String> logLines,
    SourceColorClass sourceClass,
    String? tonemapAlgorithm,
  })
  _buildToneMappingFilter(
    VideoStreamInfo video,
    ToneMappingConfig config, {
    required bool hasZscale,
  }) {
    final SourceColorClass sourceClass = detectSourceColorClass(video);
    if (!hasZscale) {
      return (
        filterChain: '',
        metadataArgs: const <String>[],
        logLines: const <String>['WARN: ffmpeg 未启用 libzimg，色调映射已跳过'],
        sourceClass: sourceClass,
        tonemapAlgorithm: null,
      );
    }
    _validateToneMappingConfig(config);
    switch (config.tonemapMode) {
      case 'auto':
        switch (sourceClass) {
          case SourceColorClass.sdrBt709:
            return (
              filterChain: '',
              metadataArgs: _bt709MetadataArgs(),
              logLines: const <String>[],
              sourceClass: sourceClass,
              tonemapAlgorithm: null,
            );
          case SourceColorClass.sdrWideGamut:
            return (
              filterChain: 'zscale=p=bt709:t=bt709:m=bt709:r=tv,format=yuv420p',
              metadataArgs: _bt709MetadataArgs(),
              logLines: const <String>[],
              sourceClass: sourceClass,
              tonemapAlgorithm: null,
            );
          case SourceColorClass.hdrPq:
          case SourceColorClass.hdrHlg:
            return (
              filterChain: _buildPqToneMapChain(config),
              metadataArgs: _bt709MetadataArgs(),
              logLines: const <String>[],
              sourceClass: sourceClass,
              tonemapAlgorithm: config.tonemapAlgo,
            );
          case SourceColorClass.dolbyVision:
            return (
              filterChain: _buildPqToneMapChain(config),
              metadataArgs: _bt709MetadataArgs(),
              logLines: const <String>[
                'WARN: 检测到 Dolby Vision，AEMT 仅按 PQ 基础层处理',
              ],
              sourceClass: sourceClass,
              tonemapAlgorithm: config.tonemapAlgo,
            );
          case SourceColorClass.unknown:
            return (
              filterChain: '',
              metadataArgs: _bt709MetadataArgs(),
              logLines: const <String>['WARN: 无法识别源色彩特性，已按 BT.709 直通输出'],
              sourceClass: sourceClass,
              tonemapAlgorithm: null,
            );
        }
      case 'on':
        return (
          filterChain: _buildPqToneMapChain(config),
          metadataArgs: _metadataArgsForOutputAxes(config),
          logLines: const <String>[],
          sourceClass: sourceClass,
          tonemapAlgorithm: config.tonemapAlgo,
        );
      case 'off':
        final List<String> metadataArgs = _metadataArgsForOutputAxes(config);
        final String filter = _anyToneMappingAxisNotSource(config)
            ? _buildManualZscaleFilter(config)
            : '';
        return (
          filterChain: filter,
          metadataArgs: metadataArgs,
          logLines: const <String>[],
          sourceClass: sourceClass,
          tonemapAlgorithm: null,
        );
      default:
        throw Exception('色调映射参数非法: tonemapMode');
    }
  }

  void _validateToneMappingConfig(ToneMappingConfig config) {
    if (config.desat < 0 || config.desat > 2) {
      throw Exception('色调映射参数非法: desat');
    }
    if (config.peak != 'auto') {
      final double? peak = double.tryParse(config.peak);
      if (peak == null || peak <= 0) {
        throw Exception('色调映射参数非法: peak');
      }
    }
  }

  String _buildPqToneMapChain(ToneMappingConfig config) {
    final String peak = config.peak == 'auto' ? '' : ':peak=${config.peak}';
    return 'zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,'
        'tonemap=tonemap=${config.tonemapAlgo}:desat=${_fmt(config.desat)}$peak,'
        'zscale=t=bt709:m=bt709:r=tv,format=yuv420p';
  }

  List<String> _bt709MetadataArgs() {
    return const <String>[
      '-color_primaries',
      'bt709',
      '-color_trc',
      'bt709',
      '-colorspace',
      'bt709',
      '-color_range',
      'tv',
    ];
  }

  List<String> _metadataArgsForOutputAxes(ToneMappingConfig config) {
    final List<String> args = <String>[];
    final String primaries = _mapPrimaries(config.outputPrimaries);
    if (primaries.isNotEmpty) {
      args.addAll(<String>['-color_primaries', primaries]);
      args.addAll(<String>['-colorspace', _mapMatrix(config.outputPrimaries)]);
    }
    final String transfer = _mapTransfer(config.outputTransfer);
    if (transfer.isNotEmpty) {
      args.addAll(<String>['-color_trc', transfer]);
    }
    final String range = _mapRange(config.outputRange);
    if (range.isNotEmpty) {
      args.addAll(<String>['-color_range', range]);
    }
    return args;
  }

  bool _anyToneMappingAxisNotSource(ToneMappingConfig config) {
    return _mapPrimaries(config.outputPrimaries).isNotEmpty ||
        _mapTransfer(config.outputTransfer).isNotEmpty ||
        _mapRange(config.outputRange).isNotEmpty;
  }

  String _buildManualZscaleFilter(ToneMappingConfig config) {
    final List<String> parts = <String>[];
    final String primaries = _mapPrimaries(config.outputPrimaries);
    if (primaries.isNotEmpty) {
      parts.add('p=$primaries');
      parts.add('m=${_mapMatrix(config.outputPrimaries)}');
    }
    final String transfer = _mapTransfer(config.outputTransfer);
    if (transfer.isNotEmpty) {
      parts.add('t=$transfer');
    }
    final String range = _mapRange(config.outputRange);
    if (range.isNotEmpty) {
      parts.add('r=$range');
    }
    return parts.isEmpty ? '' : 'zscale=${parts.join(':')}';
  }

  String _mapPrimaries(String value) {
    return switch (value) {
      'bt709' || 'BT.709' => 'bt709',
      'bt2020' || 'BT.2020' => 'bt2020',
      'p3d65' || 'P3-D65' => 'smpte432',
      'source' || '保持源' => '',
      _ => value,
    };
  }

  String _mapTransfer(String value) {
    return switch (value) {
      'bt709' || 'BT.709' => 'bt709',
      'smpte2084' || 'PQ' => 'smpte2084',
      'arib-std-b67' || 'HLG' => 'arib-std-b67',
      'source' || '保持源' => '',
      _ => value,
    };
  }

  String _mapMatrix(String value) {
    return switch (value) {
      'bt2020' || 'BT.2020' => 'bt2020nc',
      'p3d65' || 'P3-D65' => 'bt709',
      'source' || '保持源' => '',
      _ => 'bt709',
    };
  }

  String _mapRange(String value) {
    return switch (value) {
      'tv' || 'pc' => value,
      'source' || '保持源' => '',
      _ => value,
    };
  }

  String _joinVideoFilters(Iterable<String> filters) {
    return filters
        .map((String filter) => filter.trim())
        .where((String filter) => filter.isNotEmpty)
        .join(',');
  }

  List<String> _buildVideoRateControlArguments(
    _EncoderSelection selection,
    VideoEncodingConfig config,
  ) {
    final List<String> supported =
        kSupportedRcModes[selection.encoder] ?? const <String>[];
    if (!supported.contains(config.mode)) {
      throw Exception('当前编码器 ${selection.encoder} 不支持模式 ${config.mode}');
    }
    switch (config.mode) {
      case 'CRF':
        _validateVideoRange('crf', config.crf);
        final List<String> args = <String>['-crf', config.crf.toString()];
        final String maxrate = config.maxrate.trim();
        final String bufsize = config.bufsize.trim();
        if (maxrate.isNotEmpty) {
          _validateVideoBitrate(maxrate);
          args.addAll(<String>['-maxrate', maxrate]);
        }
        if (bufsize.isNotEmpty) {
          _validateVideoBitrate(bufsize);
          args.addAll(<String>['-bufsize', bufsize]);
        }
        args.addAll(_buildEncoderTuningArguments(selection));
        return args;
      case 'CBR':
        _validateVideoBitrate(config.bitrate);
        final String maxrate = config.maxrate.trim().isEmpty
            ? config.bitrate.trim()
            : config.maxrate.trim();
        _validateVideoBitrate(maxrate);
        final String bufsize = config.bufsize.trim().isEmpty
            ? _doubleBitrate(config.bitrate.trim())
            : config.bufsize.trim();
        _validateVideoBitrate(bufsize);
        return <String>[
          '-b:v',
          config.bitrate.trim(),
          '-maxrate',
          maxrate,
          '-minrate',
          config.bitrate.trim(),
          '-bufsize',
          bufsize,
          ..._buildEncoderRateSwitch(selection, cbr: true),
          ..._buildEncoderTuningArguments(selection),
        ];
      case 'VBR':
        _validateVideoBitrate(config.bitrate);
        final String maxrate = config.maxrate.trim();
        final String bufsize = config.bufsize.trim();
        _validateVideoBitrate(maxrate);
        _validateVideoBitrate(bufsize);
        return <String>[
          '-b:v',
          config.bitrate.trim(),
          ..._buildEncoderRateSwitch(selection, cbr: false),
          '-maxrate',
          maxrate,
          '-bufsize',
          bufsize,
          ..._buildEncoderTuningArguments(selection),
        ];
      case 'CQP':
        for (final int value in <int>[config.qpI, config.qpP, config.qpB]) {
          _validateVideoRange('qp', value);
        }
        return <String>[
          ..._buildCqpArguments(selection, config),
          ..._buildEncoderTuningArguments(selection),
        ];
      default:
        throw Exception('当前编码器 ${selection.encoder} 不支持模式 ${config.mode}');
    }
  }

  List<String> _buildEncoderTuningArguments(_EncoderSelection selection) {
    final EncoderTuning tuning = _controller.encoderTunings[selection.encoder]!;
    final List<String> args = <String>[];
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

  List<String> _buildEncoderRateSwitch(
    _EncoderSelection selection, {
    required bool cbr,
  }) {
    final String mode = cbr ? 'cbr' : 'vbr';
    if (selection.encoder.contains('nvenc')) {
      return <String>['-rc', mode];
    }
    if (selection.encoder.contains('qsv')) {
      return <String>['-rc:v', mode];
    }
    if (selection.encoder.contains('amf')) {
      return <String>['-rc_mode', cbr ? 'cbr' : 'vbr_peak'];
    }
    return const <String>[];
  }

  List<String> _buildCqpArguments(
    _EncoderSelection selection,
    VideoEncodingConfig config,
  ) {
    if (selection.encoder.contains('nvenc')) {
      return <String>[
        '-rc',
        'constqp',
        '-qp',
        config.qpI.toString(),
        '-init_qpP',
        config.qpP.toString(),
        '-init_qpB',
        config.qpB.toString(),
      ];
    }
    if (selection.encoder.contains('qsv')) {
      return <String>[
        '-rc:v',
        'cqp',
        '-q',
        config.qpI.toString(),
        '-global_quality',
        config.qpI.toString(),
      ];
    }
    if (selection.encoder.contains('amf')) {
      return <String>[
        '-rc_mode',
        'cqp',
        '-qp_i',
        config.qpI.toString(),
        '-qp_p',
        config.qpP.toString(),
        '-qp_b',
        config.qpB.toString(),
      ];
    }
    throw Exception('当前编码器 ${selection.encoder} 不支持模式 CQP');
  }

  void _validateVideoBitrate(String value) {
    if (!RegExp(r'^\d+[kKmM]$').hasMatch(value.trim())) {
      throw Exception('视频码率格式非法');
    }
  }

  void _validateVideoRange(String field, int value) {
    if (value < 0 || value > 51) {
      throw Exception('$field 范围应为 0-51');
    }
  }

  String _doubleBitrate(String bitrate) {
    final RegExpMatch? match = RegExp(
      r'^(\d+)([kKmM])$',
    ).firstMatch(bitrate.trim());
    if (match == null) {
      throw Exception('视频码率格式非法');
    }
    return '${int.parse(match.group(1)!) * 2}${match.group(2)!}';
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

  String _subtitlePathForPlanner(
    String originalPath,
    _FontPipelineResult fontPipeline,
  ) {
    if (fontPipeline.renameMap.isEmpty) {
      return originalPath;
    }
    return fontPipeline.rewrittenAssPaths[originalPath] ?? originalPath;
  }

  bool _isAssSubtitlePath(String path) {
    final String extension = p.extension(path).toLowerCase();
    return extension == '.ass' || extension == '.ssa';
  }

  List<String> _buildDiagnosticComments({
    required List<MediaStreamEntry> enabledAudio,
    required _EncoderSelection encoder,
    required ({
      String filterChain,
      List<String> metadataArgs,
      List<String> logLines,
      SourceColorClass sourceClass,
      String? tonemapAlgorithm,
    })
    toneMapping,
  }) {
    final List<String> comments = <String>[];
    for (var i = 0; i < enabledAudio.length; i++) {
      final MediaStreamEntry stream = enabledAudio[i];
      final String key = _controller._audioStreamConfigKey(
        _controller.mediaInfo?.inputPath ?? '',
        stream.index,
      );
      final AudioStreamConfig config =
          _controller.audioStreamConfigs[key] ??
          (shouldUseLegacyAudioPath(enabledAudio)
              ? const AudioStreamConfig.defaultAac()
              : _controller.audioDefaultProfile);
      comments.add('# audio:$i ${config.encoder.trim()}');
    }
    final VideoEncodingConfig videoConfig =
        _controller.videoEncodingConfigs[encoder.encoder] ??
        VideoEncodingConfig.defaultsFor(encoder.encoder);
    if (videoConfig.userOverridden) {
      comments.add('# video ${encoder.encoder} rc=${videoConfig.mode}');
    }
    if (toneMapping.filterChain.contains('zscale') ||
        toneMapping.filterChain.contains('tonemap')) {
      comments.add(
        '# tonemap source=${toneMapping.sourceClass.name} -> bt709 '
        'algo=${toneMapping.tonemapAlgorithm ?? 'none'}',
      );
    }
    return comments;
  }

  List<String> _hdrToneMappingUserChoiceLogLines(SourceColorClass sourceClass) {
    if (_controller.toneMappingConfig.tonemapMode != 'off') {
      return const <String>[];
    }
    if (sourceClass != SourceColorClass.hdrPq &&
        sourceClass != SourceColorClass.hdrHlg &&
        sourceClass != SourceColorClass.dolbyVision) {
      return const <String>[];
    }
    return const <String>['INFO: 用户已关闭 HDR 源的色调映射，输出可能偏色'];
  }

  String _renderCommandPreview(
    List<String> diagnosticComments,
    String command,
    String workDir,
  ) {
    final String maskedCommand = _maskWorkDir(command, workDir);
    if (diagnosticComments.isEmpty) {
      return maskedCommand;
    }
    return <String>[...diagnosticComments, maskedCommand].join('\n');
  }

  String _maskWorkDir(String text, String workDir) {
    final String normalized = workDir.replaceAll(r'\', '/');
    final String escapedNormalized = normalized.replaceAll(':', r'\:');
    return text
        .replaceAll(workDir, '<workDir>')
        .replaceAll(normalized, '<workDir>')
        .replaceAll(escapedNormalized, '<workDir>')
        .replaceAll(r'<workDir>\', '<workDir>/')
        .replaceAll(r'\', '/');
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
      final String languageTag = buildLanguageTag(stream);
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

  _EncoderSelection resolveEncoder(
    String videoCodec, {
    String? preferredCodecFamily,
  }) {
    final String codecFamily =
        preferredCodecFamily ??
        (videoCodec.contains('265') || videoCodec.contains('hevc')
            ? 'hevc'
            : 'avc');
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

  String codecFamilyForProfile(ExportProfile profile) {
    final OutputVideoCodec codec = switch (profile) {
      ExportProfile.hardsubMp4 => _controller.hardsubVideoCodec,
      ExportProfile.muxMkv => _controller.muxVideoCodec,
    };
    return codec == OutputVideoCodec.h265 ? 'hevc' : 'avc';
  }
}
