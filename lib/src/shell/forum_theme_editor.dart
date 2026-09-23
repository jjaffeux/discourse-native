import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/forum_background.dart';
import '../models/forum_theme.dart';
import 'forum_theme_clipboard.dart';
import 'forum_theme_picker.dart';
import 'forum_theme_save_dialog.dart';
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
    required this.onSave,
    required this.onBackgroundChanged,
    required this.onBrightnessChanged,
    this.onDelete,
    this.forumPalettes = const {},
  });

  final Map<Brightness, ForumTheme> palettes;
  final ForumBackground background;
  final Brightness brightness;
  final List<ForumTheme> customThemes;
  final Map<Brightness, ForumTheme> forumPalettes;
  final ValueChanged<ForumTheme> onChanged;
  final Future<void> Function(ForumTheme) onSave;
  final ValueChanged<ForumBackground> onBackgroundChanged;
  final ValueChanged<Brightness> onBrightnessChanged;
  final ValueChanged<String>? onDelete;

  @override
  State<ForumThemeEditor> createState() => _ForumThemeEditorState();
}

class _ForumThemeEditorState extends State<ForumThemeEditor> {
  ForumTheme get _palette => widget.palettes[widget.brightness]!;

  ForumTheme _portable(String name) => ForumTheme.fromJson({
    ...widget.palettes[Brightness.light]!.toJson(),
    'name': name,
    'background': widget.background.toJson(),
    'alternate': {
      ...widget.palettes[Brightness.dark]!.toJson(),
      'name': name,
      'background': widget.background.toJson(),
    },
  }, id: 'custom-${DateTime.now().microsecondsSinceEpoch}');

  Future<void> _save() async {
    final snapshot = _portable('My theme');
    await showDDialog<void>(
      context: context,
      builder: (context, controller) => ForumThemeSaveDialog(
        controller: controller,
        onSave: (name) => widget.onSave(
          ForumTheme.fromJson({
            ...snapshot.toJson(),
            'name': name,
            'alternate': {...snapshot.alternate!.toJson(), 'name': name},
          }, id: snapshot.id),
        ),
      ),
    );
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
        DSwitchTile(
          key: const ValueKey('custom-theme-darker-sidebars'),
          title: const Text('Darker sidebars'),
          size: DSwitchSize.preference,
          value: palette.darkerSidebars,
          onChanged: (value) =>
              widget.onChanged(palette.copyWith(darkerSidebars: value)),
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
        Wrap(
          spacing: DSpacing.controlGap,
          runSpacing: DSpacing.controlGap,
          children: [
            DButton(label: const Text('Save theme'), onPressed: _save),
            DButton(
              label: const Text('Copy theme'),
              variant: DButtonVariant.outline,
              onPressed: () => copyForumTheme(context, _portable('My theme')),
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
