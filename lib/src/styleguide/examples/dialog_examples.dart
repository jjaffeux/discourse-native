import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final dialogExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'A focused modal window that makes the content underneath inert.',
  notes:
      'The public parts reproduce the frozen base-nova Dialog composition. '
      'Routes use the nearest Navigator unless useRootNavigator is requested, '
      'return typed results, trap and restore focus, and retain live preview '
      'theme, direction, text scale and reduced-motion updates. Forms compose '
      'the shared DInput owner while richer Field layouts remain separately '
      'owned by their catalogue task. Dialog owns neither form '
      'validation nor asynchronous persistence.',
  examples: [
    StyleguideExample(
      title: 'Edit profile',
      description:
          'Frozen default composition with local Form validation and async save.',
      code: _profileCode,
      builder: (_) => const _ProfileDialog(),
      states: const ['open', 'focused', 'invalid', 'submitting', 'saved'],
    ),
    StyleguideExample(
      title: 'Custom Close Button',
      description:
          'The default corner X remains while the footer uses a composed close action.',
      code: _customCloseCode,
      builder: (_) => const _CustomCloseDialog(),
    ),
    StyleguideExample(
      title: 'No Close Button',
      description:
          'Hides the corner control. Escape, backdrop and the explicit footer action remain usable.',
      code: _noCloseCode,
      builder: (_) => const _NoCloseDialog(),
    ),
    StyleguideExample(
      title: 'Sticky Footer',
      description:
          'A 50vh inner region scrolls independently while footer actions stay visible.',
      code: _stickyCode,
      builder: (_) => const _LongDialog(stickyFooter: true),
    ),
    StyleguideExample(
      title: 'Scrollable Content',
      description:
          'Long inner content scrolls with the title and description fixed.',
      code: _scrollableCode,
      builder: (_) => const _LongDialog(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic copy, logical close placement and responsive footer order.',
      code: _rtlCode,
      builder: (_) => const DDirection(
        textDirection: TextDirection.rtl,
        child: _ProfileDialog(arabic: true),
      ),
    ),
    StyleguideExample(
      title: 'Controlled and typed result',
      description:
          'External state observes trigger, Escape, barrier and close reasons; the helper returns a typed result.',
      code: _controlledCode,
      builder: (_) => const _ControlledDialog(),
      states: const ['controlled', 'typed result', 'dismissal policy'],
    ),
  ],
);

const _profileCode = '''DDialog<String>(
  controller: controller,
  trigger: DDialogTrigger(builder: (context, open) =>
    DButton(onPressed: open, variant: DButtonVariant.outline,
      label: const Text('Open Dialog'))),
  content: DDialogContent(children: [
    const DDialogHeader(children: [
      DDialogTitle(child: Text('Edit profile')),
      DDialogDescription(child: Text('Make changes to your profile here. Click save when you’re done.')),
    ]),
    Form(key: formKey, child: profileFields),
    DDialogFooter(children: [
      DDialogClose<String>(builder: closeButton),
      DButton(onPressed: () => controller.submit(save), label: const Text('Save changes')),
    ]),
  ]),
)''';

const _customCloseCode = '''DDialog<void>(
  trigger: DDialogTrigger(builder: (context, open) =>
    DButton(onPressed: open, variant: DButtonVariant.outline, label: const Text('Share'))),
  content: DDialogContent(children: [
    const DDialogHeader(children: [DDialogTitle(child: Text('Share link')),
      DDialogDescription(child: Text('Anyone who has this link will be able to view this.'))]),
    readOnlyLinkField,
    DDialogFooter(wideAlignment: WrapAlignment.start,
      children: [DDialogClose<void>(builder: closeButton)]),
  ]),
)''';

const _noCloseCode = '''DDialog<void>(
  trigger: trigger,
  content: DDialogContent(showCloseButton: false, children: [
    DDialogHeader(children: [DDialogTitle(child: Text('No Close Button')),
      DDialogDescription(child: Text('This dialog doesn’t have a close button in the top-right corner.'))]),
  ]),
)''';

const _stickyCode = '''DDialogContent(children: [
  header,
  DDialogScrollArea(child: longContent),
  DDialogFooter(children: [DDialogClose<void>(builder: closeButton)]),
])''';

const _scrollableCode = '''DDialogContent(children: [
  header,
  DDialogScrollArea(child: longContent),
])''';

const _rtlCode = '''DDirection(
  textDirection: TextDirection.rtl,
  child: profileDialogWithArabicLabels,
)''';

const _controlledCode = '''DDialog<String>(
  open: open,
  onOpenChanged: (details) => setState(() {
    open = details.open;
    lastReason = details.reason;
  }),
  trigger: trigger,
  content: contentWithDDialogCloseResult,
)

final result = await showDDialog<String>(context: context,
  builder: (_, controller) => typedContent);''';

Widget _trigger(String label, VoidCallback open) => DButton(
  onPressed: open,
  variant: DButtonVariant.outline,
  label: Text(label),
  hasPopup: true,
);

Widget _closeButton(BuildContext context, VoidCallback close) => DButton(
  onPressed: close,
  variant: DButtonVariant.outline,
  label: const Text('Cancel'),
);

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({this.arabic = false});
  final bool arabic;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'Pedro Duarte');
  final _username = TextEditingController(text: '@peduarte');
  final _controller = DDialogController<String>();
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
    await Future<void>.delayed(const Duration(milliseconds: 500));
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
        DDialog<String>(
          controller: _controller,
          trigger: DDialogTrigger(
            builder: (context, open) =>
                _trigger(ar ? 'فتح الحوار' : 'Open Dialog', open),
          ),
          content: DDialogContent(
            semanticLabel: ar ? 'تعديل الملف الشخصي' : 'Edit profile',
            children: [
              DDialogHeader(
                children: [
                  DDialogTitle(
                    child: Text(ar ? 'تعديل الملف الشخصي' : 'Edit profile'),
                  ),
                  DDialogDescription(
                    child: Text(
                      ar
                          ? 'قم بإجراء تغييرات على ملفك الشخصي هنا. انقر فوق حفظ عند الانتهاء.'
                          : 'Make changes to your profile here. Click save when you’re done.',
                    ),
                  ),
                ],
              ),
              Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DInput(
                      controller: _name,
                      labelText: ar ? 'الاسم' : 'Name',
                      hintText: ar ? 'الاسم' : 'Name',
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? (ar ? 'الاسم مطلوب' : 'Name is required')
                          : null,
                    ),
                    const SizedBox(height: 16),
                    DInput(
                      controller: _username,
                      labelText: ar ? 'اسم المستخدم' : 'Username',
                      hintText: ar ? 'اسم المستخدم' : 'Username',
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => DDialogFooter(
                  children: [
                    const DDialogClose<String>(builder: _closeButton),
                    DButton(
                      onPressed: _controller.isBusy
                          ? null
                          : () {
                              unawaited(
                                _controller
                                    .submit(_save)
                                    .catchError((Object _) => null),
                              );
                            },
                      loading: _controller.isBusy,
                      label: Text(ar ? 'حفظ التغييرات' : 'Save changes'),
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

class _CustomCloseDialog extends StatelessWidget {
  const _CustomCloseDialog();

  @override
  Widget build(BuildContext context) => DDialog<void>(
    trigger: DDialogTrigger(
      builder: (context, open) => _trigger('Share', open),
    ),
    content: DDialogContent(
      maxWidth: 448,
      semanticLabel: 'Share link',
      children: [
        const DDialogHeader(
          children: [
            DDialogTitle(child: Text('Share link')),
            DDialogDescription(
              child: Text(
                'Anyone who has this link will be able to view this.',
              ),
            ),
          ],
        ),
        DInput(
          readOnly: true,
          labelText: 'Link',
          initialValue: 'https://example.com/docs/installation',
        ),
        DDialogFooter(
          wideAlignment: WrapAlignment.start,
          children: [
            DDialogClose<void>(
              builder: (context, close) =>
                  DButton(onPressed: close, label: const Text('Close')),
            ),
          ],
        ),
      ],
    ),
  );
}

class _NoCloseDialog extends StatelessWidget {
  const _NoCloseDialog();

  @override
  Widget build(BuildContext context) => DDialog<void>(
    trigger: DDialogTrigger(
      builder: (context, open) => _trigger('No Close Button', open),
    ),
    content: const DDialogContent(
      showCloseButton: false,
      semanticLabel: 'No Close Button',
      children: [
        DDialogHeader(
          children: [
            DDialogTitle(child: Text('No Close Button')),
            DDialogDescription(
              child: Text(
                'This dialog doesn’t have a close button in the top-right corner.',
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _LongDialog extends StatelessWidget {
  const _LongDialog({this.stickyFooter = false});
  final bool stickyFooter;

  @override
  Widget build(BuildContext context) => DDialog<void>(
    trigger: DDialogTrigger(
      builder: (context, open) =>
          _trigger(stickyFooter ? 'Sticky Footer' : 'Scrollable Content', open),
    ),
    content: DDialogContent(
      semanticLabel: stickyFooter ? 'Sticky Footer' : 'Scrollable Content',
      children: [
        DDialogHeader(
          children: [
            DDialogTitle(
              child: Text(
                stickyFooter ? 'Sticky Footer' : 'Scrollable Content',
              ),
            ),
            DDialogDescription(
              child: Text(
                stickyFooter
                    ? 'This dialog has a sticky footer that stays visible while the content scrolls.'
                    : 'This is a dialog with scrollable content.',
              ),
            ),
          ],
        ),
        DDialogScrollArea(
          child: Column(
            children: List.generate(
              10,
              (index) => const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.',
                ),
              ),
            ),
          ),
        ),
        if (stickyFooter)
          DDialogFooter(
            children: [
              DDialogClose<void>(
                builder: (context, close) => DButton(
                  onPressed: close,
                  variant: DButtonVariant.outline,
                  label: const Text('Close'),
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class _ControlledDialog extends StatefulWidget {
  const _ControlledDialog();

  @override
  State<_ControlledDialog> createState() => _ControlledDialogState();
}

class _ControlledDialogState extends State<_ControlledDialog> {
  bool _open = false;
  String _status = 'Closed';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DDialog<String>(
        open: _open,
        onOpenChanged: (details) => setState(() {
          _open = details.open;
          _status = details.open
              ? 'Opened by ${details.reason.name}'
              : 'Closed by ${details.reason.name}${details.result == null ? '' : ': ${details.result}'}';
        }),
        trigger: DDialogTrigger(
          builder: (context, open) => _trigger('Open controlled dialog', open),
        ),
        content: DDialogContent(
          semanticLabel: 'Choose a result',
          children: [
            const DDialogHeader(
              children: [
                DDialogTitle(child: Text('Choose a result')),
                DDialogDescription(
                  child: Text(
                    'The typed result is returned to external state.',
                  ),
                ),
              ],
            ),
            DDialogFooter(
              children: [
                DDialogClose<String>(
                  result: 'Accepted',
                  builder: (context, close) =>
                      DButton(onPressed: close, label: const Text('Accept')),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(_status),
      const SizedBox(height: 8),
      DButton(
        onPressed: () async {
          final result = await showDDialog<String>(
            context: context,
            builder: (_, controller) => DDialogContent(
              semanticLabel: 'Helper dialog',
              children: [
                const DDialogTitle(child: Text('Helper dialog')),
                DDialogClose<String>(
                  result: 'Helper result',
                  builder: (context, close) => DButton(
                    onPressed: close,
                    label: const Text('Return result'),
                  ),
                ),
              ],
            ),
          );
          if (mounted) setState(() => _status = 'Helper returned: $result');
        },
        variant: DButtonVariant.secondary,
        label: const Text('Use showDDialog'),
      ),
    ],
  );
}
