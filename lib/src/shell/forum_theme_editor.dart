import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/forum_theme.dart';
import '../models/forum_theme_presets.dart';

class ForumThemeEditor extends StatefulWidget {
  const ForumThemeEditor({
    super.key,
    required this.initialTheme,
    required this.customThemes,
    required this.onChanged,
    required this.onSave,
    this.enabled = true,
  });

  final ForumTheme initialTheme;
  final List<ForumTheme> customThemes;
  final ValueChanged<ForumTheme> onChanged;
  final Future<void> Function(ForumTheme) onSave;
  final bool enabled;

  @override
  State<ForumThemeEditor> createState() => _ForumThemeEditorState();
}

class _ForumThemeEditorState extends State<ForumThemeEditor> {
  static const _roles = {
    'secondary': 'Background',
    'primary': 'Text',
    'tertiary': 'Accent',
    'quaternary': 'Highlight',
    'success': 'Success',
    'danger': 'Attention',
    'love': 'Reactions',
  };
  late String _id;
  late final TextEditingController _name;
  late final Map<String, TextEditingController> _colors;
  late Brightness _brightness;
  String? _notice;

  String _newId() => 'custom-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    final theme = widget.initialTheme;
    _id = theme.id.startsWith('custom-') ? theme.id : _newId();
    _name = TextEditingController(
      text: theme.id.startsWith('custom-')
          ? theme.name
          : '${theme.name} custom',
    );
    _brightness = theme.brightness;
    final colors = theme.toJson()['colors'] as Map<String, String>;
    _colors = {
      for (final key in _roles.keys)
        key: TextEditingController(text: colors[key]),
    };
  }

  @override
  void dispose() {
    _name.dispose();
    for (final controller in _colors.values) {
      controller.dispose();
    }
    super.dispose();
  }

  ForumTheme? get _theme {
    try {
      return ForumTheme.fromJson({
        'version': 1,
        'name': _name.text,
        'mode': _brightness.name,
        'colors': {
          for (final entry in _colors.entries) entry.key: entry.value.text,
        },
      }, id: _id);
    } on FormatException {
      return null;
    }
  }

  void _changed(String _) {
    setState(() => _notice = null);
    final theme = _theme;
    if (theme != null) widget.onChanged(theme);
  }

  void _usePalette(ForumTheme theme, {bool imported = false}) {
    if (imported) {
      _id = _newId();
      _name.text = theme.name;
    }
    _brightness = theme.brightness;
    final colors = theme.toJson()['colors'] as Map<String, String>;
    for (final entry in _colors.entries) {
      entry.value.text = colors[entry.key]!;
    }
    _changed('');
  }

  Future<void> _import() async {
    final theme = await showDDialog<ForumTheme>(
      context: context,
      builder: (_, controller) =>
          _ImportThemeDialog(onImport: controller.close),
    );
    if (theme != null && mounted) _usePalette(theme, imported: true);
  }

  Future<void> _export() async {
    final theme = _theme;
    if (theme == null) return;
    try {
      await Clipboard.setData(
        ClipboardData(
          text: const JsonEncoder.withIndent('  ').convert(theme.toJson()),
        ),
      );
      if (mounted) setState(() => _notice = 'Theme copied.');
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not copy theme.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    final valid = theme != null;
    final presets = [...forumThemePresets, ...widget.customThemes];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.md,
      children: [
        DInput(
          key: const ValueKey('custom-theme-name'),
          labelText: 'Name',
          controller: _name,
          maxLength: 48,
          enabled: widget.enabled,
          errorText: _name.text.trim().isEmpty ? 'Enter a name.' : null,
          onChanged: _changed,
        ),
        DSelect<String>(
          semanticLabel: 'Start from',
          initialValue: presets.any((p) => p.id == widget.initialTheme.id)
              ? widget.initialTheme.id
              : null,
          label: const Text('Start from'),
          isExpanded: true,
          entries: [
            for (final preset in presets)
              DSelectOption(
                value: preset.id,
                label: preset.name,
                child: Text(preset.name),
              ),
          ],
          onChanged: widget.enabled
              ? (id) {
                  if (id != null) {
                    _usePalette(presets.firstWhere((p) => p.id == id));
                  }
                }
              : null,
        ),
        DSelect<Brightness>.controlled(
          semanticLabel: 'Palette mode',
          label: const Text('Palette mode'),
          value: _brightness,
          isExpanded: true,
          entries: const [
            DSelectOption(
              value: Brightness.light,
              label: 'Light',
              child: Text('Light'),
            ),
            DSelectOption(
              value: Brightness.dark,
              label: 'Dark',
              child: Text('Dark'),
            ),
          ],
          onChanged: widget.enabled
              ? (value) {
                  if (value != null && value != _brightness) {
                    final background = _colors['secondary']!.text;
                    _colors['secondary']!.text = _colors['primary']!.text;
                    _colors['primary']!.text = background;
                    _brightness = value;
                    _changed('');
                  }
                }
              : null,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >= 300 &&
                    MediaQuery.textScalerOf(context).scale(14) < 21
                ? 2
                : 1;
            return Wrap(
              spacing: DSpacing.md,
              runSpacing: DSpacing.md,
              children: [
                for (final entry in _colors.entries)
                  SizedBox(
                    width:
                        (constraints.maxWidth - DSpacing.md * (columns - 1)) /
                        columns,
                    child: DInput(
                      key: ValueKey('custom-theme-${entry.key}'),
                      controller: entry.value,
                      labelText: _roles[entry.key],
                      semanticLabel: '${_roles[entry.key]} color',
                      prefix:
                          RegExp(
                            r'^#[a-fA-F0-9]{6}$',
                          ).hasMatch(entry.value.text)
                          ? SizedBox.square(
                              dimension: 16,
                              child: ColoredBox(
                                color: Color(
                                  0xff000000 |
                                      int.parse(
                                        entry.value.text.substring(1),
                                        radix: 16,
                                      ),
                                ),
                              ),
                            )
                          : null,
                      textDirection: TextDirection.ltr,
                      enabled: widget.enabled,
                      autocorrect: false,
                      maxLength: 7,
                      errorText:
                          RegExp(
                            r'^#[a-fA-F0-9]{6}$',
                          ).hasMatch(entry.value.text)
                          ? null
                          : 'Use #RRGGBB.',
                      onChanged: _changed,
                    ),
                  ),
              ],
            );
          },
        ),
        if (theme != null && _contrast(theme) < 4.5)
          const DAlert(
            description: DAlertDescription(
              child: Text('Text contrast is below 4.5:1.'),
            ),
          ),
        Wrap(
          spacing: DSpacing.sm,
          runSpacing: DSpacing.sm,
          children: [
            DButton(
              label: const Text('Import'),
              onPressed: widget.enabled ? _import : null,
            ),
            DButton(
              label: const Text('Copy theme'),
              onPressed: widget.enabled && valid ? _export : null,
            ),
            DButton(
              key: const ValueKey('save-custom-theme'),
              variant: DButtonVariant.primary,
              label: const Text('Save theme'),
              onPressed: widget.enabled && valid
                  ? () => widget.onSave(theme)
                  : null,
            ),
          ],
        ),
        if (_notice != null)
          Text(_notice!, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  double _contrast(ForumTheme theme) {
    final a = theme.primary.computeLuminance();
    final b = theme.secondary.computeLuminance();
    return ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05);
  }
}

class _ImportThemeDialog extends StatefulWidget {
  const _ImportThemeDialog({required this.onImport});
  final ValueChanged<ForumTheme> onImport;
  @override
  State<_ImportThemeDialog> createState() => _ImportThemeDialogState();
}

class _ImportThemeDialogState extends State<_ImportThemeDialog> {
  final _json = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DDialogContent(
    maxWidth: 480,
    semanticLabel: 'Import theme',
    children: [
      const DDialogTitle(child: Text('Import theme')),
      DTextarea(
        key: const ValueKey('import-theme-json'),
        controller: _json,
        semanticLabel: 'Theme JSON',
        hintText: 'Paste theme JSON',
        minLines: 5,
        maxLines: 8,
        maxLength: 16000,
        errorText: _error,
      ),
      DDialogFooter(
        children: [
          DButton(
            key: const ValueKey('confirm-import-theme'),
            label: const Text('Import'),
            onPressed: () {
              try {
                final value = jsonDecode(_json.text);
                if (value is! Map<String, dynamic>) {
                  throw const FormatException();
                }
                widget.onImport(ForumTheme.fromJson(value, id: 'import'));
              } catch (_) {
                setState(() => _error = 'Paste a valid exported theme.');
              }
            },
          ),
        ],
      ),
    ],
  );
}
