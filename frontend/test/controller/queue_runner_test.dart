import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/src/controller.dart';
import 'package:frontend/src/models.dart';
import 'package:path/path.dart' as p;

CommandStep _subsetStep(String label) {
  return CommandStep(
    executable: 'C:/fake/pyftsubset.exe',
    arguments: const <String>['--flag'],
    description: '子集化字幕字体',
    fontSubsetStep: FontSubsetStepPlan(
      originalFont: const ResolvedFontFile(
        path: 'C:/font/original.ttf',
        fileName: 'original.ttf',
        mimeType: 'font/ttf',
      ),
      outputFont: const ResolvedFontFile(
        path: 'C:/font/subset.ttf',
        fileName: 'original.ttf',
        mimeType: 'font/ttf',
      ),
      normalizedKey: label,
      randomName: 'ABCDEFGH',
      codepoints: const <int>[0x41],
      pyftsubsetPath: 'C:/fake/pyftsubset.exe',
      ttxPath: 'C:/fake/ttx.exe',
      aemtVersion: 'test',
      fontToolsVersion: '4.55.0',
      sourceHanEllipsisFix: true,
      verifyAfterSubset: true,
      fsTypeRestricted: false,
      subsetDir: 'C:/tmp/subsetted',
      codepointsFilePath: 'C:/tmp/codepoints.txt',
      subsetTempPath: 'C:/tmp/subset_tmp.ttf',
      ttxXmlPath: 'C:/tmp/font.ttx',
    ),
  );
}

Future<CommandStep> _realCancellableSubsetStep() async {
  final Directory workDir = await Directory.systemTemp.createTemp(
    'aemt_subset_cancel_',
  );
  final String scriptPath = p.join(workDir.path, 'slow_pyftsubset.dart');
  await File(scriptPath).writeAsString('''
import 'dart:async';

Future<void> main(List<String> args) async {
  await Future<void>.delayed(const Duration(seconds: 30));
}
''');
  final String subsetDir = p.join(workDir.path, 'subsetted');
  return CommandStep(
    executable: Platform.resolvedExecutable,
    arguments: <String>['--disable-dart-dev', scriptPath],
    description: '子集化字幕字体',
    fontSubsetStep: FontSubsetStepPlan(
      originalFont: ResolvedFontFile(
        path: scriptPath,
        fileName: p.basename(scriptPath),
        mimeType: 'font/ttf',
      ),
      outputFont: ResolvedFontFile(
        path: p.join(subsetDir, 'slow.subset.ttf'),
        fileName: 'slow.ttf',
        mimeType: 'font/ttf',
      ),
      normalizedKey: 'slow',
      randomName: 'ABCDEFGH',
      codepoints: const <int>[0x41],
      pyftsubsetPath: Platform.resolvedExecutable,
      ttxPath: Platform.resolvedExecutable,
      aemtVersion: 'test',
      fontToolsVersion: '4.55.0',
      sourceHanEllipsisFix: true,
      verifyAfterSubset: true,
      fsTypeRestricted: false,
      subsetDir: subsetDir,
      codepointsFilePath: p.join(subsetDir, 'slow.unicodes.txt'),
      subsetTempPath: p.join(subsetDir, 'slow.subset_tmp_.ttf'),
      ttxXmlPath: p.join(subsetDir, 'slow.ttx'),
    ),
  );
}

CommandStep _cmdStep({required String description, required int exitCode}) {
  return CommandStep(
    executable: 'cmd.exe',
    arguments: <String>[
      '/c',
      exitCode == 0
          ? 'exit /b 0'
          : 'echo planned failure 1>&2 & exit /b $exitCode',
    ],
    description: description,
  );
}

ExportTask _queuedTask(String id) {
  return ExportTask(
    id: id,
    profile: ExportProfile.hardsubMp4,
    bindingKeys: const <String>['chs'],
    label: 'task',
    outputPath: 'out.mp4',
    status: TaskStatus.queued,
    progress: 0,
    currentStep: '',
    commandPreview: '',
    log: '',
  );
}

CommandStep _toneMappingFailureStep() {
  return CommandStep(
    executable: 'cmd.exe',
    arguments: const <String>[
      '/c',
      'echo Cannot find a matching filter: zscale 1>&2 & exit /b 1',
    ],
    description: '导出内嵌 MP4',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Property 21: subset-step progress accounting', () async {
    final AemtController controller = AemtController(initializePlayer: false);
    final List<String> seenCurrentSteps = <String>[];
    final List<double> seenProgress = <double>[];

    controller.addListener(() {
      if (controller.tasks.isEmpty) return;
      seenCurrentSteps.add(controller.tasks.first.currentStep);
      seenProgress.add(controller.tasks.first.progress);
    });

    controller.debugTaskPlanBuilder = (ExportTask task) async {
      return TaskPlan(
        outputPath: task.outputPath,
        commandPreview: 'preview',
        steps: <CommandStep>[_subsetStep('font-a'), _subsetStep('font-b')],
        workingDirectory: '.',
        expectedDuration: const Duration(seconds: 1),
      );
    };
    controller.debugSubsetStepExecutor =
        (FontSubsetStepPlan plan, Stream<void> cancelSignal) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return (
            verifyLogLine: 'subset OK: ${plan.originalFont.fileName} (1)',
            fsTypeWarning: null,
          );
        };

    controller.tasks.add(_queuedTask('t1'));

    await controller.runQueue();

    expect(seenCurrentSteps.any((String s) => s == '子集化字幕字体 (1/2)'), isTrue);
    expect(seenCurrentSteps.any((String s) => s == '子集化字幕字体 (2/2)'), isTrue);
    expect(
      controller.tasks.first.log.contains('C:/fake/pyftsubset.exe'),
      isTrue,
    );
    expect(controller.tasks.first.log.contains('C:/fake/ttx.exe'), isTrue);
    expect(seenProgress.any((double p) => p > 0 && p < 1), isTrue);
    expect(controller.tasks.first.status, TaskStatus.success);
  });

  test('Property 23: cancellation terminates pyftsubset promptly', () async {
    final AemtController controller = AemtController(initializePlayer: false);
    final CommandStep step = await _realCancellableSubsetStep();

    controller.debugTaskPlanBuilder = (ExportTask task) async {
      return TaskPlan(
        outputPath: task.outputPath,
        commandPreview: 'preview',
        steps: <CommandStep>[step],
        workingDirectory: '.',
        expectedDuration: const Duration(seconds: 1),
      );
    };

    controller.tasks.add(_queuedTask('t2'));

    final Future<void> queueFuture = controller.runQueue();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final Stopwatch sw = Stopwatch()..start();
    await controller.stopAllTasks();
    await queueFuture.timeout(const Duration(seconds: 5));
    sw.stop();

    expect(sw.elapsedMilliseconds < 500, isTrue);
    expect(controller.tasks.first.status, TaskStatus.cancelled);
    expect(controller.tasks.first.error, '任务已停止');
  });

  test(
    'zscale stderr failure marks task failed with tone-mapping advice',
    () async {
      final AemtController controller = AemtController(initializePlayer: false);
      final CommandStep step = _toneMappingFailureStep();

      controller.debugTaskPlanBuilder = (ExportTask task) async {
        return TaskPlan(
          outputPath: task.outputPath,
          commandPreview: 'preview',
          steps: <CommandStep>[step],
          workingDirectory: '.',
          expectedDuration: const Duration(seconds: 1),
        );
      };

      controller.tasks.add(_queuedTask('t3'));

      await controller.runQueue();

      expect(controller.tasks.first.status, TaskStatus.failed);
      expect(controller.tasks.first.error, '色调映射执行失败');
      expect(
        controller.tasks.first.log,
        contains('ERROR: 色调映射执行失败，建议检查 ffmpeg 是否启用 libzimg'),
      );
    },
  );

  test(
    'task-owned temp directory is deleted after successful completion',
    () async {
      final AemtController controller = AemtController(initializePlayer: false);
      final Directory workDir = await Directory.systemTemp.createTemp(
        'aemt_success_cleanup_',
      );
      final CommandStep step = _cmdStep(description: '成功命令', exitCode: 0);
      controller.debugTaskPlanBuilder = (ExportTask task) async {
        return TaskPlan(
          outputPath: task.outputPath,
          commandPreview: 'preview',
          steps: <CommandStep>[step],
          workingDirectory: workDir.path,
          expectedDuration: const Duration(seconds: 1),
        );
      };
      controller.tasks.add(_queuedTask('t4'));

      await controller.runQueue();

      expect(controller.tasks.first.status, TaskStatus.success);
      expect(await workDir.exists(), isFalse);
    },
  );

  test(
    'task-owned temp directory is deleted after failed completion',
    () async {
      final AemtController controller = AemtController(initializePlayer: false);
      final Directory workDir = await Directory.systemTemp.createTemp(
        'aemt_failure_cleanup_',
      );
      final CommandStep step = _cmdStep(description: '失败命令', exitCode: 7);
      controller.debugTaskPlanBuilder = (ExportTask task) async {
        return TaskPlan(
          outputPath: task.outputPath,
          commandPreview: 'preview',
          steps: <CommandStep>[step],
          workingDirectory: workDir.path,
          expectedDuration: const Duration(seconds: 1),
        );
      };
      controller.tasks.add(_queuedTask('t5'));

      await controller.runQueue();

      expect(controller.tasks.first.status, TaskStatus.failed);
      expect(controller.tasks.first.error, '退出码 7');
      expect(await workDir.exists(), isFalse);
    },
  );

  test(
    'task-owned temp directory is deleted after process start error',
    () async {
      final AemtController controller = AemtController(initializePlayer: false);
      final Directory workDir = await Directory.systemTemp.createTemp(
        'aemt_start_error_cleanup_',
      );
      controller.debugTaskPlanBuilder = (ExportTask task) async {
        return TaskPlan(
          outputPath: task.outputPath,
          commandPreview: 'preview',
          steps: const <CommandStep>[
            CommandStep(
              executable: 'C:/definitely/not/a/real/executable.exe',
              arguments: <String>[],
              description: '启动失败',
            ),
          ],
          workingDirectory: workDir.path,
          expectedDuration: const Duration(seconds: 1),
        );
      };
      controller.tasks.add(_queuedTask('t6'));

      await controller.runQueue();

      expect(controller.tasks.first.status, TaskStatus.failed);
      expect(controller.tasks.first.error, contains('executable'));
      expect(await workDir.exists(), isFalse);
    },
  );

  test('retry clears stale task error before rerun starts', () async {
    final AemtController controller = AemtController(initializePlayer: false);
    final List<String?> seenErrors = <String?>[];
    controller.addListener(() {
      if (controller.tasks.isNotEmpty) {
        seenErrors.add(controller.tasks.first.error);
      }
    });
    controller.debugTaskPlanBuilder = (ExportTask task) async {
      return TaskPlan(
        outputPath: task.outputPath,
        commandPreview: 'preview',
        steps: <CommandStep>[_cmdStep(description: '成功命令', exitCode: 0)],
        workingDirectory: '.',
        expectedDuration: const Duration(seconds: 1),
      );
    };
    controller.tasks.add(
      _queuedTask('t7').copyWith(
        status: TaskStatus.failed,
        progress: 0.35,
        currentStep: '失败阶段',
        commandPreview: 'old preview',
        log: 'old log',
        error: 'Exception: 旧错误',
      ),
    );

    await controller.retryAll();

    expect(seenErrors, contains(null));
    expect(controller.tasks.first.status, TaskStatus.success);
    expect(controller.tasks.first.error, isNull);
    expect(controller.tasks.first.log, isNot(contains('旧错误')));
  });

  test('temp cleanup guard only accepts aemt-owned temp subdirectories', () {
    final AemtController controller = AemtController(initializePlayer: false);
    final String tempRoot = Directory.systemTemp.path;

    expect(
      controller.debugIsOwnedTempDirectory(
        p.join(tempRoot, 'aemt_guard_example'),
      ),
      isTrue,
    );
    expect(controller.debugIsOwnedTempDirectory(tempRoot), isFalse);
    expect(
      controller.debugIsOwnedTempDirectory(p.join(tempRoot, 'not_aemt')),
      isFalse,
    );
    expect(
      controller.debugIsOwnedTempDirectory('C:/not-temp/aemt_guard_example'),
      isFalse,
    );
  });
}
