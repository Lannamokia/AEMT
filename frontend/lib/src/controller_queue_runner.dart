part of 'controller.dart';

class _QueueRunner {
  _QueueRunner(this._controller);

  final AemtController _controller;

  Future<void> exportNow(
    ExportProfile profile,
    List<String> bindingKeys,
  ) async {
    _controller.tasks.add(await createTask(profile, bindingKeys));
    _controller._markChanged();
    unawaited(runQueue());
  }

  Future<void> enqueueTask(
    ExportProfile profile,
    List<String> bindingKeys,
  ) async {
    _controller.tasks.add(await createTask(profile, bindingKeys));
    _controller._markChanged();
  }

  Future<void> enqueueSelectedTasks() async {
    final List<String> hardsubKeys = _controller._selectedExistingBindingKeys(
      _controller.selectedHardsubBindingKeys,
    );
    for (final String key in hardsubKeys) {
      await enqueueTask(ExportProfile.hardsubMp4, <String>[key]);
    }
    final List<String> muxKeys = _controller._selectedExistingBindingKeys(
      _controller.selectedMuxBindingKeys,
    );
    if (muxKeys.isNotEmpty) {
      await enqueueTask(ExportProfile.muxMkv, muxKeys);
    }
  }

  Future<void> enqueueSelectedHardsubTasks() async {
    final List<String> hardsubKeys = _controller._selectedExistingBindingKeys(
      _controller.selectedHardsubBindingKeys,
    );
    for (final String key in hardsubKeys) {
      await enqueueTask(ExportProfile.hardsubMp4, <String>[key]);
    }
  }

  Future<void> enqueueSelectedMuxTask() async {
    final List<String> muxKeys = _controller._selectedExistingBindingKeys(
      _controller.selectedMuxBindingKeys,
    );
    if (muxKeys.isEmpty) {
      return;
    }
    await enqueueTask(ExportProfile.muxMkv, muxKeys);
  }

  Future<void> runQueue() async {
    if (_controller.queueRunning || _controller._activeProcess != null) {
      return;
    }
    _controller.stopQueueRequested = false;
    _controller.queueRunning = true;
    _controller._markChanged();
    while (true) {
      if (_controller.stopQueueRequested) {
        break;
      }
      final int taskIndex = _controller.tasks.indexWhere(
        (ExportTask task) => task.status == TaskStatus.queued,
      );
      if (taskIndex == -1) {
        break;
      }
      _controller.tasks[taskIndex] = _controller.tasks[taskIndex].copyWith(
        status: TaskStatus.running,
        progress: 0,
        currentStep: '准备任务资源',
        commandPreview: '',
        log: '',
      );
      _controller._markChanged();
      TaskPlan? plan;
      try {
        final DebugTaskPlanBuilder? debugBuilder =
            _controller.debugTaskPlanBuilder;
        plan = debugBuilder == null
            ? await _controller._taskPlanner.buildTaskPlan(
                _controller.tasks[taskIndex],
              )
            : await debugBuilder(_controller.tasks[taskIndex]);
        _controller.tasks[taskIndex] = _controller.tasks[taskIndex].copyWith(
          progress: 0,
          currentStep: plan.steps.first.description,
          commandPreview: plan.commandPreview,
          log: '',
        );
      } catch (error) {
        _controller.tasks[taskIndex] = _controller.tasks[taskIndex].copyWith(
          status: TaskStatus.failed,
          progress: 0,
          currentStep: '',
          error: error.toString(),
          log: error.toString(),
        );
        _controller._markChanged();
        continue;
      }
      _controller._markChanged();
      final TaskPlan resolvedPlan = plan;
      final StringBuffer buffer = StringBuffer();
      var exitCode = 0;
      try {
        for (
          var stepIndex = 0;
          stepIndex < resolvedPlan.steps.length;
          stepIndex++
        ) {
          final CommandStep step = resolvedPlan.steps[stepIndex];
          final FontSubsetStepPlan? subsetPlan = step.fontSubsetStep;
          final String stepDescription = subsetPlan == null
              ? step.description
              : _subsetStepDescription(
                  resolvedPlan.steps,
                  currentStepIndex: stepIndex,
                );
          buffer.writeln('> $stepDescription');
          if (subsetPlan == null) {
            buffer.writeln(renderCommand(step.executable, step.arguments));
          } else {
            _writeSubsetStepCommandLines(buffer, subsetPlan);
          }
          _controller.tasks[taskIndex] = _controller.tasks[taskIndex].copyWith(
            currentStep: stepDescription,
            progress: stepIndex / resolvedPlan.steps.length,
            log: buffer.toString(),
          );
          _controller._markChanged();
          if (subsetPlan != null) {
            final DebugSubsetStepExecutor? debugExecutor =
                _controller.debugSubsetStepExecutor;
            ({String verifyLogLine, String? fsTypeWarning}) result;
            try {
              result = debugExecutor == null
                  ? await _controller._fontAssetService.executeSubsetFontStep(
                      subsetPlan,
                      cancelSignal: _controller._queueCancelSignal.stream,
                    )
                  : await debugExecutor(
                      subsetPlan,
                      _controller._queueCancelSignal.stream,
                    );
            } catch (error) {
              buffer.writeln(error);
              exitCode = 1;
              break;
            }
            buffer.writeln(result.verifyLogLine);
            if (result.fsTypeWarning != null) {
              buffer.writeln(result.fsTypeWarning);
            }
            if (_controller.stopQueueRequested) {
              exitCode = 1;
              break;
            }
            _controller.tasks[taskIndex] = _controller.tasks[taskIndex]
                .copyWith(
                  progress: (stepIndex + 1) / resolvedPlan.steps.length,
                  log: buffer.toString(),
                );
            _controller._markChanged();
            continue;
          }
          final Process process = await Process.start(
            step.executable,
            step.arguments,
            workingDirectory: resolvedPlan.workingDirectory,
            runInShell: false,
          );
          _controller._activeProcess = process;
          final bool canTrackProgress = _isFfmpegProgressStep(step);
          final StreamSubscription<String> stdoutSub = process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((String line) {
                _handleTaskOutputLine(
                  taskIndex: taskIndex,
                  line: line,
                  buffer: buffer,
                  canTrackProgress: canTrackProgress,
                  stepIndex: stepIndex,
                  totalSteps: resolvedPlan.steps.length,
                  expectedDuration: resolvedPlan.expectedDuration,
                );
              });
          final StreamSubscription<String> stderrSub = process.stderr
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((String line) {
                _handleTaskOutputLine(
                  taskIndex: taskIndex,
                  line: line,
                  buffer: buffer,
                  canTrackProgress: canTrackProgress,
                  stepIndex: stepIndex,
                  totalSteps: resolvedPlan.steps.length,
                  expectedDuration: resolvedPlan.expectedDuration,
                );
              });
          exitCode = await process.exitCode;
          await stdoutSub.cancel();
          await stderrSub.cancel();
          if (exitCode == 0) {
            _controller.tasks[taskIndex] = _controller.tasks[taskIndex]
                .copyWith(
                  progress: (stepIndex + 1) / resolvedPlan.steps.length,
                  log: buffer.toString(),
                );
            _controller._markChanged();
          }
          if (exitCode != 0 || _controller.stopQueueRequested) {
            break;
          }
        }
      } finally {
        _controller._activeProcess = null;
      }
      _controller.tasks[taskIndex] = _controller.tasks[taskIndex].copyWith(
        status: _controller.stopQueueRequested
            ? TaskStatus.cancelled
            : (exitCode == 0 ? TaskStatus.success : TaskStatus.failed),
        progress: exitCode == 0 ? 1 : _controller.tasks[taskIndex].progress,
        currentStep: _controller.stopQueueRequested
            ? '已停止'
            : (exitCode == 0
                  ? '已完成'
                  : _controller.tasks[taskIndex].currentStep),
        error: _controller.stopQueueRequested
            ? '任务已停止'
            : (exitCode == 0 ? null : '退出码 $exitCode'),
        log: buffer.toString(),
      );
      _controller._markChanged();
    }
    _controller.queueRunning = false;
    _controller.stopQueueRequested = false;
    _controller._markChanged();
  }

  Future<void> stopAllTasks() async {
    _controller.stopQueueRequested = true;
    _controller._queueCancelSignal.add(null);
    _controller._activeProcess?.kill(ProcessSignal.sigterm);
    _controller._markChanged();
  }

  void clearCompleted() {
    _controller.tasks.removeWhere(
      (ExportTask task) => task.status == TaskStatus.success,
    );
    _controller._markChanged();
  }

  void clearQueue() {
    _controller.tasks.removeWhere(
      (ExportTask task) => task.status == TaskStatus.queued,
    );
    _controller._markChanged();
  }

  Future<void> retryAll() async {
    var hasRetriedTask = false;
    for (var i = 0; i < _controller.tasks.length; i++) {
      final ExportTask task = _controller.tasks[i];
      if (task.status != TaskStatus.failed &&
          task.status != TaskStatus.cancelled) {
        continue;
      }
      hasRetriedTask = true;
      _controller.tasks[i] = task.copyWith(
        status: TaskStatus.queued,
        progress: 0,
        currentStep: '',
        commandPreview: '',
        log: '',
        error: null,
      );
    }
    _controller._markChanged();
    if (hasRetriedTask && !_controller.queueRunning) {
      await runQueue();
    }
  }

  Future<ExportTask> createTask(
    ExportProfile profile,
    List<String> bindingKeys,
  ) async {
    final List<String> resolvedBindingKeys = _controller
        ._selectedExistingBindingKeys(bindingKeys);
    return ExportTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      profile: profile,
      bindingKeys: resolvedBindingKeys,
      label: _controller._exportConfig.buildTaskLabel(
        profile,
        resolvedBindingKeys,
      ),
      outputPath: _controller._exportConfig.buildOutputPath(
        profile,
        resolvedBindingKeys,
      ),
      status: TaskStatus.queued,
      progress: 0,
      currentStep: '',
      commandPreview: '',
      log: '',
    );
  }

  void _handleTaskOutputLine({
    required int taskIndex,
    required String line,
    required StringBuffer buffer,
    required bool canTrackProgress,
    required int stepIndex,
    required int totalSteps,
    required Duration expectedDuration,
  }) {
    buffer.writeln(line);
    double? progress;
    if (canTrackProgress) {
      progress = _extractTaskProgress(
        line: line,
        stepIndex: stepIndex,
        totalSteps: totalSteps,
        expectedDuration: expectedDuration,
      );
    }
    _controller.tasks[taskIndex] = _controller.tasks[taskIndex].copyWith(
      progress: progress ?? _controller.tasks[taskIndex].progress,
      log: buffer.toString(),
    );
    _controller._markChanged();
  }

  double? _extractTaskProgress({
    required String line,
    required int stepIndex,
    required int totalSteps,
    required Duration expectedDuration,
  }) {
    if (expectedDuration <= Duration.zero || totalSteps <= 0) {
      return null;
    }
    final String trimmed = line.trim();
    int? outTimeUs;
    if (trimmed.startsWith('out_time_us=')) {
      outTimeUs = int.tryParse(trimmed.substring('out_time_us='.length));
    } else if (trimmed.startsWith('out_time_ms=')) {
      outTimeUs = int.tryParse(trimmed.substring('out_time_ms='.length));
    } else if (trimmed == 'progress=end') {
      return (stepIndex + 1) / totalSteps;
    }
    if (outTimeUs == null) {
      return null;
    }
    final double stepProgress = (outTimeUs / expectedDuration.inMicroseconds)
        .clamp(0, 1)
        .toDouble();
    return ((stepIndex + stepProgress) / totalSteps).clamp(0, 1).toDouble();
  }

  bool _isFfmpegProgressStep(CommandStep step) {
    return step.fontSubsetStep == null &&
        p.basename(step.executable).toLowerCase() == 'ffmpeg.exe';
  }

  String _subsetStepDescription(
    List<CommandStep> steps, {
    required int currentStepIndex,
  }) {
    var totalSubsetSteps = 0;
    var currentSubsetOrdinal = 0;
    for (var i = 0; i < steps.length; i++) {
      if (steps[i].fontSubsetStep == null) {
        continue;
      }
      totalSubsetSteps++;
      if (i <= currentStepIndex) {
        currentSubsetOrdinal++;
      }
    }
    return '子集化字幕字体 ($currentSubsetOrdinal/$totalSubsetSteps)';
  }

  void _writeSubsetStepCommandLines(
    StringBuffer buffer,
    FontSubsetStepPlan plan,
  ) {
    buffer
      ..writeln(renderCommand(plan.pyftsubsetPath, plan.pyftsubsetArguments))
      ..writeln(renderCommand(plan.ttxPath, plan.ttxDumpArguments))
      ..writeln(renderCommand(plan.ttxPath, plan.ttxCompileArguments));
  }
}
