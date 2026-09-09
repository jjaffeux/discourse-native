import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final sheetExamples = ComponentExamples(
  status: ComponentStatus.baseline,
  description:
      'A Dialog-backed panel that complements the current screen from an edge.',
  notes:
      'Sheet preserves Dialog controller, typed-result, focus, nesting and '
      'dismissal ownership while matching base-nova edge geometry and motion. '
      'Physical sides remain physical in RTL; start and end are also available '
      'for native direction-aware layouts. Swipe handles, detents and snap '
      'points belong to Drawer.',
  examples: [
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
          'The documented top, right, bottom and left physical sides. Long content scrolls without moving its actions.',
      code: _sideCode,
      builder: (_) => const _SideSheets(),
      states: const ['top', 'right', 'bottom', 'left', 'scrollable'],
    ),
    StyleguideExample(
      title: 'No Close Button',
      description:
          'The compact corner X is omitted; outside click, Escape and the explicit action still close.',
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
  ],
);

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
    topBottomMaxHeightFactor: .5,
    children: [header, DSheetBody(child: longContent), footer],
  ),
)''';

const _noCloseCode = '''DSheet<void>(
  trigger: trigger,
  content: DSheetContent(showCloseButton: false, children: [
    DSheetHeader(children: [
      DSheetTitle(child: Text('No Close Button')),
      DSheetDescription(child: Text('Click outside to close.')),
    ]),
    DSheetFooter(children: [DSheetClose<void>(builder: closeButton)]),
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

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _controller.dispose();
    super.dispose();
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
                      onPressed: _controller.isBusy
                          ? null
                          : () => unawaited(
                              _controller
                                  .submit(_save)
                                  .catchError((Object _) => null),
                            ),
                      loading: _controller.isBusy,
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
            topBottomMaxHeightFactor: .5,
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
                        'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
                        'Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.',
                      ),
                    ],
                  ],
                ),
              ),
              DSheetFooter(
                children: [
                  DButton(onPressed: () {}, label: const Text('Save changes')),
                  const DSheetClose<void>(builder: _closeButton),
                ],
              ),
            ],
          ),
        ),
    ],
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
        DSheetFooter(children: [DSheetClose<void>(builder: _closeButton)]),
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
                      result: 'accepted',
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
                          result: 'helper result',
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
