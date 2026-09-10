import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../styleguide_example.dart';

final attachmentExamples = ComponentExamples(
  topLevelExampleIndex: 7,
  status: ComponentStatus.implemented,
  description:
      'File and image attachments with metadata, lifecycle states, actions, and full-card triggers.',
  notes:
      'Frozen base-nova Attachment composition and geometry. The host supplies palette, font, and radius. '
      'Upload work and file navigation remain caller-owned. Icon actions and full-card triggers expose separate '
      'focus and semantic nodes; touch expands controls without enlarging desktop artwork. Groups borrow or own '
      'their scroll/focus resources and support pointer drag, keyboard scrolling, edge fade, and item snapping. '
      'Image examples use the bundled app artwork so the styleguide remains deterministic and offline.',
  examples: [
    StyleguideExample(
      title: 'Composition',
      description: 'The documented icon, content, metadata, and remove action.',
      code: r'''DAttachment(
  children: [
    DAttachmentMedia(child: AttachmentExampleIcon.file()),
    DAttachmentContent(children: [
      DAttachmentTitle(child: Text('sales-dashboard.pdf')),
      DAttachmentDescription(child: Text('PDF · 2.4 MB')),
    ]),
    DAttachmentActions(children: [
      DAttachmentAction(icon: AttachmentExampleIcon.x(), tooltip: 'Remove sales-dashboard.pdf', onPressed: remove),
    ]),
  ],
)''',
      builder: (context) => const _BasicExample(),
      states: const ['default', 'hover', 'focus', 'disabled action'],
    ),
    StyleguideExample(
      title: 'Image',
      description:
          'Vertical image attachments retain separate open and remove controls.',
      code: r'''DAttachmentGroup(
  snapExtent: 108,
  children: images.map((image) => DAttachment(
    orientation: DAttachmentOrientation.vertical,
    children: [
      DAttachmentMedia(variant: DAttachmentMediaVariant.image, child: Image.asset(image.asset)),
      DAttachmentContent(children: [DAttachmentTitle(child: Text(image.name)), DAttachmentDescription(child: Text(image.meta))]),
      DAttachmentActions(children: [DAttachmentAction(icon: xIcon, tooltip: 'Remove ${image.name}', onPressed: remove)]),
      DAttachmentTrigger(semanticLabel: 'Open ${image.name}', isLink: true, onPressed: open),
    ],
  )).toList(),
)''',
      builder: (context) => const _ImageExample(),
      states: const ['image', 'vertical', 'group', 'trigger', 'action'],
    ),
    StyleguideExample(
      title: 'States',
      description:
          'Idle, uploading, processing, error, and done remain distinguishable beyond color.',
      code: r'''Column(children: [
  attachment(state: DAttachmentState.idle, description: 'Ready to upload'),
  attachment(state: DAttachmentState.uploading, description: 'Uploading · 64%'),
  attachment(state: DAttachmentState.processing, description: 'Processing document'),
  attachment(state: DAttachmentState.error, description: 'Upload failed. Try again.'),
  attachment(state: DAttachmentState.done, description: 'Uploaded · 1.8 MB'),
])''',
      builder: (context) => const _StatesExample(),
      states: const ['idle', 'uploading', 'processing', 'error', 'done'],
    ),
    StyleguideExample(
      title: 'Sizes',
      description: 'Default, small, and extra-small reference geometry.',
      code: r'''Column(children: [
  attachment(size: DAttachmentSize.regular, title: 'Default attachment', description: 'PDF · 2.4 MB'),
  attachment(size: DAttachmentSize.small, title: 'Small attachment', description: 'PDF · 2.4 MB'),
  attachment(size: DAttachmentSize.extraSmall, title: 'Extra small attachment'),
])''',
      builder: (context) => const _SizesExample(),
      states: const ['default', 'sm', 'xs'],
    ),
    StyleguideExample(
      title: 'Group',
      description:
          'Scrollable, snapping 256px cards with an edge fade and keyboard-scrolling group label.',
      code: r'''DAttachmentGroup(
  semanticLabel: 'Project attachments',
  children: items.map((item) => DAttachment(width: 256, children: attachmentParts(item))).toList(),
)''',
      builder: (context) => const _GroupExample(),
      states: const ['scroll', 'snap', 'edge fade', 'keyboard'],
    ),
    StyleguideExample(
      title: 'Trigger',
      description:
          'The card opens a dialog while Copy and Remove remain independent actions.',
      code: r'''DDialog<void>(
  trigger: DDialogTrigger(builder: (context, open) => DAttachment(
    children: [media, content, actions, DAttachmentTrigger(semanticLabel: 'Preview research-summary.pdf', onPressed: open)],
  )),
  content: DDialogContent(children: [
    DDialogHeader(children: [DDialogTitle(child: Text('research-summary.pdf')), DDialogDescription(child: Text('The card opens this preview while its actions remain independent.'))]),
  ]),
)''',
      builder: (context) => const _TriggerExample(),
      states: const ['button trigger', 'dialog', 'independent actions'],
    ),
    StyleguideExample(
      title: 'RTL and large text',
      description:
          'Directional placement, truncation, touch targets, and narrow wrapping use the live host settings.',
      code: r'''Directionality(
  textDirection: TextDirection.rtl,
  child: DAttachment(width: double.infinity, children: [media, longContent, actions, trigger]),
)''',
      builder: (context) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _BasicExample(arabic: true),
      ),
      states: const ['RTL', '200% text', 'narrow', 'truncation'],
    ),
    StyleguideExample(
      title: 'Reference demo',
      description:
          'The canonical image group, uploading document, and source-file attachment.',
      states: const ['Image group', 'Uploading', 'File', 'Actions'],
      code: r'''Column(spacing: 12, children: [
  DAttachmentGroup(children: imageAttachments),
  DAttachment(
    state: DAttachmentState.uploading,
    width: double.infinity,
    children: [
      DAttachmentMedia(child: DSpinner()),
      DAttachmentContent(children: [
        DAttachmentTitle(child: Text('sales-dashboard.pdf')),
        DAttachmentDescription(child: Text('Uploading · 64%')),
      ]),
      DAttachmentActions(children: [
        DAttachmentAction(
          tooltip: 'Cancel upload',
          icon: AttachmentExampleIcon('x'),
          onPressed: cancelUpload,
        ),
      ]),
    ],
  ),
  DAttachment(
    width: double.infinity,
    children: [
      DAttachmentMedia(child: AttachmentExampleIcon('code')),
      DAttachmentContent(children: [
        DAttachmentTitle(child: Text('message-renderer.tsx')),
        DAttachmentDescription(child: Text('TypeScript · 12 KB')),
      ]),
      DAttachmentActions(children: [
        DAttachmentAction(
          tooltip: 'Remove message-renderer.tsx',
          icon: AttachmentExampleIcon('x'),
          onPressed: removeFile,
        ),
      ]),
    ],
  ),
])''',
      builder: (_) => const _AttachmentReferenceDemo(),
    ),
  ],
);

class _AttachmentReferenceDemo extends StatefulWidget {
  const _AttachmentReferenceDemo();

  @override
  State<_AttachmentReferenceDemo> createState() =>
      _AttachmentReferenceDemoState();
}

class _AttachmentReferenceDemoState extends State<_AttachmentReferenceDemo> {
  bool _showUpload = true;
  bool _showSource = true;

  static const _images = [
    ('workspace.png', 'PNG · 820 KB'),
    ('desk-reference.jpg', 'JPG · 1.1 MB'),
    ('office-reference.jpg', 'JPG · 940 KB'),
  ];

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 384),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        DAttachmentGroup(
          children: [
            for (final image in _images)
              DAttachment(
                orientation: DAttachmentOrientation.vertical,
                children: [
                  DAttachmentMedia(
                    variant: DAttachmentMediaVariant.image,
                    semanticLabel: image.$1,
                    child: Image.asset(
                      'packages/discourse_native/src/styleguide/assets/discourse.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  DAttachmentContent(
                    children: [
                      DAttachmentTitle(child: Text(image.$1)),
                      DAttachmentDescription(child: Text(image.$2)),
                    ],
                  ),
                ],
              ),
          ],
        ),
        if (_showUpload)
          DAttachment(
            state: DAttachmentState.uploading,
            width: double.infinity,
            children: [
              const DAttachmentMedia(child: DSpinner()),
              const DAttachmentContent(
                children: [
                  DAttachmentTitle(child: Text('sales-dashboard.pdf')),
                  DAttachmentDescription(child: Text('Uploading · 64%')),
                ],
              ),
              DAttachmentActions(
                children: [
                  DAttachmentAction(
                    icon: const AttachmentExampleIcon('x'),
                    tooltip: 'Cancel upload',
                    onPressed: () => setState(() => _showUpload = false),
                  ),
                ],
              ),
            ],
          ),
        if (_showSource)
          DAttachment(
            width: double.infinity,
            children: [
              const DAttachmentMedia(child: AttachmentExampleIcon('code')),
              const DAttachmentContent(
                children: [
                  DAttachmentTitle(child: Text('message-renderer.tsx')),
                  DAttachmentDescription(child: Text('TypeScript · 12 KB')),
                ],
              ),
              DAttachmentActions(
                children: [
                  DAttachmentAction(
                    icon: const AttachmentExampleIcon('x'),
                    tooltip: 'Remove message-renderer.tsx',
                    onPressed: () => setState(() => _showSource = false),
                  ),
                ],
              ),
            ],
          ),
      ],
    ),
  );
}

class _BasicExample extends StatefulWidget {
  const _BasicExample({this.arabic = false});
  final bool arabic;

  @override
  State<_BasicExample> createState() => _BasicExampleState();
}

class _BasicExampleState extends State<_BasicExample> {
  var removed = false;

  @override
  Widget build(BuildContext context) {
    if (removed) {
      return DButton(
        label: Text(widget.arabic ? 'استعادة المرفق' : 'Restore attachment'),
        variant: DButtonVariant.outline,
        size: DButtonSize.small,
        onPressed: () => setState(() => removed = false),
      );
    }
    final title = widget.arabic
        ? 'تقرير-المبيعات-الربع-الأخير.pdf'
        : 'sales-dashboard.pdf';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 384),
      child: DAttachment(
        width: double.infinity,
        children: [
          const DAttachmentMedia(child: AttachmentExampleIcon('file')),
          DAttachmentContent(
            children: [
              DAttachmentTitle(child: Text(title)),
              DAttachmentDescription(
                child: Text(widget.arabic ? 'PDF · ٢٫٤ م.ب' : 'PDF · 2.4 MB'),
              ),
            ],
          ),
          DAttachmentActions(
            children: [
              DAttachmentAction(
                icon: const AttachmentExampleIcon('x'),
                tooltip: widget.arabic ? 'إزالة $title' : 'Remove $title',
                onPressed: () => setState(() => removed = true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImageExample extends StatefulWidget {
  const _ImageExample();

  @override
  State<_ImageExample> createState() => _ImageExampleState();
}

class _ImageExampleState extends State<_ImageExample> {
  final names = ['workspace.png', 'desk-reference.jpg', 'office-reference.jpg'];
  String status = '';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 360,
        child: DAttachmentGroup(
          snapExtent: 108,
          children: [
            for (final name in names)
              DAttachment(
                orientation: DAttachmentOrientation.vertical,
                children: [
                  DAttachmentMedia(
                    variant: DAttachmentMediaVariant.image,
                    semanticLabel: 'Preview of $name',
                    child: Image.asset(
                      'packages/discourse_native/src/styleguide/assets/discourse.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  DAttachmentContent(
                    children: [
                      DAttachmentTitle(child: Text(name)),
                      const DAttachmentDescription(child: Text('PNG · 820 KB')),
                    ],
                  ),
                  DAttachmentActions(
                    children: [
                      DAttachmentAction(
                        icon: const AttachmentExampleIcon('x'),
                        tooltip: 'Remove $name',
                        onPressed: () => setState(() {
                          names.remove(name);
                          status = '$name removed';
                        }),
                      ),
                    ],
                  ),
                  DAttachmentTrigger(
                    semanticLabel: 'Open $name',
                    isLink: true,
                    onPressed: () => setState(() => status = '$name opened'),
                  ),
                ],
              ),
          ],
        ),
      ),
      if (status.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Semantics(liveRegion: true, child: Text(status)),
        ),
    ],
  );
}

class _StatesExample extends StatefulWidget {
  const _StatesExample();

  @override
  State<_StatesExample> createState() => _StatesExampleState();
}

class _StatesExampleState extends State<_StatesExample> {
  var retrying = false;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 384),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stateRow(
          DAttachmentState.idle,
          'selected-file.pdf',
          'Ready to upload',
          'clock',
        ),
        _stateRow(
          DAttachmentState.uploading,
          'design-system.zip',
          'Uploading · 64%',
          'spinner',
        ),
        _stateRow(
          DAttachmentState.processing,
          'market-research.pdf',
          'Processing document',
          'file',
        ),
        _stateRow(
          retrying ? DAttachmentState.uploading : DAttachmentState.error,
          'financial-model.xlsx',
          retrying ? 'Retrying upload' : 'Upload failed. Try again.',
          retrying ? 'spinner' : 'warning',
          retry: !retrying,
        ),
        _stateRow(
          DAttachmentState.done,
          'uploaded-report.pdf',
          'Uploaded · 1.8 MB',
          'check',
        ),
      ],
    ),
  );

  Widget _stateRow(
    DAttachmentState state,
    String title,
    String description,
    String icon, {
    bool retry = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: DAttachment(
      width: double.infinity,
      state: state,
      liveRegion:
          state != DAttachmentState.done && state != DAttachmentState.idle,
      children: [
        DAttachmentMedia(
          child: icon == 'spinner'
              ? const DSpinner(size: 16, semanticLabel: null)
              : AttachmentExampleIcon(icon),
        ),
        DAttachmentContent(
          children: [
            DAttachmentTitle(child: Text(title)),
            DAttachmentDescription(child: Text(description)),
          ],
        ),
        DAttachmentActions(
          children: [
            if (retry)
              DAttachmentAction(
                icon: const AttachmentExampleIcon('refresh'),
                tooltip: 'Retry upload',
                onPressed: () => setState(() => retrying = true),
              ),
            DAttachmentAction(
              icon: const AttachmentExampleIcon('x'),
              tooltip: state == DAttachmentState.uploading
                  ? 'Cancel upload'
                  : 'Remove $title',
              onPressed: () {},
            ),
          ],
        ),
      ],
    ),
  );
}

class _SizesExample extends StatelessWidget {
  const _SizesExample();

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 384),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(DAttachmentSize.regular, 'Default attachment', 'PDF · 2.4 MB'),
        _row(DAttachmentSize.small, 'Small attachment', 'PDF · 2.4 MB'),
        _row(DAttachmentSize.extraSmall, 'Extra small attachment', null),
      ],
    ),
  );

  Widget _row(DAttachmentSize size, String title, String? description) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DAttachment(
          width: double.infinity,
          size: size,
          children: [
            const DAttachmentMedia(child: AttachmentExampleIcon('file')),
            DAttachmentContent(
              children: [
                DAttachmentTitle(child: Text(title)),
                if (description != null)
                  DAttachmentDescription(child: Text(description)),
              ],
            ),
          ],
        ),
      );
}

class _GroupExample extends StatelessWidget {
  const _GroupExample();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('briefing-notes.pdf', 'PDF · 1.4 MB', 'file'),
      ('workspace.png', 'PNG · 820 KB', 'image'),
      ('customers.csv', 'CSV · 18 KB', 'table'),
      ('renderer.tsx', 'TSX · 12 KB', 'code'),
    ];
    return SizedBox(
      width: 384,
      child: DAttachmentGroup(
        semanticLabel: 'Project attachments',
        children: [
          for (final item in items)
            DAttachment(
              width: 256,
              children: [
                DAttachmentMedia(
                  variant: item.$3 == 'image'
                      ? DAttachmentMediaVariant.image
                      : DAttachmentMediaVariant.icon,
                  child: item.$3 == 'image'
                      ? Image.asset(
                          'packages/discourse_native/src/styleguide/assets/discourse.png',
                          fit: BoxFit.cover,
                        )
                      : AttachmentExampleIcon(item.$3),
                ),
                DAttachmentContent(
                  children: [
                    DAttachmentTitle(child: Text(item.$1)),
                    DAttachmentDescription(child: Text(item.$2)),
                  ],
                ),
                DAttachmentActions(
                  children: [
                    DAttachmentAction(
                      icon: const AttachmentExampleIcon('x'),
                      tooltip: 'Remove ${item.$1}',
                      onPressed: () {},
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TriggerExample extends StatefulWidget {
  const _TriggerExample();

  @override
  State<_TriggerExample> createState() => _TriggerExampleState();
}

class _TriggerExampleState extends State<_TriggerExample> {
  var action = '';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 384),
        child: DDialog<void>(
          trigger: DDialogTrigger(
            builder: (context, open) => DAttachment(
              width: double.infinity,
              children: [
                const DAttachmentMedia(child: AttachmentExampleIcon('search')),
                const DAttachmentContent(
                  children: [
                    DAttachmentTitle(child: Text('research-summary.pdf')),
                    DAttachmentDescription(child: Text('Open preview dialog')),
                  ],
                ),
                DAttachmentActions(
                  children: [
                    DAttachmentAction(
                      icon: const AttachmentExampleIcon('copy'),
                      tooltip: 'Copy link',
                      onPressed: () =>
                          setState(() => action = 'Link copied locally'),
                    ),
                    DAttachmentAction(
                      icon: const AttachmentExampleIcon('x'),
                      tooltip: 'Remove research-summary.pdf',
                      onPressed: () =>
                          setState(() => action = 'Remove requested'),
                    ),
                  ],
                ),
                DAttachmentTrigger(
                  semanticLabel: 'Preview research-summary.pdf',
                  onPressed: open,
                ),
              ],
            ),
          ),
          content: const DDialogContent(
            semanticLabel: 'research-summary.pdf preview',
            children: [
              DDialogHeader(
                children: [
                  DDialogTitle(child: Text('research-summary.pdf')),
                  DDialogDescription(
                    child: Text(
                      'The attachment trigger fills the card and opens this preview, while the actions stay independently clickable.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      if (action.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Semantics(liveRegion: true, child: Text(action)),
        ),
    ],
  );
}

class AttachmentExampleIcon extends StatelessWidget {
  const AttachmentExampleIcon(this.name, {super.key});
  final String name;

  @override
  Widget build(BuildContext context) {
    final icon = switch (name) {
      'x' => '<path d="M18 6 6 18M6 6l12 12"/>',
      'clock' => '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
      'warning' =>
        '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7zM14 2v6h6M12 11v4M12 18h.01"/>',
      'check' => '<path d="M20 6 9 17l-5-5"/>',
      'refresh' =>
        '<path d="M20 6v5h-5M4 18v-5h5M18 9a7 7 0 0 0-12-2L4 11M6 15a7 7 0 0 0 12 2l2-4"/>',
      'copy' =>
        '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M15 9V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h3"/>',
      'search' =>
        '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V6zM14 2v4h4M11 13a3 3 0 1 0 0 6 3 3 0 0 0 0-6M13 18l2 2"/>',
      'table' =>
        '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 10h18M9 4v16"/>',
      'code' =>
        '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V6zM14 2v4h4M10 13l-2 2 2 2M14 13l2 2-2 2"/>',
      _ =>
        '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V6zM14 2v4h4"/>',
    };
    final size = IconTheme.of(context).size ?? 16;
    final color = IconTheme.of(context).color ?? DTokens.of(context).foreground;
    return SvgPicture.string(
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">$icon</svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
