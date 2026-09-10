import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final messageScrollerExamples = ComponentExamples(
  topLevelExampleIndex: 7,
  status: ComponentStatus.implemented,
  description:
      'Reader-intent-aware message timelines with stable anchors, commands, live following and scalable virtualization.',
  notes:
      'These examples use the final Message and Bubble composition APIs. The viewport owns scrolling, anchoring, visibility and announcement timing; callers retain transport, pagination, persistence and message state. Browser and signed-native acceptance remain with the independent reviewer.',
  examples: [
    StyleguideExample(
      title: 'Streaming and previous context',
      description:
          'Send an offline turn, stop a streaming reply, or reset to empty. Choose entry motion while new turns retain a 64px preview of context.',
      code: _streamingCode,
      states: const [
        'live edge',
        'reader paused',
        'new turn',
        'composer',
        'empty',
        'animation preset',
      ],
      builder: (_) => const _StreamingExample(),
    ),
    StyleguideExample(
      title: 'Anchoring and group chat',
      description:
          'Stable message IDs survive variable row heights. Choose which role anchors a newly appended turn.',
      code: _anchoringCode,
      states: const [
        'saved anchor',
        'variable height',
        'grouped sender',
        'anchor role',
      ],
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
          'Typed commands and a hover-preview outline target stable IDs and expose edge, anchor and visible-message state.',
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
    StyleguideExample(
      title: 'Reference demo',
      description:
          'The canonical read-only chat card combines an empty transcript, reset action, queued prompt, composer tools, and send control.',
      code: '''DMessageScrollerProvider(
  child: Column(children: [
    DCard(
      spacing: DSpacing.xl,
      children: [
        DCardHeader(
          border: true,
          title: DCardTitle(child: Text('New Chat')),
          description: DCardDescription(
            child: Text('How can I help you today?')),
          action: DCardAction(child: resetButton),
        ),
        DCardContent(
          edgeToEdge: true,
          joinNext: true,
          child: SizedBox(
            height: 294,
            child: messages.isEmpty
              ? DEmpty(
                  padding: EdgeInsets.all(DSpacing.xl),
                  children: [
                    DEmptyHeader(children: [
                      DEmptyMedia(
                        variant: DEmptyMediaVariant.icon,
                        child: Icon(Icons.chat_bubble_outline),
                      ),
                      DEmptyTitle('Morning, Alex!'),
                      DEmptyDescription(
                        'What are we working on today? Press send to start a new conversation'),
                    ]),
                  ],
                )
              : DMessageScroller(children: [
                  DMessageScrollerViewport.builder(/* messages */),
                  DMessageScrollerButton(),
                ]),
          ),
        ),
      ],
      footer: DCardFooter(
        border: false,
        muted: false,
        child: messageComposer,
      ),
    ),
    SizedBox(height: DSpacing.lg),
    Text('Demo is read only. Press send to send messages.'),
  ]),
)''',
      states: const ['Empty', 'Messages', 'Reset', 'Composer', 'Read only'],
      builder: (_) => const _MessageScrollerReferenceDemo(),
    ),
  ],
);

class _MessageScrollerReferenceDemo extends StatefulWidget {
  const _MessageScrollerReferenceDemo();

  @override
  State<_MessageScrollerReferenceDemo> createState() =>
      _MessageScrollerReferenceDemoState();
}

class _MessageScrollerReferenceDemoState
    extends State<_MessageScrollerReferenceDemo> {
  static const _script = [
    "I'm building a chat for our app and the scroll behavior is driving me nuts. Every time the AI streams a reply, the whole thread jumps around.",
    "That's the classic streaming scroll problem. Message Scroller follows new content only while the reader is already at the live edge.",
    'Okay, but when someone sends a new message the view still feels jarring.',
    'Turn anchoring settles the new prompt near the top while preserving a small peek of the previous exchange.',
  ];

  final _messages = <String>[];
  var _selectedTool = '';

  String get _nextMessage => _messages.length < _script.length
      ? _script[_messages.length]
      : 'No messages queued. Reset the conversation.';

  void _send() {
    if (_messages.length >= _script.length) return;
    setState(() => _messages.add(_nextMessage));
  }

  @override
  Widget build(BuildContext context) => DMessageScrollerProvider(
    autoScroll: true,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 384),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DCard(
            spacing: DSpacing.xl,
            footer: DCardFooter(
              border: false,
              muted: false,
              child: DInputGroup(
                semanticLabel: 'Read-only message composer',
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      12,
                      10,
                      12,
                      4,
                    ),
                    child: Text(
                      _nextMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DInputGroupAddon(
                    alignment: DInputGroupAddonAlignment.blockEnd,
                    child: Row(
                      children: [
                        DDropdownMenu(
                          content: DDropdownMenuContent(
                            semanticLabel: 'Add files and tools',
                            side: DPopoverSide.top,
                            width: 176,
                            children: [
                              for (final (label, icon) in const [
                                ('Add Photos & Files', Icons.attach_file),
                                ('Create Image', Icons.image_outlined),
                                ('Deep Research', Icons.travel_explore),
                                ('Web Search', Icons.public),
                              ])
                                DDropdownMenuItem(
                                  leading: Icon(icon),
                                  onPressed: () =>
                                      setState(() => _selectedTool = label),
                                  child: Text(label),
                                ),
                            ],
                          ),
                          child: DDropdownMenuTrigger(
                            builder: (context, menu) => DInputGroupButton.icon(
                              icon: const Icon(Icons.add),
                              tooltip: 'Add files',
                              hasPopup: true,
                              focusNode: menu.focusNode,
                              onPressed: menu.toggle,
                              size: DInputGroupButtonSize.iconSmall,
                              variant: DButtonVariant.outline,
                            ),
                          ),
                        ),
                        const Spacer(),
                        DInputGroupButton.icon(
                          icon: const Icon(Icons.arrow_upward),
                          tooltip: 'Send',
                          onPressed: _messages.length < _script.length
                              ? _send
                              : null,
                          size: DInputGroupButtonSize.iconSmall,
                          variant: DButtonVariant.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            children: [
              DCardHeader(
                border: true,
                title: const DCardTitle(child: Text('New Chat')),
                description: const DCardDescription(
                  child: Text('How can I help you today?'),
                ),
                action: DCardAction(
                  child: DTooltip(
                    message: 'Reset',
                    child: DButton.iconOnly(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Reset conversation',
                      variant: DButtonVariant.outline,
                      onPressed: () => setState(() {
                        _messages.clear();
                        _selectedTool = '';
                      }),
                    ),
                  ),
                ),
              ),
              DCardContent(
                edgeToEdge: true,
                joinNext: true,
                child: SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(294),
                  child: _messages.isEmpty
                      ? const DEmpty(
                          padding: EdgeInsets.all(DSpacing.xl),
                          children: [
                            DEmptyHeader(
                              children: [
                                DEmptyMedia(
                                  variant: DEmptyMediaVariant.icon,
                                  child: Icon(Icons.chat_bubble_outline),
                                ),
                                DEmptyTitle('Morning, Alex!'),
                                DEmptyDescription(
                                  'What are we working on today? Press send to start a new conversation',
                                ),
                              ],
                            ),
                          ],
                        )
                      : DMessageScroller(
                          children: [
                            DMessageScrollerViewport.builder(
                              itemCount: _messages.length,
                              itemIdBuilder: (index) => 'reference-$index',
                              scrollAnchorBuilder: (index) => index.isEven,
                              announcementBuilder: (index) => _messages[index],
                              contentPadding: const EdgeInsets.all(DSpacing.md),
                              itemBuilder: (context, index) => _MessageRow(
                                text: _messages[index],
                                outgoing: index.isEven,
                                sender: index.isEven ? 'You' : 'Assistant',
                                animate: false,
                                animation: _EntryAnimation.none,
                              ),
                            ),
                            const DMessageScrollerButton(),
                          ],
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              _selectedTool.isEmpty
                  ? 'Demo is read only. Press send to send messages.'
                  : '$_selectedTool selected · Demo is read only.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: DTokens.of(context).mutedForeground,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _StreamingExample extends StatefulWidget {
  const _StreamingExample();

  @override
  State<_StreamingExample> createState() => _StreamingExampleState();
}

class _StreamingExampleState extends State<_StreamingExample> {
  final _messages = <String>[
    'Can you summarize the release notes?',
    'Yes — the update improves navigation and offline recovery.',
  ];
  final _prompt = TextEditingController(
    text: 'What changed for keyboard users?',
  );
  Timer? _timer;
  var _streaming = false;
  var _previousContext = 64.0;
  var _animation = _EntryAnimation.slide;
  String? _tool;

  @override
  void dispose() {
    _timer?.cancel();
    _prompt.dispose();
    super.dispose();
  }

  void _streamReply() {
    if (_streaming) return;
    setState(() {
      final prompt = _prompt.text.trim();
      _messages.add(
        '${_tool == null ? '' : '[$_tool] '}${prompt.isEmpty ? 'Tell me more about this update.' : prompt}',
      );
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
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DButton(
            label: Text(_streaming ? 'Stop reply' : 'Stream reply'),
            onPressed: _streaming
                ? () {
                    _timer?.cancel();
                    setState(() => _streaming = false);
                  }
                : _streamReply,
            variant: DButtonVariant.secondary,
          ),
          DTooltip(
            message: 'Start an empty offline conversation',
            child: DButton(
              label: const Text('Reset conversation'),
              onPressed: () {
                _timer?.cancel();
                setState(() {
                  _streaming = false;
                  _messages.clear();
                });
              },
              variant: DButtonVariant.outline,
            ),
          ),
        ],
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
      const SizedBox(height: 8),
      DSelect<_EntryAnimation>(
        value: _animation,
        semanticLabel: 'Entry animation',
        entries: [
          for (final preset in _EntryAnimation.values)
            DSelectOption(
              value: preset,
              label: preset.label,
              child: Text(preset.label),
            ),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _animation = value);
        },
      ),
      const SizedBox(height: 12),
      _Frame(
        child: _messages.isEmpty
            ? const DEmpty(
                children: [
                  DEmptyHeader(
                    children: [
                      DEmptyMedia(
                        variant: DEmptyMediaVariant.icon,
                        child: Icon(Icons.chat_bubble_outline),
                      ),
                      DEmptyTitle('New conversation'),
                      DEmptyDescription(
                        'Send a message to start this offline demo.',
                      ),
                    ],
                  ),
                ],
              )
            : DMessageScrollerProvider(
                autoScroll: true,
                previousItemPeek: _previousContext,
                child: DMessageScroller(
                  children: [
                    DMessageScrollerViewport.builder(
                      itemCount: _messages.length,
                      itemIdBuilder: (index) => 'stream-$index',
                      scrollAnchorBuilder: (index) => index.isEven,
                      announcementBuilder: (index) => _messages[index],
                      busy: _streaming,
                      contentPadding: const EdgeInsets.all(16),
                      itemBuilder: (context, index) => _MessageRow(
                        text: _messages[index],
                        outgoing: index.isEven,
                        sender: index.isEven ? 'You' : 'Nova',
                        animate: index == _messages.length - 1,
                        animation: _animation,
                      ),
                    ),
                    const DMessageScrollerButton(),
                  ],
                ),
              ),
      ),
      const SizedBox(height: 12),
      DInputGroup(
        semanticLabel: 'Offline message composer',
        children: [
          DInputGroupTextarea(
            controller: _prompt,
            semanticLabel: 'Message prompt',
            minLines: 2,
            maxLines: 3,
          ),
          DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.blockEnd,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                DDropdownMenu(
                  content: DDropdownMenuContent(
                    side: DPopoverSide.top,
                    width: 220,
                    semanticLabel: 'Offline composer tools',
                    children: [
                      for (final tool in const [
                        'Photos & files',
                        'Create image',
                        'Deep research',
                        'Web search',
                      ])
                        DDropdownMenuItem(
                          onPressed: () => setState(() => _tool = tool),
                          child: Text(tool),
                        ),
                    ],
                  ),
                  child: DDropdownMenuTrigger(
                    builder: (context, menu) => DInputGroupButton.icon(
                      icon: const Icon(Icons.add),
                      tooltip: 'Composer tools',
                      hasPopup: true,
                      focusNode: menu.focusNode,
                      onPressed: menu.toggle,
                      size: DInputGroupButtonSize.iconSmall,
                      variant: DButtonVariant.outline,
                    ),
                  ),
                ),
                DInputGroupButton.icon(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Send message',
                  onPressed: _streaming ? null : _streamReply,
                  size: DInputGroupButtonSize.iconSmall,
                  variant: DButtonVariant.primary,
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text('Offline demo · next message: ${_tool ?? 'plain text'}'),
    ],
  );
}

class _AnchoringExample extends StatefulWidget {
  const _AnchoringExample();

  @override
  State<_AnchoringExample> createState() => _AnchoringExampleState();
}

class _AnchoringExampleState extends State<_AnchoringExample> {
  var _role = 'user';
  var _count = 12;
  var _anchor = 7;
  var _reset = 0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DToggleGroup<String>(
        values: [_role],
        allowEmptySelection: false,
        semanticLabel: 'Scroll anchor role',
        items: const [
          DToggleGroupItem(
            value: 'user',
            child: Text('User'),
            semanticLabel: 'Anchor user messages',
          ),
          DToggleGroupItem(
            value: 'assistant',
            child: Text('Assistant'),
            semanticLabel: 'Anchor assistant messages',
          ),
        ],
        onChanged: (values) => setState(() {
          _role = values.single;
          _anchor = _role == 'user' ? 7 : 8;
          _count = 12;
          _reset++;
        }),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: DButton(
          label: const Text('Append turn'),
          onPressed: () => setState(() {
            _anchor = _count + (_role == 'user' ? 0 : 1);
            _count += 2;
          }),
          variant: DButtonVariant.secondary,
        ),
      ),
      const SizedBox(height: 12),
      _Frame(
        child: DMessageScrollerProvider(
          key: ValueKey(_reset),
          initialPosition: DMessageScrollerInitialPosition.lastAnchor,
          child: DMessageScroller(
            children: [
              DMessageScrollerViewport.builder(
                itemCount: _count,
                itemIdBuilder: (index) => 'group-$index',
                scrollAnchorBuilder: (index) => index == _anchor,
                contentPadding: const EdgeInsets.all(16),
                itemBuilder: (context, index) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (index == _anchor)
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
      ),
    ],
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
  var _outlineExpanded = false;

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
          DHoverCard(
            trigger: DHoverCardTrigger(
              builder: (context, trigger) => Semantics(
                expanded: _outlineExpanded,
                child: DButton(
                  label: const Text('Transcript outline'),
                  focusNode: trigger.focusNode,
                  variant: DButtonVariant.outline,
                  onPressed: () =>
                      setState(() => _outlineExpanded = !_outlineExpanded),
                ),
              ),
            ),
            content: DHoverCardContent(child: _outline(preview: true)),
          ),
        ],
      ),
      if (_outlineExpanded) ...[const SizedBox(height: 8), _outline()],
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
                scrollAnchorBuilder: (index) => index % 8 == 0,
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

  Widget _outline({bool preview = false}) => AnimatedBuilder(
    key: ValueKey('transcript-outline-$preview'),
    animation: _controller,
    builder: (context, _) => Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var index = 0; index < 40; index += 8)
          DButton(
            label: Text('Turn ${index ~/ 8 + 1}'),
            variant: _controller.state.currentAnchorId == 'command-$index'
                ? DButtonVariant.secondary
                : DButtonVariant.ghost,
            onPressed: () => _controller.scrollToMessage(
              'command-$index',
              options: const DMessageScrollerScrollOptions(
                behavior: DMessageScrollerScrollBehavior.smooth,
              ),
            ),
          ),
      ],
    ),
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
  var _showFocusRing = false;
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
          DButton(
            label: Text(_showFocusRing ? 'Hide focus ring' : 'Show focus ring'),
            onPressed: () => setState(() => _showFocusRing = !_showFocusRing),
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
                showFocusRing: _showFocusRing,
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

enum _EntryAnimation {
  slide('Slide and fade'),
  fade('Fade'),
  none('No animation');

  const _EntryAnimation(this.label);
  final String label;
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.text,
    required this.sender,
    this.outgoing = false,
    this.animate = false,
    this.animation = _EntryAnimation.slide,
  });

  final String text;
  final String sender;
  final bool outgoing;
  final bool animate;
  final _EntryAnimation animation;

  @override
  Widget build(BuildContext context) {
    final align = outgoing ? DMessageAlign.end : DMessageAlign.start;
    final bubbleAlign = outgoing ? DBubbleAlign.end : DBubbleAlign.start;
    final message = DMessage(
      align: align,
      children: [
        DMessageAvatar(
          child: DAvatar(
            dimension: 32,
            semanticLabel: '$sender avatar',
            fallback: DAvatarFallback(child: Text(sender.characters.first)),
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
    if (!animate || animation == _EntryAnimation.none) return message;
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
          offset: Offset(
            0,
            animation == _EntryAnimation.slide ? 8 * (1 - value) : 0,
          ),
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
  options: const DMessageScrollerScrollOptions(
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
