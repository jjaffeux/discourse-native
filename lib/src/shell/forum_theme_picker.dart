import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/forum_theme.dart';
import '../models/forum_theme_preferences.dart';
import '../models/forum_theme_presets.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'forum_theme_thumbnail.dart';

/// One list of every theme the forum can show in the active mode: the user's
/// saved themes, then the forum's own palette and the built-in presets. The
/// app around the page previews each choice as it is made.
class ForumThemePicker extends StatefulWidget {
  const ForumThemePicker({
    super.key,
    required this.preferences,
    required this.forum,
    required this.brightness,
    required this.onForum,
    required this.onPreset,
    required this.onTheme,
    required this.onNewTheme,
    required this.onEdit,
    this.fontFamily,
  });

  final ForumThemePreferences preferences;
  final ForumTheme forum;

  /// The active appearance mode used for the preset list and thumbnails.
  final Brightness brightness;
  final VoidCallback onForum;
  final void Function(Brightness mode, String id) onPreset;
  final ValueChanged<String> onTheme;

  /// Starts a theme of the user's own, from the named theme when given.
  final void Function({String? base}) onNewTheme;
  final ValueChanged<ForumTheme> onEdit;
  final String? fontFamily;

  @override
  State<ForumThemePicker> createState() => _ForumThemePickerState();
}

class _ForumThemePickerState extends State<ForumThemePicker> {
  /// A choice redraws the list; every row's miniature keeps its theme.
  final _themes = <(ForumTheme, Brightness, String?), ThemeData>{};

  ThemeData _theme(ForumTheme theme) {
    final key = (theme, widget.brightness, widget.fontFamily);
    if (_themes.length > 64) _themes.clear();
    return _themes[key] ??= AppTheme.fromPalette(
      theme.colours.resolve(widget.brightness),
      fontFamily: widget.fontFamily,
    );
  }

  @override
  Widget build(BuildContext context) {
    final preferences = widget.preferences;
    final preset = preferences.presetFor(widget.brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.md,
      children: [
        _list([
          for (final theme in preferences.customThemes)
            _row(
              theme,
              chosen:
                  preferences.source == ForumThemeSource.custom &&
                  theme.id == preferences.customId,
              onPressed: () => widget.onTheme(theme.id),
              onEdit: () => widget.onEdit(theme),
              editLabel: 'Edit ${theme.name}',
            ),
          _row(
            widget.forum,
            // Whatever leaves this mode without a palette shows the forum's.
            chosen: preferences.themeFor(widget.brightness) == null,
            onPressed: widget.onForum,
            onEdit: () => widget.onNewTheme(base: widget.forum.id),
            editLabel: 'Create theme based on ${widget.forum.name}',
          ),
          for (final option in forumThemePresetsFor(widget.brightness))
            _row(
              option,
              chosen:
                  preferences.source == ForumThemeSource.preset &&
                  option.id == preset?.id,
              onPressed: () => widget.onPreset(widget.brightness, option.id),
              onEdit: () => widget.onNewTheme(base: option.id),
              editLabel: 'Create theme based on ${option.name}',
            ),
        ]),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DButton(
            key: const ValueKey('new-theme'),
            label: Text(
              widget.brightness == Brightness.dark
                  ? 'New dark theme'
                  : 'New light theme',
            ),
            icon: const DIcon(DIcons.plus),
            variant: DButtonVariant.outline,
            onPressed: widget.onNewTheme,
          ),
        ),
      ],
    );
  }

  Widget _list(List<Widget> rows) => Semantics(
    role: SemanticsRole.list,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 2,
      children: rows,
    ),
  );

  Widget _row(
    ForumTheme theme, {
    required bool chosen,
    required VoidCallback onPressed,
    required VoidCallback onEdit,
    required String editLabel,
  }) => _ThemeChoiceRow(
    key: ValueKey(('theme-row', theme.id)),
    theme: theme,
    previewTheme: _theme(theme.forBrightness(widget.brightness)),
    chosen: chosen,
    onPressed: onPressed,
    onEdit: onEdit,
    editLabel: editLabel,
  );
}

class _ThemeChoiceRow extends StatefulWidget {
  const _ThemeChoiceRow({
    super.key,
    required this.theme,
    required this.previewTheme,
    required this.chosen,
    required this.onPressed,
    required this.onEdit,
    required this.editLabel,
  });

  final ForumTheme theme;
  final ThemeData previewTheme;
  final bool chosen;
  final VoidCallback onPressed;
  final VoidCallback onEdit;
  final String editLabel;

  @override
  State<_ThemeChoiceRow> createState() => _ThemeChoiceRowState();
}

class _ThemeChoiceRowState extends State<_ThemeChoiceRow> {
  bool _hovered = false;
  bool _focusWithin = false;

  @override
  Widget build(BuildContext context) {
    final showEdit = widget.chosen || _hovered || _focusWithin;
    return Focus(
      canRequestFocus: false,
      onFocusChange: (focused) => setState(() => _focusWithin = focused),
      child: DItem(
        key: ValueKey(('theme-choice', widget.theme.id)),
        size: DItemSize.sm,
        selected: widget.chosen,
        showSelectionIndicator: false,
        onPressed: widget.onPressed,
        onHoverChanged: (hovered) => setState(() => _hovered = hovered),
        children: [
          DItemMedia(child: ThemeThumbnail(theme: widget.previewTheme)),
          DItemContent(children: [DItemTitle(child: Text(widget.theme.name))]),
          DItemActions(
            children: [
              IgnorePointer(
                ignoring: !showEdit,
                child: Opacity(
                  key: ValueKey(('edit-theme-visibility', widget.theme.id)),
                  opacity: showEdit ? 1 : 0,
                  child: DButton.iconOnly(
                    key: ValueKey(('edit-theme', widget.theme.id)),
                    icon: const DIcon(DIcons.pencil),
                    tooltip: widget.editLabel,
                    variant: DButtonVariant.outline,
                    size: DButtonSize.small,
                    onPressed: widget.onEdit,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
