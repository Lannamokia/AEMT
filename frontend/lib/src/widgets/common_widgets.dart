import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../controller.dart';
import '../models.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
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
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (subtitle.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF667085)),
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
}

class BindingBox extends StatelessWidget {
  const BindingBox({
    super.key,
    required this.controller,
    required this.binding,
    this.onRemove,
  });

  final AemtController controller;
  final SubtitleBinding binding;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final bool isCustom = binding.key.startsWith('custom_');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: softBox(),
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
            binding.filePath == null
                ? '未选择字幕文件'
                : p.basename(binding.filePath!),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: buildField(
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
                child: buildField(
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
                child: buildField(
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
}

Widget buildField(
  String label,
  String value,
  ValueChanged<String> onChanged, {
  required String key,
  String? hintText,
  int maxLines = 1,
  bool enabled = true,
}) {
  return SyncedTextField(
    key: ValueKey<String>(key),
    label: label,
    value: value,
    hintText: hintText,
    maxLines: maxLines,
    enabled: enabled,
    onChanged: onChanged,
  );
}

class SyncedTextField extends StatefulWidget {
  const SyncedTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hintText,
    this.maxLines = 1,
    this.enabled = true,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final int maxLines;
  final bool enabled;

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus || _textController.text == widget.value) {
      return;
    }
    _textController.value = TextEditingValue(
      text: widget.value,
      selection: TextSelection.collapsed(offset: widget.value.length),
    );
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _textController.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    final String value = _textController.text;
    if (value != widget.value) {
      widget.onChanged(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _textController,
      focusNode: _focusNode,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
      ),
      enabled: widget.enabled,
      maxLines: widget.maxLines,
      onFieldSubmitted: (_) => _commit(),
    );
  }
}

class EpisodicNamingTemplateEditor extends StatefulWidget {
  const EpisodicNamingTemplateEditor({super.key, required this.controller});

  final AemtController controller;

  @override
  State<EpisodicNamingTemplateEditor> createState() =>
      _EpisodicNamingTemplateEditorState();
}

class _EpisodicNamingTemplateEditorState
    extends State<EpisodicNamingTemplateEditor> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.controller.episodicNamingTemplate,
    );
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant EpisodicNamingTemplateEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String nextValue = widget.controller.episodicNamingTemplate;
    if (_focusNode.hasFocus || _textController.text == nextValue) {
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
    _focusNode.removeListener(_handleFocusChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    final String value = _textController.text;
    if (value != widget.controller.episodicNamingTemplate) {
      widget.controller.setEpisodicNamingTemplate(value);
    }
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
          onFieldSubmitted: (_) => _commit(),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: softBox(),
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

Widget toolChip(RuntimeToolInfo tool) {
  return statusChip(
    label: tool.name,
    status: tool.available ? '已就绪' : '未找到',
    ok: tool.available,
  );
}

Widget statusChip({
  required String label,
  required String status,
  required bool ok,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: ok ? const Color(0xFFE8F3EB) : const Color(0xFFFDECEC),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text('$label: $status'),
  );
}

Widget modeChip(String label, bool selected, VoidCallback? onTap) {
  return ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: onTap == null ? null : (_) => onTap(),
  );
}

BoxDecoration softBox() {
  return BoxDecoration(
    color: const Color(0xFFF7F9FD),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: const Color(0xFFD7E0EE)),
  );
}
