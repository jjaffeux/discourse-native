import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/forum_theme.dart';
import '../models/forum_theme_preferences.dart';
import '../models/forum_theme_presets.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'forum_theme_thumbnail.dart';

/// Where the forum's colours come from. Choosing a source never edits one:
/// the forum's palette and the presets apply as they are.
class ForumThemeSources extends StatelessWidget {
  const ForumThemeSources({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final ForumThemeSource value;
  final ValueChanged<ForumThemeSource> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) =>
      DRadioGroup<ForumThemeSource>.controlled(
        key: const ValueKey('theme-source'),
        groupValue: value,
        enabled: enabled,
        onChanged: (source) {
          if (source != null) onChanged(source);
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            const items = [
              DRadioGroupItem(
                key: ValueKey(('theme-source', ForumThemeSource.forum)),
                value: ForumThemeSource.forum,
                card: true,
                label: Text('Forum default'),
                description: Text('The forum’s own colours'),
              ),
              DRadioGroupItem(
                key: ValueKey(('theme-source', ForumThemeSource.preset)),
                value: ForumThemeSource.preset,
                card: true,
                label: Text('Preset'),
                description: Text('A built-in palette'),
              ),
              DRadioGroupItem(
                key: ValueKey(('theme-source', ForumThemeSource.custom)),
                value: ForumThemeSource.custom,
                card: true,
                label: Text('Your own'),
                description: Text('Build and save themes'),
              ),
            ];
            final wide =
                constraints.maxWidth >=
                540 * MediaQuery.textScalerOf(context).scale(14) / 14;
            return wide
                ? IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: DSpacing.md,
                      children: [
                        for (final item in items) Expanded(child: item),
                      ],
                    ),
                  )
                : const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: DSpacing.sm,
                    children: items,
                  );
          },
        ),
      );
}

/// The content of the chosen source: the forum's own colours, the presets for
/// one mode, or the user's saved themes. The app around the page is the
/// preview: a choice applies as it is made, in the mode shown here.
class ForumThemePicker extends StatefulWidget {
  const ForumThemePicker({
    super.key,
    required this.preferences,
    required this.brightness,
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

  /// The active appearance mode used for the preset list and thumbnails.
  final Brightness brightness;
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
      theme.resolve(widget.brightness),
      fontFamily: widget.fontFamily,
    );
  }

  String get _mode => widget.brightness == Brightness.dark ? 'dark' : 'light';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: DSpacing.md,
    children: switch (widget.preferences.source) {
      ForumThemeSource.forum => _forum(context),
      ForumThemeSource.preset => _presets(context),
      ForumThemeSource.custom => _saved(context),
    },
  );

  Widget _caption(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12.5,
      height: 1.45,
      color: DTokens.of(context).mutedForeground,
    ),
  );

  Widget _footer(List<Widget> children) => Wrap(
    spacing: DSpacing.md,
    runSpacing: DSpacing.sm,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children,
  );

  Widget _makeOwn(String base) => DButton(
    key: ValueKey(('make-own-theme', base)),
    label: const Text('Make my own from this'),
    variant: DButtonVariant.outline,
    size: DButtonSize.small,
    onPressed: () => widget.onNewTheme(base: base),
  );

  List<Widget> _forum(BuildContext context) => [
    const DFieldLabel(child: Text('The forum’s own colours')),
    _footer([
      _caption(
        context,
        'Light and dark come from the forum, and follow it when its admins '
        'change them.',
      ),
      _makeOwn('forum'),
    ]),
  ];

  List<Widget> _presets(BuildContext context) {
    final chosen = widget.preferences.presetFor(widget.brightness);
    return [
      if (chosen == null)
        _caption(
          context,
          'No preset chosen for $_mode mode yet, so it keeps the forum’s '
          'colours.',
        ),
      _list([
        for (final preset in forumThemePresetsFor(widget.brightness))
          _row(
            preset,
            chosen: preset.id == chosen?.id,
            onPressed: () => widget.onPreset(widget.brightness, preset.id),
            onCustomize: () => widget.onNewTheme(base: preset.id),
          ),
      ]),
    ];
  }

  List<Widget> _saved(BuildContext context) => [
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
