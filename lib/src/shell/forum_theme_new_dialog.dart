import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/forum_theme.dart';
import '../models/forum_theme_presets.dart';
import '../theme/app_theme.dart';
import 'forum_theme_thumbnail.dart';

/// What a new theme is called and the colours it starts from.
typedef ForumThemeStart = ({String name, ForumTheme base});

/// Names a new theme of the user's own and picks where it starts: plain
/// greys, the forum's colours, a preset or another of their themes. Nothing is
/// created here; the editor that follows saves the theme.
class ForumThemeNewDialog extends StatefulWidget {
  const ForumThemeNewDialog({
    super.key,
    required this.controller,
    required this.brightness,
    required this.forum,
    required this.saved,
    this.initial,
  });

  final DDialogController<ForumThemeStart> controller;

  /// The mode the starting points are drawn in.
  final Brightness brightness;

  /// The forum's own colours for both modes.
  final ForumTheme forum;
  final List<ForumTheme> saved;

  /// The id of the starting point chosen when the dialog opens.
  final String? initial;

  @override
  State<ForumThemeNewDialog> createState() => _ForumThemeNewDialogState();
}

class _ForumThemeNewDialogState extends State<ForumThemeNewDialog> {
  late final List<ForumTheme> _presets = forumThemePresetsFor(
    widget.brightness,
  ).toList();
  late ForumTheme _base =
      [
        blankForumTheme,
        widget.forum,
        ...forumThemePresets,
        ...widget.saved,
      ].where((theme) => theme.id == widget.initial).firstOrNull ??
      blankForumTheme;
  late final _name = TextEditingController(text: _suggestedName(_base));

  /// The name follows the starting point until the user types their own.
  bool _named = false;

  /// Typing redraws the dialog; each starting point keeps its miniature.
  final _thumbnails = <String, ThemeData>{};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static String _suggestedName(ForumTheme base) {
    if (base.id == blankForumTheme.id) return 'My theme';
    final name = '${base.name} copy';
    return name.length <= 48 ? name : name.substring(0, 48).trimRight();
  }

  void _choose(ForumTheme base) => setState(() {
    _base = base;
    if (!_named) _name.text = _suggestedName(base);
  });

  void _continue() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    widget.controller.close((name: name, base: _base));
  }

  String get _note {
    final base = _base;
    if (base.id == blankForumTheme.id) {
      return 'Starts with plain greys for light and dark.';
    }
    if (base.id == widget.forum.id) {
      return 'Starts with the forum’s light and dark colours. Your copy won’t '
          'follow later changes the forum makes.';
    }
    if (widget.saved.contains(base)) {
      return 'Starts as a copy of ${base.name}, light and dark.';
    }
    final missing = Brightness.values
        .where((mode) => !forumThemeHasMode(base, mode))
        .firstOrNull;
    if (missing == null) {
      return 'Starts with ${base.name}’s light and dark versions.';
    }
    final authored = missing == Brightness.light ? 'dark' : 'light';
    return '${base.name} only has a $authored version, so the '
        '${missing.name} one is generated from it. You can adjust both.';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return DDialogContent(
      semanticLabel: 'New theme',
      maxWidth: 560,
      children: [
        const DDialogHeader(
          children: [
            DDialogTitle(child: Text('New theme')),
            DDialogDescription(
              child: Text(
                'Start blank or from a theme you like. You can change every '
                'colour afterwards.',
              ),
            ),
          ],
        ),
        DInput(
          key: const ValueKey('new-theme-name'),
          controller: _name,
          labelText: 'Name',
          autofocus: true,
          maxLength: 48,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _named = true),
          onSubmitted: (_) => _continue(),
        ),
        DDialogScrollArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DSpacing.md,
            children: [
              const DFieldLabel(child: Text('Start from')),
              _grid([blankForumTheme, widget.forum]),
              _group('Presets', _presets),
              if (widget.saved.isNotEmpty) _group('Your themes', widget.saved),
            ],
          ),
        ),
        Text(
          _note,
          key: const ValueKey('new-theme-note'),
          style: TextStyle(
            fontSize: 12.5,
            height: 1.45,
            color: tokens.mutedForeground,
          ),
        ),
        DDialogFooter(
          children: [
            DButton(
              label: const Text('Cancel'),
              variant: DButtonVariant.outline,
              onPressed: widget.controller.close,
            ),
            DButton(
              key: const ValueKey('new-theme-continue'),
              label: const Text('Continue'),
              onPressed: _name.text.trim().isEmpty ? null : _continue,
            ),
          ],
        ),
      ],
    );
  }

  Widget _group(String label, List<ForumTheme> themes) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: DSpacing.sm,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: DTokens.of(context).mutedForeground,
        ),
      ),
      _grid(themes),
    ],
  );

  Widget _grid(List<ForumTheme> themes) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = DSpacing.sm;
      final minimum = 104 * MediaQuery.textScalerOf(context).scale(13) / 13;
      final columns = ((constraints.maxWidth + gap) / (minimum + gap))
          .floor()
          .clamp(1, 4);
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Semantics(
        role: SemanticsRole.list,
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final theme in themes)
              SizedBox(
                width: width,
                child: DItem(
                  key: ValueKey(('new-theme-base', theme.id)),
                  variant: DItemVariant.outline,
                  shape: DItemShape.card,
                  size: DItemSize.xs,
                  selected: theme.id == _base.id,
                  selectionStyle: DItemSelectionStyle.outline,
                  showSelectionIndicator: false,
                  onPressed: () => _choose(theme),
                  header: DItemHeader(
                    child: SizedBox(
                      height: 40,
                      child: FittedBox(
                        child: ThemeThumbnail(
                          theme: _thumbnails[theme.id] ??= AppTheme.fromPalette(
                            theme.resolve(widget.brightness),
                          ),
                        ),
                      ),
                    ),
                  ),
                  children: [
                    DItemContent(
                      children: [
                        Text(
                          theme.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
