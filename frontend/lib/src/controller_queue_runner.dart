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
    final Map<String, _SharedFontPipelineContext> sharedPipelines =
        await _prepareSharedFontPipelines();
    try {
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
        await _runTaskAtIndex(taskIndex, sharedPipelines);
      }
    } finally {
      for (final _SharedFontPipelineContext context in sharedPipelines.values) {
        await _controller._deleteOwnedTempDirectory(context.workDir);
      }
      sharedPipelines.clear();
      _controller.queueRunning = false;
      _controller.stopQueueRequested = false;
      _controller._markChanged();
    }
  }

  Future<void> _runTaskAtIndex(
    int taskIndex,
    Map<String, _SharedFontPipelineContext> sharedPipelines,
  ) async {
    _controller.tasks[taskIndex] = _controller.tasks[taskIndex].copyWith(
      status: TaskStatus.running,
      progress: 0,
      currentStep: '准备任务资源',
      commandPreview: '',
      log: '',
      clearError: true,
    );
    _controller._markChanged();
    TaskPlan? plan;
    try {
      final DebugTaskPlanBuilder? debugBuilder =
          _controller.debugTaskPlanBuilder;
      final _SharedFontPipelineUse? sharedUse = debugBuilder == null
          ? _sharedFontPipelineUseForTask(
              _controller.tasks[taskIndex],
              sharedPipelines,
            )
          : null;
      plan = debugBuilder == null
          ? await _controller._taskPlanner.buildTaskPlan(
              _controller.tasks[taskIndex],
              sharedFontPipeline: sharedUse,
            )
          : await debugBuilder(_controller.tasks[taskIndex]);
      _controller.tasks[taskIndex] = _controller.tasks[taskIndex].copyWith(
        progress: 0,
        currentStep: plan.steps.first.description,
        commandPreview: plan.commandPreview,
        log: '',
      );
    } catch (error) {
      if (plan != null) {
        await _cleanupTaskWorkingDirectory(plan, sharedPipelines);
      }
      _controller.tasks[taskIndex] = _controller.tasks[taskIndex].copyWith(
        status: TaskStatus.failed,
        progress: 0,
        currentStep: '',
        error: error.toString(),
        log: error.toString(),
      );
      _controller._markChanged();
      return;
    }
    _controller._markChanged();
    final TaskPlan resolvedPlan = plan;
    final StringBuffer buffer = StringBuffer();
    for (final String line in resolvedPlan.initialLogLines) {
      buffer.writeln(line);
    }
    var exitCode = 0;
    var toneMappingExecutionFailed = false;
    Object? executionError;
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
          progress: _progressBeforeStep(resolvedPlan.steps, stepIndex),
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
          _controller.tasks[taskIndex] = _controller.tasks[taskIndex].copyWith(
            progress: _progressAfterStep(resolvedPlan.steps, stepIndex),
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
              if (_isToneMappingExecutionFailure(line)) {
                toneMappingExecutionFailed = true;
              }
              _handleTaskOutputLine(
                taskIndex: taskIndex,
                line: line,
                buffer: buffer,
                canTrackProgress: canTrackProgress,
                stepIndex: stepIndex,
                steps: resolvedPlan.steps,
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
                steps: resolvedPlan.steps,
                expectedDuration: resolvedPlan.expectedDuration,
              );
            });
        exitCode = await process.exitCode;
        await stdoutSub.cancel();
        await stderrSub.cancel();
        toneMappingExecutionFailed =
            toneMappingExecutionFailed ||
            _isToneMappingExecutionFailure(buffer.toString());
        if (toneMappingExecutionFailed) {
          buffer.writeln('ERROR: 色调映射执行失败，建议检查 ffmpeg 是否启用 libzimg');
          _controller.tasks[taskIndex] = _controller.tasks[taskIndex].copyWith(
            log: buffer.toString(),
          );
          _controller._markChanged();
        }
        if (exitCode == 0) {
          _controller.tasks[taskIndex] = _controller.tasks[taskIndex].copyWith(
            progress: _progressAfterStep(resolvedPlan.steps, stepIndex),
            log: buffer.toString(),
          );
          _controller._markChanged();
        }
        if (toneMappingExecutionFailed) {
          exitCode = exitCode == 0 ? 1 : exitCode;
          break;
        }
        if (exitCode != 0 || _controller.stopQueueRequested) {
          break;
        }
      }
    } catch (error) {
      executionError = error;
      exitCode = 1;
      buffer.writeln(error);
    } finally {
      _controller._activeProcess = null;
    }
    try {
      final bool success =
          exitCode == 0 &&
          !_controller.stopQueueRequested &&
          executionError == null;
      _markSharedFontPipelineAfterTask(resolvedPlan, success, sharedPipelines);
      _controller.tasks[taskIndex] = _controller.tasks[taskIndex].copyWith(
        status: _controller.stopQueueRequested
            ? TaskStatus.cancelled
            : (success ? TaskStatus.success : TaskStatus.failed),
        progress: success ? 1 : _controller.tasks[taskIndex].progress,
        currentStep: _controller.stopQueueRequested
            ? '已停止'
            : (success ? '已完成' : _controller.tasks[taskIndex].currentStep),
        error: _controller.stopQueueRequested
            ? '任务已停止'
            : (success
                  ? null
                  : (toneMappingExecutionFailed
                        ? '色调映射执行失败'
                        : executionError?.toString() ?? '退出码 $exitCode')),
        log: buffer.toString(),
      );
      _controller._markChanged();
    } finally {
      await _cleanupTaskWorkingDirectory(resolvedPlan, sharedPipelines);
    }
  }

  Future<void> stopAllTasks() async {
    _controller.stopQueueRequested = true;
    _controller._queueCancelSignal.add(null);
    _controller._activeProcess?.kill(ProcessSignal.sigterm);
    _controller._markChanged();
  }

  Future<Map<String, _SharedFontPipelineContext>>
  _prepareSharedFontPipelines() async {
    if (_controller.debugTaskPlanBuilder != null ||
        _controller.mediaInfo == null) {
      return <String, _SharedFontPipelineContext>{};
    }
    final List<ExportTask> queued = _controller.tasks
        .where((ExportTask task) => task.status == TaskStatus.queued)
        .toList();
    if (queued.length < 2) {
      return <String, _SharedFontPipelineContext>{};
    }
    final Set<String> bindingKeys = <String>{};
    final Set<String> taskIds = <String>{};
    for (final ExportTask task in queued) {
      bindingKeys.addAll(task.bindingKeys);
      taskIds.add(task.id);
    }
    if (bindingKeys.isEmpty) {
      return <String, _SharedFontPipelineContext>{};
    }
    final Directory workDir = await Directory.systemTemp.createTemp(
      'aemt_shared_',
    );
    try {
      final List<SubtitleBinding> bindings = _controller._resolveBindings(
        bindingKeys.toList(),
      );
      if (bindings.isEmpty) {
        await _controller._deleteOwnedTempDirectory(workDir.path);
        return <String, _SharedFontPipelineContext>{};
      }
      final _FontPipelineResult result = await _controller._taskPlanner
          ._runFontPipelineForBindings(bindings, workDir.path);
      if (result.subsetSteps.isEmpty) {
        await _controller._deleteOwnedTempDirectory(workDir.path);
        return <String, _SharedFontPipelineContext>{};
      }
      final String key = _sharedFontPipelineKeyForMedia();
      return <String, _SharedFontPipelineContext>{
        key: _SharedFontPipelineContext(
          key: key,
          workDir: workDir.path,
          result: result,
          pendingTaskIds: taskIds,
        ),
      };
    } catch (_) {
      await _controller._deleteOwnedTempDirectory(workDir.path);
      return <String, _SharedFontPipelineContext>{};
    }
  }

  _SharedFontPipelineUse? _sharedFontPipelineUseForTask(
    ExportTask task,
    Map<String, _SharedFontPipelineContext> sharedPipelines,
  ) {
    final _SharedFontPipelineContext? context =
        sharedPipelines[_sharedFontPipelineKeyForMedia()];
    if (context == null ||
        context.failed ||
        !context.pendingTaskIds.contains(task.id)) {
      return null;
    }
    if (!context.executorAssigned) {
      context.executorAssigned = true;
      return _SharedFontPipelineUse(
        key: context.key,
        result: context.result,
        includeSubsetSteps: true,
      );
    }
    if (!context.subsetReady) {
      return null;
    }
    return _SharedFontPipelineUse(
      key: context.key,
      result: context.result,
      includeSubsetSteps: false,
    );
  }

  void _markSharedFontPipelineAfterTask(
    TaskPlan plan,
    bool success,
    Map<String, _SharedFontPipelineContext> sharedPipelines,
  ) {
    final String? key = plan.sharedFontPipelineKey;
    if (key == null) {
      return;
    }
    final _SharedFontPipelineContext? context = sharedPipelines[key];
    if (context == null) {
      return;
    }
    if (success) {
      context.subsetReady = true;
    } else {
      context.failed = true;
    }
  }

  Future<void> _cleanupTaskWorkingDirectory(
    TaskPlan plan,
    Map<String, _SharedFontPipelineContext> sharedPipelines,
  ) async {
    for (final _SharedFontPipelineContext context in sharedPipelines.values) {
      if (p.equals(plan.workingDirectory, context.workDir)) {
        return;
      }
    }
    await _controller._deleteOwnedTempDirectory(plan.workingDirectory);
  }

  String _sharedFontPipelineKeyForMedia() {
    return p.normalize(_controller.mediaInfo?.inputPath ?? '');
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

  void clearAllTasks() {
    if (_controller.queueRunning || _controller._activeProcess != null) {
      _controller.tasks.removeWhere(
        (ExportTask task) => task.status != TaskStatus.running,
      );
    } else {
      _controller.tasks.clear();
    }
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
        clearError: true,
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
    required List<CommandStep> steps,
    required Duration expectedDuration,
  }) {
    buffer.writeln(line);
    double? progress;
    if (canTrackProgress) {
      progress = _extractTaskProgress(
        line: line,
        stepIndex: stepIndex,
        steps: steps,
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
    required List<CommandStep> steps,
    required Duration expectedDuration,
  }) {
    if (expectedDuration <= Duration.zero || steps.isEmpty) {
      return null;
    }
    final String trimmed = line.trim();
    int? outTimeUs;
    if (trimmed.startsWith('out_time_us=')) {
      outTimeUs = int.tryParse(trimmed.substring('out_time_us='.length));
    } else if (trimmed.startsWith('out_time_ms=')) {
      outTimeUs = int.tryParse(trimmed.substring('out_time_ms='.length));
    } else if (trimmed == 'progress=end') {
      return _progressAfterStep(steps, stepIndex);
    }
    if (outTimeUs == null) {
      return null;
    }
    final double stepProgress = (outTimeUs / expectedDuration.inMicroseconds)
        .clamp(0, 1)
        .toDouble();
    final double start = _progressBeforeStep(steps, stepIndex);
    final double end = _progressAfterStep(steps, stepIndex);
    return (start + (end - start) * stepProgress).clamp(0, 1).toDouble();
  }

  double _progressBeforeStep(List<CommandStep> steps, int stepIndex) {
    return _progressForCompletedSteps(steps, stepIndex);
  }

  double _progressAfterStep(List<CommandStep> steps, int stepIndex) {
    return _progressForCompletedSteps(steps, stepIndex + 1);
  }

  double _progressForCompletedSteps(List<CommandStep> steps, int completed) {
    if (steps.isEmpty) {
      return 0;
    }
    final int ffmpegIndex = steps.indexWhere(_isFfmpegProgressStep);
    if (ffmpegIndex == -1) {
      return (completed / steps.length).clamp(0, 1).toDouble();
    }
    final int preCount = ffmpegIndex;
    final int postCount = steps.length - ffmpegIndex - 1;
    if (completed <= ffmpegIndex) {
      return preCount == 0 ? 0 : (completed / preCount) * 0.1;
    }
    if (completed == ffmpegIndex + 1) {
      return 0.9;
    }
    final int completedPost = completed - ffmpegIndex - 1;
    return 0.9 + (postCount == 0 ? 0.1 : (completedPost / postCount) * 0.1);
  }

  bool _isFfmpegProgressStep(CommandStep step) {
    return step.fontSubsetStep == null &&
        p.basename(step.executable).toLowerCase() == 'ffmpeg.exe';
  }

  bool _isToneMappingExecutionFailure(String line) {
    return line.contains('Cannot find a matching filter') ||
        line.contains('zscale: command not found');
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
