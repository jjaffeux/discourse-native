import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart' as sharing;

import '../models/forum_background.dart';
import '../models/forum_theme.dart';
import 'forum_theme_clipboard.dart';
import 'forum_theme_picker.dart';
import 'settings_section.dart';
import 'theme_icons.dart';

/// Controlled, live theme fields. Light and dark retain separate raw palettes;
/// tint, opacity and texture are shared window preferences.
class ForumThemeEditor extends StatefulWidget {
  const ForumThemeEditor({
    super.key,
    required this.palettes,
    required this.background,
    required this.brightness,
    required this.customThemes,
    required this.onChanged,
    required this.onBackgroundChanged,
    required this.onBrightnessChanged,
    required this.onImport,
    required this.onSave,
    this.onDelete,
    this.forumPalettes = const {},
  });

  final Map<Brightness, ForumTheme> palettes;
  final ForumBackground background;
  final Brightness brightness;
  final List<ForumTheme> customThemes;
  final Map<Brightness, ForumTheme> forumPalettes;
  final ValueChanged<ForumTheme> onChanged;
  final ValueChanged<ForumBackground> onBackgroundChanged;
  final ValueChanged<Brightness> onBrightnessChanged;
  final ValueChanged<ForumTheme> onImport;
  final Future<void> Function(ForumTheme) onSave;
  final ValueChanged<String>? onDelete;

  @override
  State<ForumThemeEditor> createState() => _ForumThemeEditorState();
}

class _ForumThemeEditorState extends State<ForumThemeEditor> {
  final _name = TextEditingController(text: 'My theme');
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
  ForumTheme get _palette => widget.palettes[widget.brightness]!;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ForumTheme get _portable => ForumTheme.fromJson({
    ...widget.palettes[Brightness.light]!.toJson(),
    'name': _name.text.trim(),
    'background': widget.background.toJson(),
    'alternate': {
      ...widget.palettes[Brightness.dark]!.toJson(),
      'name': _name.text.trim(),
      'background': widget.background.toJson(),
    },
  }, id: 'custom-${DateTime.now().microsecondsSinceEpoch}');

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
      final theme = ForumTheme.fromJson(
        value,
        id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) return;
      _name.text = theme.name;
      widget.onImport(theme);
    } on FormatException {
      if (mounted) setState(() => _notice = 'Choose a valid theme JSON file.');
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not read theme file.');
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _export() async {
    final theme = _portable;
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
      if (mounted) setState(() => _notice = 'Theme exported.');
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not export theme.');
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _transferring = true;
      _notice = null;
    });
    try {
      await widget.onSave(_portable);
      if (mounted) setState(() => _notice = 'Theme saved.');
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not save theme. Try again.');
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _delete(ForumTheme theme) async {
    final confirmed = await showDAlertDialog<bool>(
      context: context,
      builder: (context, close) => DAlertDialogContent(
        semanticLabel: 'Delete theme',
        children: [
          DAlertDialogHeader(
            title: Text('Delete “${theme.name}”?'),
            description: const Text(
              'This removes the theme from your saved themes. '
              'Your current appearance will stay as it is.',
            ),
          ),
          const DAlertDialogFooter(
            children: [
              DAlertDialogCancel<bool>(label: Text('Cancel'), result: false),
              DAlertDialogAction<bool>(
                label: Text('Delete'),
                result: true,
                variant: DButtonVariant.destructive,
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) widget.onDelete?.call(theme.id);
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final background = widget.background;
    final textureEnabled = background.effect != ForumBackgroundEffect.normal;
    final tokens = DTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 18,
      children: [
        DTabs<Brightness>.controlled(
          key: const ValueKey('appearance-theme-select'),
          value: widget.brightness,
          onActivated: widget.onBrightnessChanged,
          children: const [
            DTabList<Brightness>(
              variant: DTabListVariant.line,
              children: [
                DTabTrigger(value: Brightness.light, child: Text('Light')),
                DTabTrigger(value: Brightness.dark, child: Text('Dark')),
              ],
            ),
          ],
        ),
        SettingsSection(
          title: 'Preset',
          icon: const ThemeIcon(ThemeIcons.preset),
          child: ForumThemePicker(
            key: const ValueKey('theme-preset'),
            palette: palette,
            background: background,
            forumPalette: widget.forumPalettes[widget.brightness],
            customThemes: widget.customThemes,
            onChanged: widget.onChanged,
            onDelete: widget.onDelete == null ? null : _delete,
          ),
        ),
        SettingsSection(
          title: 'Background',
          icon: const ThemeIcon(ThemeIcons.background),
          child: Column(
            spacing: 16,
            children: [
              _RampField(
                label: 'Tint',
                value: background.strength,
                readout: '${(background.strength * 22).round()}%',
                ramp: DSliderRamp(
                  startColor: palette.secondary,
                  endColor: Color.lerp(
                    palette.secondary,
                    palette.tertiary,
                    .22,
                  ),
                ),
                onChanged: (v) => widget.onBackgroundChanged(
                  background.copyWith(strength: v),
                ),
              ),
              _RampField(
                label: 'Opacity',
                value: 1 - background.transparency / .3,
                readout: '${((1 - background.transparency) * 100).round()}%',
                ramp: DSliderRamp(
                  startColor: palette.secondary.withValues(alpha: .7),
                  endColor: palette.secondary,
                  pattern: DSliderRampPattern.checkerboard,
                ),
                onChanged: (v) => widget.onBackgroundChanged(
                  background.copyWith(transparency: (1 - v) * .3),
                ),
              ),
            ],
          ),
        ),
        SettingsSection(
          title: 'Texture',
          icon: const ThemeIcon(ThemeIcons.texture),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              DToggleGroup<ForumBackgroundEffect>(
                key: const ValueKey('theme-texture'),
                values: [background.effect],
                allowEmptySelection: false,
                inset: true,
                expanded: true,
                density: DToggleDensity.tile,
                semanticLabel: 'Texture',
                items: const [
                  DToggleGroupItem(
                    value: ForumBackgroundEffect.normal,
                    icon: ThemeIcon(ThemeIcons.none),
                    child: Text('None'),
                  ),
                  DToggleGroupItem(
                    value: ForumBackgroundEffect.noise,
                    icon: ThemeIcon(ThemeIcons.noise),
                    child: Text('Noise'),
                  ),
                  DToggleGroupItem(
                    value: ForumBackgroundEffect.lava,
                    icon: ThemeIcon(ThemeIcons.lava),
                    child: Text('Lava lamp'),
                  ),
                  DToggleGroupItem(
                    value: ForumBackgroundEffect.gradient,
                    icon: ThemeIcon(ThemeIcons.gradient),
                    child: Text('Gradient'),
                  ),
                ],
                onChanged: (values) => widget.onBackgroundChanged(
                  background.copyWith(effect: values.single),
                ),
              ),
              _RampField(
                label: 'Intensity',
                value: background.noiseIntensity,
                ramp: DSliderRamp(
                  startColor: Color.lerp(tokens.background, Colors.black, .14),
                  pattern: DSliderRampPattern.wave,
                ),
                onChanged: textureEnabled
                    ? (v) => widget.onBackgroundChanged(
                        background.copyWith(noiseIntensity: v),
                      )
                    : null,
              ),
            ],
          ),
        ),
        SettingsSection(
          title: 'Colours',
          icon: const ThemeIcon(ThemeIcons.palette),
          child: LayoutBuilder(
            builder: (context, bounds) {
              final minimum =
                  150 * MediaQuery.textScalerOf(context).scale(13) / 13;
              final columns = ((bounds.maxWidth + 14) / (minimum + 14))
                  .floor()
                  .clamp(1, 3);
              final fields = <(String, Color, ValueChanged<Color>)>[
                (
                  'Background',
                  palette.secondary,
                  (c) => widget.onChanged(palette.copyWith(secondary: c)),
                ),
                (
                  'Text',
                  palette.primary,
                  (c) => widget.onChanged(palette.copyWith(primary: c)),
                ),
                (
                  'Accent',
                  palette.tertiary,
                  (c) => widget.onChanged(palette.copyWith(tertiary: c)),
                ),
                (
                  'Highlight',
                  palette.quaternary,
                  (c) => widget.onChanged(palette.copyWith(quaternary: c)),
                ),
                (
                  'Success',
                  palette.success,
                  (c) => widget.onChanged(palette.copyWith(success: c)),
                ),
                (
                  'Attention',
                  palette.danger,
                  (c) => widget.onChanged(palette.copyWith(danger: c)),
                ),
              ];
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final field in fields)
                    SizedBox(
                      width: (bounds.maxWidth - 14 * (columns - 1)) / columns,
                      child: _ColorField(
                        key: ValueKey((widget.brightness, field.$1)),
                        label: field.$1,
                        color: field.$2,
                        onChanged: field.$3,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        DAccordion<String>(
          children: [
            DAccordionItem<String>(
              value: 'library',
              child: Column(
                children: [
                  const DAccordionTrigger(child: Text('Save and share')),
                  DAccordionContent(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        for (final saved in widget.customThemes)
                          Wrap(
                            spacing: DSpacing.controlGap,
                            runSpacing: DSpacing.controlGap,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(saved.name),
                              DButton(
                                key: ValueKey(('copy-saved-theme', saved.id)),
                                label: const Text('Copy theme'),
                                variant: DButtonVariant.outline,
                                onPressed: () => copyForumTheme(context, saved),
                              ),
                            ],
                          ),
                        DInput(
                          filled: true,
                          key: const ValueKey('theme-name'),
                          labelText: 'Name',
                          controller: _name,
                          maxLength: 48,
                          onChanged: (_) => setState(() {}),
                        ),
                        Wrap(
                          spacing: DSpacing.controlGap,
                          runSpacing: DSpacing.controlGap,
                          children: [
                            DButton(
                              label: const Text('Save theme'),
                              onPressed:
                                  !_transferring && _name.text.trim().isNotEmpty
                                  ? _save
                                  : null,
                            ),
                            DButton(
                              label: const Text('Export'),
                              variant: DButtonVariant.outline,
                              onPressed:
                                  !_transferring && _name.text.trim().isNotEmpty
                                  ? _export
                                  : null,
                            ),
                            DButton(
                              key: const ValueKey('copy-custom-theme'),
                              label: const Text('Copy theme'),
                              variant: DButtonVariant.outline,
                              onPressed:
                                  !_transferring && _name.text.trim().isNotEmpty
                                  ? () => copyForumTheme(context, _portable)
                                  : null,
                            ),
                            DButton(
                              label: const Text('Import'),
                              variant: DButtonVariant.outline,
                              onPressed: !_transferring ? _import : null,
                            ),
                          ],
                        ),
                        if (_notice != null) Text(_notice!),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RampField extends StatelessWidget {
  const _RampField({
    required this.label,
    required this.value,
    required this.ramp,
    required this.onChanged,
    this.readout,
  });
  final String label;
  final double value;
  final DSliderRamp ramp;
  final ValueChanged<double>? onChanged;
  final String? readout;

  @override
  Widget build(BuildContext context) => DField(
    children: [
      Opacity(
        opacity: onChanged == null ? .4 : 1,
        child: Row(
          children: [
            Expanded(child: DFieldLabel(child: Text(label))),
            Text(
              readout ?? '${(value * 100).round()}%',
              style: TextStyle(
                color: DTokens.of(context).mutedForeground,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
      DSlider(
        key: ValueKey('theme-${label.toLowerCase()}'),
        value: value * 100,
        variant: DSliderVariant.ramp,
        ramp: ramp,
        semanticLabel: label,
        semanticFormatterCallback: (_) =>
            readout ?? '${(value * 100).round()}%',
        onChanged: onChanged == null ? null : (v) => onChanged!(v / 100),
      ),
    ],
  );
}

class _ColorField extends StatefulWidget {
  const _ColorField({
    super.key,
    required this.label,
    required this.color,
    required this.onChanged,
  });
  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;
  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  late final _text = TextEditingController(text: ForumTheme.hex(widget.color));
  bool _invalid = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _text.text = ForumTheme.hex(widget.color);
      _invalid = false;
    }
  }

  void _pick(Color color) {
    setState(() {
      _invalid = false;
      _text.text = ForumTheme.hex(color);
    });
    widget.onChanged(color);
  }

  @override
  Widget build(BuildContext context) => DField(
    children: [
      DFieldLabel(child: Text(widget.label)),
      DColorPicker.inline(
        size: DColorPickerSize.compact,
        value: widget.color,
        semanticLabel: '${widget.label} colour palette',
        onChanged: _pick,
      ),
      DInput(
        filled: true,
        key: ValueKey('theme-color-${widget.label.toLowerCase()}'),
        controller: _text,
        semanticLabel: '${widget.label} hex colour',
        prefix: DColorPicker(
          size: DColorPickerSize.compact,
          value: widget.color,
          semanticLabel: 'Choose ${widget.label.toLowerCase()} colour',
          onChanged: _pick,
        ),
        textDirection: TextDirection.ltr,
        autocorrect: false,
        enableSuggestions: false,
        maxLength: 7,
        errorText: _invalid ? 'Use #RRGGBB.' : null,
        onChanged: (value) {
          final parsed = ForumTheme.parseHex(value.trim());
          setState(() => _invalid = parsed == null);
          if (parsed != null) widget.onChanged(parsed);
        },
      ),
    ],
  );
}
