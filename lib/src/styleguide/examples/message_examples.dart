import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final messageExamples = ComponentExamples(
  status: ComponentStatus.planned,
  description:
      'Conversation rows with logical alignment, avatars, rich surfaces, metadata, actions, attachments, and status updates.',
  notes:
      'Frozen base-nova source: 8px row/group gap, 10px content gap, 32px avatar slot and footer shift, 12px metadata inset, 14/20 row text, and 12/16 medium metadata. '
      'Message is presentational: identity, scrolling, delivery, permissions and network work stay with callers. '
      'Use matching DMessageAlign and DBubbleAlign values because Bubble owns its own content alignment. '
      'Icon-only actions retain independent labels. DMessageStatus and DMarker live regions are opt-in status announcements. '
      'The app adapter may explicitly keep top-anchored avatars and existing spacing; the default remains the reference bottom anchoring. '
      'Prepared Bubble and Attachment source is not accepted until their reviewers merge; this page remains planned until independent Message review completes browser/native acceptance.',
  examples: [
    StyleguideExample(
      title: 'Overview and composition',
      description:
          'The frozen conversation composition with sender/receiver alignment, delivery metadata, a same-sender bubble group, reactions, and typing status.',
      states: const ['Start', 'End', 'Footer', 'Group', 'Status'],
      code: '''DMessage(
  align: DMessageAlign.end,
  children: [
    DMessageAvatar(child: DAvatar(...)),
    DMessageContent(children: [
      DBubble(align: DBubbleAlign.end, children: [
        DBubbleContent(child: Text('Deploying to prod real quick.')),
      ]),
      DMessageFooter(children: [Text('Delivered')]),
    ]),
  ],
)''',
      builder: (_) => const _OverviewExample(),
    ),
    StyleguideExample(
      title: 'Avatar and message groups',
      description:
          'Empty avatar slots preserve the 32px column for earlier messages; the final message provides the actual Avatar owner.',
      states: const ['Avatar', 'Empty slot', 'Consecutive sender'],
      code: '''DMessageGroup(children: [
  DMessage(children: [
    DMessageAvatar(),
    DMessageContent(children: [DBubble(...)]),
  ]),
  DMessage(children: [
    DMessageAvatar(child: DAvatar(...)),
    DMessageContent(children: [DBubble(...)]),
  ]),
])''',
      builder: (_) => const _GroupExample(),
    ),
    StyleguideExample(
      title: 'Header and footer',
      description:
          'Headers stay at logical start; footer metadata follows the message side and wraps under large text.',
      states: const ['Sender', 'Timestamp', 'Read status'],
      code: '''DMessage(
  children: [DMessageContent(children: [
    DMessageHeader(children: [Text('Olivia'), Text('Yesterday')]),
    DBubble(variant: DBubbleVariant.muted, children: [...]),
    DMessageFooter(children: [Text('Read yesterday')]),
  ])],
)''',
      builder: (_) => const _MetadataExample(),
    ),
    StyleguideExample(
      title: 'Actions and delivery states',
      description:
          'Copy, feedback and retry actions are real independently labeled buttons. Retry transitions controlled failed state to delivered.',
      states: const ['Copy', 'Like', 'Dislike', 'Failed', 'Retry'],
      code: '''DMessageFooter(children: [
  DMessageStatus(state: DMessageDeliveryState.failed),
  DButton.iconOnly(
    icon: Icon(Icons.refresh), tooltip: 'Retry', onPressed: retry,
    variant: DButtonVariant.ghost, size: DButtonSize.extraSmall,
  ),
])''',
      builder: (_) => const _ActionsExample(),
    ),
    StyleguideExample(
      title: 'Attachments',
      description:
          'Final Attachment cards compose beside bubbles; image and file actions remain separately labeled and locally controlled.',
      states: const ['Vertical image', 'File', 'Download'],
      code: '''DMessageContent(children: [
  DAttachment(
    orientation: DAttachmentOrientation.vertical,
    children: [DAttachmentMedia(variant: DAttachmentMediaVariant.image, ...)],
  ),
  DBubble(...),
])''',
      builder: (_) => const _AttachmentExample(),
    ),
    StyleguideExample(
      title: 'Accessibility and status updates',
      description:
          'Toggle pending, failed, deleted and complete states. Only changing status nodes are live regions; ordinary message content stays presentational.',
      states: const ['Pending', 'Failed', 'Deleted', 'Marker live status'],
      code: '''DMarker(
  liveRegion: true,
  child: DMarkerContent(child: Text('Checking the logs...')),
)
DMessageStatus(
  state: DMessageDeliveryState.deleted,
  liveRegion: true,
)''',
      builder: (_) => const _StatusExample(),
    ),
  ],
);

class _Conversation extends StatelessWidget {
  const _Conversation({required this.children, this.gap = 24});
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 384),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: gap,
        children: children,
      ),
    ),
  );
}

class _OverviewExample extends StatelessWidget {
  const _OverviewExample();

  @override
  Widget build(BuildContext context) => const _Conversation(
    children: [
      DMessage(
        align: DMessageAlign.end,
        children: [
          DMessageAvatar(
            child: _Avatar(label: 'ME', name: 'You'),
          ),
          DMessageContent(
            children: [
              DBubble(
                align: DBubbleAlign.end,
                children: [
                  DBubbleContent(child: Text('Deploying to prod real quick.')),
                ],
              ),
            ],
          ),
        ],
      ),
      DMessage(
        children: [
          DMessageAvatar(
            child: _Avatar(label: 'R', name: 'Rabbit'),
          ),
          DMessageContent(
            children: [
              DBubble(
                variant: DBubbleVariant.muted,
                children: [
                  DBubbleContent(child: Text("It's 4:55 PM. On a Friday.")),
                ],
              ),
            ],
          ),
        ],
      ),
      DMessage(
        align: DMessageAlign.end,
        children: [
          DMessageAvatar(
            child: _Avatar(label: 'ME', name: 'You'),
          ),
          DMessageContent(
            children: [
              DBubble(
                align: DBubbleAlign.end,
                children: [
                  DBubbleContent(child: Text("It's a one-line change.")),
                ],
              ),
              DMessageFooter(
                children: [
                  DMessageStatus(
                    state: DMessageDeliveryState.delivered,
                    liveRegion: false,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      DMessage(
        children: [
          DMessageAvatar(
            child: _Avatar(label: 'R', name: 'Rabbit'),
          ),
          DMessageContent(
            children: [
              DBubbleGroup(
                children: [
                  DBubble(
                    variant: DBubbleVariant.muted,
                    children: [
                      DBubbleContent(
                        child: Text("It's always a one-line change 😭."),
                      ),
                    ],
                  ),
                  DBubble(
                    variant: DBubbleVariant.muted,
                    children: [
                      DBubbleContent(
                        child: Text('Alright, let me take a look.'),
                      ),
                      DBubbleReactions(
                        semanticLabel: 'Reactions: thumbs up',
                        children: [Text('👍')],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      DMarker(
        liveRegion: true,
        child: DMarkerContent(child: Text('Oliver is typing...')),
      ),
    ],
  );
}

class _GroupExample extends StatelessWidget {
  const _GroupExample();

  @override
  Widget build(BuildContext context) => const _Conversation(
    children: [
      DMessageGroup(
        children: [
          DMessage(
            children: [
              DMessageAvatar(),
              DMessageContent(
                children: [
                  DBubble(
                    variant: DBubbleVariant.muted,
                    children: [
                      DBubbleContent(
                        child: Text('I checked the registry addresses.'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          DMessage(
            children: [
              DMessageAvatar(
                child: _Avatar(label: 'CN', name: 'Contributor'),
              ),
              DMessageContent(
                children: [
                  DBubble(
                    variant: DBubbleVariant.muted,
                    children: [
                      DBubbleContent(
                        child: Text(
                          'The component and example JSON now live under the UI registry.',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _MetadataExample extends StatelessWidget {
  const _MetadataExample();

  @override
  Widget build(BuildContext context) => const _Conversation(
    gap: 32,
    children: [
      DMessage(
        children: [
          DMessageContent(
            children: [
              DMessageHeader(children: [Text('Olivia'), Text('Yesterday')]),
              DBubble(
                variant: DBubbleVariant.muted,
                children: [
                  DBubbleContent(child: Text('I already checked the logs.')),
                ],
              ),
            ],
          ),
        ],
      ),
      DMessage(
        align: DMessageAlign.end,
        children: [
          DMessageContent(
            children: [
              DBubble(
                align: DBubbleAlign.end,
                children: [
                  DBubbleContent(child: Text('Send the report to the team.')),
                ],
              ),
              DMessageFooter(children: [Text('Read'), Text('Yesterday')]),
            ],
          ),
        ],
      ),
    ],
  );
}

class _ActionsExample extends StatefulWidget {
  const _ActionsExample();
  @override
  State<_ActionsExample> createState() => _ActionsExampleState();
}

class _ActionsExampleState extends State<_ActionsExample> {
  var copied = false;
  var liked = false;
  var delivery = DMessageDeliveryState.failed;

  @override
  Widget build(BuildContext context) => _Conversation(
    gap: 32,
    children: [
      DMessage(
        children: [
          DMessageContent(
            children: [
              const DBubble(
                variant: DBubbleVariant.muted,
                children: [
                  DBubbleContent(
                    child: Text(
                      'The install failure is coming from the workspace package.',
                    ),
                  ),
                ],
              ),
              DMessageFooter(
                spacing: 2,
                children: [
                  DButton.iconOnly(
                    icon: Icon(copied ? Icons.check : Icons.copy_outlined),
                    tooltip: 'Copy',
                    onPressed: () => setState(() => copied = !copied),
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.extraSmall,
                  ),
                  DButton.iconOnly(
                    icon: Icon(
                      liked ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                    ),
                    tooltip: 'Like',
                    onPressed: () => setState(() => liked = !liked),
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.extraSmall,
                  ),
                  DButton.iconOnly(
                    icon: const Icon(Icons.thumb_down_alt_outlined),
                    tooltip: 'Dislike',
                    onPressed: () {},
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.extraSmall,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      DMessage(
        align: DMessageAlign.end,
        children: [
          DMessageContent(
            children: [
              const DBubble(
                align: DBubbleAlign.end,
                children: [
                  DBubbleContent(
                    child: Text('Okay, drop me a link. Taking a look...'),
                  ),
                ],
              ),
              DMessageFooter(
                spacing: 8,
                children: [
                  DMessageStatus(state: delivery),
                  DButton.iconOnly(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Retry',
                    onPressed: delivery == DMessageDeliveryState.failed
                        ? () => setState(
                            () => delivery = DMessageDeliveryState.delivered,
                          )
                        : null,
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.extraSmall,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      Text(
        copied ? 'Message copied' : 'Copy has not run',
        key: const ValueKey('message-action-result'),
      ),
    ],
  );
}

class _AttachmentExample extends StatefulWidget {
  const _AttachmentExample();
  @override
  State<_AttachmentExample> createState() => _AttachmentExampleState();
}

class _AttachmentExampleState extends State<_AttachmentExample> {
  var downloaded = false;

  @override
  Widget build(BuildContext context) => _Conversation(
    gap: 32,
    children: [
      DMessage(
        align: DMessageAlign.end,
        children: [
          DMessageContent(
            children: [
              DAttachment(
                orientation: DAttachmentOrientation.vertical,
                children: [
                  DAttachmentMedia(
                    variant: DAttachmentMediaVariant.image,
                    semanticLabel: 'Workspace',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            DTokens.of(context).muted,
                            DTokens.of(context).primary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Center(child: Icon(Icons.image_outlined)),
                    ),
                  ),
                ],
              ),
              const DBubble(
                align: DBubbleAlign.end,
                children: [
                  DBubbleContent(
                    child: Text('Can you add this image to the PDF cover?'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      DMessage(
        children: [
          DMessageContent(
            children: [
              const DBubble(
                variant: DBubbleVariant.muted,
                children: [
                  DBubbleContent(child: Text("Done. Here's the PDF.")),
                ],
              ),
              DAttachment(
                semanticLabel: 'sales-dashboard.pdf, PDF, 2.4 MB',
                children: [
                  const DAttachmentMedia(
                    child: Icon(Icons.description_outlined),
                  ),
                  const DAttachmentContent(
                    children: [
                      DAttachmentTitle(child: Text('sales-dashboard.pdf')),
                      DAttachmentDescription(child: Text('PDF · 2.4 MB')),
                    ],
                  ),
                  DAttachmentActions(
                    children: [
                      DAttachmentAction(
                        icon: Icon(
                          downloaded ? Icons.check : Icons.download_outlined,
                        ),
                        tooltip: 'Download',
                        onPressed: () => setState(() => downloaded = true),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      Text(
        downloaded ? 'Download started' : 'Download has not started',
        key: const ValueKey('message-attachment-result'),
      ),
    ],
  );
}

class _StatusExample extends StatefulWidget {
  const _StatusExample();
  @override
  State<_StatusExample> createState() => _StatusExampleState();
}

class _StatusExampleState extends State<_StatusExample> {
  var state = DMessageDeliveryState.pending;

  @override
  Widget build(BuildContext context) => _Conversation(
    children: [
      DMessage(
        align: DMessageAlign.end,
        children: [
          DMessageContent(
            children: [
              const DBubble(
                align: DBubbleAlign.end,
                children: [
                  DBubbleContent(child: Text('Publish the release notes.')),
                ],
              ),
              DMessageFooter(children: [DMessageStatus(state: state)]),
            ],
          ),
        ],
      ),
      const DMessage(
        children: [
          DMessageContent(
            children: [
              DBubble(
                variant: DBubbleVariant.ghost,
                children: [
                  DBubbleContent(child: Text('This message was removed.')),
                ],
              ),
              DMessageFooter(
                children: [
                  DMessageStatus(
                    state: DMessageDeliveryState.deleted,
                    liveRegion: false,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      const DMarker(
        liveRegion: true,
        child: DMarkerContent(child: Text('Checking the logs...')),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final next in DMessageDeliveryState.values)
            DButton(
              label: Text(next.name),
              onPressed: () => setState(() => state = next),
              variant: state == next
                  ? DButtonVariant.secondary
                  : DButtonVariant.outline,
              size: DButtonSize.small,
            ),
        ],
      ),
    ],
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, required this.name});
  final String label;
  final String name;

  @override
  Widget build(BuildContext context) => DAvatar(
    semanticLabel: name,
    fallback: DAvatarFallback(child: Text(label)),
  );
}
