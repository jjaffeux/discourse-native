import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final messageScrollerExamples = ComponentExamples(
  status: ComponentStatus.baseline,
  description:
      'Reader-intent-aware message timelines with stable anchors, commands, live following and scalable virtualization.',
  notes:
      'These examples use the final Message and Bubble composition APIs. The viewport owns scrolling, anchoring, visibility and announcement timing; callers retain transport, pagination, persistence and message state. Browser and signed-native acceptance remain with the independent reviewer.',
  examples: [
    StyleguideExample(
      title: 'Streaming and previous context',
      description:
          'Auto-follow stays at the live edge until the reader scrolls away. New turns retain a 64px preview of context.',
      code: _streamingCode,
      states: const ['live edge', 'reader paused', 'new turn'],
      builder: (_) => const _StreamingExample(),
    ),
    StyleguideExample(
      title: 'Anchoring and group chat',
      description:
          'Stable message IDs survive variable row heights; the saved marker opens as the initial anchor.',
      code: _anchoringCode,
      states: const ['saved anchor', 'variable height', 'grouped sender'],
      builder: (_) => const _AnchoringExample(),
    ),
    StyleguideExample(
      title: 'Opening a saved thread',
      description:
          'Choose start, end or the last marked anchor without a visible first-frame jump.',
      code: _openingCode,
      states: const ['start', 'end', 'last anchor', 'no flash'],
      builder: (_) => const _OpeningExample(),
    ),
    StyleguideExample(
      title: 'Load history',
      description:
          'Prepending variable-height history preserves the first visible stable row.',
      code: _historyCode,
      states: const ['prepend', 'position preserved'],
      builder: (_) => const _HistoryExample(),
    ),
    StyleguideExample(
      title: 'Commands, visibility and scroll state',
      description:
          'Typed commands target stable IDs and expose edge, anchor and visible-message state.',
      code: _commandsCode,
      states: const ['start', 'center', 'end', 'nearest'],
      builder: (_) => const _CommandsExample(),
    ),
    StyleguideExample(
      title: 'Virtualized transcript',
      description:
          'One thousand variable-height rows are built lazily while remaining addressable by stable ID.',
      code: _virtualizedCode,
      states: const ['1000 rows', 'stable target'],
      builder: (_) => const _VirtualizedExample(),
    ),
    StyleguideExample(
      title: 'Accessibility and unstyled composition',
      description:
          'A labelled transcript defers live additions while busy; styling and scrollbar chrome can be omitted.',
      code: _accessibilityCode,
      states: const ['busy', 'live log', 'unstyled', 'reduced motion'],
      builder: (_) => const _AccessibilityExample(),
    ),
  ],
);

class _StreamingExample extends StatefulWidget {
  const _StreamingExample();

  @override
  State<_StreamingExample> createState() => _StreamingExampleState();
}

class _StreamingExampleState extends State<_StreamingExample> {
  final _messages = <String>[
    'Can you summarize the release notes?',
    'Yes — the update improves navigation and offline recovery.',
    'What changed for keyboard users?',
  ];
  Timer? _timer;
  var _streaming = false;
  var _previousContext = 64.0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _streamReply() {
    if (_streaming) return;
    setState(() {
      _streaming = true;
      _messages.add('Keyboard focus now remains anchored');
    });
    var ticks = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 220), (timer) {
      if (!mounted) return;
      ticks++;
      setState(() {
        _messages[_messages.length - 1] += switch (ticks) {
          1 => ' while content',
          2 => ' streams into',
          _ => ' the same turn.',
        };
        if (ticks == 3) _streaming = false;
      });
      if (ticks == 3) timer.cancel();
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DButton(
        label: const Text('Stream reply'),
        onPressed: _streaming ? null : _streamReply,
        loading: _streaming,
        variant: DButtonVariant.secondary,
        tooltip: 'Append a gradually growing message',
      ),
      const SizedBox(height: 8),
      Text('Previous context: ${_previousContext.round()}px'),
      DSlider(
        value: _previousContext,
        min: 0,
        max: 128,
        step: 16,
        semanticLabel: 'Previous context',
        onChanged: (value) => setState(() => _previousContext = value),
      ),
      const SizedBox(height: 12),
      _Frame(
        child: DMessageScrollerProvider(
          autoScroll: true,
          previousItemPeek: _previousContext,
          child: DMessageScroller(
            children: [
              DMessageScrollerViewport.builder(
                itemCount: _messages.length,
                itemIdBuilder: (index) => 'stream-$index',
                announcementBuilder: (index) => _messages[index],
                contentPadding: const EdgeInsets.all(16),
                itemBuilder: (context, index) => _MessageRow(
                  text: _messages[index],
                  outgoing: index.isOdd,
                  sender: index.isOdd ? 'You' : 'Nova',
                  animate: index == _messages.length - 1,
                ),
              ),
              const DMessageScrollerButton(),
            ],
          ),
        ),
      ),
    ],
  );
}

class _AnchoringExample extends StatelessWidget {
  const _AnchoringExample();

  @override
  Widget build(BuildContext context) => _Frame(
    child: DMessageScrollerProvider(
      initialPosition: DMessageScrollerInitialPosition.lastAnchor,
      child: DMessageScroller(
        children: [
          DMessageScrollerViewport.builder(
            itemCount: 12,
            itemIdBuilder: (index) => 'group-$index',
            scrollAnchorBuilder: (index) => index == 7,
            contentPadding: const EdgeInsets.all(16),
            itemBuilder: (context, index) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (index == 7)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: DMarker(child: Text('Saved position')),
                  ),
                _MessageRow(
                  text: index == 5
                      ? 'This longer group-chat response changes height but the saved message identity remains stable.'
                      : 'Message ${index + 1} in the design review',
                  sender: ['Mina', 'Kai', 'Rae'][index % 3],
                  outgoing: index % 4 == 3,
                ),
              ],
            ),
          ),
          const DMessageScrollerButton(
            direction: DMessageScrollerDirection.start,
          ),
          const DMessageScrollerButton(),
        ],
      ),
    ),
  );
}

class _OpeningExample extends StatefulWidget {
  const _OpeningExample();

  @override
  State<_OpeningExample> createState() => _OpeningExampleState();
}

class _OpeningExampleState extends State<_OpeningExample> {
  var _position = DMessageScrollerInitialPosition.lastAnchor;

  @override
  Widget build(BuildContext context) =>
      DTabs<DMessageScrollerInitialPosition>.controlled(
        value: _position,
        onChanged: (value) {
          if (value != null) setState(() => _position = value);
        },
        children: [
          const DTabList<DMessageScrollerInitialPosition>(
            children: [
              DTabTrigger(
                value: DMessageScrollerInitialPosition.start,
                child: Text('Start'),
              ),
              DTabTrigger(
                value: DMessageScrollerInitialPosition.lastAnchor,
                child: Text('Saved'),
              ),
              DTabTrigger(
                value: DMessageScrollerInitialPosition.end,
                child: Text('End'),
              ),
            ],
          ),
          for (final position in DMessageScrollerInitialPosition.values)
            DTabPanel(
              value: position,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _OpeningTranscript(position: position),
              ),
            ),
        ],
      );
}

class _OpeningTranscript extends StatelessWidget {
  const _OpeningTranscript({required this.position});

  final DMessageScrollerInitialPosition position;

  @override
  Widget build(BuildContext context) => _Frame(
    child: DMessageScrollerProvider(
      initialPosition: position,
      child: DMessageScroller(
        children: [
          DMessageScrollerViewport.builder(
            itemCount: 18,
            itemIdBuilder: (index) => 'open-$index',
            scrollAnchorBuilder: (index) => index == 9,
            contentPadding: const EdgeInsets.all(16),
            itemBuilder: (context, index) => _MessageRow(
              text: 'Saved thread message ${index + 1}',
              sender: index.isEven ? 'Sam' : 'You',
              outgoing: index.isOdd,
            ),
          ),
          const DMessageScrollerButton(),
        ],
      ),
    ),
  );
}

class _HistoryExample extends StatefulWidget {
  const _HistoryExample();

  @override
  State<_HistoryExample> createState() => _HistoryExampleState();
}

class _HistoryExampleState extends State<_HistoryExample> {
  var _first = 20;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DButton(
        label: const Text('Load earlier messages'),
        onPressed: _first == 0 ? null : () => setState(() => _first -= 10),
        variant: DButtonVariant.secondary,
      ),
      const SizedBox(height: 12),
      _Frame(
        child: DMessageScrollerProvider(
          initialPosition: DMessageScrollerInitialPosition.start,
          child: DMessageScroller(
            children: [
              DMessageScrollerViewport.builder(
                itemCount: 40 - _first,
                itemIdBuilder: (index) => 'history-${_first + index}',
                contentPadding: const EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  final number = _first + index;
                  return _MessageRow(
                    text: number % 5 == 0
                        ? 'Earlier message $number includes a second line to demonstrate variable-height restoration.'
                        : 'Earlier message $number',
                    sender: 'Archive',
                  );
                },
              ),
              const DMessageScrollerButton(),
            ],
          ),
        ),
      ),
    ],
  );
}

class _CommandsExample extends StatefulWidget {
  const _CommandsExample();

  @override
  State<_CommandsExample> createState() => _CommandsExampleState();
}

class _CommandsExampleState extends State<_CommandsExample> {
  final _controller = DMessageScrollerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DButton(
            label: const Text('Start'),
            onPressed: _controller.scrollToStart,
            variant: DButtonVariant.secondary,
          ),
          DButton(
            label: const Text('Message 24'),
            onPressed: () => _controller.scrollToMessage(
              'command-23',
              options: const DMessageScrollerScrollOptions(
                alignment: DMessageScrollerAlignment.center,
              ),
            ),
            variant: DButtonVariant.secondary,
          ),
          DButton(
            label: const Text('End'),
            onPressed: _controller.scrollToEnd,
            variant: DButtonVariant.secondary,
          ),
        ],
      ),
      const SizedBox(height: 8),
      AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Text(
          'At start: ${!_controller.state.canScrollStart} · At end: ${!_controller.state.canScrollEnd} · Visible: ${_controller.state.visibleMessageIds.length} · Anchor: ${_controller.state.currentAnchorId ?? '—'}',
        ),
      ),
      const SizedBox(height: 12),
      _Frame(
        child: DMessageScrollerProvider(
          controller: _controller,
          child: DMessageScroller(
            children: [
              DMessageScrollerViewport.builder(
                itemCount: 40,
                itemIdBuilder: (index) => 'command-$index',
                contentPadding: const EdgeInsets.all(16),
                itemBuilder: (context, index) => _MessageRow(
                  text: 'Addressable message ${index + 1}',
                  sender: 'System',
                ),
              ),
              const DMessageScrollerButton(
                direction: DMessageScrollerDirection.start,
              ),
              const DMessageScrollerButton(),
            ],
          ),
        ),
      ),
    ],
  );
}

class _VirtualizedExample extends StatefulWidget {
  const _VirtualizedExample();

  @override
  State<_VirtualizedExample> createState() => _VirtualizedExampleState();
}

class _VirtualizedExampleState extends State<_VirtualizedExample> {
  final _controller = DMessageScrollerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DButton(
        label: const Text('Jump to row 750'),
        onPressed: () => _controller.scrollToMessage('virtual-749'),
        variant: DButtonVariant.secondary,
      ),
      const SizedBox(height: 12),
      _Frame(
        child: DMessageScrollerProvider(
          controller: _controller,
          initialPosition: DMessageScrollerInitialPosition.start,
          child: DMessageScroller(
            children: [
              DMessageScrollerViewport.builder(
                itemCount: 1000,
                itemIdBuilder: (index) => 'virtual-$index',
                contentPadding: const EdgeInsets.all(16),
                itemBuilder: (context, index) => _MessageRow(
                  text: index % 11 == 0
                      ? 'Virtual message ${index + 1} has a measured, variable-height body for realistic anchoring.'
                      : 'Virtual message ${index + 1}',
                  sender: index.isEven ? 'Ari' : 'Bo',
                  outgoing: index.isOdd,
                ),
              ),
              const DMessageScrollerButton(),
            ],
          ),
        ),
      ),
    ],
  );
}

class _AccessibilityExample extends StatefulWidget {
  const _AccessibilityExample();

  @override
  State<_AccessibilityExample> createState() => _AccessibilityExampleState();
}

class _AccessibilityExampleState extends State<_AccessibilityExample> {
  var _busy = true;
  final _messages = <String>['Existing accessible message', 'A second message'];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        children: [
          DButton(
            label: Text(_busy ? 'Finish loading' : 'Mark busy'),
            onPressed: () => setState(() => _busy = !_busy),
            variant: DButtonVariant.secondary,
          ),
          DButton(
            label: const Text('Add message'),
            onPressed: () => setState(
              () => _messages.add('New live message ${_messages.length + 1}'),
            ),
            variant: DButtonVariant.secondary,
          ),
        ],
      ),
      const SizedBox(height: 12),
      _Frame(
        decorated: false,
        child: DMessageScrollerProvider(
          autoScroll: true,
          child: DMessageScroller(
            children: [
              DMessageScrollerViewport.builder(
                semanticLabel: 'Accessible support conversation',
                styled: false,
                showScrollbar: false,
                busy: _busy,
                itemCount: _messages.length,
                itemIdBuilder: (index) => 'accessible-$index',
                announcementBuilder: (index) => _messages[index],
                contentPadding: const EdgeInsets.all(16),
                itemBuilder: (context, index) =>
                    _MessageRow(text: _messages[index], sender: 'Support'),
              ),
              const DMessageScrollerButton(),
            ],
          ),
        ),
      ),
    ],
  );
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child, this.decorated = true});

  final Widget child;
  final bool decorated;

  @override
  Widget build(BuildContext context) {
    final frame = SizedBox(height: 320, child: child);
    return decorated ? DCard(child: frame) : frame;
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.text,
    required this.sender,
    this.outgoing = false,
    this.animate = false,
  });

  final String text;
  final String sender;
  final bool outgoing;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final align = outgoing ? DMessageAlign.end : DMessageAlign.start;
    final bubbleAlign = outgoing ? DBubbleAlign.end : DBubbleAlign.start;
    final message = DMessage(
      align: align,
      children: [
        DMessageAvatar(
          child: CircleAvatar(
            radius: 16,
            child: Text(
              sender.characters.first,
              semanticsLabel: '$sender avatar',
            ),
          ),
        ),
        DMessageContent(
          children: [
            DMessageHeader(children: [Text(sender)]),
            DBubble(
              align: bubbleAlign,
              variant: outgoing ? DBubbleVariant.primary : DBubbleVariant.muted,
              children: [DBubbleContent(child: Text(text))],
            ),
            const DMessageFooter(children: [Text('Just now')]),
          ],
        ),
      ],
    );
    if (!animate) return message;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - value)),
          child: child,
        ),
      ),
      child: message,
    );
  }
}

const _streamingCode = '''DMessageScrollerProvider(
  autoScroll: true,
  child: DMessageScroller(children: [
    DMessageScrollerViewport.builder(
      itemCount: messages.length,
      itemIdBuilder: (index) => messages[index].id,
      announcementBuilder: (index) => messages[index].accessibleText,
      itemBuilder: (context, index) => MessageRow(messages[index]),
    ),
    DMessageScrollerButton(),
  ]),
)''';

const _anchoringCode = '''DMessageScrollerViewport.builder(
  itemIdBuilder: (index) => messages[index].id,
  scrollAnchorBuilder: (index) => messages[index].isSaved,
  itemBuilder: (context, index) => DMessage(...),
)''';

const _openingCode = '''DMessageScrollerProvider(
  initialPosition: DMessageScrollerInitialPosition.lastAnchor,
  child: transcript,
)''';

const _historyCode = '''DMessageScrollerViewport.builder(
  preserveScrollOnPrepend: true,
  itemIdBuilder: (index) => messages[index].id,
  itemBuilder: buildVariableHeightMessage,
)''';

const _commandsCode = '''controller.scrollToMessage(
  'message-24',
  const DMessageScrollerScrollOptions(
    alignment: DMessageScrollerAlignment.center,
  ),
);''';

const _virtualizedCode = '''DMessageScrollerViewport.builder(
  itemCount: 1000,
  itemIdBuilder: (index) => 'message-\$index',
  itemBuilder: buildMessage,
)''';

const _accessibilityCode = '''DMessageScrollerViewport.builder(
  semanticLabel: 'Support conversation',
  busy: isLoading,
  styled: false,
  showScrollbar: false,
  announcementBuilder: (index) => messages[index].accessibleText,
  ...
)''';
