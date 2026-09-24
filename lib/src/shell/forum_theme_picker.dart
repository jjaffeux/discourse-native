import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/forum_theme.dart';
import '../models/forum_theme_preferences.dart';
import '../models/forum_theme_presets.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'forum_theme_preview.dart';
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
/// one mode, or the user's saved themes, each with a preview of every colour
/// in the choice under the pointer or in use.
class ForumThemePicker extends StatefulWidget {
  const ForumThemePicker({
    super.key,
    required this.preferences,
    required this.forum,
    required this.brightness,
    required this.onBrightnessChanged,
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

  /// The forum's own palette for each mode.
  final Map<Brightness, ForumTheme> forum;

  /// The mode whose colours the lists and preview show.
  final Brightness brightness;
  final ValueChanged<Brightness> onBrightnessChanged;
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
  String? _hovered;

  /// Hovering redraws the preview; every row's miniature keeps its theme.
  final _themes = <(ForumTheme, Brightness, String?), ThemeData>{};

  @override
  void didUpdateWidget(ForumThemePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences.source != widget.preferences.source ||
        oldWidget.brightness != widget.brightness) {
      _hovered = null;
    }
  }

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
  Widget build(BuildContext context) => switch (widget.preferences.source) {
    ForumThemeSource.forum => _forum(context),
    ForumThemeSource.preset => _presets(context),
    ForumThemeSource.custom => _saved(context),
  };

  Widget _header(String label) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: DSpacing.md,
    runSpacing: DSpacing.sm,
    children: [
      DFieldLabel(child: Text(label)),
      DToggleGroup<Brightness>(
        key: const ValueKey('theme-preview-mode'),
        values: [widget.brightness],
        allowEmptySelection: false,
        size: DToggleSize.small,
        variant: DToggleVariant.outline,
        semanticLabel: 'Colours shown',
        items: const [
          DToggleGroupItem(
            value: Brightness.light,
            icon: Icon(Icons.light_mode_outlined),
            child: Text('Light'),
          ),
          DToggleGroupItem(
            value: Brightness.dark,
            icon: Icon(Icons.dark_mode_outlined),
            child: Text('Dark'),
          ),
        ],
        onChanged: (values) => widget.onBrightnessChanged(values.single),
      ),
    ],
  );

  Widget _preview(ForumTheme theme) => ForumThemePreview(
    key: const ValueKey('theme-preview'),
    theme: _theme(theme.forBrightness(widget.brightness)),
  );

  Widget _caption(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12.5,
      height: 1.45,
      color: DTokens.of(context).mutedForeground,
    ),
  );

  Widget _forum(BuildContext context) {
    final forum = widget.forum[widget.brightness]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.md,
      children: [
        _header('The forum’s own colours'),
        _preview(forum),
        Wrap(
          spacing: DSpacing.md,
          runSpacing: DSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _caption(
              context,
              'Light and dark come from the forum, and follow it when its '
              'admins change them.',
            ),
            _makeOwn('forum'),
          ],
        ),
      ],
    );
  }

  Widget _makeOwn(String base) => DButton(
    key: ValueKey(('make-own-theme', base)),
    label: const Text('Make my own from this'),
    variant: DButtonVariant.outline,
    size: DButtonSize.small,
    onPressed: () => widget.onNewTheme(base: base),
  );

  Widget _presets(BuildContext context) {
    final chosen = widget.preferences.presets[widget.brightness];
    return _Browser(
      header: _header('Built-in presets'),
      rows: [
        for (final preset in forumThemePresetsFor(widget.brightness))
          _row(
            preset,
            chosen: chosen == preset.id,
            onPressed: () {
              widget.onPreset(widget.brightness, preset.id);
            },
          ),
      ],
      detail: _presetDetail(context, chosen),
    );
  }

  Widget _presetDetail(BuildContext context, String? chosen) {
    final shown = [_hovered, chosen]
        .whereType<String>()
        .map((id) => forumThemePresetFor(id, widget.brightness))
        .whereType<ForumTheme>()
        .firstOrNull;
    if (shown == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DSpacing.sm,
        children: [
          _preview(widget.forum[widget.brightness]!),
          _caption(
            context,
            'No preset chosen for $_mode mode yet, so it keeps the forum’s '
            'colours.',
          ),
        ],
      );
    }
    final both = forumThemeHasMode(
      shown,
      widget.brightness == Brightness.dark ? Brightness.light : Brightness.dark,
    );
    return _Detail(
      preview: _preview(shown),
      name: shown.name,
      inUse: shown.id == chosen,
      palette: _theme(shown.forBrightness(widget.brightness)),
      caption: _caption(
        context,
        both ? 'Built-in · has light and dark' : 'Built-in · $_mode only',
      ),
      actions: [_makeOwn(shown.id)],
    );
  }

  Widget _saved(BuildContext context) {
    final themes = widget.preferences.customThemes;
    final chosen = widget.preferences.customId;
    final shown =
        themes.where((theme) => theme.id == _hovered).firstOrNull ??
        widget.preferences.customTheme;
    return _Browser(
      header: _header('Your themes'),
      rows: [
        for (final theme in themes)
          _row(
            theme,
            chosen: theme.id == chosen,
            onPressed: () {
              widget.onTheme(theme.id);
            },
          ),
        DItem(
          key: const ValueKey('new-theme'),
          size: DItemSize.sm,
          onPressed: widget.onNewTheme,
          children: const [
            DItemMedia(
              variant: DItemMediaVariant.icon,
              child: DIcon(DIcons.plus),
            ),
            DItemContent(children: [DItemTitle(child: Text('New theme'))]),
          ],
        ),
      ],
      detail: shown == null
          ? _preview(widget.forum[widget.brightness]!)
          : _Detail(
              preview: _preview(shown),
              name: shown.name,
              inUse: shown.id == chosen,
              palette: _theme(shown.forBrightness(widget.brightness)),
              caption: _caption(context, 'Your theme · light and dark'),
              actions: [
                DButton(
                  key: ValueKey(('edit-theme', shown.id)),
                  label: const Text('Edit'),
                  icon: const DIcon(DIcons.pencil),
                  variant: DButtonVariant.outline,
                  size: DButtonSize.small,
                  onPressed: () => widget.onEdit(shown),
                ),
                _ThemeActions(
                  theme: shown,
                  onDuplicate: widget.onDuplicate,
                  onCopy: widget.onCopy,
                  onDelete: widget.onDelete,
                ),
              ],
            ),
    );
  }

  Widget _row(
    ForumTheme theme, {
    required bool chosen,
    required VoidCallback onPressed,
  }) => DItem(
    key: ValueKey(('theme-choice', theme.id)),
    size: DItemSize.sm,
    selected: chosen,
    onPressed: onPressed,
    onHoverChanged: (hovered) => setState(() {
      if (hovered) {
        _hovered = theme.id;
      } else if (_hovered == theme.id) {
        _hovered = null;
      }
    }),
    children: [
      DItemMedia(
        child: ThemeThumbnail(
          theme: _theme(theme.forBrightness(widget.brightness)),
        ),
      ),
      DItemContent(children: [DItemTitle(child: Text(theme.name))]),
    ],
  );
}

/// A list beside the preview when there is room for both, else below it.
class _Browser extends StatelessWidget {
  const _Browser({
    required this.header,
    required this.rows,
    required this.detail,
  });

  final Widget header;
  final List<Widget> rows;
  final Widget detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: DSpacing.md,
    children: [
      header,
      LayoutBuilder(
        builder: (context, constraints) {
          final list = Semantics(
            role: SemanticsRole.list,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 2,
              children: rows,
            ),
          );
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          if (constraints.maxWidth < 560 * scale) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DSpacing.lg,
              children: [detail, list],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 20,
            children: [
              SizedBox(width: 232 * scale, child: list),
              Expanded(child: detail),
            ],
          );
        },
      ),
    ],
  );
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.preview,
    required this.name,
    required this.inUse,
    required this.palette,
    required this.caption,
    required this.actions,
  });

  final Widget preview;
  final String name;
  final bool inUse;
  final ThemeData palette;
  final Widget caption;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: DSpacing.sm,
    children: [
      preview,
      Row(
        spacing: DSpacing.sm,
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DTokens.of(context).foreground,
              ),
            ),
          ),
          DBadge(
            key: const ValueKey('theme-status'),
            variant: inUse ? DBadgeVariant.primary : DBadgeVariant.outline,
            child: Text(inUse ? 'In use' : 'Preview'),
          ),
          const Spacer(),
          ExcludeSemantics(
            child: SizedBox(
              width: 100,
              height: 14,
              child: FittedBox(child: ThemePaletteStrip(theme: palette)),
            ),
          ),
        ],
      ),
      Wrap(
        spacing: DSpacing.controlGap,
        runSpacing: DSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: DSpacing.sm),
            child: caption,
          ),
          ...actions,
        ],
      ),
    ],
  );
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
        variant: DButtonVariant.outline,
        size: DButtonSize.small,
        hasPopup: true,
        focusNode: trigger.focusNode,
        onPressed: trigger.toggle,
      ),
    ),
  );
}
