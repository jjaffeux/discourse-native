import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/forum_background.dart';
import '../models/forum_theme.dart';
import '../models/forum_theme_presets.dart';
import '../theme/app_theme.dart';
import 'forum_theme_thumbnail.dart';

/// A visual library of saved themes followed by the forum's available presets.
class ForumThemePicker extends StatelessWidget {
  const ForumThemePicker({
    super.key,
    required this.palette,
    required this.customThemes,
    required this.onChanged,
    this.forumPalette,
    this.onDelete,
    this.onForumDefault,
    this.isForumDefault = false,
  });

  final ForumTheme palette;
  final List<ForumTheme> customThemes;
  final ValueChanged<ForumTheme> onChanged;
  final ForumTheme? forumPalette;
  final VoidCallback? onForumDefault;
  final bool isForumDefault;
  final ValueChanged<ForumTheme>? onDelete;

  @override
  Widget build(BuildContext context) {
    final brightness = palette.brightness;
    final presets = [
      ?forumPalette,
      for (final preset in forumThemePresets)
        if (preset.brightness == brightness ||
            preset.alternate?.brightness == brightness)
          preset.forBrightness(brightness),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.md,
      children: [
        if (customThemes.isNotEmpty) ...[
          const DFieldLabel(child: Text('Your themes')),
          _grid(context, [
            for (final theme in customThemes)
              theme.forBrightness(brightness).copyWith(name: theme.name),
          ], owned: true),
          const DFieldLabel(child: Text('Presets')),
        ],
        _grid(context, presets),
      ],
    );
  }

  Widget _grid(
    BuildContext context,
    List<ForumTheme> themes, {
    bool owned = false,
  }) => LayoutBuilder(
    builder: (context, bounds) {
      final minimum = 156 * MediaQuery.textScalerOf(context).scale(13) / 13;
      const gap = DSpacing.md;
      final columns = ((bounds.maxWidth + gap) / (minimum + gap)).floor().clamp(
        1,
        3,
      );
      return Semantics(
        role: SemanticsRole.list,
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final theme in themes)
              Semantics(
                role: SemanticsRole.listItem,
                child: SizedBox(
                  width: (bounds.maxWidth - gap * (columns - 1)) / columns,
                  child: DItem(
                    key: ValueKey(('theme-preset', theme.id)),
                    variant: DItemVariant.outline,
                    shape: DItemShape.card,
                    size: DItemSize.sm,
                    selected: theme.id == forumPalette?.id
                        ? isForumDefault
                        : !isForumDefault && palette.id == theme.id,
                    selectionStyle: DItemSelectionStyle.outline,
                    showSelectionIndicator: false,
                    onPressed:
                        theme.id == forumPalette?.id && onForumDefault != null
                        ? onForumDefault
                        : () => onChanged(theme),
                    cornerAction: owned && onDelete != null
                        ? DButton.iconOnly(
                            key: ValueKey(('delete-theme', theme.id)),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Delete ${theme.name}',
                            variant: DButtonVariant.outline,
                            size: DButtonSize.small,
                            hasPopup: true,
                            onPressed: () => onDelete!(theme),
                          )
                        : null,
                    header: DItemHeader(
                      child: SizedBox(
                        height: 80,
                        child: FittedBox(
                          child: ThemeThumbnail(
                            theme: AppTheme.fromPalette(
                              theme
                                  .copyWith(
                                    background:
                                        theme.background ??
                                        const ForumBackground.appearance(),
                                  )
                                  .resolve(palette.brightness),
                            ),
                          ),
                        ),
                      ),
                    ),
                    children: [
                      DItemContent(children: [Text(theme.name)]),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
