import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'controller.dart';
import 'models.dart';
import 'utils/export_utils.dart';
import 'widgets/common_widgets.dart';
import 'widgets/encoding_panel.dart';
import 'widgets/preview_panel.dart';
import 'widgets/streams_panel.dart';
import 'widgets/task_panel.dart';

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
                    SectionCard(
                      title: '快速导入',
                      subtitle: '选择视频与外挂字幕。',
                      child: Wrap(
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
                    SectionCard(
                      title: '运行时解析',
                      subtitle: controller.statusMessage ?? '查看运行依赖与硬件编码探测结果。',
                      child: ExpansionTile(
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
                              toolChip(controller.diagnostics.ffmpeg),
                              toolChip(controller.diagnostics.ffprobe),
                              toolChip(controller.diagnostics.mkvpropedit),
                              toolChip(controller.diagnostics.sevenZip),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      title: '字幕绑定',
                      subtitle: '设置外挂字幕与轨道标识。',
                      trailing: OutlinedButton.icon(
                        onPressed: controller.addCustomSubtitleBinding,
                        icon: const Icon(Icons.add),
                        label: const Text('添加自定义字幕'),
                      ),
                      child: Column(
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
                                child: BindingBox(
                                  controller: controller,
                                  binding: binding,
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
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      title: '导入自定义字体',
                      subtitle: '',
                      trailing: OutlinedButton.icon(
                        onPressed: controller.importFonts,
                        icon: const Icon(Icons.folder_zip_outlined),
                        label: const Text('导入字体包'),
                      ),
                      child: controller.importedFontSources.isEmpty
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
                                    decoration: softBox(),
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
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      title: '视频预览',
                      subtitle: media == null ? '导入视频后可预览。' : media.displayName,
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        initiallyExpanded: false,
                        title: const Text('展开预览'),
                        children: <Widget>[
                          const SizedBox(height: 8),
                          PreviewPanel(controller: controller, media: media),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      title: '章节',
                      subtitle: media == null
                          ? '暂无章节。'
                          : '共 ${media.chapters.length} 个章节。',
                      trailing: OutlinedButton.icon(
                        onPressed: media == null ? null : controller.addChapter,
                        icon: const Icon(Icons.add),
                        label: const Text('新增章节'),
                      ),
                      child: media == null
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
                                        child: buildField(
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
                                        child: buildField(
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
                                        child: buildField(
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
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      title: '音视频 / 字幕 / 字体流',
                      subtitle: media == null
                          ? '暂无流信息。'
                          : '导入时默认剥离内封字幕，但仍可在这里手动启用。',
                      trailing: OutlinedButton.icon(
                        onPressed: media == null
                            ? null
                            : controller.removeAllEmbeddedSubtitles,
                        icon: const Icon(Icons.subtitles_off_outlined),
                        label: const Text('移除全部内封字幕'),
                      ),
                      child: StreamsPanel(controller: controller, media: media),
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      title: '编码参数',
                      subtitle: '基础设置、硬件模式和高级 preset / tune。',
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
                      child: EncodingPanel(
                        controller: controller,
                        media: media,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 360,
              child: TaskPanel(
                controller: controller,
                taskListScrollController: taskListScrollController,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
