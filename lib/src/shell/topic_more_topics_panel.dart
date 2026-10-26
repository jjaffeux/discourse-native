import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            child: child,
          ),
        ),
      ),
    ),
  );
}
