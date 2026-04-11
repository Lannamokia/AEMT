import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../controller.dart';
import '../models.dart';

class PreviewPanel extends StatelessWidget {
  const PreviewPanel({
    super.key,
    required this.controller,
    required this.media,
  });

  final AemtController controller;
  final MediaInfo? media;

  @override
  Widget build(BuildContext context) {
    if (media == null) {
      return const SizedBox(height: 280, child: Center(child: Text('尚未载入视频')));
    }
    final MediaInfo resolvedMedia = media!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        StreamBuilder<Tracks>(
          stream: controller.player.stream.tracks,
          initialData: controller.player.state.tracks,
          builder: (BuildContext context, AsyncSnapshot<Tracks> snapshot) {
            final List<MediaStreamEntry> inputSubtitleStreams = resolvedMedia
                .streams
                .where(
                  (MediaStreamEntry stream) =>
                      stream.kind == StreamKind.subtitle &&
                      stream.origin == StreamOrigin.input,
                )
                .toList();
            final List<SubtitleTrack> embeddedTracks = snapshot.data!.subtitle
                .where(
                  (SubtitleTrack track) =>
                      track.id != 'auto' && track.id != 'no',
                )
                .toList();
            final String dropdownRefreshKey = _previewDropdownRefreshKey(
              resolvedMedia.streams,
              embeddedTracks,
            );
            final List<DropdownMenuItem<String>>
            items = <DropdownMenuItem<String>>[
              const DropdownMenuItem<String>(value: 'off', child: Text('关闭字幕')),
              ...controller.allBindings
                  .where((SubtitleBinding binding) {
                    return binding.filePath != null &&
                        resolvedMedia.streams.any(
                          (MediaStreamEntry stream) =>
                              stream.origin == StreamOrigin.externalSubtitle &&
                              stream.externalPath == binding.filePath &&
                              stream.enabled,
                        );
                  })
                  .map(
                    (SubtitleBinding binding) => DropdownMenuItem<String>(
                      value: 'external:${binding.key}',
                      child: Text(
                        '外挂字幕: ${binding.trackName.isEmpty ? binding.label : binding.trackName}',
                      ),
                    ),
                  ),
            ];
            var embeddedCursor = 0;
            for (final MediaStreamEntry stream in inputSubtitleStreams) {
              final bool useCompatPreview = controller
                  .shouldUseCompatibleSubtitlePreview(stream);
              final bool supportsDirectPreview = controller
                  .supportsDirectEmbeddedSubtitlePreview(stream);
              SubtitleTrack? embeddedTrack;
              if (!useCompatPreview &&
                  supportsDirectPreview &&
                  embeddedCursor < embeddedTracks.length) {
                embeddedTrack = embeddedTracks[embeddedCursor++];
              }
              if (!stream.enabled) {
                continue;
              }
              final String baseLabel = stream.title.isNotEmpty
                  ? stream.title
                  : (embeddedTrack?.title?.isNotEmpty == true
                        ? embeddedTrack!.title!
                        : '内封字幕 ${stream.index}');
              if (useCompatPreview) {
                if (!controller.canExtractSubtitleForPreview(stream)) {
                  continue;
                }
                items.add(
                  DropdownMenuItem<String>(
                    value: 'compat:${stream.index}',
                    child: Text('兼容预览: $baseLabel'),
                  ),
                );
                continue;
              }
              if (embeddedTrack == null) {
                if (!controller.shouldFallbackToCompatibleSubtitlePreview(
                  stream,
                )) {
                  continue;
                }
                items.add(
                  DropdownMenuItem<String>(
                    value: 'compat:${stream.index}',
                    child: Text('兼容预览: $baseLabel'),
                  ),
                );
                continue;
              }
              items.add(
                DropdownMenuItem<String>(
                  value: 'embedded:${embeddedTrack.id}',
                  child: Text(baseLabel),
                ),
              );
            }
            final Set<String> values = items
                .map((DropdownMenuItem<String> item) => item.value!)
                .toSet();
            final String selected =
                values.contains(controller.previewSubtitleKey)
                ? controller.previewSubtitleKey
                : 'off';
            return Row(
              children: <Widget>[
                const Text('预览字幕'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    key: ValueKey<String>(dropdownRefreshKey),
                    isExpanded: true,
                    value: selected,
                    items: items,
                    onChanged: (String? value) {
                      if (value != null) {
                        unawaited(controller.selectPreviewSubtitle(value));
                      }
                    },
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '提示：源文件自带的内封字幕默认不会出现在预览列表里，如需预览请先到“音视频 / 字幕 / 字体流”面板手动启用对应字幕流。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF5E6C84)),
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: resolvedMedia.width == 0 || resolvedMedia.height == 0
                ? 16 / 9
                : resolvedMedia.width / resolvedMedia.height,
            child: ColoredBox(
              color: Colors.black,
              child: Video(
                controller: controller.videoController,
                subtitleViewConfiguration: const SubtitleViewConfiguration(
                  visible: true,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _previewDropdownRefreshKey(
  List<MediaStreamEntry> streams,
  List<SubtitleTrack> embeddedTracks,
) {
  final String streamState = streams
      .where((MediaStreamEntry stream) => stream.kind == StreamKind.subtitle)
      .map(
        (MediaStreamEntry stream) =>
            '${stream.origin.index}:${stream.index}:${stream.enabled ? 1 : 0}:${stream.externalPath ?? ''}:${stream.title}:${stream.language}:${stream.regionCode}',
      )
      .join('|');
  final String trackState = embeddedTracks
      .map((SubtitleTrack track) => '${track.id}:${track.title ?? ''}')
      .join('|');
  return '$streamState#$trackState';
}
