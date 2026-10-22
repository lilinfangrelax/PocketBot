import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Replaces the system-browser launch in tests.
@visibleForTesting
Future<bool> Function(Uri uri)? elicitationUrlLauncherOverride;

/// Shows the ACP `elicitation/create` prompt and returns the JSON-RPC result.
Future<Map<String, dynamic>> showElicitationDialog(
  BuildContext context,
  Map<String, dynamic> params,
) async {
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => params['mode'] == 'url'
        ? _UrlElicitationDialog(params: params)
        : _FormElicitationDialog(params: params),
  );
  return result ?? <String, dynamic>{'action': 'cancel'};
}

Map<String, dynamic> _asMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

class _Choice {
  const _Choice(this.value, this.label, [this.description]);

  final String value;
  final String label;
  final String? description;
}

List<_Choice> _choicesFor(Map<String, dynamic> schema) {
  final enumValues = schema['enum'];
  if (enumValues is List) {
    return [
      for (final value in enumValues)
        if (value != null) _Choice('$value', '$value'),
    ];
  }
  final variants = schema['oneOf'] ?? schema['anyOf'];
  if (variants is List) {
    return [
      for (final variant in variants.map(_asMap))
        if (variant.containsKey('const'))
          _Choice(
            '${variant['const']}',
            (variant['title'] as String?)?.trim().isNotEmpty == true
                ? variant['title'] as String
                : '${variant['const']}',
            variant['description'] as String?,
          ),
    ];
  }
  return const [];
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return value == null ? null : int.tryParse('$value');
}

num? _asNum(dynamic value) {
  if (value is num) return value;
  return value == null ? null : num.tryParse('$value');
}

class _FormElicitationDialog extends StatefulWidget {
  const _FormElicitationDialog({required this.params});

  final Map<String, dynamic> params;

  @override
  State<_FormElicitationDialog> createState() => _FormElicitationDialogState();
}

class _FormElicitationDialogState extends State<_FormElicitationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _textControllers = <String, TextEditingController>{};
  final _numberControllers = <String, TextEditingController>{};
  final _choiceValues = <String, String?>{};
  final _arrayValues = <String, Set<String>>{};
  final _boolValues = <String, bool>{};
  final _arrayErrors = <String, String>{};
  final _properties = <String, dynamic>{};
  final _required = <String>{};

  @override
  void initState() {
    super.initState();
    final schema = _asMap(widget.params['requestedSchema']);
    _properties.addAll(_asMap(schema['properties']));
    _required.addAll(
      (schema['required'] as List? ?? const []).map((item) => '$item'),
    );

    for (final entry in _properties.entries) {
      final property = _asMap(entry.value);
      final type = property['type'] as String? ?? 'string';
      final defaultValue = property['default'];
      if (type == 'boolean') {
        _boolValues[entry.key] = defaultValue == true;
      } else if (type == 'array') {
        _arrayValues[entry.key] = {
          for (final item in defaultValue as List? ?? const []) '$item',
        };
      } else if (_choicesFor(property).isNotEmpty) {
        final initial = defaultValue == null ? null : '$defaultValue';
        final choices = _choicesFor(property);
        _choiceValues[entry.key] =
            choices.any((choice) => choice.value == initial) ? initial : null;
      } else if (type == 'number' || type == 'integer') {
        _numberControllers[entry.key] = TextEditingController(
          text: defaultValue == null ? '' : '$defaultValue',
        );
      } else {
        _textControllers[entry.key] = TextEditingController(
          text: defaultValue is String ? defaultValue : '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    for (final controller in _numberControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _labelFor(String key, Map<String, dynamic> property) {
    final title = (property['title'] as String?)?.trim() ?? '';
    final label = title.isEmpty ? key : title;
    return _required.contains(key) ? '$label *' : label;
  }

  String? _helperFor(Map<String, dynamic> property) {
    final description = (property['description'] as String?)?.trim() ?? '';
    return description.isEmpty ? null : description;
  }

  @override
  Widget build(BuildContext context) {
    final message = (widget.params['message'] as String?)?.trim() ?? '';
    return AlertDialog(
      title: const Text('需要你的输入'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(message),
                  ),
                for (final entry in _properties.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildField(entry.key, _asMap(entry.value)),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, {'action': 'cancel'}),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, {'action': 'decline'}),
          child: const Text('拒绝'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('提交'),
        ),
      ],
    );
  }

  Widget _buildField(String key, Map<String, dynamic> property) {
    final type = property['type'] as String? ?? 'string';
    final label = _labelFor(key, property);
    final helper = _helperFor(property);
    final required = _required.contains(key);

    if (type == 'boolean') {
      return SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: helper == null ? null : Text(helper),
        value: _boolValues[key] ?? false,
        onChanged: (value) => setState(() => _boolValues[key] = value),
      );
    }

    if (type == 'array') {
      return _buildArrayField(key, property, label, helper, required);
    }

    final choices = _choicesFor(property);
    if (choices.isNotEmpty) {
      return DropdownButtonFormField<String>(
        initialValue: _choiceValues[key],
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
        ),
        items: [
          for (final choice in choices)
            DropdownMenuItem(
              value: choice.value,
              child: Text(choice.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) => _choiceValues[key] = value,
        validator: (value) {
          if (required && (value == null || value.isEmpty)) {
            return '请选择${property['title'] ?? key}';
          }
          return null;
        },
      );
    }

    if (type == 'number' || type == 'integer') {
      final isInteger = type == 'integer';
      return TextFormField(
        controller: _numberControllers[key],
        keyboardType: TextInputType.numberWithOptions(
          decimal: !isInteger,
          signed: true,
        ),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
        ),
        validator: (raw) => _validateNumber(
          key,
          property,
          raw ?? '',
          isInteger: isInteger,
          required: required,
        ),
      );
    }

    final format = property['format'] as String? ?? '';
    return TextFormField(
      controller: _textControllers[key],
      keyboardType: switch (format) {
        'email' => TextInputType.emailAddress,
        'uri' => TextInputType.url,
        _ => TextInputType.text,
      },
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
      ),
      validator: (raw) =>
          _validateString(key, property, raw ?? '', required: required),
    );
  }

  Widget _buildArrayField(
    String key,
    Map<String, dynamic> property,
    String label,
    String? helper,
    bool required,
  ) {
    final choices = _choicesFor(_asMap(property['items']));
    final selected = _arrayValues.putIfAbsent(key, () => <String>{});
    final error = _arrayErrors[key];
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              helper,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (choices.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '不支持的数组字段',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        for (final choice in choices)
          CheckboxListTile(
            value: selected.contains(choice.value),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(choice.label),
            subtitle: choice.description == null
                ? null
                : Text(choice.description as String),
            onChanged: (checked) {
              setState(() {
                if (checked == true) {
                  selected.add(choice.value);
                } else {
                  selected.remove(choice.value);
                }
                _arrayValues[key] = selected;
                _arrayErrors.remove(key);
              });
            },
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  String? _validateString(
    String key,
    Map<String, dynamic> property,
    String raw, {
    required bool required,
  }) {
    final text = raw.trim();
    if (text.isEmpty) {
      return required ? '请输入${property['title'] ?? key}' : null;
    }
    final label = property['title'] ?? key;
    final minLength = _asInt(property['minLength']);
    final maxLength = _asInt(property['maxLength']);
    if (minLength != null && text.runes.length < minLength) {
      return '$label至少需要$minLength个字符';
    }
    if (maxLength != null && text.runes.length > maxLength) {
      return '$label不能超过$maxLength个字符';
    }
    final pattern = property['pattern'] as String?;
    if (pattern != null && pattern.isNotEmpty) {
      try {
        if (!RegExp(pattern).hasMatch(text)) return '$label格式不正确';
      } on FormatException {
        // An invalid agent-provided pattern must not block the whole form.
      }
    }
    if (property['format'] == 'email' &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
      return '请输入有效的邮箱地址';
    }
    if (property['format'] == 'uri') {
      final uri = Uri.tryParse(text);
      if (uri == null || !uri.hasScheme) return '请输入有效的链接';
    }
    return null;
  }

  String? _validateNumber(
    String key,
    Map<String, dynamic> property,
    String raw, {
    required bool isInteger,
    required bool required,
  }) {
    final text = raw.trim();
    if (text.isEmpty) {
      return required ? '请输入${property['title'] ?? key}' : null;
    }
    final value =
        isInteger ? int.tryParse(text)?.toDouble() : double.tryParse(text);
    if (value == null) return isInteger ? '请输入整数' : '请输入数字';
    final label = property['title'] ?? key;
    final minimum = _asNum(property['minimum']);
    final maximum = _asNum(property['maximum']);
    if (minimum != null && value < minimum) {
      return '$label不能小于$minimum';
    }
    if (maximum != null && value > maximum) {
      return '$label不能大于$maximum';
    }
    return null;
  }

  Map<String, dynamic> _collectContent() {
    final content = <String, dynamic>{};
    for (final entry in _properties.entries) {
      final key = entry.key;
      final property = _asMap(entry.value);
      final type = property['type'] as String? ?? 'string';
      if (type == 'boolean') {
        content[key] = _boolValues[key] ?? false;
        continue;
      }
      if (type == 'array') {
        if ((_arrayValues[key] ?? const {}).isNotEmpty) {
          final selected = _arrayValues[key]!;
          content[key] = [
            for (final choice in _choicesFor(_asMap(property['items'])))
              if (selected.contains(choice.value)) choice.value,
          ];
        }
        continue;
      }
      final choices = _choicesFor(property);
      if (choices.isNotEmpty) {
        final value = _choiceValues[key];
        if (value != null && value.isNotEmpty) content[key] = value;
        continue;
      }
      if (type == 'number' || type == 'integer') {
        final text = _numberControllers[key]?.text.trim() ?? '';
        if (text.isEmpty) continue;
        content[key] =
            type == 'integer' ? int.tryParse(text) : double.tryParse(text);
        continue;
      }
      final text = _textControllers[key]?.text ?? '';
      if (text.trim().isNotEmpty) content[key] = text;
    }
    return content;
  }

  Map<String, String> _validateArrays() {
    final errors = <String, String>{};
    for (final entry in _properties.entries) {
      final property = _asMap(entry.value);
      if (property['type'] != 'array') continue;
      final key = entry.key;
      final selected = _arrayValues[key] ?? const <String>{};
      final label = property['title'] ?? key;
      final minItems = _asInt(property['minItems']);
      final maxItems = _asInt(property['maxItems']);
      if (_required.contains(key) && selected.isEmpty) {
        errors[key] = '请选择$label';
      } else if (selected.isNotEmpty &&
          minItems != null &&
          selected.length < minItems) {
        errors[key] = '$label至少选择$minItems项';
      } else if (maxItems != null && selected.length > maxItems) {
        errors[key] = '$label最多选择$maxItems项';
      }
    }
    return errors;
  }

  void _submit() {
    final formValid = _formKey.currentState?.validate() ?? false;
    final arrayErrors = _validateArrays();
    setState(() {
      _arrayErrors
        ..clear()
        ..addAll(arrayErrors);
    });
    if (!formValid || arrayErrors.isNotEmpty) return;
    Navigator.pop(context, {
      'action': 'accept',
      'content': _collectContent(),
    });
  }
}

class _UrlElicitationDialog extends StatefulWidget {
  const _UrlElicitationDialog({required this.params});

  final Map<String, dynamic> params;

  @override
  State<_UrlElicitationDialog> createState() => _UrlElicitationDialogState();
}

class _UrlElicitationDialogState extends State<_UrlElicitationDialog> {
  bool _opening = false;
  String? _error;

  Uri? get _uri => Uri.tryParse(
        (widget.params['url'] as String?)?.trim() ?? '',
      );

  bool get _canOpen {
    final uri = _uri;
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  Future<void> _open() async {
    final uri = _uri;
    if (uri == null || !_canOpen) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    var opened = false;
    try {
      final launcher = elicitationUrlLauncherOverride ??
          (Uri value) => launchUrl(value, mode: LaunchMode.externalApplication);
      opened = await launcher(uri);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    if (opened) {
      Navigator.pop(context, {'action': 'accept'});
      return;
    }
    setState(() {
      _opening = false;
      _error = '无法打开链接，请检查系统浏览器设置';
    });
  }

  @override
  Widget build(BuildContext context) {
    final message = (widget.params['message'] as String?)?.trim() ?? '';
    final rawUrl = (widget.params['url'] as String?)?.trim() ?? '';
    final uri = _uri;
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('需要你的授权'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(message),
                ),
              Text(
                uri == null || !_canOpen ? '目标网站：无效链接' : '目标网站：${uri.host}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  rawUrl,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'PocketBot 会在系统浏览器中打开该链接，不会读取页面内容。'
                '请确认链接与 Agent 请求的操作一致。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _opening
              ? null
              : () => Navigator.pop(context, {'action': 'cancel'}),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _opening
              ? null
              : () => Navigator.pop(context, {'action': 'decline'}),
          child: const Text('拒绝'),
        ),
        FilledButton(
          onPressed: _opening || !_canOpen ? null : _open,
          child: _opening
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('打开链接'),
        ),
      ],
    );
  }
}
