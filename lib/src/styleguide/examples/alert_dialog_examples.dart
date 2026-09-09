import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../styleguide_example.dart';

final alertDialogExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'A focused confirmation flow that interrupts the user and requires an explicit response.',
  notes:
      'Covers the frozen base-nova Composition, Basic, Small, Media, Small with Media, Destructive and RTL sections. '
      'The native route replaces Portal, Backdrop and Viewport while preserving their modal, focus-containment and live-environment responsibilities. '
      'Outside presses never dismiss; Escape is an explicit cancel path. There is intentionally no Dialog corner close. '
      'Default content grows from 320 to 384 logical pixels at 640px; small remains 320px. '
      'Footer controls are real DButton owners and keep cancel first in keyboard order even where the narrow visual column is reversed. '
      'Async work remains caller-owned: successful submit closes the same open session, double activation coalesces, and errors stay visible without dismissal.',
  examples: [
    StyleguideExample(
      title: 'Basic',
      description: 'Title, description, cancel, and affirmative action.',
      code: _basicCode,
      builder: (_) => const _AlertDialogExample(kind: _ExampleKind.basic),
      states: const ['open', 'cancelled', 'continued'],
    ),
    StyleguideExample(
      title: 'Small',
      description: 'The 320px small surface keeps two equal action columns.',
      code: _smallCode,
      builder: (_) => const _AlertDialogExample(kind: _ExampleKind.small),
    ),
    StyleguideExample(
      title: 'Media',
      description:
          'Media centers above copy on narrow windows and moves to the logical start on wide windows.',
      code: _mediaCode,
      builder: (_) => const _AlertDialogExample(kind: _ExampleKind.media),
    ),
    StyleguideExample(
      title: 'Small with Media',
      description: 'The small accessory confirmation with 40px media tile.',
      code: _smallMediaCode,
      builder: (_) => const _AlertDialogExample(kind: _ExampleKind.smallMedia),
    ),
    StyleguideExample(
      title: 'Destructive',
      description:
          'A destructive media/action palette with local loading, failure, retry, and success.',
      code: _destructiveCode,
      builder: (_) => const _AlertDialogExample(kind: _ExampleKind.destructive),
      states: const ['destructive', 'loading', 'error', 'retry', 'disabled'],
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic regular and small/media confirmations use logical geometry and action order.',
      code: _rtlCode,
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _AlertDialogExample(kind: _ExampleKind.rtl),
            _AlertDialogExample(kind: _ExampleKind.rtlSmall),
          ],
        ),
      ),
    ),
    StyleguideExample(
      title: 'Controlled and typed',
      description:
          'External state and a borrowed controller observe reasons and typed results without losing trigger focus.',
      code: _controlledCode,
      builder: (_) => const _ControlledAlertDialog(),
      states: const ['controlled', 'typed result', 'Escape', 'programmatic'],
    ),
  ],
);

const _basicCode = '''DAlertDialog<bool>(
  trigger: DAlertDialogTrigger(builder: (_, open) => DButton(
    onPressed: open, variant: DButtonVariant.outline,
    label: const Text('Show Dialog'), hasPopup: true)),
  content: DAlertDialogContent(semanticLabel: 'Permanent action', children: [
    const DAlertDialogHeader(
      title: Text('Are you absolutely sure?'),
      description: Text('This action cannot be undone. This will permanently delete your account and remove your data from our servers.')),
    DAlertDialogFooter(children: [
      const DAlertDialogCancel<bool>(label: Text('Cancel'), result: false),
      const DAlertDialogAction<bool>(label: Text('Continue'), result: true),
    ]),
  ]),
)''';

const _smallCode =
    '''DAlertDialogContent(size: DAlertDialogSize.small, children: [
  const DAlertDialogHeader(title: Text('Allow accessory to connect?'),
    description: Text('Do you want to allow the USB accessory to connect to this device?')),
  DAlertDialogFooter(children: [
    const DAlertDialogCancel<bool>(label: Text("Don't allow"), result: false),
    const DAlertDialogAction<bool>(label: Text('Allow'), result: true),
  ]),
])''';

const _mediaCode = '''DAlertDialogHeader(
  media: const DAlertDialogMedia(child: DIcon(DIcons.shareNodes)),
  title: const Text('Share this project?'),
  description: const Text('Anyone with the link will be able to view and edit this project.'),
)''';

const _smallMediaCode =
    '''DAlertDialogContent(size: DAlertDialogSize.small, children: [
  DAlertDialogHeader(media: accessoryIcon,
    title: const Text('Allow accessory to connect?'),
    description: const Text('Do you want to allow the USB accessory to connect to this device?')),
  actions,
])''';

const _destructiveCode = '''DAlertDialogAction<bool>(
  controller: controller,
  onSubmit: deleteLocally,
  onError: (error, stack) => setState(() => message = 'Deletion failed. Try again.'),
  closeOnPressed: false,
  variant: DButtonVariant.destructive,
  label: const Text('Delete'),
)''';

const _rtlCode = '''Directionality(textDirection: TextDirection.rtl, child:
  DAlertDialogContent(children: [
    const DAlertDialogHeader(title: Text('هل أنت متأكد تمامًا؟'),
      description: Text('لا يمكن التراجع عن هذا الإجراء. سيؤدي هذا إلى حذف حسابك نهائيًا من خوادمنا.')),
    arabicActions,
  ]))''';

const _controlledCode = r'''DAlertDialog<String>(
  open: open,
  controller: controller, // borrowed; caller disposes it
  onOpenChanged: (details) => setState(() {
    open = details.open;
    status = '${details.reason}: ${details.result}';
  }),
  trigger: trigger,
  content: contentWithTypedResult,
)''';

enum _ExampleKind {
  basic,
  small,
  media,
  smallMedia,
  destructive,
  rtl,
  rtlSmall,
}

class _AlertDialogExample extends StatefulWidget {
  const _AlertDialogExample({required this.kind});
  final _ExampleKind kind;

  @override
  State<_AlertDialogExample> createState() => _AlertDialogExampleState();
}

class _AlertDialogExampleState extends State<_AlertDialogExample> {
  final _controller = DDialogController<bool>();
  String _status = '';
  bool _failNext = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _small => switch (widget.kind) {
    _ExampleKind.small ||
    _ExampleKind.smallMedia ||
    _ExampleKind.destructive ||
    _ExampleKind.rtlSmall => true,
    _ => false,
  };

  Widget? get _media => switch (widget.kind) {
    _ExampleKind.media => const DAlertDialogMedia(
      child: DIcon(DIcons.shareNodes),
    ),
    _ExampleKind.smallMedia || _ExampleKind.rtlSmall => const DAlertDialogMedia(
      child: Icon(Icons.bluetooth),
    ),
    _ExampleKind.destructive => const DAlertDialogMedia(
      destructive: true,
      child: DIcon(DIcons.trashCan),
    ),
    _ => null,
  };

  String get _trigger => switch (widget.kind) {
    _ExampleKind.media => 'Share Project',
    _ExampleKind.destructive => 'Delete Chat',
    _ExampleKind.rtl => 'إظهار الحوار',
    _ExampleKind.rtlSmall => 'إظهار الحوار (صغير)',
    _ => 'Show Dialog',
  };

  (String, String, String, String) get _copy => switch (widget.kind) {
    _ExampleKind.small || _ExampleKind.smallMedia => (
      'Allow accessory to connect?',
      'Do you want to allow the USB accessory to connect to this device?',
      "Don't allow",
      'Allow',
    ),
    _ExampleKind.media => (
      'Share this project?',
      'Anyone with the link will be able to view and edit this project.',
      'Cancel',
      'Share',
    ),
    _ExampleKind.destructive => (
      'Delete chat?',
      'This will permanently delete this chat conversation and cannot be undone.',
      'Cancel',
      'Delete',
    ),
    _ExampleKind.rtl => (
      'هل أنت متأكد تمامًا؟',
      'لا يمكن التراجع عن هذا الإجراء. سيؤدي هذا إلى حذف حسابك نهائيًا من خوادمنا.',
      'إلغاء',
      'متابعة',
    ),
    _ExampleKind.rtlSmall => (
      'السماح للملحق بالاتصال؟',
      'هل تريد السماح لملحق USB بالاتصال بهذا الجهاز؟',
      'عدم السماح',
      'السماح',
    ),
    _ => (
      'Are you absolutely sure?',
      'This action cannot be undone. This will permanently delete your account and remove your data from our servers.',
      'Cancel',
      'Continue',
    ),
  };

  Future<bool> _delete() async {
    setState(() => _status = 'Deleting locally…');
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (_failNext) {
      _failNext = false;
      throw StateError('local fixture rejection');
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DAlertDialog<bool>(
          controller: _controller,
          onOpenChanged: (details) {
            if (!details.open && mounted) {
              setState(
                () => _status = details.result == true
                    ? 'Confirmed locally'
                    : 'Cancelled',
              );
            }
          },
          trigger: DAlertDialogTrigger(
            builder: (context, open) => DButton(
              onPressed: open,
              variant: widget.kind == _ExampleKind.destructive
                  ? DButtonVariant.destructive
                  : DButtonVariant.outline,
              label: Text(_trigger),
              hasPopup: true,
            ),
          ),
          content: DAlertDialogContent(
            size: _small ? DAlertDialogSize.small : DAlertDialogSize.regular,
            semanticLabel: copy.$1,
            children: [
              DAlertDialogHeader(
                media: _media,
                title: Text(copy.$1),
                description: Text(copy.$2),
              ),
              if (widget.kind == _ExampleKind.destructive &&
                  _status.contains('failed'))
                DAlertDialogError(message: _status),
              DAlertDialogFooter(
                children: [
                  DAlertDialogCancel<bool>(label: Text(copy.$3), result: false),
                  if (widget.kind == _ExampleKind.destructive)
                    DAlertDialogAction<bool>(
                      controller: _controller,
                      onSubmit: _delete,
                      onError: (error, stack) {
                        if (mounted) {
                          setState(
                            () => _status = 'Deletion failed. Try again.',
                          );
                        }
                      },
                      closeOnPressed: false,
                      variant: DButtonVariant.destructive,
                      label: Text(copy.$4),
                    )
                  else
                    DAlertDialogAction<bool>(
                      label: Text(copy.$4),
                      result: true,
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_status.isNotEmpty) ...[const SizedBox(height: 8), Text(_status)],
      ],
    );
  }
}

class _ControlledAlertDialog extends StatefulWidget {
  const _ControlledAlertDialog();

  @override
  State<_ControlledAlertDialog> createState() => _ControlledAlertDialogState();
}

class _ControlledAlertDialogState extends State<_ControlledAlertDialog> {
  final _controller = DDialogController<String>();
  bool _open = false;
  String _status = 'Closed';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DAlertDialog<String>(
        controller: _controller,
        open: _open,
        onOpenChanged: (details) => setState(() {
          _open = details.open;
          _status = '${details.reason.name}: ${details.result ?? 'none'}';
        }),
        trigger: DAlertDialogTrigger(
          builder: (context, open) => DButton(
            onPressed: open,
            variant: DButtonVariant.outline,
            label: const Text('Open controlled alert'),
            hasPopup: true,
          ),
        ),
        content: const DAlertDialogContent(
          semanticLabel: 'Replace local draft',
          children: [
            DAlertDialogHeader(
              title: Text('Replace local draft?'),
              description: Text(
                'The selected server copy will replace the unsaved local text.',
              ),
            ),
            DAlertDialogFooter(
              children: [
                DAlertDialogCancel<String>(
                  label: Text('Keep local'),
                  result: 'keep',
                ),
                DAlertDialogAction<String>(
                  label: Text('Replace'),
                  result: 'replace',
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(_status),
    ],
  );
}
