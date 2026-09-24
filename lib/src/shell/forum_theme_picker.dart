import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/forum_theme.dart';
import '../models/forum_theme_preferences.dart';
import '../models/forum_theme_presets.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'forum_theme_thumbnail.dart';
import 'settings_section.dart';

/// Choose between ready-made palettes and the user's saved themes.
class ForumThemeSources extends StatelessWidget {
  const ForumThemeSources({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ForumThemeSource value;
  final ValueChanged<ForumThemeSource> onChanged;

  @override
  Widget build(BuildContext context) =>
      DRadioGroup<ForumThemeSource>.controlled(
        key: const ValueKey('theme-source'),
        groupValue: value == ForumThemeSource.forum
            ? ForumThemeSource.preset
            : value,
        onChanged: (source) {
          if (source != null &&
              !(value == ForumThemeSource.forum &&
                  source == ForumThemeSource.preset)) {
            onChanged(source);
          }
        },
        child: const SettingsChoiceCards(
          children: [
            DRadioGroupItem(
              key: ValueKey(('theme-source', ForumThemeSource.preset)),
              value: ForumThemeSource.preset,
              card: true,
              label: Text('Presets'),
              description: Text('Forum and built-in palettes'),
            ),
            DRadioGroupItem(
              key: ValueKey(('theme-source', ForumThemeSource.custom)),
              value: ForumThemeSource.custom,
              card: true,
              label: Text('Your own'),
              description: Text('Build and save themes'),
            ),
          ],
        ),
      );
}

/// Shows the forum and built-in palettes for the active mode, or the user's
/// saved themes. The app around the page previews each choice as it is made.
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
    required this.onDuplicate,
    required this.onCopy,
    required this.onDelete,
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
  final ValueChanged<ForumTheme> onDuplicate;
  final ValueChanged<ForumTheme> onCopy;
  final ValueChanged<ForumTheme> onDelete;
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: DSpacing.md,
    children: switch (widget.preferences.source) {
      ForumThemeSource.forum || ForumThemeSource.preset => _presets(),
      ForumThemeSource.custom => _saved(),
    },
  );

  List<Widget> _presets() {
    final chosen = widget.preferences.presetFor(widget.brightness);
    return [
      _list([
        _row(
          widget.forum,
          chosen:
              widget.preferences.source == ForumThemeSource.forum ||
              chosen == null,
          onPressed: widget.onForum,
          onCustomize: () => widget.onNewTheme(base: widget.forum.id),
        ),
        for (final preset in forumThemePresetsFor(widget.brightness))
          _row(
            preset,
            chosen:
                widget.preferences.source == ForumThemeSource.preset &&
                preset.id == chosen?.id,
            onPressed: () => widget.onPreset(widget.brightness, preset.id),
            onCustomize: () => widget.onNewTheme(base: preset.id),
          ),
      ]),
    ];
  }

  List<Widget> _saved() => [
    const DFieldLabel(child: Text('Your themes')),
    _list([
      for (final theme in widget.preferences.customThemes)
        _row(
          theme,
          chosen: theme.id == widget.preferences.customId,
          onPressed: () => widget.onTheme(theme.id),
          actions: [
            DButton.iconOnly(
              key: ValueKey(('edit-theme', theme.id)),
              icon: const DIcon(DIcons.pencil),
              tooltip: 'Edit',
              semanticLabel: 'Edit ${theme.name}',
              variant: DButtonVariant.ghost,
              size: DButtonSize.small,
              onPressed: () => widget.onEdit(theme),
            ),
            _ThemeActions(
              theme: theme,
              onDuplicate: widget.onDuplicate,
              onCopy: widget.onCopy,
              onDelete: widget.onDelete,
            ),
          ],
        ),
    ]),
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: DButton(
        key: const ValueKey('new-theme'),
        label: const Text('New theme'),
        icon: const DIcon(DIcons.plus),
        variant: DButtonVariant.primary,
        onPressed: widget.onNewTheme,
      ),
    ),
  ];

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
    VoidCallback? onCustomize,
    List<Widget> actions = const [],
  }) => _ThemeChoiceRow(
    key: ValueKey(('theme-row', theme.id)),
    theme: theme,
    previewTheme: _theme(theme.forBrightness(widget.brightness)),
    chosen: chosen,
    onPressed: onPressed,
    onCustomize: onCustomize,
    actions: actions,
  );
}

class _ThemeChoiceRow extends StatefulWidget {
  const _ThemeChoiceRow({
    super.key,
    required this.theme,
    required this.previewTheme,
    required this.chosen,
    required this.onPressed,
    required this.onCustomize,
    required this.actions,
  });

  final ForumTheme theme;
  final ThemeData previewTheme;
  final bool chosen;
  final VoidCallback onPressed;
  final VoidCallback? onCustomize;
  final List<Widget> actions;

  @override
  State<_ThemeChoiceRow> createState() => _ThemeChoiceRowState();
}

class _ThemeChoiceRowState extends State<_ThemeChoiceRow> {
  bool _hovered = false;
  bool _focusWithin = false;

  @override
  Widget build(BuildContext context) {
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    final showCustomize =
        _hovered ||
        _focusWithin ||
        touch ||
        MediaQuery.accessibleNavigationOf(context);
    return Focus(
      canRequestFocus: false,
      onFocusChange: widget.onCustomize == null
          ? null
          : (focused) => setState(() => _focusWithin = focused),
      child: DItem(
        key: ValueKey(('theme-choice', widget.theme.id)),
        size: DItemSize.sm,
        selected: widget.chosen,
        showSelectionIndicator: false,
        onPressed: widget.onPressed,
        onHoverChanged: widget.onCustomize == null
            ? null
            : (hovered) => setState(() => _hovered = hovered),
        children: [
          DItemMedia(child: ThemeThumbnail(theme: widget.previewTheme)),
          DItemContent(children: [DItemTitle(child: Text(widget.theme.name))]),
          if (widget.onCustomize != null || widget.actions.isNotEmpty)
            DItemActions(
              children: [
                if (widget.onCustomize case final customize?)
                  Opacity(
                    opacity: showCustomize ? 1 : 0,
                    alwaysIncludeSemantics: true,
                    child: DButton(
                      key: ValueKey(('customize-theme', widget.theme.id)),
                      label: const Text('Customize'),
                      semanticLabel: 'Customize ${widget.theme.name}',
                      variant: DButtonVariant.outline,
                      size: DButtonSize.small,
                      onPressed: customize,
                    ),
                  ),
                ...widget.actions,
              ],
            ),
        ],
      ),
    );
  }
}

class _ThemeActions extends StatelessWidget {
  const _ThemeActions({
    required this.theme,
    required this.onDuplicate,
    required this.onCopy,
    required this.onDelete,
  });

  final ForumTheme theme;
  final ValueChanged<ForumTheme> onDuplicate;
  final ValueChanged<ForumTheme> onCopy;
  final ValueChanged<ForumTheme> onDelete;

  @override
  Widget build(BuildContext context) => DDropdownMenu(
    sheetOnMobile: true,
    content: DDropdownMenuContent(
      semanticLabel: '${theme.name} actions',
      children: [
        DDropdownMenuItem(
          key: ValueKey(('duplicate-theme', theme.id)),
          onPressed: () => onDuplicate(theme),
          child: const Text('Duplicate'),
        ),
        DDropdownMenuItem(
          key: ValueKey(('copy-theme', theme.id)),
          onPressed: () => onCopy(theme),
          child: const Text('Copy theme'),
        ),
        DDropdownMenuItem(
          key: ValueKey(('delete-theme', theme.id)),
          onPressed: () => onDelete(theme),
          child: const Text('Delete'),
        ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, trigger) => DButton.iconOnly(
        key: ValueKey(('theme-actions', theme.id)),
        icon: const DIcon(DIcons.ellipsis),
        tooltip: 'More actions for ${theme.name}',
        variant: DButtonVariant.ghost,
        size: DButtonSize.small,
        hasPopup: true,
        focusNode: trigger.focusNode,
        onPressed: trigger.toggle,
      ),
    ),
  );
}
