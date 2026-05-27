import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import 'common_widgets.dart';

class TaskPanel extends StatelessWidget {
  const TaskPanel({
    super.key,
    required this.controller,
    required this.taskListScrollController,
  });

  final AemtController controller;
  final ScrollController taskListScrollController;

  @override
  Widget build(BuildContext context) {
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
                    onPressed: controller.clearAllTasks,
                    child: const Text('清空全部'),
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
                        findChildIndexCallback: (Key key) {
                          if (key case ValueKey<String>(:final value)) {
                            final int index = controller.tasks.indexWhere(
                              (ExportTask task) => task.id == value,
                            );
                            return index == -1 ? null : index;
                          }
                          return null;
                        },
                        itemBuilder: (BuildContext context, int index) {
                          final ExportTask task = controller.tasks[index];
                          final bool canShowLog =
                              task.log.isNotEmpty &&
                              task.status != TaskStatus.running;
                          return Padding(
                            key: ValueKey<String>(task.id),
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
                              child: Semantics(
                                container: true,
                                excludeSemantics: true,
                                label: _taskSemanticsLabel(task),
                                value: _taskSemanticsValue(task),
                                button: canShowLog,
                                onTap: canShowLog
                                    ? () => unawaited(
                                        _showTaskLogDialog(context, task),
                                      )
                                    : null,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    children: <Widget>[
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: softBox(),
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
                                            Text(_taskProgressLabel(task)),
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
                                                  color: _taskOverlayColor(
                                                    task,
                                                  ),
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

String _taskSemanticsLabel(ExportTask task) {
  final List<String> parts = <String>[
    task.label,
    _profileLabel(task.profile),
    _statusLabel(task.status),
  ];
  if (task.currentStep.isNotEmpty) {
    parts.add(task.currentStep);
  }
  if (task.error case final String error) {
    parts.add(error);
  }
  return parts.join('，');
}

String _taskSemanticsValue(ExportTask task) {
  return _taskProgressLabel(task);
}

String _taskProgressLabel(ExportTask task) {
  return '${(task.progress * 100).clamp(0, 100).toStringAsFixed(task.status == TaskStatus.running ? 1 : 0)}%';
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
