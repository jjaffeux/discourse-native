import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/forum_background.dart';
import '../models/forum_theme.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'forum_appearance_effects.dart';
import 'forum_theme_thumbnail.dart';

/// Edits a draft of one of the user's own themes. The app shows the draft as
/// it changes, and nothing is stored until Save. Light and dark keep separate
/// palettes, each with its sidebar tone, tint, and window effects.
class ForumThemeEditor extends StatefulWidget {
  const ForumThemeEditor({
    super.key,
    required this.theme,
    this.creating = false,
    required this.brightness,
    required this.onChanged,
    required this.onSave,
    required this.onCancel,
  });

  /// The theme as it was saved, or the starting point of a new one.
  final ForumTheme theme;
  final bool creating;

  /// The mode whose colours are edited, and the app shows.
  final Brightness brightness;

  /// The draft after each change to how it looks.
  final ValueChanged<ForumTheme> onChanged;
  final Future<void> Function(ForumTheme) onSave;
  final VoidCallback onCancel;

  @override
  State<ForumThemeEditor> createState() => _ForumThemeEditorState();
}

class _ForumThemeEditorState extends State<ForumThemeEditor> {
  late final _name = TextEditingController(
    text: widget.creating ? '' : widget.theme.name,
  );
  late final _palettes = {
    for (final mode in Brightness.values)
      mode: widget.theme.forBrightness(mode),
  };
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ForumTheme get _palette => _palettes[widget.brightness]!;

  set _palette(ForumTheme value) {
    setState(() => _palettes[widget.brightness] = value);
    widget.onChanged(_theme(widget.theme.name));
  }

  ForumTheme _theme(String name) {
    Map<String, dynamic> part(Brightness mode) => {
      ..._palettes[mode]!.toJson(),
      'name': name,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        Row(
          children: [
            DButton(
              key: const ValueKey('all-themes'),
              label: const Text('All themes'),
              icon: const DIcon(DIcons.chevronLeft, size: 11),
              variant: DButtonVariant.inline,
              size: DButtonSize.small,
              onPressed: widget.onCancel,
            ),
            const Spacer(),
            ThemeThumbnail(
              key: const ValueKey('theme-editor-thumbnail'),
              theme: AppTheme.fromPalette(
                palette.colours.resolve(widget.brightness),
              ),
            ),
          ],
        ),
        DInput(
          key: const ValueKey('theme-name'),
          controller: _name,
          labelText: 'Name',
          hintText: 'Name this theme',
          maxLength: 48,
          readOnly: _saving,
          onChanged: (_) => setState(() {}),
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
        DField(
          children: [
            const DFieldLabel(child: Text('Sidebar')),
            DToggleGroup<bool>(
              key: const ValueKey('theme-sidebar'),
              values: [palette.darkerSidebars],
              size: DToggleSize.segment,
              expanded: true,
              inset: true,
              allowEmptySelection: false,
              semanticLabel: 'Sidebar',
              onChanged: (values) {
                if (values.isNotEmpty) {
                  _palette = palette.copyWith(darkerSidebars: values.first);
                }
              },
              items: const [
                DToggleGroupItem(value: false, child: Text('Neutral')),
                DToggleGroupItem(value: true, child: Text('Darker')),
              ],
            ),
          ],
        ),
        ForumAppearanceEffects(
          effects: palette.background ?? const ForumBackground.appearance(),
          tint: palette.tint,
          onTintChanged: (value) => _palette = palette.copyWith(tint: value),
          onChanged: (change) => _palette = palette.copyWith(
            background: change(
              palette.background ?? const ForumBackground.appearance(),
            ),
          ),
        ),
        if (_error case final error?)
          DAlert(
            variant: DAlertVariant.destructive,
            description: DAlertDescription(child: Text(error)),
          ),
        Row(
          spacing: DSpacing.controlGap,
          children: [
            if (widget.creating)
              const Expanded(
                child: DFieldDescription(
                  child: Text(
                    'Starts from the theme in use. Name it to keep it.',
                  ),
                ),
              )
            else
              const Spacer(),
            DButton(
              key: const ValueKey('theme-save'),
              label: Text(widget.creating ? 'Create theme' : 'Save theme'),
              loading: _saving,
              loadingSemanticLabel: 'Saving theme',
              onPressed: _name.text.trim().isEmpty ? null : _save,
            ),
          ],
        ),
      ],
    );
  }
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
