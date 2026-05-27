part of 'controller.dart';

class _ExportConfig {
  _ExportConfig(this._controller);

  final AemtController _controller;

  String buildOutputPath(ExportProfile profile, List<String> bindingKeys) {
    final MediaInfo? info = _controller.mediaInfo;
    if (info == null) {
      return '';
    }
    final String fileName;
    if (_controller.compressionMode == CompressionMode.episodic) {
      fileName = _buildEpisodicFileName(info, profile, bindingKeys);
    } else {
      final String baseName = _controller.outputFileNameOverride.isEmpty
          ? p.basenameWithoutExtension(info.displayName)
          : _controller.outputFileNameOverride;
      switch (profile) {
        case ExportProfile.hardsubMp4:
          final String bindingLabel = _buildBindingSuffix(bindingKeys);
          fileName = '$baseName [$bindingLabel Hardsub].mp4';
        case ExportProfile.muxMkv:
          final String bindingLabel = _buildBindingSuffix(bindingKeys);
          fileName = '$baseName [$bindingLabel Mux].mkv';
      }
    }
    final String safeFileName = _sanitizeOutputFileName(fileName);
    if (_controller.outputDirectory.trim().isEmpty) {
      return safeFileName;
    }
    return p.join(_controller.outputDirectory, safeFileName);
  }

  String buildTaskLabel(ExportProfile profile, List<String> bindingKeys) {
    final String outputPath = buildOutputPath(profile, bindingKeys);
    if (outputPath.trim().isNotEmpty) {
      return p.basenameWithoutExtension(outputPath);
    }
    return '未命名';
  }

  EncodingSettingsSnapshot buildEncodingSettingsSnapshot() {
    return EncodingSettingsSnapshot(
      compressionMode: _controller.compressionMode,
      hardwareMode: _controller.hardwareMode,
      outputFileNameOverride: _controller.outputFileNameOverride,
      releaseGroup: _controller.releaseGroup,
      titleOverride: _controller.titleOverride,
      seasonNumber: _controller.seasonNumber,
      episodeNumber: _controller.episodeNumber,
      sourceLabel: _controller.sourceLabel,
      episodicNamingTemplate: resolvedEpisodicNamingTemplate,
      outputResolution: _controller.outputResolution,
      outputFps: _controller.outputFps,
      outputDirectory: _controller.outputDirectory,
      avcBitrate: _controller.avcBitrate,
      avcMaxrate: _controller.avcMaxrate,
      hevcBitrate: _controller.hevcBitrate,
      hevcMaxrate: _controller.hevcMaxrate,
      audioStreamConfigs: Map<String, AudioStreamConfig>.from(
        _controller.audioStreamConfigs,
      ),
      audioDefaultProfile: _controller.audioDefaultProfile,
      videoEncodingConfigs: Map<String, VideoEncodingConfig>.from(
        _controller.videoEncodingConfigs,
      ),
      toneMappingConfig: _controller.toneMappingConfig,
      continueOnMissingFont: _controller.continueOnMissingFont,
      fontSubsettingEnabled: _controller.fontSubsettingEnabled,
      sourceHanEllipsisFix: _controller.sourceHanEllipsisFix,
      encoderTunings: _controller.encoderTunings.map(
        (String key, EncoderTuning tuning) => MapEntry(
          key,
          EncoderTuningSelection(preset: tuning.preset, tune: tuning.tune),
        ),
      ),
    );
  }

  void applyEncodingSettingsSnapshot(EncodingSettingsSnapshot snapshot) {
    _controller.compressionMode = snapshot.compressionMode;
    _controller.hardwareMode = snapshot.hardwareMode;
    _controller.outputFileNameOverride = snapshot.outputFileNameOverride;
    _controller.releaseGroup = snapshot.releaseGroup;
    _controller.titleOverride = snapshot.titleOverride;
    _controller.seasonNumber = snapshot.seasonNumber;
    _controller.episodeNumber = snapshot.episodeNumber;
    _controller.sourceLabel = snapshot.sourceLabel;
    _controller.episodicNamingTemplate =
        snapshot.episodicNamingTemplate.trim().isEmpty
        ? AemtController.defaultEpisodicNamingTemplate
        : snapshot.episodicNamingTemplate;
    _controller.outputResolution = snapshot.outputResolution;
    _controller.outputFps = snapshot.outputFps;
    _controller.outputDirectory = snapshot.outputDirectory;
    _controller.avcBitrate = snapshot.avcBitrate;
    _controller.avcMaxrate = snapshot.avcMaxrate;
    _controller.hevcBitrate = snapshot.hevcBitrate;
    _controller.hevcMaxrate = snapshot.hevcMaxrate;
    _controller.audioDefaultProfile = snapshot.audioDefaultProfile;
    _controller.videoEncodingConfigs
      ..clear()
      ..addAll(snapshot.videoEncodingConfigs);
    for (final String encoderKey in kSupportedRcModes.keys) {
      _controller.videoEncodingConfigs.putIfAbsent(
        encoderKey,
        () => VideoEncodingConfig.defaultsFor(encoderKey),
      );
      _controller.reconcileVideoEncodingMode(encoderKey);
    }
    _applyAudioStreamConfigs(snapshot);
    _controller.toneMappingConfig = snapshot.toneMappingConfig;
    _controller.continueOnMissingFont = snapshot.continueOnMissingFont;
    _controller.fontSubsettingEnabled = snapshot.fontSubsettingEnabled;
    _controller.sourceHanEllipsisFix = snapshot.sourceHanEllipsisFix;
    snapshot.encoderTunings.forEach((String key, EncoderTuningSelection value) {
      final EncoderTuning? tuning = _controller.encoderTunings[key];
      if (tuning == null) {
        return;
      }
      _controller.encoderTunings[key] = tuning.copyWith(
        preset: tuning.presets.contains(value.preset) ? value.preset : null,
        tune: tuning.tunes.contains(value.tune) ? value.tune : null,
      );
    });
  }

  void _applyAudioStreamConfigs(EncodingSettingsSnapshot snapshot) {
    final MediaInfo? info = _controller.mediaInfo;
    if (info == null) {
      _controller.audioStreamConfigs
        ..clear()
        ..addAll(snapshot.audioStreamConfigs);
      return;
    }
    _controller._syncAudioStreamConfigsWithMedia();
    for (final MediaStreamEntry stream in info.streams.where(
      (MediaStreamEntry stream) =>
          stream.kind == StreamKind.audio &&
          stream.origin == StreamOrigin.input,
    )) {
      final String currentKey = _controller._audioStreamConfigKey(
        info.inputPath,
        stream.index,
      );
      final AudioStreamConfig? exact = snapshot.audioStreamConfigs[currentKey];
      if (exact != null) {
        _controller.audioStreamConfigs[currentKey] = exact;
        continue;
      }
      final String suffix = '#${stream.index}';
      for (final MapEntry<String, AudioStreamConfig> entry
          in snapshot.audioStreamConfigs.entries) {
        if (entry.key.endsWith(suffix)) {
          _controller.audioStreamConfigs[currentKey] = entry.value;
          break;
        }
      }
    }
  }

  String get resolvedEpisodicNamingTemplate {
    final String template = _controller.episodicNamingTemplate.trim();
    return template.isEmpty
        ? AemtController.defaultEpisodicNamingTemplate
        : template;
  }

  List<String> findUnknownTemplateVariables(String template) {
    final Map<String, String> supportedVariables = _buildSupportedTemplateMap();
    return AemtController._templateVariablePattern
        .allMatches(template)
        .map((Match match) => match.group(1) ?? '')
        .where(
          (String variable) =>
              variable.isNotEmpty && !supportedVariables.containsKey(variable),
        )
        .toSet()
        .toList()
      ..sort();
  }

  List<String> findMissingTemplateInputs(String template) {
    final List<String> missing = <String>[];
    final Set<String> variables = AemtController._templateVariablePattern
        .allMatches(template)
        .map((Match match) => match.group(1) ?? '')
        .where((String variable) => variable.isNotEmpty)
        .toSet();
    final Map<String, ({String label, String value})> requiredInputs =
        <String, ({String label, String value})>{
          'group': (label: '组标', value: _controller.releaseGroup.trim()),
          'group_raw': (label: '组标', value: _controller.releaseGroup.trim()),
          'title': (label: '片名', value: _controller.titleOverride.trim()),
          'season': (label: '季', value: _controller.seasonNumber.trim()),
          'season_raw': (label: '季', value: _controller.seasonNumber.trim()),
          'episode': (label: '集', value: _controller.episodeNumber.trim()),
          'episode_raw': (label: '集', value: _controller.episodeNumber.trim()),
          'source': (label: '视频源', value: _controller.sourceLabel.trim()),
          'source_raw': (label: '视频源', value: _controller.sourceLabel.trim()),
        };
    for (final String variable in variables) {
      final ({String label, String value})? input = requiredInputs[variable];
      if (input != null &&
          input.value.isEmpty &&
          !missing.contains(input.label)) {
        missing.add(input.label);
      }
    }
    return missing;
  }

  Map<String, String> buildEpisodicNamingVariables(
    MediaInfo info,
    ExportProfile profile,
    List<String> bindingKeys,
  ) {
    final String resolutionTag = _buildOutputResolutionTag(
      _controller.outputResolution,
      profile,
    );
    final Iterable<MediaStreamEntry> enabledVideos = info.streams.where(
      (MediaStreamEntry stream) =>
          stream.kind == StreamKind.video && stream.enabled,
    );
    final MediaStreamEntry namingVideoStream = enabledVideos.isNotEmpty
        ? enabledVideos.first
        : info.streams
              .where(
                (MediaStreamEntry stream) => stream.kind == StreamKind.video,
              )
              .first;
    final _EncoderSelection encoder = _controller._taskPlanner.resolveEncoder(
      namingVideoStream.codec,
      preferredCodecFamily: profile == ExportProfile.muxMkv ? 'hevc' : null,
    );
    final String videoTag = _buildVideoNamingTag(encoder.encoder);
    final String bindingTag = _buildBindingSuffix(bindingKeys);
    final String subtitleTag = profile == ExportProfile.muxMkv
        ? _buildMuxSubtitleTag(info, bindingKeys)
        : bindingTag;
    final String audioTag = _buildAudioCodecTag(info);
    final String encodeAudioRaw =
        '$videoTag ${resolutionTag.toLowerCase()} $audioTag';
    final String profileTags = switch (profile) {
      ExportProfile.muxMkv => _wrapTag(encodeAudioRaw),
      ExportProfile.hardsubMp4 =>
        '${_wrapTag(resolutionTag)}${_wrapTag(videoTag)}',
    };
    return <String, String>{
      'group_raw': _controller.releaseGroup.trim(),
      'group': _wrapTag(_controller.releaseGroup),
      'title': _controller.titleOverride.trim(),
      'season_raw': _controller.seasonNumber.trim(),
      'season': _wrapTag(_controller.seasonNumber),
      'episode_raw': _controller.episodeNumber.trim(),
      'episode': _wrapTag(_controller.episodeNumber),
      'source_raw': _controller.sourceLabel.trim(),
      'source': _wrapTag(_controller.sourceLabel),
      'binding_raw': bindingTag,
      'binding': _wrapTag(bindingTag),
      'subtitle_raw': subtitleTag,
      'subtitle': _wrapTag(subtitleTag),
      'resolution_raw': resolutionTag,
      'resolution': _wrapTag(resolutionTag),
      'video_raw': videoTag,
      'video': _wrapTag(videoTag),
      'audio': audioTag,
      'encode_audio': profile == ExportProfile.muxMkv
          ? _wrapTag(encodeAudioRaw)
          : '',
      'profile_tags': profileTags,
      'ext': _extensionForProfile(profile),
    };
  }

  String _buildEpisodicFileName(
    MediaInfo info,
    ExportProfile profile,
    List<String> bindingKeys,
  ) {
    final Map<String, String> variables = buildEpisodicNamingVariables(
      info,
      profile,
      bindingKeys,
    );
    String fileName = resolvedEpisodicNamingTemplate.replaceAllMapped(
      AemtController._templateVariablePattern,
      (Match match) => variables[match.group(1)] ?? '',
    );
    final String ext = variables['ext'] ?? _extensionForProfile(profile);
    fileName = fileName.trim();
    if (!fileName.toLowerCase().endsWith('.$ext')) {
      fileName = '$fileName.$ext';
    }
    return fileName;
  }

  Map<String, String> _buildSupportedTemplateMap() {
    return <String, String>{
      for (final NamingTemplateVariable variable
          in _controller.episodicNamingVariables)
        variable.name: variable.description,
    };
  }

  String _extensionForProfile(ExportProfile profile) {
    switch (profile) {
      case ExportProfile.hardsubMp4:
        return 'mp4';
      case ExportProfile.muxMkv:
        return 'mkv';
    }
  }

  String _wrapTag(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return '[$trimmed]';
  }

  String _sanitizeOutputFileName(String fileName) {
    String sanitized = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ').trim();
    sanitized = sanitized.replaceAll(RegExp(r'[. ]+$'), '');
    return sanitized.isEmpty ? 'untitled' : sanitized;
  }

  String _buildOutputResolutionTag(String resolution, ExportProfile profile) {
    final ({int width, int height})? parsed = parseResolution(resolution);
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
        .map(_controller._findBindingByKey)
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
}
