import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../styleguide_example.dart';

final notificationDotExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'A small indicator for unread messages and new activity.',
  notes:
      'DNotificationDot has an 8px colored center. The overlay constructor adds '
      'a 2px surface ring within a 12px footprint. Both use live theme colors '
      'and stay fixed at large text sizes. Dots do not receive focus or pointer '
      'input. Supply semanticLabel for a standalone state; omit it when the '
      'enclosing control already announces unread activity. Visibility and '
      'placement belong to the caller. Use DBadge for counts and DAvatarBadge '
      'for avatar presence. This is an application component approved by the '
      'user, separate from the frozen upstream reference catalogue.',
  examples: [
    StyleguideExample(
      title: 'Inline states',
      description: 'Use a compact dot beside a title or destination label.',
      states: const ['Unread', 'Urgent', 'Semantics', 'Large text'],
      code: '''const DNotificationDot(semanticLabel: 'Unread messages')
DNotificationDot(
  color: DTokens.of(context).destructive,
  semanticLabel: 'Unseen pinned messages',
)''',
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DSpacing.md,
        children: [
          const Row(
            spacing: DSpacing.sm,
            children: [
              Flexible(child: Text('Community discussion')),
              DNotificationDot(semanticLabel: 'Unread messages'),
            ],
          ),
          Row(
            spacing: DSpacing.sm,
            children: [
              const Flexible(child: Text('Pinned messages')),
              DNotificationDot(
                color: DTokens.of(context).destructive,
                semanticLabel: 'Unseen pinned messages',
              ),
            ],
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Header overlay',
      description:
          'Activate Chat to clear its dot, then restore unread activity. '
          'The button announces the state once. Try RTL and keyboard activation.',
      states: const ['Unread', 'Read', 'Keyboard', 'RTL'],
      code: '''DButton.iconOnly(
  tooltip: unread ? 'Chat, unread messages' : 'Chat',
  variant: DButtonVariant.ghost,
  onPressed: markRead,
  icon: Stack(clipBehavior: Clip.none, children: [
    const DIcon(DIcons.comment, size: 22),
    if (unread)
      PositionedDirectional(
        top: -2, end: -3,
        child: DNotificationDot.overlay(ringColor: surface),
      ),
  ]),
)''',
      builder: (_) => const _HeaderNotificationExample(),
    ),
    StyleguideExample(
      title: 'Surface rings',
      description:
          'The ring matches the surface behind the icon, including custom '
          'header and rail surfaces. The entire ring stays inside the dot’s bounds.',
      states: const ['Background', 'Muted surface', 'Custom color'],
      code: '''DNotificationDot.overlay(
  ringColor: DTokens.of(context).muted,
  color: DTokens.of(context).destructive,
  semanticLabel: 'New activity',
)''',
      builder: (context) {
        final tokens = DTokens.of(context);
        return Wrap(
          spacing: DSpacing.lg,
          runSpacing: DSpacing.md,
          children: [
            for (final surface in [tokens.background, tokens.muted])
              DecoratedBox(
                decoration: BoxDecoration(color: surface),
                child: Padding(
                  padding: const EdgeInsets.all(DSpacing.md),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const DIcon(DIcons.bell, size: 22),
                      PositionedDirectional(
                        top: -2,
                        end: -3,
                        child: DNotificationDot.overlay(
                          ringColor: surface,
                          color: tokens.destructive,
                          semanticLabel: 'New activity',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  ],
);

class _HeaderNotificationExample extends StatefulWidget {
  const _HeaderNotificationExample();

  @override
  State<_HeaderNotificationExample> createState() =>
      _HeaderNotificationExampleState();
}

class _HeaderNotificationExampleState
    extends State<_HeaderNotificationExample> {
  bool unread = true;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: DSpacing.lg,
    runSpacing: DSpacing.md,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DButton.iconOnly(
            tooltip: unread ? 'Chat, unread messages' : 'Chat',
            variant: DButtonVariant.ghost,
            onPressed: () => setState(() => unread = false),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const DIcon(DIcons.comment, size: 22),
                if (unread)
                  const PositionedDirectional(
                    top: -2,
                    end: -3,
                    child: DNotificationDot.overlay(),
                  ),
              ],
            ),
          ),
          DButton.iconOnly(
            tooltip: 'Notifications',
            variant: DButtonVariant.ghost,
            size: DButtonSize.large,
            icon: const DIcon(DIcons.bell, size: 20),
            onPressed: () => DToast.show(context, 'No new notifications'),
          ),
          DButton.iconOnly(
            tooltip: 'Profile',
            variant: DButtonVariant.ghost,
            size: DButtonSize.large,
            icon: const DAvatar(
              dimension: 26,
              decorative: true,
              fallback: DAvatarFallback(child: DIcon(DIcons.user, size: 14)),
            ),
            onPressed: () => DToast.show(context, 'Profile preview'),
          ),
        ],
      ),
      DButton(
        label: const Text('Restore unread'),
        variant: DButtonVariant.outline,
        onPressed: unread ? null : () => setState(() => unread = true),
      ),
    ],
  );
}
