import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import 'common_widgets.dart';

class EncodingPanel extends StatelessWidget {
  const EncodingPanel({
    super.key,
    required this.controller,
    required this.media,
  });

  final AemtController controller;
  final MediaInfo? media;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Column(
        children: <Widget>[
          const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: '基础设置'),
              Tab(text: '硬件加速'),
              Tab(text: '高级编码参数'),
              Tab(text: '音频参数'),
              Tab(text: '字体处理'),
              Tab(text: '色调映射'),
            ],
          ),
          SizedBox(
            height: 440,
            child: TabBarView(
              children: <Widget>[
                SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          SegmentedButton<CompressionMode>(
                            segments: const <ButtonSegment<CompressionMode>>[
                              ButtonSegment<CompressionMode>(
                                value: CompressionMode.generic,
                                label: Text('通用压制'),
                              ),
                              ButtonSegment<CompressionMode>(
                                value: CompressionMode.episodic,
                                label: Text('分集压制'),
                              ),
                            ],
                            selected: <CompressionMode>{
                              controller.compressionMode,
                            },
                            onSelectionChanged: (Set<CompressionMode> values) {
                              controller.setCompressionMode(values.first);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (controller.compressionMode == CompressionMode.generic)
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: buildField(
                                '输出文件名',
                                controller.outputFileNameOverride,
                                controller.setOutputFileNameOverride,
                                key:
                                    'output-name-${media?.inputPath ?? 'none'}',
                              ),
                            ),
                          ],
                        ),
                      if (controller.compressionMode ==
                          CompressionMode.episodic)
                        Column(
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: buildField(
                                    '组标',
                                    controller.releaseGroup,
                                    controller.setReleaseGroup,
                                    key: 'release-group',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: buildField(
                                    '片名',
                                    controller.titleOverride,
                                    controller.setTitleOverride,
                                    key:
                                        'title-override-${media?.inputPath ?? 'none'}',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: buildField(
                                    '季',
                                    controller.seasonNumber,
                                    controller.setSeasonNumber,
                                    key: 'season-number',
                                    hintText: '例如 S01 / Season1 / 1',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: buildField(
                                    '集',
                                    controller.episodeNumber,
                                    controller.setEpisodeNumber,
                                    key: 'episode-number',
                                    hintText: '例如 01 / EP01',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: buildField(
                                    '视频源',
                                    controller.sourceLabel,
                                    controller.setSourceLabel,
                                    key: 'source-label',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            EpisodicNamingTemplateEditor(
                              key: ValueKey<String>(
                                'episodic-naming-template-${media?.inputPath ?? 'none'}',
                              ),
                              controller: controller,
                            ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: buildField(
                              '输出分辨率',
                              controller.outputResolution,
                              controller.setOutputResolution,
                              key:
                                  'output-resolution-${media?.inputPath ?? 'none'}',
                              hintText: '例如 1920x1080',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: buildField(
                              '输出帧率',
                              controller.outputFps,
                              controller.setOutputFps,
                              key: 'output-fps-${media?.inputPath ?? 'none'}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: buildField(
                              '输出目录',
                              controller.outputDirectory,
                              controller.setOutputDirectory,
                              key: 'output-dir-${media?.inputPath ?? 'none'}',
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: controller.pickOutputDirectory,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('浏览'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: buildField(
                              'AVC 目标码率',
                              controller.avcBitrate,
                              controller.setAvcBitrate,
                              key: 'avc-bitrate',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: buildField(
                              'AVC 最大码率',
                              controller.avcMaxrate,
                              controller.setAvcMaxrate,
                              key: 'avc-maxrate',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: buildField(
                              'HEVC 目标码率',
                              controller.hevcBitrate,
                              controller.setHevcBitrate,
                              key: 'hevc-bitrate',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: buildField(
                              'HEVC 最大码率',
                              controller.hevcMaxrate,
                              controller.setHevcMaxrate,
                              key: 'hevc-maxrate',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: <Widget>[
                          modeChip(
                            '自动',
                            controller.hardwareMode == HardwareMode.auto,
                            () => controller.setHardwareMode(HardwareMode.auto),
                          ),
                          modeChip(
                            '软件编码',
                            controller.hardwareMode == HardwareMode.software,
                            () => controller.setHardwareMode(
                              HardwareMode.software,
                            ),
                          ),
                          modeChip(
                            'NVIDIA NVENC',
                            controller.hardwareMode == HardwareMode.nvenc,
                            controller.diagnostics.hasNvenc
                                ? () => controller.setHardwareMode(
                                    HardwareMode.nvenc,
                                  )
                                : null,
                          ),
                          modeChip(
                            'Intel QSV',
                            controller.hardwareMode == HardwareMode.qsv,
                            controller.diagnostics.hasQsv
                                ? () => controller.setHardwareMode(
                                    HardwareMode.qsv,
                                  )
                                : null,
                          ),
                          modeChip(
                            'AMD AMF',
                            controller.hardwareMode == HardwareMode.amf,
                            controller.diagnostics.hasAmf
                                ? () => controller.setHardwareMode(
                                    HardwareMode.amf,
                                  )
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '可用硬件加速视频编码探测结果: ${controller.diagnostics.hardwareVideoEncoderLabels.isEmpty ? '无' : controller.diagnostics.hardwareVideoEncoderLabels.join(', ')}',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '可用硬件加速视频解码后端: ${controller.diagnostics.hardwareDecodeLabels.isEmpty ? '无' : controller.diagnostics.hardwareDecodeLabels.join(', ')}',
                      ),
                      const SizedBox(height: 6),
                      const Text('自动模式按 NVENC -> QSV -> AMF -> SOFTWARE 顺序回落。'),
                      const SizedBox(height: 4),
                      const Text('导出主输入会按当前模式自动追加硬解参数；软件编码模式下不启用硬解。'),
                    ],
                  ),
                ),
                _VideoAdvancedTab(controller: controller),
                _AudioSettingsTab(controller: controller, media: media),
                _FontSettingsTab(controller: controller),
                _ToneMappingTab(controller: controller, media: media),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '加入任务列表',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          if (media == null)
            const Align(alignment: Alignment.centerLeft, child: Text('请先导入视频。'))
          else ...<Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: softBox(),
              child: Column(
                children: <Widget>[
                  Row(
                    children: const <Widget>[
                      Expanded(child: Text('字幕')),
                      SizedBox(width: 72, child: Text('内嵌')),
                      SizedBox(width: 72, child: Text('内封')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...controller.allBindings
                      .where(
                        (SubtitleBinding binding) => binding.filePath != null,
                      )
                      .map((SubtitleBinding binding) {
                        final bool enabled = media!.streams.any(
                          (MediaStreamEntry stream) =>
                              stream.origin == StreamOrigin.externalSubtitle &&
                              stream.externalPath == binding.filePath &&
                              stream.enabled,
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  binding.trackName.isEmpty
                                      ? binding.label
                                      : binding.trackName,
                                ),
                              ),
                              SizedBox(
                                width: 72,
                                child: Checkbox(
                                  value: controller.selectedHardsubBindingKeys
                                      .contains(binding.key),
                                  onChanged: enabled
                                      ? (bool? value) => controller
                                            .toggleHardsubBindingSelection(
                                              binding.key,
                                              value ?? false,
                                            )
                                      : null,
                                ),
                              ),
                              SizedBox(
                                width: 72,
                                child: Checkbox(
                                  value: controller.selectedMuxBindingKeys
                                      .contains(binding.key),
                                  onChanged: enabled
                                      ? (bool? value) => controller
                                            .toggleMuxBindingSelection(
                                              binding.key,
                                              value ?? false,
                                            )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                OutlinedButton(
                  onPressed: () =>
                      unawaited(controller.enqueueSelectedHardsubTasks()),
                  child: const Text('加入所选内嵌任务'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      unawaited(controller.enqueueSelectedMuxTask()),
                  child: const Text('加入所选内封任务'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(controller.enqueueSelectedTasks()),
                  icon: const Icon(Icons.queue),
                  label: const Text('全部加入'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _VideoAdvancedTab extends StatelessWidget {
  const _VideoAdvancedTab({required this.controller});

  final AemtController controller;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      padding: const EdgeInsets.only(top: 14),
      childAspectRatio: 1.15,
      children: controller.encoderTunings.values.map((EncoderTuning tuning) {
        final VideoEncodingConfig cfg =
            controller.videoEncodingConfigs[tuning.key] ??
            VideoEncodingConfig.defaultsFor(tuning.key);
        final List<String> modes =
            kSupportedRcModes[tuning.key] ?? const <String>[];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: softBox(),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  tuning.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: tuning.preset,
                  decoration: const InputDecoration(labelText: 'Preset'),
                  items: tuning.presets
                      .map(
                        (String value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) {
                    if (value != null) {
                      controller.updateEncoderPreset(tuning.key, value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: tuning.tune,
                  decoration: const InputDecoration(labelText: 'Tune'),
                  items: tuning.tunes
                      .map(
                        (String value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) {
                    if (value != null) {
                      controller.updateEncoderTune(tuning.key, value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>('video-rc-mode-${tuning.key}'),
                  initialValue: modes.contains(cfg.mode)
                      ? cfg.mode
                      : VideoEncodingConfig.defaultsFor(tuning.key).mode,
                  decoration: const InputDecoration(labelText: '视频码控模式'),
                  items: modes
                      .map(
                        (String value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) {
                    if (value != null) {
                      controller.setVideoEncodingMode(tuning.key, value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                _VideoRateControlFields(
                  controller: controller,
                  encoderKey: tuning.key,
                  config: cfg,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _VideoRateControlFields extends StatelessWidget {
  const _VideoRateControlFields({
    required this.controller,
    required this.encoderKey,
    required this.config,
  });

  final AemtController controller;
  final String encoderKey;
  final VideoEncodingConfig config;

  @override
  Widget build(BuildContext context) {
    switch (config.mode) {
      case 'CRF':
        return _NumberField(
          label: 'CRF',
          value: config.crf.toString(),
          onSubmitted: (String value) => controller.setVideoEncodingField(
            encoderKey,
            crf: int.tryParse(value) ?? config.crf,
          ),
        );
      case 'CBR':
        return Column(
          children: <Widget>[
            _VideoBitrateField(
              label: 'bitrate',
              value: config.bitrate,
              onSubmitted: (String value) =>
                  controller.setVideoEncodingField(encoderKey, bitrate: value),
            ),
            const SizedBox(height: 8),
            _VideoBitrateField(
              label: 'maxrate',
              value: config.maxrate,
              onSubmitted: (String value) =>
                  controller.setVideoEncodingField(encoderKey, maxrate: value),
            ),
            const SizedBox(height: 8),
            _VideoBitrateField(
              label: 'minrate',
              value: config.minrate,
              onSubmitted: (String value) =>
                  controller.setVideoEncodingField(encoderKey, minrate: value),
            ),
            const SizedBox(height: 8),
            _VideoBitrateField(
              label: 'bufsize',
              value: config.bufsize,
              onSubmitted: (String value) =>
                  controller.setVideoEncodingField(encoderKey, bufsize: value),
            ),
          ],
        );
      case 'VBR':
        return Column(
          children: <Widget>[
            _VideoBitrateField(
              label: 'bitrate',
              value: config.bitrate,
              onSubmitted: (String value) =>
                  controller.setVideoEncodingField(encoderKey, bitrate: value),
            ),
            const SizedBox(height: 8),
            _VideoBitrateField(
              label: 'maxrate',
              value: config.maxrate,
              onSubmitted: (String value) =>
                  controller.setVideoEncodingField(encoderKey, maxrate: value),
            ),
            const SizedBox(height: 8),
            _VideoBitrateField(
              label: 'minrate',
              value: config.minrate,
              onSubmitted: (String value) =>
                  controller.setVideoEncodingField(encoderKey, minrate: value),
            ),
            const SizedBox(height: 8),
            _VideoBitrateField(
              label: 'bufsize',
              value: config.bufsize,
              onSubmitted: (String value) =>
                  controller.setVideoEncodingField(encoderKey, bufsize: value),
            ),
          ],
        );
      case 'CQP':
        return Row(
          children: <Widget>[
            Expanded(
              child: _NumberField(
                label: 'qpI',
                value: config.qpI.toString(),
                onSubmitted: (String value) => controller.setVideoEncodingField(
                  encoderKey,
                  qpI: int.tryParse(value) ?? config.qpI,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumberField(
                label: 'qpP',
                value: config.qpP.toString(),
                onSubmitted: (String value) => controller.setVideoEncodingField(
                  encoderKey,
                  qpP: int.tryParse(value) ?? config.qpP,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumberField(
                label: 'qpB',
                value: config.qpB.toString(),
                onSubmitted: (String value) => controller.setVideoEncodingField(
                  encoderKey,
                  qpB: int.tryParse(value) ?? config.qpB,
                ),
              ),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _VideoBitrateField extends StatefulWidget {
  const _VideoBitrateField({
    required this.label,
    required this.value,
    required this.onSubmitted,
  });

  final String label;
  final String value;
  final ValueChanged<String> onSubmitted;

  @override
  State<_VideoBitrateField> createState() => _VideoBitrateFieldState();
}

class _VideoBitrateFieldState extends State<_VideoBitrateField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  var _touched = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _VideoBitrateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
      _touched = false;
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _submit();
    }
  }

  void _submit() {
    _touched = true;
    setState(() {});
    final String value = _controller.text;
    if (_isValid(value) && value != widget.value) {
      widget.onSubmitted(value);
    }
  }

  bool _isValid(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty || RegExp(r'^\d+[kKmM]$').hasMatch(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final bool invalid = _touched && !_isValid(_controller.text);
    return TextFormField(
      key: ValueKey<String>('video-${widget.label}'),
      controller: _controller,
      focusNode: _focusNode,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: invalid ? '码率格式应为如 8000k 或 5M' : null,
      ),
      onChanged: (_) {
        if (_touched) {
          setState(() => _touched = false);
        }
      },
      onFieldSubmitted: (_) => _submit(),
    );
  }
}

class _AudioSettingsTab extends StatelessWidget {
  const _AudioSettingsTab({required this.controller, required this.media});

  final AemtController controller;
  final MediaInfo? media;

  @override
  Widget build(BuildContext context) {
    final MediaInfo? info = media;
    if (info == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Align(alignment: Alignment.topLeft, child: Text('请先导入视频。')),
      );
    }
    final List<MediaStreamEntry> streams = info.streams
        .where((MediaStreamEntry stream) => stream.kind == StreamKind.audio)
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => controller.setAudioDefaultProfile(
                controller.audioDefaultProfile,
              ),
              icon: const Icon(Icons.restore),
              label: const Text('全部恢复默认'),
            ),
          ),
          const SizedBox(height: 8),
          for (final MediaStreamEntry stream in streams)
            _AudioStreamTile(
              controller: controller,
              info: info,
              stream: stream,
            ),
        ],
      ),
    );
  }
}

class _AudioStreamTile extends StatelessWidget {
  const _AudioStreamTile({
    required this.controller,
    required this.info,
    required this.stream,
  });

  final AemtController controller;
  final MediaInfo info;
  final MediaStreamEntry stream;

  @override
  Widget build(BuildContext context) {
    final String key = '${info.inputPath}#${stream.index}';
    final AudioStreamConfig config =
        controller.audioStreamConfigs[key] ?? controller.audioDefaultProfile;
    final bool enabled = stream.enabled;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: softBox(),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          initiallyExpanded: true,
          title: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${stream.index} / ${stream.codec} / ${stream.language.isEmpty ? 'und' : stream.language} / ${stream.title.isEmpty ? 'untitled' : stream.title}',
                ),
              ),
              if (!enabled)
                const Text(
                  '已禁用',
                  style: TextStyle(
                    color: Color(0xFFB42318),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: enabled
                    ? () => controller.setAudioStreamConfig(
                        key,
                        controller.audioDefaultProfile.copyWith(),
                      )
                    : null,
                child: const Text('恢复默认'),
              ),
            ),
            const SizedBox(height: 10),
            _AudioConfigEditor(
              enabled: enabled,
              config: config,
              sourceStream: stream,
              availableEncoders: controller.diagnostics.audioEncoders,
              onChanged: (AudioStreamConfig value) =>
                  controller.setAudioStreamConfig(key, value),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioConfigEditor extends StatelessWidget {
  const _AudioConfigEditor({
    required this.enabled,
    required this.config,
    required this.sourceStream,
    required this.availableEncoders,
    required this.onChanged,
  });

  final bool enabled;
  final AudioStreamConfig config;
  final MediaStreamEntry sourceStream;
  final Set<String> availableEncoders;
  final ValueChanged<AudioStreamConfig> onChanged;

  static const List<String> _encoders = <String>[
    'copy',
    'aac',
    'libfdk_aac',
    'libopus',
    'flac',
    'ac3',
    'eac3',
  ];

  @override
  Widget build(BuildContext context) {
    final bool copy = config.encoder == 'copy';
    final bool bitrateVisible = !copy && config.encoder != 'flac';
    final bool filtersVisible = !copy;
    final bool profileVisible =
        config.encoder == 'aac' || config.encoder == 'libfdk_aac';
    final bool compressionVisible =
        config.encoder == 'libopus' || config.encoder == 'flac';
    return Column(
      children: <Widget>[
        DropdownButtonFormField<String>(
          key: const ValueKey<String>('audio-encoder-dropdown'),
          initialValue: config.encoder,
          decoration: const InputDecoration(labelText: '编码器'),
          items: _encoders
              .map(
                (String encoder) => DropdownMenuItem<String>(
                  value: encoder,
                  child: Text(
                    encoder == 'copy' || availableEncoders.contains(encoder)
                        ? encoder
                        : '$encoder（未探测到）',
                  ),
                ),
              )
              .toList(),
          onChanged: enabled
              ? (String? value) {
                  if (value != null) {
                    onChanged(config.copyWith(encoder: value));
                  }
                }
              : null,
        ),
        if (bitrateVisible) ...<Widget>[
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'CBR', label: Text('CBR')),
              ButtonSegment<String>(value: 'VBR', label: Text('VBR')),
            ],
            selected: <String>{config.mode},
            onSelectionChanged: enabled
                ? (Set<String> values) =>
                      onChanged(config.copyWith(mode: values.first))
                : null,
          ),
          const SizedBox(height: 10),
          if (config.mode == 'CBR')
            _AudioBitrateField(
              enabled: enabled,
              value: config.bitrate,
              onSubmitted: (String value) =>
                  onChanged(config.copyWith(bitrate: value)),
            )
          else if (config.encoder == 'libopus')
            _DropdownField<String>(
              enabled: enabled,
              label: 'VBR 模式',
              value: config.vbrModeOpus,
              values: const <String>['off', 'on', 'constrained'],
              onChanged: (String value) =>
                  onChanged(config.copyWith(vbrModeOpus: value)),
            )
          else if (config.encoder == 'libfdk_aac')
            _DropdownField<int>(
              enabled: enabled,
              label: 'VBR 等级',
              value: config.vbrQuality,
              values: const <int>[1, 2, 3, 4, 5],
              onChanged: (int value) =>
                  onChanged(config.copyWith(vbrQuality: value)),
            )
          else if (config.encoder == 'aac')
            _SliderField(
              enabled: enabled,
              label: 'VBR 质量',
              value: config.vbrQuality,
              min: 1,
              max: 5,
              onChanged: (int value) =>
                  onChanged(config.copyWith(vbrQuality: value)),
            )
          else
            _NumberField(
              enabled: enabled,
              label: 'VBR 质量',
              value: config.vbrQuality.toString(),
              onSubmitted: (String value) => onChanged(
                config.copyWith(
                  vbrQuality: int.tryParse(value) ?? config.vbrQuality,
                ),
              ),
            ),
        ],
        if (!copy) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _DropdownField<String>(
                  enabled: enabled,
                  label: '采样率',
                  value: config.sampleRate,
                  values: config.encoder == 'libopus'
                      ? const <String>[
                          '保持源',
                          '8000',
                          '12000',
                          '16000',
                          '24000',
                          '48000',
                        ]
                      : const <String>[
                          '保持源',
                          '44100',
                          '48000',
                          '88200',
                          '96000',
                        ],
                  onChanged: (String value) =>
                      onChanged(config.copyWith(sampleRate: value)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DropdownField<String>(
                  enabled: enabled,
                  label: '声道布局',
                  value: config.channelLayout,
                  values: const <String>['保持源', 'mono', 'stereo', '5.1', '7.1'],
                  onChanged: (String value) =>
                      onChanged(config.copyWith(channelLayout: value)),
                ),
              ),
            ],
          ),
          if (config.channelLayout == 'stereo' &&
              sourceStream.channels > 2) ...<Widget>[
            const SizedBox(height: 10),
            _DropdownField<String>(
              enabled: enabled,
              label: '降混算法',
              value: config.downmixAlgo,
              values: const <String>['默认', 'dpl2'],
              onChanged: (String value) =>
                  onChanged(config.copyWith(downmixAlgo: value)),
            ),
          ],
          if (profileVisible) ...<Widget>[
            const SizedBox(height: 10),
            _DropdownField<String>(
              enabled: enabled,
              label: 'profile',
              value: config.profile,
              values: config.encoder == 'aac'
                  ? const <String>[
                      'aac_low',
                      'aac_he',
                      'aac_he_v2',
                      'aac_ld',
                      'aac_eld',
                    ]
                  : const <String>['aac_low', 'aac_he', 'aac_he_v2'],
              onChanged: (String value) =>
                  onChanged(config.copyWith(profile: value)),
            ),
          ],
          if (compressionVisible) ...<Widget>[
            const SizedBox(height: 10),
            _NumberField(
              enabled: enabled,
              label: 'compression_level',
              value: config.compressionLevel.toString(),
              onSubmitted: (String value) => onChanged(
                config.copyWith(
                  compressionLevel:
                      int.tryParse(value) ?? config.compressionLevel,
                ),
              ),
            ),
          ],
        ],
        if (filtersVisible) ...<Widget>[
          const SizedBox(height: 10),
          SwitchListTile(
            title: const Text('响度归一化'),
            value: config.loudnormEnabled,
            onChanged: enabled
                ? (bool value) =>
                      onChanged(config.copyWith(loudnormEnabled: value))
                : null,
          ),
          if (config.loudnormEnabled)
            Row(
              children: <Widget>[
                Expanded(
                  child: _NumberField(
                    enabled: enabled,
                    label: 'I',
                    value: config.loudnormI.toString(),
                    onSubmitted: (String value) => onChanged(
                      config.copyWith(
                        loudnormI: double.tryParse(value) ?? config.loudnormI,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NumberField(
                    enabled: enabled,
                    label: 'TP',
                    value: config.loudnormTp.toString(),
                    onSubmitted: (String value) => onChanged(
                      config.copyWith(
                        loudnormTp: double.tryParse(value) ?? config.loudnormTp,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NumberField(
                    enabled: enabled,
                    label: 'LRA',
                    value: config.loudnormLra.toString(),
                    onSubmitted: (String value) => onChanged(
                      config.copyWith(
                        loudnormLra:
                            double.tryParse(value) ?? config.loudnormLra,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          SwitchListTile(
            title: const Text('动态范围压缩 (DRC)'),
            value: config.drcEnabled,
            onChanged: enabled
                ? (bool value) => onChanged(config.copyWith(drcEnabled: value))
                : null,
          ),
          if (config.drcEnabled)
            Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _NumberField(
                        enabled: enabled,
                        label: 'threshold',
                        value: config.drcThreshold.toString(),
                        onSubmitted: (String value) => onChanged(
                          config.copyWith(
                            drcThreshold:
                                double.tryParse(value) ?? config.drcThreshold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _NumberField(
                        enabled: enabled,
                        label: 'ratio',
                        value: config.drcRatio.toString(),
                        onSubmitted: (String value) => onChanged(
                          config.copyWith(
                            drcRatio: double.tryParse(value) ?? config.drcRatio,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _NumberField(
                        enabled: enabled,
                        label: 'attack',
                        value: config.drcAttack.toString(),
                        onSubmitted: (String value) => onChanged(
                          config.copyWith(
                            drcAttack:
                                double.tryParse(value) ?? config.drcAttack,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _NumberField(
                        enabled: enabled,
                        label: 'release',
                        value: config.drcRelease.toString(),
                        onSubmitted: (String value) => onChanged(
                          config.copyWith(
                            drcRelease:
                                double.tryParse(value) ?? config.drcRelease,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 10),
          buildField(
            '自定义滤镜',
            config.customFilter,
            enabled
                ? (String value) =>
                      onChanged(config.copyWith(customFilter: value))
                : (_) {},
            key: 'audio-custom-filter-${config.encoder}-${config.customFilter}',
            enabled: enabled,
          ),
        ],
      ],
    );
  }
}

class _AudioBitrateField extends StatefulWidget {
  const _AudioBitrateField({
    required this.enabled,
    required this.value,
    required this.onSubmitted,
  });

  final bool enabled;
  final String value;
  final ValueChanged<String> onSubmitted;

  @override
  State<_AudioBitrateField> createState() => _AudioBitrateFieldState();
}

class _AudioBitrateFieldState extends State<_AudioBitrateField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  var _touched = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(_AudioBitrateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
      _touched = false;
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _submit();
    }
  }

  void _submit() {
    final String value = _controller.text;
    _touched = true;
    setState(() {});
    if (_isValid(value) && value != widget.value) {
      widget.onSubmitted(value);
    }
  }

  bool _isValid(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty || RegExp(r'^\d+[kK]$').hasMatch(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final bool invalid = _touched && !_isValid(_controller.text);
    return TextFormField(
      key: const ValueKey<String>('audio-bitrate-field'),
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      decoration: InputDecoration(
        labelText: '码率',
        errorText: invalid ? '码率格式应为如 192k' : null,
      ),
      onChanged: (_) {
        if (_touched) {
          setState(() {
            _touched = false;
          });
        }
      },
      onFieldSubmitted: (_) => _submit(),
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.enabled,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final bool enabled;
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final int clamped = value.clamp(min, max).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$label: $clamped'),
        Slider(
          value: clamped.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          label: clamped.toString(),
          onChanged: enabled
              ? (double value) => onChanged(value.round())
              : null,
        ),
      ],
    );
  }
}

class _FontSettingsTab extends StatelessWidget {
  const _FontSettingsTab({required this.controller});

  final AemtController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: <Widget>[
          SwitchListTile(
            title: const Text('缺失字体时仍继续导出'),
            subtitle: const Text('默认关闭。开启后字幕字体匹配失败时不再终止任务，但成品可能出现字体替换。'),
            value: controller.continueOnMissingFont,
            onChanged: controller.setContinueOnMissingFont,
          ),
          SwitchListTile(
            title: const Text('启用字体子集化'),
            subtitle: const Text(
              '关闭后不改写 ASS 字体名，也不运行 pyftsubset/ttx；内封会附加完整匹配字体，烧录会用完整字体目录。',
            ),
            value: controller.fontSubsettingEnabled,
            onChanged: controller.setFontSubsettingEnabled,
          ),
          SwitchListTile(
            title: const Text('思源黑/宋字体省略号居中对齐'),
            subtitle: const Text(
              '子集化时移除横排省略号的低基线替换规则，使横排字幕中省略号居中显示。仅对识别为 Source Han 系列的字体生效。',
            ),
            value: controller.sourceHanEllipsisFix,
            onChanged: controller.setSourceHanEllipsisFix,
          ),
        ],
      ),
    );
  }
}

class _ToneMappingTab extends StatefulWidget {
  const _ToneMappingTab({required this.controller, required this.media});

  final AemtController controller;
  final MediaInfo? media;

  @override
  State<_ToneMappingTab> createState() => _ToneMappingTabState();
}

class _ToneMappingTabState extends State<_ToneMappingTab> {
  var _advancedExpanded = false;

  @override
  Widget build(BuildContext context) {
    final AemtController controller = widget.controller;
    final VideoStreamInfo? video = widget.media?.primaryVideo;
    if (video == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Align(alignment: Alignment.topLeft, child: Text('请先导入视频。')),
      );
    }
    final SourceColorClass sourceClass = detectSourceColorClass(video);
    final bool zscaleAvailable = controller.diagnostics.hasZscale;
    final ToneMappingConfig cfg = controller.toneMappingConfig;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!zscaleAvailable)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('当前 ffmpeg 未启用 libzimg，色调映射不可用，导出将按源色彩直通'),
            ),
          if (!zscaleAvailable) const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: softBox(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        '源色彩特性',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Chip(
                      label: Text(_sourceClassLabel(sourceClass)),
                      backgroundColor: _sourceClassColor(sourceClass),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: <Widget>[
                    _InfoText('color_space', video.colorSpace),
                    _InfoText('color_primaries', video.colorPrimaries),
                    _InfoText('color_transfer', video.colorTransfer),
                    _InfoText('color_range', video.colorRange),
                    _InfoText('bit_depth', video.bitsPerRawSample.toString()),
                    _InfoText('master_display', video.masterDisplay),
                    _InfoText('max_cll', video.maxCll.toString()),
                    _InfoText('max_fall', video.maxFall.toString()),
                    _InfoText('dolby_vision', video.dolbyVision.toString()),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: softBox(),
            child: sourceClass == SourceColorClass.sdrBt709
                ? const Text('源已是 BT.709 SDR，无需色调映射')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        '推荐输出配置',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(_recommendationText(sourceClass)),
                      const SizedBox(height: 4),
                      Text('滤镜链: ${_recommendationFilterChain(sourceClass)}'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: <Widget>[
                          OutlinedButton(
                            onPressed: zscaleAvailable
                                ? () => controller.setToneMappingConfig(
                                    cfg.copyWith(
                                      tonemapMode: 'auto',
                                      tonemapAlgo: 'hable',
                                      peak: 'auto',
                                      desat: 0,
                                    ),
                                  )
                                : null,
                            child: const Text('一键采纳'),
                          ),
                          OutlinedButton(
                            onPressed: () =>
                                setState(() => _advancedExpanded = true),
                            child: const Text('我自己来'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: softBox(),
            child: Material(
              color: Colors.transparent,
              child: ExpansionTile(
                key: ValueKey<bool>(_advancedExpanded),
                title: const Text('高级覆盖'),
                initiallyExpanded: _advancedExpanded,
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _DropdownField<String>(
                          enabled: zscaleAvailable,
                          label: '输出色域',
                          value: cfg.outputPrimaries,
                          values: const <String>[
                            'bt709',
                            'bt2020',
                            'p3d65',
                            'source',
                          ],
                          onChanged: (String value) =>
                              controller.setToneMappingConfig(
                                cfg.copyWith(outputPrimaries: value),
                              ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DropdownField<String>(
                          enabled: zscaleAvailable,
                          label: '输出 Transfer',
                          value: cfg.outputTransfer,
                          values: const <String>[
                            'bt709',
                            'smpte2084',
                            'arib-std-b67',
                            'source',
                          ],
                          onChanged: (String value) =>
                              controller.setToneMappingConfig(
                                cfg.copyWith(outputTransfer: value),
                              ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DropdownField<String>(
                          enabled: zscaleAvailable,
                          label: '输出 Range',
                          value: cfg.outputRange,
                          values: const <String>['tv', 'pc', 'source'],
                          onChanged: (String value) =>
                              controller.setToneMappingConfig(
                                cfg.copyWith(outputRange: value),
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _DropdownField<String>(
                          enabled: zscaleAvailable,
                          label: 'tonemap 模式',
                          value: cfg.tonemapMode,
                          values: const <String>['auto', 'on', 'off'],
                          onChanged: (String value) =>
                              controller.setToneMappingConfig(
                                cfg.copyWith(tonemapMode: value),
                              ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DropdownField<String>(
                          enabled:
                              zscaleAvailable &&
                              (cfg.tonemapMode == 'on' ||
                                  (cfg.tonemapMode == 'auto' &&
                                      _isHdrClass(sourceClass))),
                          label: 'tonemap 算法',
                          value: cfg.tonemapAlgo,
                          values: const <String>[
                            'hable',
                            'mobius',
                            'reinhard',
                            'bt2390',
                            'linear',
                          ],
                          onChanged: (String value) =>
                              controller.setToneMappingConfig(
                                cfg.copyWith(tonemapAlgo: value),
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _NumberField(
                          enabled: zscaleAvailable,
                          label: 'peak',
                          value: cfg.peak,
                          errorText:
                              cfg.peak != 'auto' &&
                                  ((double.tryParse(cfg.peak) ?? 0) <= 0)
                              ? '色调映射参数非法: peak'
                              : null,
                          onSubmitted: (String value) => controller
                              .setToneMappingConfig(cfg.copyWith(peak: value)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _NumberField(
                          enabled: zscaleAvailable,
                          label: 'desat',
                          value: cfg.desat.toString(),
                          errorText: cfg.desat < 0 || cfg.desat > 2
                              ? '色调映射参数非法: desat'
                              : null,
                          onSubmitted: (String value) =>
                              controller.setToneMappingConfig(
                                cfg.copyWith(
                                  desat: double.tryParse(value) ?? cfg.desat,
                                ),
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoText extends StatelessWidget {
  const _InfoText(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final String display = value.trim().isEmpty ? 'unknown' : value;
    return Text('$label: $display');
  }
}

class _DropdownField<T extends Object> extends StatelessWidget {
  const _DropdownField({
    required this.enabled,
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final bool enabled;
  final String label;
  final T value;
  final List<T> values;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: values.contains(value) ? value : values.first,
      decoration: InputDecoration(labelText: label),
      items: values
          .map(
            (T item) =>
                DropdownMenuItem<T>(value: item, child: Text(item.toString())),
          )
          .toList(),
      onChanged: enabled
          ? (T? value) {
              if (value != null) {
                onChanged(value);
              }
            }
          : null,
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onSubmitted,
    this.enabled = true,
    this.errorText,
  });

  final String label;
  final String value;
  final bool enabled;
  final String? errorText;
  final ValueChanged<String> onSubmitted;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _submit();
    }
  }

  void _submit() {
    final String value = _controller.text;
    if (value != widget.value) {
      widget.onSubmitted(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey<String>('number-${widget.label}'),
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
      ),
      onFieldSubmitted: (_) => _submit(),
    );
  }
}

String _sourceClassLabel(SourceColorClass sourceClass) {
  return switch (sourceClass) {
    SourceColorClass.sdrBt709 => 'SDR_BT709',
    SourceColorClass.sdrWideGamut => 'SDR_WideGamut',
    SourceColorClass.hdrPq => 'HDR_PQ',
    SourceColorClass.hdrHlg => 'HDR_HLG',
    SourceColorClass.dolbyVision => 'DolbyVision',
    SourceColorClass.unknown => 'Unknown',
  };
}

Color _sourceClassColor(SourceColorClass sourceClass) {
  return switch (sourceClass) {
    SourceColorClass.sdrBt709 => const Color(0xFFE4E7EC),
    SourceColorClass.sdrWideGamut => const Color(0xFFD1E9FF),
    SourceColorClass.hdrPq ||
    SourceColorClass.hdrHlg => const Color(0xFFFEDFC7),
    SourceColorClass.dolbyVision => const Color(0xFFFEE4E2),
    SourceColorClass.unknown => const Color(0xFFFEF0C7),
  };
}

bool _isHdrClass(SourceColorClass sourceClass) {
  return sourceClass == SourceColorClass.hdrPq ||
      sourceClass == SourceColorClass.hdrHlg ||
      sourceClass == SourceColorClass.dolbyVision;
}

String _recommendationText(SourceColorClass sourceClass) {
  return switch (sourceClass) {
    SourceColorClass.sdrWideGamut => '推荐：BT.709 SDR + 仅色域转换（不启用 tonemap）',
    SourceColorClass.hdrPq || SourceColorClass.hdrHlg =>
      '推荐：BT.709 SDR + tonemap (hable, peak=auto, desat=0)',
    SourceColorClass.dolbyVision =>
      'AEMT 不内置 DV 解码，推荐先外部转换为 HDR10 PQ 再导入；若强行导出，将仅按其 PQ 基础层处理',
    SourceColorClass.unknown => '无法识别源色彩特性，将按 BT.709 直通处理；如有偏色请手动选择源类型',
    SourceColorClass.sdrBt709 => '源已是 BT.709 SDR，无需色调映射',
  };
}

String _recommendationFilterChain(SourceColorClass sourceClass) {
  return switch (sourceClass) {
    SourceColorClass.sdrWideGamut =>
      'zscale=primaries=bt709:transfer=bt709:matrix=bt709',
    SourceColorClass.hdrPq || SourceColorClass.hdrHlg =>
      'zscale=t=linear:npl=100,tonemap=hable:desat=0,zscale=p=bt709:t=bt709:m=bt709',
    SourceColorClass.dolbyVision => '外部转换 HDR10 PQ 后使用 PQ → BT.709 tonemap',
    SourceColorClass.unknown => '保持 BT.709 直通；必要时在高级覆盖中手动指定',
    SourceColorClass.sdrBt709 => '无需滤镜',
  };
}
