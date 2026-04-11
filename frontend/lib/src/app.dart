import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import 'controller.dart';
import 'models.dart';

class AemtApp extends StatefulWidget {
  const AemtApp({super.key});

  @override
  State<AemtApp> createState() => _AemtAppState();
}

class _AemtAppState extends State<AemtApp> {
  late final AemtController controller;
  late final ScrollController taskListScrollController;
  var dialogShown = false;

  @override
  void initState() {
    super.initState();
    controller = AemtController();
    taskListScrollController = ScrollController();
    unawaited(controller.initialize());
  }

  @override
  void dispose() {
    taskListScrollController.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme =
        Typography.material2021(platform: TargetPlatform.windows).black
            .apply(fontFamily: 'MiSans')
            .copyWith(
              titleLarge: const TextStyle(
                fontFamily: 'MiSans',
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
              titleMedium: const TextStyle(
                fontFamily: 'MiSans',
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              titleSmall: const TextStyle(
                fontFamily: 'MiSans',
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              bodyMedium: const TextStyle(
                fontFamily: 'MiSans',
                fontWeight: FontWeight.w400,
                fontSize: 14,
              ),
              bodySmall: const TextStyle(
                fontFamily: 'MiSans',
                fontWeight: FontWeight.w400,
                fontSize: 12,
              ),
            );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AEMT',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'MiSans',
        textTheme: textTheme,
        primaryTextTheme: textTheme,
        scaffoldBackgroundColor: const Color(0xFFF4F6FB),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3D5F96),
          brightness: Brightness.light,
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
        ),
      ),
      home: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, _) {
          if (controller.showStartupDialog && !dialogShown) {
            dialogShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await showDialog<void>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                  title: const Text('启动提醒'),
                  content: SizedBox(
                    width: 620,
                    child: SelectableText(controller.startupMessage),
                  ),
                  actions: <Widget>[
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('我知道了'),
                    ),
                  ],
                ),
              );
              await controller.dismissStartupDialog();
            });
          }
          return _Home(
            controller: controller,
            taskListScrollController: taskListScrollController,
          );
        },
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home({
    required this.controller,
    required this.taskListScrollController,
  });

  final AemtController controller;
  final ScrollController taskListScrollController;

  @override
  Widget build(BuildContext context) {
    final MediaInfo? media = controller.mediaInfo;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFE8EDF7),
        title: const Text('AEMT'),
        actions: <Widget>[
          TextButton.icon(
            onPressed: controller.refreshRuntime,
            icon: const Icon(Icons.refresh),
            label: const Text('重新探测'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    _section(
                      context,
                      '快速导入',
                      '选择视频与外挂字幕。',
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: <Widget>[
                          FilledButton.icon(
                            onPressed: controller.pickVideo,
                            icon: const Icon(Icons.video_file_outlined),
                            label: const Text('选择视频'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => controller.pickSubtitle(true),
                            icon: const Icon(Icons.closed_caption_outlined),
                            label: const Text('选择简体 ASS'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => controller.pickSubtitle(false),
                            icon: const Icon(Icons.closed_caption_outlined),
                            label: const Text('选择繁体 ASS'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      context,
                      '运行时解析',
                      controller.statusMessage ?? '查看运行依赖与硬件编码探测结果。',
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        initiallyExpanded: false,
                        title: const Text('展开运行时详情'),
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              OutlinedButton.icon(
                                onPressed: controller.pickRuntimeDirectory,
                                icon: const Icon(Icons.folder_open),
                                label: const Text('选择运行时目录'),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: controller.pickRuntimeExecutable,
                                icon: const Icon(
                                  Icons.settings_applications_outlined,
                                ),
                                label: const Text('选择运行时程序'),
                              ),
                            ],
                          ),
                          if (controller.customRuntimeDirectory
                              case final String runtimeDirectory) ...<Widget>[
                            const SizedBox(height: 8),
                            SelectableText('目录: $runtimeDirectory'),
                          ],
                          if (controller.customRuntimeExecutable
                              case final String runtimeExecutable) ...<Widget>[
                            const SizedBox(height: 8),
                            SelectableText('程序: $runtimeExecutable'),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: <Widget>[
                              _toolChip(controller.diagnostics.ffmpeg),
                              _toolChip(controller.diagnostics.ffprobe),
                              _toolChip(controller.diagnostics.mkvpropedit),
                              _toolChip(controller.diagnostics.sevenZip),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      context,
                      '字幕绑定',
                      '设置外挂字幕与轨道标识。',
                      Column(
                        children: <Widget>[
                          ...List<Widget>.generate(
                            controller.allBindings.length,
                            (int index) {
                              final SubtitleBinding binding =
                                  controller.allBindings[index];
                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom:
                                      index == controller.allBindings.length - 1
                                      ? 0
                                      : 12,
                                ),
                                child: _bindingBox(
                                  controller,
                                  binding,
                                  onRemove: binding.key.startsWith('custom_')
                                      ? () => controller.removeCustomBinding(
                                          binding.key,
                                        )
                                      : null,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      trailing: OutlinedButton.icon(
                        onPressed: controller.addCustomSubtitleBinding,
                        icon: const Icon(Icons.add),
                        label: const Text('添加自定义字幕'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      context,
                      '导入自定义字体',
                      '',
                      controller.importedFontSources.isEmpty
                          ? const Text('尚未导入导出字体资源。')
                          : Column(
                              children: controller.importedFontSources.map((
                                String item,
                              ) {
                                final List<String> entries =
                                    controller.importedFontEntries[item] ??
                                    <String>[];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: _softBox(),
                                    child: ExpansionTile(
                                      tilePadding: EdgeInsets.zero,
                                      childrenPadding: const EdgeInsets.only(
                                        bottom: 8,
                                      ),
                                      leading: const Icon(
                                        Icons.font_download_outlined,
                                      ),
                                      title: Text(p.basename(item)),
                                      subtitle: Text(item),
                                      trailing: IconButton(
                                        onPressed: () =>
                                            controller.removeFontSource(item),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                      children: <Widget>[
                                        if (entries.isEmpty)
                                          const Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text('未识别到可展开的字体文件'),
                                          ),
                                        ...entries.map(
                                          (String entry) => Align(
                                            alignment: Alignment.centerLeft,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 4,
                                              ),
                                              child: Text(entry),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                      trailing: OutlinedButton.icon(
                        onPressed: controller.importFonts,
                        icon: const Icon(Icons.folder_zip_outlined),
                        label: const Text('导入字体包'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      context,
                      '视频预览',
                      media == null ? '导入视频后可预览。' : media.displayName,
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        initiallyExpanded: false,
                        title: const Text('展开预览'),
                        children: <Widget>[
                          const SizedBox(height: 8),
                          _preview(context, media),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      context,
                      '章节',
                      media == null
                          ? '暂无章节。'
                          : '共 ${media.chapters.length} 个章节。',
                      media == null
                          ? const Text('先导入视频。')
                          : Column(
                              children: List<Widget>.generate(media.chapters.length, (
                                int index,
                              ) {
                                final ChapterEntry chapter =
                                    media.chapters[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        flex: 3,
                                        child: _field(
                                          '章节标题',
                                          chapter.title,
                                          (String value) => controller
                                              .updateChapterTitle(index, value),
                                          key:
                                              'chapter-title-$index-${media.inputPath}',
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _field(
                                          '开始',
                                          formatDuration(chapter.start),
                                          (String value) => controller
                                              .updateChapterStart(index, value),
                                          key:
                                              'chapter-start-$index-${media.inputPath}',
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _field(
                                          '结束',
                                          formatDuration(chapter.end),
                                          (String value) => controller
                                              .updateChapterEnd(index, value),
                                          key:
                                              'chapter-end-$index-${media.inputPath}',
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => unawaited(
                                          controller.seekTo(chapter.start),
                                        ),
                                        icon: const Icon(
                                          Icons.play_arrow_outlined,
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () =>
                                            controller.removeChapter(index),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                      trailing: OutlinedButton.icon(
                        onPressed: media == null ? null : controller.addChapter,
                        icon: const Icon(Icons.add),
                        label: const Text('新增章节'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      context,
                      '音视频 / 字幕 / 字体流',
                      media == null ? '暂无流信息。' : '导入时默认剥离内封字幕，但仍可在这里手动启用。',
                      _streams(context, media),
                      trailing: OutlinedButton.icon(
                        onPressed: media == null
                            ? null
                            : controller.removeAllEmbeddedSubtitles,
                        icon: const Icon(Icons.subtitles_off_outlined),
                        label: const Text('移除全部内封字幕'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      context,
                      '编码参数',
                      '基础设置、硬件模式和高级 preset / tune。',
                      _encoding(context, media),
                      trailing: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: controller.importEncodingSettings,
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('导入配置'),
                          ),
                          OutlinedButton.icon(
                            onPressed: controller.exportEncodingSettings,
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('导出配置'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(width: 360, child: _taskPanel(context)),
          ],
        ),
      ),
    );
  }

  Widget _preview(BuildContext context, MediaInfo? media) {
    if (media == null) {
      return const SizedBox(height: 280, child: Center(child: Text('尚未载入视频')));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        StreamBuilder<Tracks>(
          stream: controller.player.stream.tracks,
          initialData: controller.player.state.tracks,
          builder: (BuildContext context, AsyncSnapshot<Tracks> snapshot) {
            final List<MediaStreamEntry> inputSubtitleStreams = media.streams
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
              media.streams,
              embeddedTracks,
            );
            final List<DropdownMenuItem<String>>
            items = <DropdownMenuItem<String>>[
              const DropdownMenuItem<String>(value: 'off', child: Text('关闭字幕')),
              ...controller.allBindings
                  .where((SubtitleBinding binding) {
                    return binding.filePath != null &&
                        media.streams.any(
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
            aspectRatio: media.width == 0 || media.height == 0
                ? 16 / 9
                : media.width / media.height,
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

  Widget _streams(BuildContext context, MediaInfo? media) {
    if (media == null) {
      return const Text('先导入视频。');
    }
    final List<MediaStreamEntry> extractableStreams = media.streams
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
      title: Text('展开流详情（${media.streams.length} 条）'),
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
        ...List<Widget>.generate(media.streams.length, (int index) {
          final MediaStreamEntry stream = media.streams[index];
          final bool extractable = controller.isStreamExtractable(stream);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: _softBox(),
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

  Widget _encoding(BuildContext context, MediaInfo? media) {
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
                              child: _field(
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
                                  child: _field(
                                    '组标',
                                    controller.releaseGroup,
                                    controller.setReleaseGroup,
                                    key: 'release-group',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: _field(
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
                                  child: _field(
                                    '季',
                                    controller.seasonNumber,
                                    controller.setSeasonNumber,
                                    key: 'season-number',
                                    hintText: '例如 S01 / Season1 / 1',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _field(
                                    '集',
                                    controller.episodeNumber,
                                    controller.setEpisodeNumber,
                                    key: 'episode-number',
                                    hintText: '例如 01 / EP01',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _field(
                                    '视频源',
                                    controller.sourceLabel,
                                    controller.setSourceLabel,
                                    key: 'source-label',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _EpisodicNamingTemplateEditor(
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
                            child: _field(
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
                            child: _field(
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
                            child: _field(
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
                            child: _field(
                              'AVC 目标码率',
                              controller.avcBitrate,
                              controller.setAvcBitrate,
                              key: 'avc-bitrate',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _field(
                              'AVC 最大码率',
                              controller.avcMaxrate,
                              controller.setAvcMaxrate,
                              key: 'avc-maxrate',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _field(
                              'HEVC 目标码率',
                              controller.hevcBitrate,
                              controller.setHevcBitrate,
                              key: 'hevc-bitrate',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _field(
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
                          _modeChip(
                            '自动',
                            controller.hardwareMode == HardwareMode.auto,
                            () => controller.setHardwareMode(HardwareMode.auto),
                          ),
                          _modeChip(
                            '软件编码',
                            controller.hardwareMode == HardwareMode.software,
                            () => controller.setHardwareMode(
                              HardwareMode.software,
                            ),
                          ),
                          _modeChip(
                            'NVIDIA NVENC',
                            controller.hardwareMode == HardwareMode.nvenc,
                            controller.diagnostics.hasNvenc
                                ? () => controller.setHardwareMode(
                                    HardwareMode.nvenc,
                                  )
                                : null,
                          ),
                          _modeChip(
                            'Intel QSV',
                            controller.hardwareMode == HardwareMode.qsv,
                            controller.diagnostics.hasQsv
                                ? () => controller.setHardwareMode(
                                    HardwareMode.qsv,
                                  )
                                : null,
                          ),
                          _modeChip(
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
                      const Text('自动模式按 NVENC -> QSV -> AMF -> SOFTWARE 顺序回落。'),
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
                      decoration: _softBox(),
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
              decoration: _softBox(),
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
                        final bool enabled = media.streams.any(
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

  Widget _taskPanel(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('任务列表', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '共 ${controller.tasks.length} 个任务，所有导出都从这里执行。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF667085)),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: controller.queueRunning
                        ? null
                        : controller.runQueue,
                    child: Text(controller.queueRunning ? '执行中' : '开始队列'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        controller.queueRunning ||
                            controller.tasks.any(
                              (ExportTask task) =>
                                  task.status == TaskStatus.queued,
                            )
                        ? controller.stopAllTasks
                        : null,
                    child: const Text('停止全部'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: controller.clearCompleted,
                    child: const Text('清空完成'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: controller.clearQueue,
                    child: const Text('清空排队'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed:
                    controller.tasks.any(
                      (ExportTask task) =>
                          task.status == TaskStatus.failed ||
                          task.status == TaskStatus.cancelled,
                    )
                    ? () => unawaited(controller.retryAll())
                    : null,
                child: const Text('重试全部'),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: controller.tasks.isEmpty
                  ? const Center(child: Text('没有待执行任务'))
                  : Scrollbar(
                      controller: taskListScrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: taskListScrollController,
                        itemCount: controller.tasks.length,
                        itemBuilder: (BuildContext context, int index) {
                          final ExportTask task = controller.tasks[index];
                          final bool canShowLog =
                              task.log.isNotEmpty &&
                              task.status != TaskStatus.running;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GestureDetector(
                              onSecondaryTapDown: canShowLog
                                  ? (TapDownDetails details) =>
                                        _showTaskLogMenu(
                                          context,
                                          details.globalPosition,
                                          task,
                                        )
                                  : null,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: <Widget>[
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: _softBox(),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(task.label),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${_profileLabel(task.profile)} / ${_statusLabel(task.status)}',
                                          ),
                                          if (task
                                              .currentStep
                                              .isNotEmpty) ...<Widget>[
                                            const SizedBox(height: 6),
                                            Text(task.currentStep),
                                          ],
                                          const SizedBox(height: 6),
                                          Text(
                                            '${(task.progress * 100).clamp(0, 100).toStringAsFixed(task.status == TaskStatus.running ? 1 : 0)}%',
                                          ),
                                          if (task.error
                                              case final String
                                                  error) ...<Widget>[
                                            const SizedBox(height: 6),
                                            Text(
                                              error,
                                              style: const TextStyle(
                                                color: Colors.redAccent,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: FractionallySizedBox(
                                            widthFactor: _taskOverlayWidth(
                                              task,
                                            ),
                                            heightFactor: 1,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: _taskOverlayColor(task),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTaskLogMenu(
    BuildContext context,
    Offset position,
    ExportTask task,
  ) async {
    final String? action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'log', child: Text('查看日志')),
      ],
    );
    if (action == 'log' && context.mounted) {
      await _showTaskLogDialog(context, task);
    }
  }

  Future<void> _showTaskLogDialog(BuildContext context, ExportTask task) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(_profileLabel(task.profile)),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(child: SelectableText(task.log)),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}

double _taskOverlayWidth(ExportTask task) {
  switch (task.status) {
    case TaskStatus.success:
      return 1;
    case TaskStatus.failed:
    case TaskStatus.cancelled:
      return 1;
    case TaskStatus.running:
      return task.progress.clamp(0, 1).toDouble();
    case TaskStatus.queued:
      return 0;
  }
}

Color _taskOverlayColor(ExportTask task) {
  switch (task.status) {
    case TaskStatus.success:
      return const Color(0x6638A169);
    case TaskStatus.failed:
    case TaskStatus.cancelled:
      return const Color(0x66E53E3E);
    case TaskStatus.running:
      return const Color(0x664C7DF0);
    case TaskStatus.queued:
      return Colors.transparent;
  }
}

Widget _bindingBox(
  AemtController controller,
  SubtitleBinding binding, {
  VoidCallback? onRemove,
}) {
  final bool isCustom = binding.key.startsWith('custom_');
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: _softBox(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                binding.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          binding.filePath == null ? '未选择字幕文件' : p.basename(binding.filePath!),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _field(
                isCustom ? '语言代码*' : '语言代码',
                binding.languageCode,
                (String value) => controller.updateBindingMeta(
                  key: binding.key,
                  languageCode: value,
                ),
                key: 'lang-${binding.key}-${binding.filePath}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                isCustom ? '地区代码*' : '地区代码',
                binding.regionCode,
                (String value) => controller.updateBindingMeta(
                  key: binding.key,
                  regionCode: value,
                ),
                key: 'region-${binding.key}-${binding.filePath}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                isCustom ? '轨道名*' : '轨道名',
                binding.trackName,
                (String value) => controller.updateBindingMeta(
                  key: binding.key,
                  trackName: value,
                ),
                key: 'track-${binding.key}-${binding.filePath}',
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _section(
  BuildContext context,
  String title,
  String subtitle,
  Widget child, {
  Widget? trailing,
}) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    if (subtitle.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF667085),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing case final Widget widget) widget,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

Widget _field(
  String label,
  String value,
  ValueChanged<String> onChanged, {
  required String key,
  String? hintText,
  int maxLines = 1,
}) {
  return _SyncedTextField(
    key: ValueKey<String>(key),
    label: label,
    value: value,
    hintText: hintText,
    maxLines: maxLines,
    onChanged: onChanged,
  );
}

class _SyncedTextField extends StatefulWidget {
  const _SyncedTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hintText,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final int maxLines;

  @override
  State<_SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<_SyncedTextField> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_textController.text == widget.value) {
      return;
    }
    _textController.value = TextEditingValue(
      text: widget.value,
      selection: TextSelection.collapsed(offset: widget.value.length),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _textController,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
      ),
      maxLines: widget.maxLines,
      onChanged: widget.onChanged,
    );
  }
}

class _EpisodicNamingTemplateEditor extends StatefulWidget {
  const _EpisodicNamingTemplateEditor({super.key, required this.controller});

  final AemtController controller;

  @override
  State<_EpisodicNamingTemplateEditor> createState() =>
      _EpisodicNamingTemplateEditorState();
}

class _EpisodicNamingTemplateEditorState
    extends State<_EpisodicNamingTemplateEditor> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.controller.episodicNamingTemplate,
    );
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _EpisodicNamingTemplateEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String nextValue = widget.controller.episodicNamingTemplate;
    if (_textController.text == nextValue) {
      return;
    }
    final int offset = _textController.selection.baseOffset.clamp(
      0,
      nextValue.length,
    );
    _textController.value = TextEditingValue(
      text: nextValue,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _insertVariable(String variableName) {
    final String token = '{$variableName}';
    final TextSelection selection = _textController.selection;
    final String currentText = _textController.text;
    final int start = selection.isValid ? selection.start : currentText.length;
    final int end = selection.isValid ? selection.end : currentText.length;
    final String nextText = currentText.replaceRange(start, end, token);
    final int nextOffset = start + token.length;
    _textController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    widget.controller.setEpisodicNamingTemplate(nextText);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextFormField(
          controller: _textController,
          focusNode: _focusNode,
          decoration: const InputDecoration(
            labelText: '命名格式',
            hintText: AemtController.defaultEpisodicNamingTemplate,
          ),
          maxLines: 2,
          onChanged: widget.controller.setEpisodicNamingTemplate,
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: _softBox(),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            initiallyExpanded: false,
            title: const Text(
              '可用变量',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('点击下面的变量按钮可快速插入到命名格式设置栏。'),
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.controller.episodicNamingVariables
                      .map(
                        (NamingTemplateVariable variable) => OutlinedButton(
                          onPressed: () => _insertVariable(variable.name),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                          ),
                          child: Text(
                            '{${variable.name}}  ${variable.description}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _toolChip(RuntimeToolInfo tool) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: tool.available ? const Color(0xFFE8F3EB) : const Color(0xFFFDECEC),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text('${tool.name}: ${tool.available ? '已就绪' : '未找到'}'),
  );
}

Widget _modeChip(String label, bool selected, VoidCallback? onTap) {
  return ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: onTap == null ? null : (_) => onTap(),
  );
}

BoxDecoration _softBox() {
  return BoxDecoration(
    color: const Color(0xFFF7F9FD),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: const Color(0xFFD7E0EE)),
  );
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

String _profileLabel(ExportProfile profile) {
  switch (profile) {
    case ExportProfile.hardsubMp4:
      return '字幕内嵌 MP4';
    case ExportProfile.muxMkv:
      return '字幕内封 MKV';
  }
}

String _statusLabel(TaskStatus status) {
  switch (status) {
    case TaskStatus.queued:
      return '排队中';
    case TaskStatus.running:
      return '执行中';
    case TaskStatus.success:
      return '成功';
    case TaskStatus.failed:
      return '失败';
    case TaskStatus.cancelled:
      return '已取消';
  }
}
