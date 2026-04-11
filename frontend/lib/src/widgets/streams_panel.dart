import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../controller.dart';
import '../models.dart';
import 'common_widgets.dart';

class StreamsPanel extends StatelessWidget {
  const StreamsPanel({
    super.key,
    required this.controller,
    required this.media,
  });

  final AemtController controller;
  final MediaInfo? media;

  @override
  Widget build(BuildContext context) {
    if (media == null) {
      return const Text('先导入视频。');
    }
    final MediaInfo resolvedMedia = media!;
    final List<MediaStreamEntry> extractableStreams = resolvedMedia.streams
        .where(controller.isStreamExtractable)
        .toList();
    final int selectedCount = extractableStreams
        .where(controller.isStreamSelectedForExtraction)
        .length;
    final bool allSelected =
        extractableStreams.isNotEmpty &&
        selectedCount == extractableStreams.length;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: false,
      title: Text('展开流详情（${resolvedMedia.streams.length} 条）'),
      children: <Widget>[
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Text(
              selectedCount == 0 ? '未选择抽取流' : '已选择 $selectedCount 条流',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: extractableStreams.isEmpty
                  ? null
                  : () => controller.setAllExtractableStreamSelections(
                      !allSelected,
                    ),
              icon: Icon(
                allSelected ? Icons.deselect_outlined : Icons.select_all,
              ),
              label: Text(allSelected ? '清空选择' : '全选可抽取流'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: controller.streamExtractionRunning
                  ? null
                  : controller.extractSelectedStreams,
              icon: const Icon(Icons.download_outlined),
              label: Text(
                controller.streamExtractionRunning ? '抽取中...' : '抽取选中流',
              ),
            ),
          ],
        ),
        if (controller.streamExtractionMessage
            case final String message) ...<Widget>[
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: Text(message)),
        ],
        const SizedBox(height: 8),
        ...List<Widget>.generate(resolvedMedia.streams.length, (int index) {
          final MediaStreamEntry stream = resolvedMedia.streams[index];
          final bool extractable = controller.isStreamExtractable(stream);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: softBox(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (extractable)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Checkbox(
                        value: controller.isStreamSelectedForExtraction(stream),
                        onChanged: (bool? value) =>
                            controller.toggleStreamExtractionSelection(
                              stream,
                              value ?? false,
                            ),
                      ),
                    )
                  else
                    const SizedBox(width: 48),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '索引 ${stream.index}  ${_streamKindLabel(stream.kind)}  ${stream.codec}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(_streamSummary(stream)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: const Text('启用'),
                    selected: stream.enabled,
                    showCheckmark: true,
                    onSelected: (bool value) =>
                        controller.updateStreamEnabled(index, value),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => controller.removeStream(index),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除'),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

String _streamKindLabel(StreamKind kind) {
  switch (kind) {
    case StreamKind.video:
      return 'video';
    case StreamKind.audio:
      return 'audio';
    case StreamKind.subtitle:
      return 'subtitle';
    case StreamKind.attachment:
      return '字体附件';
    case StreamKind.data:
      return 'data';
    case StreamKind.unknown:
      return 'unknown';
  }
}

String _streamSummary(MediaStreamEntry stream) {
  final String? previewMode = _previewCapabilityLabel(stream);
  final List<String> parts = <String>[
    stream.sourceLabel,
    if (stream.title.isNotEmpty) '标题: ${stream.title}',
    if (stream.language.isNotEmpty) '语言: ${stream.language}',
    if (stream.regionCode.isNotEmpty) '地区: ${stream.regionCode}',
    if (stream.attachmentFileName?.isNotEmpty == true)
      '文件: ${stream.attachmentFileName}',
    if (stream.externalPath?.isNotEmpty == true)
      '路径: ${p.basename(stream.externalPath!)}',
    if (stream.isDefault) '默认',
    if (stream.isForced) '强制',
  ];
  if (previewMode != null) {
    parts.insert(
      parts.length - (stream.isForced ? 1 : 0) - (stream.isDefault ? 1 : 0),
      previewMode,
    );
  }
  return parts.join(' / ');
}

String? _previewCapabilityLabel(MediaStreamEntry stream) {
  if (stream.kind != StreamKind.subtitle ||
      stream.origin != StreamOrigin.input) {
    return null;
  }
  final String codec = stream.codec.trim().toLowerCase();
  if (<String>{'arib_caption'}.contains(codec)) {
    return '预览: 兼容抽取';
  }
  if (<String>{
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
  }.contains(codec)) {
    return '预览: 直通';
  }
  return null;
}
