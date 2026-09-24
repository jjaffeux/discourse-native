import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'forum_theme_surfaces.dart';
import 'shell_metrics.dart';
import 'shell_panel.dart';

/// A miniature forum painted in [theme]. It uses every colour a theme defines,
/// including ones a live page may not be showing at the time: attention on a
/// review count, highlight on a pin and a mention, likes and success.
///
/// It is a still picture: sample content takes no pointer, keyboard or
/// accessibility input, and window effects are shown without their motion.
class ForumThemePreview extends StatelessWidget {
  const ForumThemePreview({super.key, required this.theme, this.height = 280});

  final ThemeData theme;
  final double height;

  /// The narrowest column the sample forum is laid out in. A narrower one
  /// shows it scaled down, the way a screenshot would be, rather than
  /// squeezing its rows.
  static const minimumWidth = 380.0;

  @override
  Widget build(BuildContext context) {
    final host = Theme.of(context);
    return Semantics(
      label: 'Forum appearance preview',
      image: true,
      child: ExcludeSemantics(
        child: ExcludeFocus(
          child: IgnorePointer(
            child: TickerMode(
              enabled: false,
              // Like a screenshot, the picture keeps its own proportions; the
              // settings around it follow the text size.
              child: Theme(
                data: theme.copyWith(platform: host.platform),
                child: MediaQuery.withNoTextScaling(
                  child: SizedBox(
                    height: height,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        if (!width.isFinite || width >= minimumWidth) {
                          return _canvas();
                        }
                        if (width <= 0) return const SizedBox.shrink();
                        return FittedBox(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: minimumWidth,
                            height: height * minimumWidth / width,
                            child: _canvas(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _canvas() => ClipRRect(
    borderRadius: BorderRadius.circular(DRadius.panel),
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DRadius.panel),
        border: Border.all(color: theme.shell.divider),
      ),
      child: ForumWindowBackground(
        key: const ValueKey('forum-theme-preview'),
        child: Padding(
          padding: const EdgeInsets.all(workspaceEdgeInset),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: workspaceEdgeInset,
              children: [
                SizedBox(
                  width: (constraints.maxWidth * .3).clamp(112, 176),
                  child: const _Sidebar(),
                ),
                const Expanded(child: _Topics()),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) => ForumSidebarTheme(
    child: Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final tokens = DTokens.of(context);
        return WorkspacePanel(
          child: ColoredBox(
            color: ForumWindowBackground.surfaceColor(context, tokens.muted),
            child: Padding(
              padding: const EdgeInsets.all(DSpacing.sm),
              child: DefaultTextStyle.merge(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 16 / 12,
                  color: tokens.foreground,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 2,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                      child: Row(
                        spacing: DSpacing.sm,
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: tokens.primary,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'C',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1,
                                fontWeight: FontWeight.w700,
                                color: tokens.primaryForeground,
                              ),
                            ),
                          ),
                          const Flexible(
                            child: Text(
                              'Community',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const _Destination(label: 'Topics', selected: true),
                    const _Destination(label: 'My posts'),
                    _Destination(
                      label: 'Review',
                      trailing: _Count(
                        count: 2,
                        background: tokens.destructive,
                        foreground: tokens.destructiveForeground,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                      child: Text(
                        'CATEGORIES',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .6,
                          color: tokens.mutedForeground,
                        ),
                      ),
                    ),
                    _Destination(label: 'General', swatch: tokens.primary),
                    _Destination(
                      label: 'Feedback',
                      swatch: theme.colorScheme.secondary,
                    ),
                    _Destination(
                      label: 'Support',
                      swatch: theme.discourse.success,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.label,
    this.selected = false,
    this.swatch,
    this.trailing,
  });

  final String label;
  final bool selected;
  final Color? swatch;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final shell = Theme.of(context).shell;
    final tokens = DTokens.of(context);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: DSpacing.sm),
      decoration: BoxDecoration(
        color: selected ? shell.selected : null,
        borderRadius: BorderRadius.circular(DRadius.nested),
      ),
      child: Row(
        spacing: DSpacing.sm,
        children: [
          if (swatch case final color?)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? shell.selectedForeground
                    : swatch == null
                    ? tokens.mutedForeground
                    : null,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({
    required this.count,
    required this.background,
    required this.foreground,
  });

  final int count;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18),
    height: 16,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(DRadius.pill),
    ),
    child: Text(
      '$count',
      style: TextStyle(
        fontSize: 10,
        height: 1,
        fontWeight: FontWeight.w700,
        color: foreground,
      ),
    ),
  );
}

class _Topics extends StatelessWidget {
  const _Topics();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = DTokens.of(context);
    final discourse = theme.discourse;
    final divider = theme.shell.divider;
    final meta = tokens.mutedForeground;
    return WorkspacePanel(
      child: DefaultTextStyle.merge(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, height: 16 / 12, color: meta),
        child: ClipRect(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: divider)),
                  ),
                  child: Row(
                    spacing: 10,
                    children: [
                      // The tabs give way to the action rather than overflow
                      // it; the first tab and the action carry the accent.
                      Expanded(
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: AlignmentDirectional.centerStart,
                            maxWidth: double.infinity,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: 14,
                              children: [
                                Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: tokens.primary,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    'Latest',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: tokens.foreground,
                                    ),
                                  ),
                                ),
                                const Center(child: Text('Top')),
                                Center(
                                  child: Text.rich(
                                    TextSpan(
                                      text: 'Unread ',
                                      children: [
                                        TextSpan(
                                          text: '3',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: tokens.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Container(
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tokens.primary,
                          borderRadius: BorderRadius.circular(DRadius.nested),
                        ),
                        child: Text(
                          'New topic',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: tokens.primaryForeground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _TopicRow(
                  title: 'Welcome to the community',
                  category: 'General',
                  categoryColor: tokens.primary,
                  replies: '14',
                  leading: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: discourse.unreadIndicator,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                _TopicRow(
                  title: 'Sharing our dark palette',
                  category: 'Feedback',
                  categoryColor: theme.colorScheme.secondary,
                  replies: '21',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 3,
                    children: [
                      DIcon(DIcons.heart, size: 11, color: discourse.love),
                      Text(
                        '32',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: discourse.love,
                        ),
                      ),
                    ],
                  ),
                ),
                _TopicRow(
                  title: 'How do I export my bookmarks?',
                  category: 'Support',
                  categoryColor: discourse.success,
                  replies: '9',
                  trailing: Container(
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        tokens.background,
                        discourse.success,
                        .18,
                      ),
                      borderRadius: BorderRadius.circular(DRadius.code),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 3,
                      children: [
                        DIcon(DIcons.check, size: 9, color: discourse.success),
                        Text(
                          'Solved',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: discourse.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _TopicRow(
                  title: 'Community guidelines',
                  category: 'General',
                  categoryColor: tokens.primary,
                  replies: '3',
                  leading: DIcon(
                    DIcons.thumbtack,
                    size: 11,
                    color: theme.colorScheme.secondary,
                  ),
                  excerpt: Text.rich(
                    TextSpan(
                      text: 'Read this before posting. Ask ',
                      children: [
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: theme.shell.mention,
                              borderRadius: BorderRadius.circular(DRadius.code),
                            ),
                            child: Text(
                              '@moderators',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: tokens.foreground,
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(text: ' if something is unclear.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({
    required this.title,
    required this.category,
    required this.categoryColor,
    required this.replies,
    this.leading,
    this.trailing,
    this.excerpt,
  });

  final String title;
  final String category;
  final Color categoryColor;
  final String replies;
  final Widget? leading;
  final Widget? trailing;
  final Widget? excerpt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = DTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: Row(
        spacing: DSpacing.md,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Row(
                  spacing: 6,
                  children: [
                    ?leading,
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: tokens.foreground,
                        ),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                ?excerpt,
                Row(
                  spacing: 5,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: categoryColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        category,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(replies, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
