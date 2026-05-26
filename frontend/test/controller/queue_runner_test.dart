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
    arguments: <String>[scriptPath],
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

    controller.tasks.add(
      const ExportTask(
        id: 't1',
        profile: ExportProfile.hardsubMp4,
        bindingKeys: <String>['chs'],
        label: 'task',
        outputPath: 'out.mp4',
        status: TaskStatus.queued,
        progress: 0,
        currentStep: '',
        commandPreview: '',
        log: '',
      ),
    );

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

    controller.tasks.add(
      const ExportTask(
        id: 't2',
        profile: ExportProfile.hardsubMp4,
        bindingKeys: <String>['chs'],
        label: 'task',
        outputPath: 'out.mp4',
        status: TaskStatus.queued,
        progress: 0,
        currentStep: '',
        commandPreview: '',
        log: '',
      ),
    );

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
}
