import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final sheetExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'A Dialog-backed panel that complements the current screen from an edge.',
  notes:
      'Sheet preserves Dialog controller, typed-result, focus, nesting and '
      'dismissal ownership while matching base-nova edge geometry and motion. '
      'Physical sides remain physical in RTL; start and end are also available '
      'for native direction-aware layouts. Full-height sheets use the page '
      'surface over a darker opaque backdrop in both light and dark themes. '
      'Mobile bottom sheets dismiss with a downward touch swipe from their '
      'header or continued pulling down beyond the top of their content. '
      'Mobile bottom sheets also accept downward swipes on the empty backdrop '
      'above them. '
      'Upward movement at the bottom keeps the sheet open; '
      'dismissOnSwipe can disable downward dismissal gestures. '
      'Release before 30% of the distance to the screen bottom to restore the '
      'open position, including after a fast flick. '
      'The exit preserves release velocity, accelerating slower swipes until '
      'the sheet clears the screen. The backdrop fades with swipe progress '
      'to reveal the screen underneath and restores if the swipe is cancelled. '
      'Retained DSheetViewport surfaces enable swipes with onDismiss; the host '
      'removes the sheet after its exit or leaves it mounted to restore it. '
      'onSwipeDismissRequested instead restores the sheet as soon as the swipe '
      'reaches the dismissal threshold, then lets the host show close actions. '
      'DSheetDragRegion lets a pinned header drag independently of scrolling. '
      'Retained page sheets use DSheetVariant.page to fill their host with '
      '22px corners and a 36 by 5px overlaid handle. Set pageCorners to '
      'DSheetPageCorners.viewport for a page that reaches the bottom screen '
      'edge. Public display radii shape its lower corners, with a 64px visual '
      'approximation on compact iOS viewports with a home indicator. '
      'Its underlay is hidden '
      'at rest and excluded from input, focus and semantics while revealed. '
      'A pull beyond 120px or a downward flick dismisses the page. '
      'Adaptive menu sheets open at 55% for tall content and can be pulled '
      'to their full height. That upward gesture only expands the sheet; a '
      'subsequent gesture scrolls its content. Their 6px side margins, bottom '
      'clearance, and rounded foot follow the upward pull and settle together. '
      'They also animate to 6px side margins '
      'and float above the home indicator at the end of their content, for short '
      'content, or above the system keyboard. Margins remain until the sheet '
      'is closed. '
      'The scroll viewport extends through the bottom safe area. '
      'Set sizeToContent: false to keep a 55% opening viewport through '
      'asynchronous loading and result changes, and contentLoading: true '
      'while waiting so placeholders do not trigger short-content margins. '
      'Other snap-point compositions use Drawer.',
  examples: [
    StyleguideExample(
      title: 'Retained reading page',
      description:
          'A page sheet below application chrome. Pull down from the handle '
          'or the top of the reader to return to the previous page.',
      code:
          'DSheetViewport(onDismiss: closePage, underlay: previousPage, '
          'content: DSheetContent(side: DSheetSide.bottom, '
          'variant: DSheetVariant.page, pageCorners: DSheetPageCorners.viewport, '
          'showCloseButton: false, '
          'children: [Expanded(child: reader)]))',
      builder: (_) => const _PageSheetExample(),
      states: const ['open', 'pull', 'cancel', 'dismissed'],
    ),
    StyleguideExample(
      title: 'Adaptive menu sheet',
      description:
          'Pull upward to expand with floating margins and a rounded foot. '
          'Reserve a stable opening height for asynchronous results. '
          'The same surface floats above a visible keyboard.',
      code:
          'DSheetContent(variant: DSheetVariant.adaptiveMenu, sizeToContent: false, side: DSheetSide.bottom, showCloseButton: false, scrollWholeSheet: false, children: [Flexible(child: menu)])',
      builder: (_) => DSheet<void>(
        trigger: DSheetTrigger(
          builder: (context, open) => _trigger('Open adaptive menu', open),
        ),
        content: DSheetContent(
          variant: DSheetVariant.adaptiveMenu,
          sizeToContent: false,
          side: DSheetSide.bottom,
          showCloseButton: false,
          scrollWholeSheet: false,
          children: [
            Flexible(
              child: DScrollArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < 30; index++)
                      DButton(
                        label: Text('Option ${index + 1}'),
                        onPressed: () {},
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      states: const [
        'collapsed',
        'expanded',
        'scroll end',
        'keyboard',
        'reduced motion',
      ],
    ),
    StyleguideExample(
      title: 'Mobile menu sheet',
      description:
          'An inset menu with a visible grab handle above the home indicator. Swipe down to dismiss.',
      code:
          'DSheetContent(variant: DSheetVariant.menu, side: DSheetSide.bottom, inset: true, showCloseButton: false, children: [body])',
      builder: (_) => DSheet<void>(
        trigger: DSheetTrigger(
          builder: (context, open) => _trigger('Open menu sheet', open),
        ),
        content: const DSheetContent(
          variant: DSheetVariant.menu,
          side: DSheetSide.bottom,
          inset: true,
          showCloseButton: false,
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('A compact menu over the current page.'),
            ),
          ],
        ),
      ),
      states: const ['safe area', 'swipe', 'outside dismissal'],
    ),
    StyleguideExample(
      title: 'Behind the keyboard',
      description:
          'A rounded sheet over a darker opaque background. The content scrolls '
          'behind the system keyboard; bottom scroll padding keeps the final '
          'field reachable above it.',
      code: '''DSheetContent(
  side: DSheetSide.bottom,
  fillAvailableHeight: true,
  extendBehindKeyboard: true,
  scrollWholeSheet: false,
  children: [Expanded(child: scrollableEditor)],
)''',
      builder: (_) => DSheet<void>(
        trigger: DSheetTrigger(
          builder: (context, open) => _trigger('Open writing sheet', open),
        ),
        content: DSheetContent(
          side: DSheetSide.bottom,
          fillAvailableHeight: true,
          extendBehindKeyboard: true,
          scrollWholeSheet: false,
          children: [
            Expanded(
              child: Builder(
                builder: (context) => SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    DSpacing.lg,
                    DSpacing.xxl,
                    DSpacing.lg,
                    MediaQuery.viewInsetsOf(context).bottom +
                        MediaQuery.paddingOf(context).bottom +
                        DSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const DSheetHeader(
                        children: [DSheetTitle(child: Text('Write a draft'))],
                      ),
                      for (var index = 0; index < 12; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: DSpacing.lg),
                          child: DInput(
                            semanticLabel: 'Paragraph ${index + 1}',
                            hintText: 'Paragraph ${index + 1}',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      states: const ['keyboard', 'scrolling', 'opaque backdrop'],
    ),
    StyleguideExample(
      title: 'Centered reading panel',
      description:
          'A full-height inset panel using the page background, centered within its workspace.',
      code:
          'DSheetContent(backgroundColor: DTokens.of(context).background, side: DSheetSide.center, inset: true, children: [body])',
      builder: (context) => DSheet<void>(
        trigger: DSheetTrigger(
          builder: (context, open) => _trigger('Open centered sheet', open),
        ),
        content: DSheetContent(
          backgroundColor: DTokens.of(context).background,
          side: DSheetSide.center,
          inset: true,
          children: const [
            DSheetHeader(
              children: [DSheetTitle(child: Text('Centered reader'))],
            ),
            DSheetBody(
              child: Text('The panel stays centered as the workspace changes.'),
            ),
          ],
        ),
      ),
    ),
    StyleguideExample(
      title: 'Side accessory',
      description:
          'Centered navigation keeps a reserved gutter outside the sheet surface, including at the first and last item.',
      code: "DSheetContent(inset: true,   children: [body])",
      builder: (_) => const _AccessorySheet(),
      states: const ['navigation', 'disabled', 'focus', 'reserved space'],
    ),
    StyleguideExample(
      title: 'Non-modal',
      description:
          'Open the sheet, then click or type in the exposed background. Outside clicks leave it open; use Close or Escape from the sheet to dismiss it.',
      code:
          "DSheet<void>(\n  \n  trigger: trigger,\n  content: DSheetContent(\n    inset: true,\n    children: [header, DSheetBody(child: editor)],\n  ),\n)",
      builder: (_) => const _NonModalSheet(),
      states: const ['background interaction', 'retained input', 'focus'],
    ),
    StyleguideExample(
      title: 'Edit profile',
      description:
          'Frozen default right-side form with local Form validation and typed save.',
      code: _profileCode,
      builder: (_) => const _ProfileSheet(),
      states: const ['open', 'focused', 'invalid', 'submitting', 'saved'],
    ),
    StyleguideExample(
      title: 'Side',
      description:
          'The documented long content on the top, right, bottom and left physical sides.',
      code: _sideCode,
      builder: (_) => const _SideSheets(),
      states: const ['top', 'right', 'bottom', 'left'],
    ),
    StyleguideExample(
      title: 'Scrollable body',
      description:
          'Long complementary content scrolls independently without moving the header or actions.',
      code: _scrollableCode,
      builder: (_) => const _ScrollableSheet(),
      states: const ['long content', 'fixed header', 'fixed footer'],
    ),
    StyleguideExample(
      title: 'No Close Button',
      description:
          'The compact corner X is omitted; outside click and Escape still close.',
      code: _noCloseCode,
      builder: (_) => const _NoCloseSheet(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic form on the documented physical left side. The registry close remains physically right.',
      code: _rtlCode,
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _ProfileSheet(arabic: true),
      ),
      states: const ['RTL', 'physical side', 'logical text'],
    ),
    StyleguideExample(
      title: 'Controlled and typed result',
      description:
          'External state observes dismissal reasons; the imperative helper returns a typed value.',
      code: _controlledCode,
      builder: (_) => const _ControlledSheet(),
      states: const ['controlled', 'typed result', 'dismissal policy'],
    ),
    StyleguideExample(
      title: 'Inset and expanding',
      description:
          'An opt-in floating sheet keeps its content mounted as its width changes. Reduced motion disables resizing animation.',
      code:
          "DSheet<void>(\n  trigger: trigger,\n  content: DSheetContent(\n    inset: true,\n    \n    sidePanelWidth: expanded ? 700 : 400,\n    sidePanelMaxWidth: 900,\n    children: [header, DSheetBody(child: editor)],\n  ),\n)",
      builder: (_) => const _ExpandingSheet(),
      states: const ['reading', 'expanded', 'retained input', 'reduced motion'],
    ),
  ],
);

class _PageSheetExample extends StatefulWidget {
  const _PageSheetExample();

  @override
  State<_PageSheetExample> createState() => _PageSheetExampleState();
}

class _PageSheetExampleState extends State<_PageSheetExample> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final previous = DPageSurface(
      child: Center(
        child: DButton(
          label: const Text('Open reading page'),
          onPressed: () => setState(() => _open = true),
        ),
      ),
    );
    return SizedBox(
      height: 420,
      child: _open
          ? DSheetViewport(
              onDismiss: () => setState(() => _open = false),
              underlay: previous,
              content: DSheetContent(
                side: DSheetSide.bottom,
                variant: DSheetVariant.page,
                pageCorners: DSheetPageCorners.viewport,
                semanticLabel: 'Reading page',
                showCloseButton: false,
                children: [
                  Expanded(
                    child: DScrollArea(
                      child: Padding(
                        padding: const EdgeInsets.all(DSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: DSpacing.lg,
                          children: [
                            const Text('A community discussion'),
                            DButton(
                              label: const Text('Close reading page'),
                              onPressed: () => setState(() => _open = false),
                            ),
                            for (var i = 1; i <= 20; i++)
                              Text('Post $i in the discussion.'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : previous,
    );
  }
}

class _NonModalSheet extends StatefulWidget {
  const _NonModalSheet();

  @override
  State<_NonModalSheet> createState() => _NonModalSheetState();
}

class _NonModalSheetState extends State<_NonModalSheet> {
  int _clicks = 0;

  @override
  Widget build(BuildContext context) => DSheet<void>(
    trigger: DSheetTrigger(
      builder: (_, open) => Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DSpacing.md,
            children: [
              DButton(
                onPressed: open,
                label: const Text('Open non-modal sheet'),
              ),
              DButton(
                onPressed: () => setState(() => _clicks++),
                variant: DButtonVariant.outline,
                label: Text('Background clicks: $_clicks'),
              ),
              DInput(
                semanticLabel: 'Background input',
                hintText: 'Type here while the sheet is open',
              ),
            ],
          ),
        ),
      ),
    ),
    content: DSheetContent(
      inset: true,
      children: [
        const DSheetHeader(
          children: [DSheetTitle(child: Text('Keep the background available'))],
        ),
        DSheetBody(
          child: DInput(
            semanticLabel: 'Sheet input',
            hintText: 'This draft stays while you use the background',
          ),
        ),
      ],
    ),
  );
}

class _ExpandingSheet extends StatefulWidget {
  const _ExpandingSheet();
  @override
  State<_ExpandingSheet> createState() => _ExpandingSheetState();
}

class _ExpandingSheetState extends State<_ExpandingSheet> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => DSheet<void>(
    trigger: DSheetTrigger(
      builder: (_, open) => DButton(
        onPressed: open,
        variant: DButtonVariant.outline,
        label: const Text('Open expanding sheet'),
      ),
    ),
    content: DSheetContent(
      inset: true,

      sidePanelWidth: _expanded ? 700 : 400,
      sidePanelMaxWidth: 900,
      children: [
        const DSheetHeader(
          children: [DSheetTitle(child: Text('Conversation'))],
        ),
        DSheetBody(
          child: DInput(
            semanticLabel: 'Retained draft',
            hintText: 'Type, then change the sheet width…',
          ),
        ),
        DSheetFooter(
          children: [
            DButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              label: Text(_expanded ? 'Reading width' : 'Expand for reply'),
            ),
          ],
        ),
      ],
    ),
  );
}

const _profileCode = '''DSheet<String>(
  controller: controller,
  trigger: DSheetTrigger(builder: (context, open) =>
    DButton(onPressed: open, variant: DButtonVariant.outline,
      label: const Text('Open Sheet'))),
  content: DSheetContent(children: [
    const DSheetHeader(children: [
      DSheetTitle(child: Text('Edit profile')),
      DSheetDescription(child: Text('Make changes to your profile here. Click save when you’re done.')),
    ]),
    DSheetBody(child: DFieldGroup(children: profileFields)),
    DSheetFooter(children: [
      DButton(onPressed: () => controller.submit(save), label: const Text('Save changes')),
      DSheetClose<String>(builder: closeButton),
    ]),
  ]),
)''';

const _sideCode = '''for (final side in const [
  DSheetSide.top, DSheetSide.right, DSheetSide.bottom, DSheetSide.left,
]) DSheet<void>(
  trigger: sideButton,
  content: DSheetContent(
    side: side,
    topBottomMaxHeightFactor: side == DSheetSide.top || side == DSheetSide.bottom
        ? .5
        : null,
    children: [header, DSheetBody(child: longContent), footer],
  ),
)''';

const _scrollableCode = '''DSheet<void>(
  trigger: trigger,
  content: DSheetContent(children: [
    header,
    DSheetBody(child: longContent),
    footer,
  ]),
)''';

const _noCloseCode = '''DSheet<void>(
  trigger: trigger,
  content: DSheetContent(showCloseButton: false, children: [
    DSheetHeader(children: [
      DSheetTitle(child: Text('No Close Button')),
      DSheetDescription(child: Text('Click outside to close.')),
    ]),
  ]),
)''';

const _rtlCode = '''Directionality(
  textDirection: TextDirection.rtl,
  child: DSheet<void>(
    trigger: arabicTrigger,
    content: DSheetContent(side: DSheetSide.left, children: arabicForm),
  ),
)''';

const _controlledCode = '''DSheet<String>(
  open: open,
  onOpenChanged: (details) => setState(() {
    open = details.open;
    lastReason = details.reason;
  }),
  trigger: trigger,
  content: contentWithTypedDSheetClose,
)

final result = await showDSheet<String>(
  context: context,
  builder: (_, controller) => typedContent,
);''';

Widget _trigger(String label, VoidCallback open) => DButton(
  onPressed: open,
  variant: DButtonVariant.outline,
  label: Text(label),
  hasPopup: true,
);

Widget _closeButton(BuildContext context, VoidCallback close) => DButton(
  onPressed: close,
  variant: DButtonVariant.outline,
  label: const Text('Close'),
);

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet({this.arabic = false});

  final bool arabic;

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'Pedro Duarte');
  final _username = TextEditingController(text: '@peduarte');
  final _controller = DSheetController<String>();
  String _status = '';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final result = await _save();
      if (mounted && _controller.isOpen) _controller.close(result);
    } on FormatException {
      // The form displays its own validation errors.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String> _save() async {
    if (!_form.currentState!.validate()) throw const FormatException('invalid');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (mounted) {
      setState(
        () => _status = widget.arabic ? 'تم الحفظ محلياً' : 'Saved locally',
      );
    }
    return _name.text;
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.arabic;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DSheet<String>(
          controller: _controller,
          trigger: DSheetTrigger(
            builder: (context, open) =>
                _trigger(ar ? 'فتح' : 'Open Sheet', open),
          ),
          content: DSheetContent(
            side: ar ? DSheetSide.left : DSheetSide.right,
            semanticLabel: ar ? 'تعديل الملف الشخصي' : 'Edit profile',
            children: [
              DSheetHeader(
                children: [
                  DSheetTitle(
                    child: Text(ar ? 'تعديل الملف الشخصي' : 'Edit profile'),
                  ),
                  DSheetDescription(
                    child: Text(
                      ar
                          ? 'قم بإجراء تغييرات على ملفك الشخصي هنا. انقر حفظ عند الانتهاء.'
                          : 'Make changes to your profile here. Click save when you’re done.',
                    ),
                  ),
                ],
              ),
              DSheetBody(
                child: Form(
                  key: _form,
                  child: DFieldGroup(
                    children: [
                      DField(
                        children: [
                          DInput(
                            controller: _name,
                            labelText: ar ? 'الاسم' : 'Name',
                            validator: (value) =>
                                (value?.trim().isEmpty ?? true)
                                ? (ar ? 'الاسم مطلوب' : 'Name is required')
                                : null,
                          ),
                        ],
                      ),
                      DField(
                        children: [
                          DInput(
                            controller: _username,
                            labelText: ar ? 'اسم المستخدم' : 'Username',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => DSheetFooter(
                  children: [
                    DButton(
                      onPressed: _saving ? null : () => unawaited(_submit()),
                      loading: _saving,
                      label: Text(ar ? 'حفظ التغييرات' : 'Save changes'),
                    ),
                    DSheetClose<String>(
                      builder: (context, close) => DButton(
                        onPressed: close,
                        variant: DButtonVariant.outline,
                        label: Text(ar ? 'إغلاق' : 'Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_status.isNotEmpty) ...[const SizedBox(height: 8), Text(_status)],
      ],
    );
  }
}

class _SideSheets extends StatelessWidget {
  const _SideSheets();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final side in const [
        DSheetSide.top,
        DSheetSide.right,
        DSheetSide.bottom,
        DSheetSide.left,
      ])
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) => _trigger(side.name, open),
          ),
          content: DSheetContent(
            side: side,
            topBottomMaxHeightFactor:
                side == DSheetSide.top || side == DSheetSide.bottom ? .5 : null,
            semanticLabel: '${side.name} sheet',
            children: [
              const DSheetHeader(
                children: [
                  DSheetTitle(child: Text('Edit profile')),
                  DSheetDescription(
                    child: Text(
                      'Make changes to your profile here. Click save when you’re done.',
                    ),
                  ),
                ],
              ),
              DSheetBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < 10; index++) ...[
                      if (index > 0) const SizedBox(height: 8),
                      const Text(
                        'Lorem ipsum dolor sit amet, consectetur adipiscing '
                        'elit. Sed do eiusmod tempor incididunt ut labore et '
                        'dolore magna aliqua. Ut enim ad minim veniam, quis '
                        'nostrud exercitation ullamco laboris nisi ut aliquip '
                        'ex ea commodo consequat. Duis aute irure dolor in '
                        'reprehenderit in voluptate velit esse cillum dolore '
                        'eu fugiat nulla pariatur. Excepteur sint occaecat '
                        'cupidatat non proident, sunt in culpa qui officia '
                        'deserunt mollit anim id est laborum.',
                      ),
                    ],
                  ],
                ),
              ),
              DSheetFooter(
                children: [
                  DButton(onPressed: () {}, label: const Text('Save changes')),
                  DSheetClose<void>(
                    builder: (context, close) => DButton(
                      onPressed: close,
                      variant: DButtonVariant.outline,
                      label: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
    ],
  );
}

class _ScrollableSheet extends StatelessWidget {
  const _ScrollableSheet();

  @override
  Widget build(BuildContext context) => DSheet<void>(
    trigger: DSheetTrigger(
      builder: (context, open) => _trigger('Open long sheet', open),
    ),
    content: DSheetContent(
      semanticLabel: 'Scrollable sheet',
      children: [
        const DSheetHeader(
          children: [
            DSheetTitle(child: Text('Scrollable body')),
            DSheetDescription(
              child: Text('The header and footer remain fixed.'),
            ),
          ],
        ),
        DSheetBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < 14; index++) ...[
                if (index > 0) const SizedBox(height: 8),
                Text(
                  'Section ${index + 1}: complementary details remain reachable.',
                ),
              ],
            ],
          ),
        ),
        const DSheetFooter(
          children: [DSheetClose<void>(builder: _closeButton)],
        ),
      ],
    ),
  );
}

class _NoCloseSheet extends StatelessWidget {
  const _NoCloseSheet();

  @override
  Widget build(BuildContext context) => DSheet<void>(
    trigger: DSheetTrigger(
      builder: (context, open) => _trigger('Open Sheet', open),
    ),
    content: const DSheetContent(
      showCloseButton: false,
      semanticLabel: 'No Close Button',
      children: [
        DSheetHeader(
          children: [
            DSheetTitle(child: Text('No Close Button')),
            DSheetDescription(
              child: Text(
                'This sheet doesn’t have a close button in the top-right corner. Click outside to close.',
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ControlledSheet extends StatefulWidget {
  const _ControlledSheet();

  @override
  State<_ControlledSheet> createState() => _ControlledSheetState();
}

class _ControlledSheetState extends State<_ControlledSheet> {
  bool _open = false;
  String _status = 'Closed';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DSheet<String>(
            open: _open,
            onOpenChanged: (details) => setState(() {
              _open = details.open;
              _status = details.open
                  ? 'Opened: ${details.reason.name}'
                  : 'Closed: ${details.reason.name} ${details.result ?? ''}'
                        .trim();
            }),
            trigger: DSheetTrigger(
              builder: (context, open) => _trigger('Controlled', open),
            ),
            content: DSheetContent(
              side: DSheetSide.start,
              semanticLabel: 'Controlled sheet',
              children: [
                const DSheetHeader(
                  children: [DSheetTitle(child: Text('Controlled sheet'))],
                ),
                DSheetFooter(
                  children: [
                    DSheetClose<String>(
                      builder: (context, close) => DButton(
                        onPressed: close,
                        label: const Text('Return result'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          DButton(
            onPressed: () async {
              final result = await showDSheet<String>(
                context: context,
                side: DSheetSide.end,
                builder: (context, controller) => DSheetContent(
                  side: DSheetSide.end,
                  semanticLabel: 'Typed helper',
                  children: [
                    const DSheetHeader(
                      children: [DSheetTitle(child: Text('Typed helper'))],
                    ),
                    DSheetFooter(
                      children: [
                        DSheetClose<String>(
                          builder: (context, close) => DButton(
                            onPressed: close,
                            label: const Text('Return helper result'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
              if (mounted) setState(() => _status = result ?? 'Dismissed');
            },
            variant: DButtonVariant.outline,
            label: const Text('Typed helper'),
            hasPopup: true,
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(_status),
    ],
  );
}

class _AccessorySheet extends StatefulWidget {
  const _AccessorySheet();

  @override
  State<_AccessorySheet> createState() => _AccessorySheetState();
}

class _AccessorySheetState extends State<_AccessorySheet> {
  final int _index = 0;

  @override
  Widget build(BuildContext context) => DSheet<void>(
    trigger: DSheetTrigger(
      builder: (context, open) =>
          DButton(label: const Text('Open with navigation'), onPressed: open),
    ),
    content: DSheetContent(
      inset: true,
      sidePanelWidth: 500,
      sidePanelMaxWidth: 500,

      children: [
        DSheetHeader(
          children: [DSheetTitle(child: Text('Item ${_index + 1} of 3'))],
        ),
        const DSheetBody(
          child: Text(
            'Move between items with the arrows beside this sheet. Both controls keep their place at either end.',
          ),
        ),
      ],
    ),
  );
}
