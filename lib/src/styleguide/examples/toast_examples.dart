import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final toastExamples = ComponentExamples(
  description: 'Succinct, temporary feedback with actions and async updates.',
  status: ComponentStatus.implemented,
  notes:
      'DToaster owns a local viewport and an optional controller. The default '
      'base-nova mapping is a max-width 384px popover surface with 16px padding, '
      '12px content gaps, 14/20 text, proportional 2xl radius, border, shadow, '
      '16px status artwork, outline action and ghost close action. F6 moves '
      'focus into notifications; Escape, close, timeout, programmatic close and '
      'horizontal swipe dismiss. Hover, focus and app background pause timeouts. '
      'Promise updates are revision-checked, so disposal, replacement and reused '
      'ids cannot receive a late completion. Text grows and wraps; placement is '
      'directional. The styleguide adds a nested DToaster so notices cannot leak '
      'into another example. Flutter uses native drag recognition and semantics '
      'instead of browser pointer events and ARIA.',
  examples: [
    StyleguideExample(
      title: 'Basic',
      description:
          'Show the documented title, description, action, and close composition.',
      states: const ['Title', 'Description', 'Action', 'Close', 'Timeout'],
      code: r'''final id = DToast.of(context).add(DToastOptions(
  title: 'Event created',
  description: 'Sunday, December 3 at 9:00 AM',
  action: DToastAction(label: 'Undo', onPressed: undo),
));''',
      builder: (_) => const _BasicToastExample(),
    ),
    StyleguideExample(
      title: 'Types',
      description:
          'Each documented built-in type has a visible icon and spoken status content.',
      states: const [
        'Default',
        'Success',
        'Info',
        'Warning',
        'Error',
        'Loading',
      ],
      code: r'''DToast.show(context, 'Event has been created.',
  type: DToastType.success);
DToast.show(context, 'Creating event…',
  type: DToastType.loading, duration: null);''',
      builder: (_) => const _TypesToastExample(),
    ),
    StyleguideExample(
      title: 'Promise',
      description:
          'Run a deterministic success or error, then reset while loading to prove late results stay in their original scope.',
      states: const ['Loading', 'Success', 'Error', 'Replacement', 'Reset'],
      code: r'''controller.promise(createEvent(),
  loading: const DToastOptions(description: 'Creating event…'),
  success: (event) => DToastOptions(description: '${event.name} created.'),
  error: (_) => const DToastOptions(description: 'Could not create event.'),
);''',
      builder: (_) => const _PromiseToastExample(),
    ),
    StyleguideExample(
      title: 'Stacking, limits, and custom content',
      description:
          'Add repeated ids, exceed the three-item limit, dismiss by button or swipe, and inspect custom child composition.',
      states: const [
        'Stack',
        'Limit 3',
        'Repeated id',
        'Custom content',
        'Swipe',
        'F6/Escape',
      ],
      code: r'''DToast.of(context).add(
  DToastOptions(contentBuilder: (context, toast) => customCard),
  id: 'sync', // Reusing this id updates in place.
);''',
      builder: (_) => const _StackToastExample(),
    ),
    StyleguideExample(
      title: 'Position, direction, and scale',
      description:
          'Cycle all six placements. Start/end follow RTL, and visible toasts retain state through live theme, radius, and text-scale changes.',
      states: const [
        'Six positions',
        'RTL',
        '200% text',
        'Narrow',
        'Live theme',
      ],
      code: r'''DToaster(
  position: DToastPosition.topStart,
  child: page,
)''',
      builder: (_) => const _PositionToastExample(),
    ),
  ],
);

class _BasicToastExample extends StatelessWidget {
  const _BasicToastExample();

  @override
  Widget build(BuildContext context) => DButton(
    label: const Text('Show Toast'),
    variant: DButtonVariant.outline,
    onPressed: () {
      late Object id;
      id = DToast.of(context).add(
        DToastOptions(
          title: 'Event created',
          description: 'Sunday, December 3 at 9:00 AM',
          action: DToastAction(
            label: 'Undo',
            onPressed: () => DToast.of(context).close(id),
          ),
        ),
      );
    },
  );
}

class _TypesToastExample extends StatelessWidget {
  const _TypesToastExample();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final type in DToastType.values)
        DButton(
          label: Text(_typeName(type)),
          variant: DButtonVariant.outline,
          onPressed: () => DToast.show(
            context,
            _typeMessage(type),
            type: type,
            duration: type == DToastType.loading
                ? null
                : const Duration(seconds: 5),
            priority: type == DToastType.error
                ? DToastPriority.high
                : DToastPriority.normal,
          ),
        ),
    ],
  );
}

class _PromiseToastExample extends StatefulWidget {
  const _PromiseToastExample();
  @override
  State<_PromiseToastExample> createState() => _PromiseToastExampleState();
}

class _PromiseToastExampleState extends State<_PromiseToastExample> {
  Timer? _timer;
  int _generation = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _run(BuildContext context, bool succeed) {
    final completion = Completer<String>();
    final generation = ++_generation;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (!mounted || generation != _generation) return;
      if (succeed) {
        completion.complete('Event');
      } else {
        completion.completeError(StateError('offline'));
      }
    });
    DToast.of(context).promise(
      completion.future,
      id: 'styleguide-promise',
      loading: const DToastOptions(description: 'Creating event…'),
      success: (name) => DToastOptions(description: '$name created.'),
      error: (_) => const DToastOptions(description: 'Could not create event.'),
    );
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      DButton(
        label: const Text('Resolve promise'),
        variant: DButtonVariant.outline,
        onPressed: () => _run(context, true),
      ),
      DButton(
        label: const Text('Reject promise'),
        variant: DButtonVariant.outline,
        onPressed: () => _run(context, false),
      ),
      DButton(
        label: const Text('Replace id'),
        variant: DButtonVariant.ghost,
        onPressed: () => DToast.show(
          context,
          'The pending result no longer owns this notice.',
          id: 'styleguide-promise',
          duration: null,
        ),
      ),
    ],
  );
}

class _StackToastExample extends StatefulWidget {
  const _StackToastExample();
  @override
  State<_StackToastExample> createState() => _StackToastExampleState();
}

class _StackToastExampleState extends State<_StackToastExample> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      DButton(
        label: const Text('Add notice'),
        variant: DButtonVariant.outline,
        onPressed: () => DToast.show(
          context,
          'Notice ${++_count}; only the newest three remain.',
          duration: null,
        ),
      ),
      DButton(
        label: const Text('Update sync'),
        variant: DButtonVariant.outline,
        onPressed: () => DToast.show(
          context,
          'Synchronized revision ${++_count}',
          id: 'sync',
          type: DToastType.info,
          duration: null,
        ),
      ),
      DButton(
        label: const Text('Custom'),
        variant: DButtonVariant.outline,
        onPressed: () => DToast.of(context).add(
          DToastOptions(
            duration: null,
            contentBuilder: (context, toast) => Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const DAvatar(
                    size: DAvatarSize.lg,
                    fallback: DAvatarFallback(child: Text('A')),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('A custom composed notification')),
                  DButton.iconOnly(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'Close toast',
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.extraSmall,
                    onPressed: () => DToast.of(context).close(toast.id),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      DButton(
        label: const Text('Dismiss all'),
        variant: DButtonVariant.ghost,
        onPressed: () => DToast.of(context).closeAll(),
      ),
    ],
  );
}

class _PositionToastExample extends StatefulWidget {
  const _PositionToastExample();
  @override
  State<_PositionToastExample> createState() => _PositionToastExampleState();
}

class _PositionToastExampleState extends State<_PositionToastExample> {
  final _controller = DToastController();
  var _position = DToastPosition.bottomEnd;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 560,
    height: 260,
    child: DToaster(
      controller: _controller,
      position: _position,
      child: Center(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DButton(
              label: Text(_position.name),
              variant: DButtonVariant.outline,
              onPressed: () {
                setState(() {
                  _position =
                      DToastPosition.values[(_position.index + 1) %
                          DToastPosition.values.length];
                });
                _controller.add(
                  DToastOptions(
                    description: 'Placed at ${_position.name}',
                    duration: null,
                  ),
                  id: 'position',
                );
              },
            ),
            DButton(
              label: const Text('Dismiss'),
              variant: DButtonVariant.ghost,
              onPressed: _controller.closeAll,
            ),
          ],
        ),
      ),
    ),
  );
}

String _typeName(DToastType type) => switch (type) {
  DToastType.standard => 'Default',
  _ => '${type.name[0].toUpperCase()}${type.name.substring(1)}',
};

String _typeMessage(DToastType type) => switch (type) {
  DToastType.standard => 'Event has been created.',
  DToastType.success => 'Event has been created.',
  DToastType.info => 'Arrive 10 minutes before the event.',
  DToastType.warning => 'The event cannot start before 8:00 AM.',
  DToastType.error => 'The event could not be created.',
  DToastType.loading => 'Creating event…',
};
