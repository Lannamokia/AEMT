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
      length: 3,
      child: Column(
        children: <Widget>[
          const TabBar(
            tabs: <Widget>[
              Tab(text: '基础设置'),
              Tab(text: '硬件加速'),
              Tab(text: '高级编码参数'),
            ],
          ),
          SizedBox(
            height: 320,
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
                GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  padding: const EdgeInsets.only(top: 14),
                  childAspectRatio: 1.7,
                  children: controller.encoderTunings.values.map((
                    EncoderTuning tuning,
                  ) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: softBox(),
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
                            decoration: const InputDecoration(
                              labelText: 'Preset',
                            ),
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
                                controller.updateEncoderPreset(
                                  tuning.key,
                                  value,
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: tuning.tune,
                            decoration: const InputDecoration(
                              labelText: 'Tune',
                            ),
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
                        ],
                      ),
                    );
                  }).toList(),
                ),
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
