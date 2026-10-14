import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/d_icons.dart';

/// The topic's end is separate from the recommendations that follow it.
class TopicEndActions extends StatelessWidget {
  const TopicEndActions({super.key, required this.onMoreTopics, this.onReply});
  final VoidCallback onMoreTopics;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DSeparator(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final label = Text(
                context.l10n.topicEndReached,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DTokens.of(context).mutedForeground,
                ),
              );
              final actions = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DButton(
                    key: const ValueKey('topic-more-topics-jump'),
                    variant: DButtonVariant.ghost,
                    label: Text(context.l10n.moreTopics),
                    icon: const DIcon(DIcons.chevronDown),
                    iconPosition: DButtonIconPosition.end,
                    onPressed: onMoreTopics,
                  ),
                  if (onReply != null)
                    DButton(
                      key: const ValueKey('topic-end-reply'),
                      variant: DButtonVariant.ghost,
                      label: Text(context.l10n.reply),
                      icon: const DIcon(DIcons.reply),
                      onPressed: onReply,
                    ),
                ],
              );
              if (constraints.maxWidth <
                  650 * MediaQuery.textScalerOf(context).scale(1)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [label, const SizedBox(height: 8), actions],
                );
              }
              return Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 8),
                  actions,
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class TopicMoreTopicsPanel extends StatelessWidget {
  const TopicMoreTopicsPanel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: context.l10n.moreTopics,
    child: DCard(
      key: const ValueKey('topic-end-more-topics-panel'),
      spacing: 0,
      borderRadius: BorderRadius.circular(14),
      backgroundColor: Theme.of(context).shell.panel,
      child: child,
    ),
  );
}

class TopicMoreTopicsHeading extends StatelessWidget {
  const TopicMoreTopicsHeading({super.key, required this.showTitle, this.tabs});
  final bool showTitle;
  final Widget? tabs;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (!showTitle) return tabs ?? const SizedBox.shrink();
        final title = Semantics(
          header: true,
          child: Text(
            context.l10n.moreTopics,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        );
        final stacked =
            constraints.maxWidth <
            600 * MediaQuery.textScalerOf(context).scale(1);
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: stacked && tabs != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [title, const SizedBox(height: 8), tabs!],
                  )
                : Row(
                    children: [
                      Expanded(child: title),
                      if (tabs != null) ...[
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth / 2,
                          ),
                          child: IntrinsicWidth(child: tabs!),
                        ),
                      ],
                    ],
                  ),
          ),
        );
      },
    ),
  );
}

/// Hide topic-only overlays without changing the reading viewport's extent.
class TopicChromeVisibility extends StatelessWidget {
  const TopicChromeVisibility({
    super.key,
    required this.covered,
    required this.child,
  });
  final ValueListenable<bool> covered;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: covered,
    child: child,
    builder: (context, hidden, child) => IgnorePointer(
      ignoring: hidden,
      child: ExcludeFocus(
        excluding: hidden,
        child: ExcludeSemantics(
          excluding: hidden,
          child: AnimatedOpacity(
            opacity: hidden ? 0 : 1,
            duration:
                MediaQuery.disableAnimationsOf(context) ||
                    DMaterialTheme.glassOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            child: child,
          ),
        ),
      ),
    ),
  );
}
