import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'composer_controller.dart';
import 'composer_inline_formatting.dart';

/// The BBCode adapter for Native's preset palette. Recent choices live for the
/// lifetime of the draft, including after its selection menu is dismissed.
class ComposerSelectionColors extends StatelessWidget {
  const ComposerSelectionColors({
    super.key,
    required this.composer,
    this.size = DControlSize.regular,
    this.enabled = true,
  });

  final ComposerController composer;
  final DControlSize size;
  final bool enabled;
  static final _recent = Expando<List<DColorPreset>>();

  static List<(String, int, int)> get _colors => [
    (appL10n.gray, 0xff9b9b9b, 0xff373736),
    (appL10n.brown, 0xffb58b71, 0xff523e32),
    (appL10n.orange, 0xffe58b39, 0xff613b21),
    (appL10n.yellow, 0xffd8ad45, 0xff5b4a1e),
    (appL10n.green, 0xff58a47a, 0xff244c39),
    (appL10n.blue, 0xff4d94d5, 0xff233f5c),
    (appL10n.purple, 0xffa578c3, 0xff463153),
    (appL10n.pink, 0xffc9669b, 0xff552c44),
    (appL10n.red, 0xffd75c55, 0xff592d2a),
  ];

  List<DColorPreset> _presets(bool background) => [
    for (final (name, text, fill) in _colors)
      DColorPreset(
        color: Color(background ? fill : text),
        label: appL10n.colorComposerselectioncolors(
          (background).toString(),
          ((background) ? (appL10n.background) : '').toString(),
          (name).toString(),
          ((!(background)) ? (appL10n.text) : '').toString(),
        ),
        appearance: background
            ? DColorPresetAppearance.background
            : DColorPresetAppearance.text,
      ),
  ];

  String _hex(Color color) =>
      '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';

  DColorPreset? _selected(bool background, List<DColorPreset> presets) {
    final current = composerSelectionColor(
      composer.value,
      background: background,
    );
    if (current == null) return null;
    return presets
            .where((preset) => _hex(preset.color) == current)
            .firstOrNull ??
        // An existing custom/named color is not the default swatch.
        DColorPreset(
          color: Colors.transparent,
          label: current,
          appearance: background
              ? DColorPresetAppearance.background
              : DColorPresetAppearance.text,
        );
  }

  void _apply(DColorPreset? preset, bool background, VoidCallback close) {
    composer.formatSelection(
      (value) => setComposerColor(
        value,
        preset == null ? null : _hex(preset.color),
        background: background,
      ),
    );
    if (preset != null) {
      final recent = _recent[composer] ??= [];
      recent.remove(preset);
      recent.insert(0, preset);
      if (recent.length > 5) recent.removeLast();
    }
    close();
    composer.focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => DDropdownMenu(
    restoreFocus: false,
    content: DDropdownMenuContent(
      key: const ValueKey('composer-color-palette'),
      semanticLabel: context.l10n.textAndBackgroundColors,
      autofocus: !DControlStyle.isTouch(context),
      width: DControlStyle.isTouch(context) ? 292 : 220,
      side: DPopoverSide.top,
      align: DPopoverAlign.start,
      children: [
        for (final background in [false, true]) ...[
          if (background) const SizedBox(height: DSpacing.lg),
          DPopoverClose(
            builder: (context, close) => TextFieldTapRegion(
              child: DColorPickerPresets(
                semanticLabel: background
                    ? context.l10n.backgroundColor
                    : context.l10n.textColor,
                appearance: background
                    ? DColorPresetAppearance.background
                    : DColorPresetAppearance.text,
                presets: _presets(background),
                selected: _selected(background, _presets(background)),
                recentColors: background
                    ? const []
                    : _recent[composer] ?? const [],
                onChanged: (preset) => _apply(
                  preset,
                  preset.appearance == DColorPresetAppearance.background,
                  close,
                ),
                onReset: () => _apply(null, background, close),
              ),
            ),
          ),
        ],
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, state) => DButton.iconOnly(
        tooltip: context.l10n.color,
        semanticLabel: context.l10n.color,
        icon: const Icon(Icons.format_color_text),
        variant: DButtonVariant.ghost,
        size: size,
        focusNode: state.focusNode,
        expanded: state.open,
        hasPopup: true,
        onPressed: enabled && composer.isEditing ? state.toggle : null,
      ),
    ),
  );
}
