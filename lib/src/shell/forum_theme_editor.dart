import 'dart:convert';
import 'dart:math';

import 'package:discourse_native/discourse_ui.dart';
import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart' as sharing;

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
  bool _transferring = false;
  static const _jsonTypes = [
    selector.XTypeGroup(
      label: 'JSON theme',
      extensions: ['json'],
      mimeTypes: ['application/json'],
      uniformTypeIdentifiers: ['public.json'],
    ),
  ];
  String? _baseId;
  final _random = Random();

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
    _baseId = theme.id;
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
    _baseId = imported ? null : theme.id;
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

  void _surprise() {
    final base = forumThemePresets[_random.nextInt(forumThemePresets.length)];
    final accents = ['#47798B', '#9772A5', '#C28B45', '#4E8E7D', '#AB6674']
        .where((color) => color != _colors['tertiary']!.text.toUpperCase())
        .toList();
    _baseId = base.id;
    _brightness = base.brightness;
    final colors = base.toJson()['colors'] as Map<String, String>;
    for (final entry in _colors.entries) {
      entry.value.text = colors[entry.key]!;
    }
    _colors['tertiary']!.text = accents[_random.nextInt(accents.length)];
    _changed('');
  }

  Future<void> _import() async {
    setState(() {
      _transferring = true;
      _notice = null;
    });
    try {
      final file = await selector.openFile(acceptedTypeGroups: _jsonTypes);
      if (file == null || !mounted) return;
      if (await file.length() > 65536) throw const FormatException();
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, dynamic>) throw const FormatException();
      final theme = ForumTheme.fromJson(value, id: 'import');
      if (mounted) _usePalette(theme, imported: true);
    } on FormatException {
      if (mounted) setState(() => _notice = 'Choose a valid theme JSON file.');
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not read theme file.');
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _export() async {
    final theme = _theme;
    if (theme == null) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    final stem = theme.name
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final filename = '${stem.isEmpty ? 'theme' : stem}.json';
    final bytes = Uint8List.fromList(
      utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert(theme.toJson())}\n',
      ),
    );
    setState(() {
      _transferring = true;
      _notice = null;
    });
    try {
      if (!kIsWeb &&
          {
            TargetPlatform.macOS,
            TargetPlatform.windows,
            TargetPlatform.linux,
          }.contains(defaultTargetPlatform)) {
        final location = await selector.getSaveLocation(
          suggestedName: filename,
          acceptedTypeGroups: _jsonTypes,
        );
        if (location == null || !mounted) return;
        await selector.XFile.fromData(
          bytes,
          name: filename,
          mimeType: 'application/json',
        ).saveTo(location.path);
        if (mounted) setState(() => _notice = 'Theme exported.');
      } else {
        await sharing.SharePlus.instance.share(
          sharing.ShareParams(
            files: [
              sharing.XFile.fromData(
                bytes,
                name: filename,
                mimeType: 'application/json',
              ),
            ],
            fileNameOverrides: [filename],
            sharePositionOrigin: origin,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not export theme.');
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    final valid = theme != null;
    final enabled = widget.enabled && !_transferring;
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
          enabled: enabled,
          errorText: _name.text.trim().isEmpty ? 'Enter a name.' : null,
          onChanged: _changed,
        ),
        DSelect<String>.controlled(
          semanticLabel: 'Start from',
          value: presets.any((p) => p.id == _baseId) ? _baseId : null,
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
          onChanged: enabled
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
          onChanged: enabled
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
                      enabled: enabled,
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
          spacing: DSpacing.controlGap,
          runSpacing: DSpacing.sm,
          children: [
            DButton(
              label: const Text('Import'),
              onPressed: enabled ? _import : null,
            ),
            DButton(
              label: const Text('Export'),
              onPressed: enabled && valid ? _export : null,
            ),
            DButton(
              label: const Text('Surprise me'),
              onPressed: enabled ? _surprise : null,
            ),
            DButton(
              key: const ValueKey('save-custom-theme'),
              variant: DButtonVariant.primary,
              label: const Text('Save theme'),
              onPressed: enabled && valid ? () => widget.onSave(theme) : null,
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
