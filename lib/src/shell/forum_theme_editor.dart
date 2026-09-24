import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/forum_background.dart';
import '../models/forum_theme.dart';
import 'settings_section.dart';
import 'theme_icons.dart';

/// Edits a draft of one of the user's own themes. The app shows the draft as
/// it changes, and nothing is stored until Save. Light and dark keep separate
/// palettes and share one window background.
class ForumThemeEditor extends StatefulWidget {
  const ForumThemeEditor({
    super.key,
    required this.theme,
    required this.brightness,
    required this.onBrightnessChanged,
    required this.sources,
    required this.onChanged,
    required this.onSave,
    required this.onCancel,
  });

  /// The theme as it was saved, or the starting point of a new one.
  final ForumTheme theme;

  /// The mode whose colours are edited, and the app shows.
  final Brightness brightness;
  final ValueChanged<Brightness> onBrightnessChanged;

  /// The Theme section's choice of source, shown above the draft.
  final Widget sources;

  /// The draft after each change to how it looks.
  final ValueChanged<ForumTheme> onChanged;
  final Future<void> Function(ForumTheme) onSave;
  final VoidCallback onCancel;

  @override
  State<ForumThemeEditor> createState() => _ForumThemeEditorState();
}

class _ForumThemeEditorState extends State<ForumThemeEditor> {
  late final _name = TextEditingController(text: widget.theme.name);
  late final _palettes = {
    for (final mode in Brightness.values)
      mode: widget.theme.forBrightness(mode),
  };
  late var _background = _editable(
    widget.theme.background ?? widget.theme.alternate?.background,
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Older shared themes chose their own tint colour; this editor's tint is
  /// the accent, at the strength the old tint reached.
  static ForumBackground _editable(ForumBackground? background) {
    if (background == null) return const ForumBackground.appearance();
    if (background.useAccentTint) return background;
    return ForumBackground.appearance(
      strength: (background.strength * .45 / .22).clamp(0, 1),
      effect: background.effect,
      noiseIntensity: background.noiseIntensity,
      transparency: background.transparency,
    );
  }

  ForumTheme get _palette => _palettes[widget.brightness]!;

  set _palette(ForumTheme value) {
    setState(() => _palettes[widget.brightness] = value);
    widget.onChanged(_theme(widget.theme.name));
  }

  void _changeBackground(ForumBackground value) {
    setState(() => _background = value);
    widget.onChanged(_theme(widget.theme.name));
  }

  ForumTheme _theme(String name) {
    Map<String, dynamic> part(Brightness mode) => {
      ..._palettes[mode]!.toJson(),
      'name': name,
      'background': _background.toJson(),
    };
    return ForumTheme.fromJson({
      ...part(Brightness.light),
      'alternate': part(Brightness.dark),
    }, id: widget.theme.id);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (_saving || name.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_theme(name));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save theme. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final background = _background;
    final textureEnabled = background.effect != ForumBackgroundEffect.normal;
    final tokens = DTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 18,
      children: [
        SettingsSection(
          title: 'Theme',
          icon: const ThemeIcon(ThemeIcons.preset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              widget.sources,
              DInput(
                key: const ValueKey('theme-name'),
                controller: _name,
                labelText: 'Name',
                maxLength: 48,
                readOnly: _saving,
                onChanged: (_) => setState(() {}),
              ),
            ],
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
                onChanged: (v) =>
                    _changeBackground(background.copyWith(strength: v)),
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
                onChanged: (v) => _changeBackground(
                  background.copyWith(transparency: (1 - v) * .3),
                ),
              ),
            ],
          ),
        ),
        DSwitchTile(
          key: const ValueKey('custom-theme-darker-sidebars'),
          title: const Text('Darker sidebars'),
          size: DSwitchSize.preference,
          value: palette.darkerSidebars,
          onChanged: (value) =>
              _palette = palette.copyWith(darkerSidebars: value),
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
                onChanged: (values) => _changeBackground(
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
                    ? (v) => _changeBackground(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              DTabs<Brightness>.controlled(
                key: const ValueKey('appearance-theme-select'),
                value: widget.brightness,
                onActivated: widget.onBrightnessChanged,
                children: const [
                  DTabList<Brightness>(
                    variant: DTabListVariant.line,
                    children: [
                      DTabTrigger(
                        value: Brightness.light,
                        child: Text('Light'),
                      ),
                      DTabTrigger(value: Brightness.dark, child: Text('Dark')),
                    ],
                  ),
                ],
              ),
              LayoutBuilder(
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
                      (c) => _palette = palette.copyWith(secondary: c),
                    ),
                    (
                      'Text',
                      palette.primary,
                      (c) => _palette = palette.copyWith(primary: c),
                    ),
                    (
                      'Accent',
                      palette.tertiary,
                      (c) => _palette = palette.copyWith(tertiary: c),
                    ),
                    (
                      'Highlight',
                      palette.quaternary,
                      (c) => _palette = palette.copyWith(quaternary: c),
                    ),
                    (
                      'Success',
                      palette.success,
                      (c) => _palette = palette.copyWith(success: c),
                    ),
                    (
                      'Attention',
                      palette.danger,
                      (c) => _palette = palette.copyWith(danger: c),
                    ),
                  ];
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (final field in fields)
                        SizedBox(
                          width:
                              (bounds.maxWidth - 14 * (columns - 1)) / columns,
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
            ],
          ),
        ),
        if (_error case final error?)
          DAlert(
            variant: DAlertVariant.destructive,
            description: DAlertDescription(child: Text(error)),
          ),
        Wrap(
          spacing: DSpacing.controlGap,
          runSpacing: DSpacing.controlGap,
          children: [
            DButton(
              key: const ValueKey('theme-save'),
              label: const Text('Save'),
              loading: _saving,
              loadingSemanticLabel: 'Saving theme',
              onPressed: _name.text.trim().isEmpty ? null : _save,
            ),
            DButton(
              key: const ValueKey('theme-cancel'),
              label: const Text('Cancel'),
              variant: DButtonVariant.outline,
              onPressed: _saving ? null : widget.onCancel,
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
