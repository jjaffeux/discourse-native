import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

void main() {
  Widget host(
    Widget child, {
    double width = 360,
    double height = 320,
    bool disableAnimations = false,
    double textScale = 1,
    TextDirection direction = TextDirection.ltr,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        disableAnimations: disableAnimations,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Center(
            child: SizedBox(width: width, height: height, child: child),
          ),
        ),
      ),
    ),
  );

  List<DMessageScrollerItem> rows(
    Iterable<String> ids, {
    Set<String> anchors = const {},
    double Function(String id)? height,
  }) => [
    for (final id in ids)
      DMessageScrollerItem(
        key: ValueKey(id),
        messageId: id,
        scrollAnchor: anchors.contains(id),
        announcement: 'New message $id',
        child: SizedBox(
          height: height?.call(id) ?? 72,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('Message $id'),
          ),
        ),
      ),
  ];

  Widget scroller({
    required List<DMessageScrollerItem> items,
    DMessageScrollerController? controller,
    ScrollController? scrollController,
    bool autoScroll = false,
    DMessageScrollerInitialPosition initial =
        DMessageScrollerInitialPosition.end,
    bool busy = false,
    bool showButton = true,
    VoidCallback? onUserScrollIntent,
  }) => DMessageScrollerProvider(
    controller: controller,
    autoScroll: autoScroll,
    initialPosition: initial,
    child: DMessageScroller(
      children: [
        DMessageScrollerViewport(
          scrollController: scrollController,
          onUserScrollIntent: onUserScrollIntent,
          content: DMessageScrollerContent(
            padding: const EdgeInsets.all(16),
            busy: busy,
            children: items,
          ),
        ),
        if (showButton) const DMessageScrollerButton(),
      ],
    ),
  );

  testWidgets('opens at the end without flashing and publishes edge state', (
    tester,
  ) async {
    final controller = DMessageScrollerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(scroller(controller: controller, items: rows(['1', '2', '3', '4']))),
    );

    Iterable<Visibility> hiddenMaintainedViewports() => tester
        .widgetList<Visibility>(find.byType(Visibility))
        .where(
          (widget) =>
              !widget.visible && widget.maintainState && widget.maintainSize,
        );
    expect(hiddenMaintainedViewports(), hasLength(1));

    await tester.pump();
    await tester.pump();

    expect(hiddenMaintainedViewports(), isEmpty);

    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, scroll.position.maxScrollExtent);
    expect(controller.state.pendingInitialScroll, isFalse);
    expect(controller.state.canScrollStart, isTrue);
    expect(controller.state.canScrollEnd, isFalse);
    expect(find.bySemanticsLabel('Scroll to end'), findsNothing);
    expect(find.bySemanticsLabel('Messages'), findsOneWidget);
  });

  testWidgets('commands align stable ids and reject an unknown mounted id', (
    tester,
  ) async {
    final controller = DMessageScrollerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        scroller(
          controller: controller,
          initial: DMessageScrollerInitialPosition.start,
          items: rows(List.generate(10, (index) => '$index')),
        ),
      ),
    );
    await tester.pump();

    expect(controller.scrollToMessage('6'), isTrue);
    await tester.pumpAndSettle();
    final viewportTop = tester
        .getTopLeft(find.byType(DMessageScrollerViewport))
        .dy;
    // The label is centered inside its 72px row; the row itself is at start.
    expect(
      tester.getTopLeft(find.text('Message 6')).dy - viewportTop,
      closeTo(26, 1),
    );
    expect(controller.scrollToMessage('missing'), isFalse);

    expect(controller.scrollToStart(), isTrue);
    await tester.pump();
    expect(controller.state.canScrollStart, isFalse);
    expect(controller.scrollToEnd(), isTrue);
    await tester.pump();
    expect(controller.state.canScrollEnd, isFalse);
  });

  testWidgets('custom edge-button content keeps scrolling and callbacks', (
    tester,
  ) async {
    final controller = DMessageScrollerController();
    var presses = 0;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        DMessageScrollerProvider(
          controller: controller,
          initialPosition: DMessageScrollerInitialPosition.start,
          child: DMessageScroller(
            children: [
              DMessageScrollerViewport(
                content: DMessageScrollerContent(
                  children: rows(['1', '2', '3', '4', '5', '6']),
                ),
              ),
              DMessageScrollerButton(
                semanticLabel: 'Latest custom',
                onPressed: () => presses++,
                child: const Icon(Icons.vertical_align_bottom),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.state.canScrollEnd, isTrue);

    expect(find.bySemanticsLabel('Latest custom'), findsOneWidget);
    await tester.tap(find.byType(DButton));
    expect(presses, 1);
    await tester.pumpAndSettle();

    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, scroll.position.maxScrollExtent);
  });

  testWidgets('borrowed controllers and focus nodes remain caller-owned', (
    tester,
  ) async {
    final controller = DMessageScrollerController();
    final scroll = ScrollController();
    final list = ListController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    addTearDown(list.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      host(
        DMessageScrollerProvider(
          controller: controller,
          child: DMessageScroller(
            children: [
              DMessageScrollerViewport(
                scrollController: scroll,
                listController: list,
                focusNode: focus,
                content: DMessageScrollerContent(children: rows(['1', '2'])),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    void listener() {}
    expect(() => controller.addListener(listener), returnsNormally);
    controller.removeListener(listener);
    expect(() => scroll.addListener(listener), returnsNormally);
    scroll.removeListener(listener);
    expect(() => list.addListener(listener), returnsNormally);
    list.removeListener(listener);
    expect(() => focus.addListener(listener), returnsNormally);
    focus.removeListener(listener);
  });

  testWidgets(
    'queues a message target until an initially empty transcript mounts',
    (tester) async {
      final controller = DMessageScrollerController();
      addTearDown(controller.dispose);
      final key = GlobalKey<_MutableTranscriptState>();
      await tester.pumpWidget(
        host(_MutableTranscript(key: key, controller: controller)),
      );
      await tester.pump();

      expect(controller.scrollToMessage('later'), isTrue);
      key.currentState!.replace(['before', 'later', 'after', 'tail']);
      await tester.pumpAndSettle();
      final viewportTop = tester
          .getTopLeft(find.byType(DMessageScrollerViewport))
          .dy;
      expect(
        tester.getTopLeft(find.text('Message later')).dy - viewportTop,
        closeTo(0, 1),
      );
    },
  );

  testWidgets('anchors a newly appended turn with the previous-context peek', (
    tester,
  ) async {
    final controller = DMessageScrollerController();
    addTearDown(controller.dispose);
    final key = GlobalKey<_MutableTranscriptState>();
    await tester.pumpWidget(
      host(
        _MutableTranscript(
          key: key,
          controller: controller,
          autoScroll: true,
          initialIds: const ['old-1', 'old-2', 'old-3', 'old-4'],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    key.currentState!.append('new-turn', anchor: true, height: 180);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final viewportTop = tester
        .getTopLeft(find.byType(DMessageScrollerViewport))
        .dy;
    final anchorTop = tester.getTopLeft(find.text('Message new-turn')).dy;
    expect(anchorTop - viewportTop, closeTo(64, 2));
    expect(controller.state.currentAnchorId, 'new-turn');

    controller.scrollToEnd();
    await tester.pumpAndSettle();
    key.currentState!.append('second-turn', anchor: true, height: 180);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final secondAnchorTop = tester.getTopLeft(find.text('Message second-turn'));
    expect(secondAnchorTop.dy - viewportTop, closeTo(64, 2));
    expect(controller.state.currentAnchorId, 'second-turn');
  });

  testWidgets('follows streaming growth only until the reader moves away', (
    tester,
  ) async {
    final controller = DMessageScrollerController();
    addTearDown(controller.dispose);
    final key = GlobalKey<_MutableTranscriptState>();
    await tester.pumpWidget(
      host(
        _MutableTranscript(
          key: key,
          controller: controller,
          autoScroll: true,
          initialIds: const ['1', '2', '3', '4'],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(controller.state.followingLiveEdge, isTrue);

    key.currentState!.setHeight('4', 180);
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, scroll.position.maxScrollExtent);

    await tester.drag(find.byType(Scrollable), const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(controller.state.followingLiveEdge, isFalse);
    final heldId = controller.state.visibleMessageIds.first;
    final heldTop = tester.getTopLeft(find.text('Message $heldId')).dy;
    key.currentState!.setHeight('4', 260);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Message $heldId')).dy,
      closeTo(heldTop, 1),
    );
    expect(controller.state.canScrollEnd, isTrue);
  });

  testWidgets(
    'preserves the first visible variable-height row when history prepends',
    (tester) async {
      final scroll = ScrollController();
      final controller = DMessageScrollerController();
      addTearDown(scroll.dispose);
      addTearDown(controller.dispose);
      final key = GlobalKey<_MutableTranscriptState>();
      await tester.pumpWidget(
        host(
          _MutableTranscript(
            key: key,
            controller: controller,
            scrollController: scroll,
            initialIds: const ['4', '5', '6', '7', '8', '9'],
            initial: DMessageScrollerInitialPosition.start,
          ),
        ),
      );
      await tester.pump();
      scroll.jumpTo(120);
      await tester.pump();
      final before = tester.getTopLeft(find.text('Message 5')).dy;

      key.currentState!.prepend(['1', '2', '3'], heights: [40, 96, 52]);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(tester.getTopLeft(find.text('Message 5')).dy, closeTo(before, 1));
    },
  );

  testWidgets('virtualized builder jumps across a thousand stable rows', (
    tester,
  ) async {
    final controller = DMessageScrollerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        DMessageScrollerProvider(
          controller: controller,
          initialPosition: DMessageScrollerInitialPosition.start,
          child: DMessageScroller(
            children: [
              DMessageScrollerViewport.builder(
                itemCount: 1000,
                itemIdBuilder: (index) => 'row-$index',
                scrollAnchorBuilder: (index) => index.isEven,
                itemBuilder: (_, index) => SizedBox(
                  height: 40 + (index % 4) * 11,
                  child: Text('Virtual $index'),
                ),
              ),
              const DMessageScrollerButton(),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Virtual 900'), findsNothing);
    expect(controller.scrollToMessage('row-900'), isTrue);
    await tester.pump();
    await tester.pump();
    expect(find.text('Virtual 900'), findsOneWidget);
    expect(controller.state.visibleMessageIds, contains('row-900'));
  });

  testWidgets(
    'keyboard, wheel, RTL, large text and reduced motion preserve intent',
    (tester) async {
      final controller = DMessageScrollerController();
      var intents = 0;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          scroller(
            controller: controller,
            initial: DMessageScrollerInitialPosition.start,
            onUserScrollIntent: () => intents++,
            items: rows(List.generate(12, (index) => '$index')),
          ),
          width: 220,
          textScale: 2,
          direction: TextDirection.rtl,
          disableAnimations: true,
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      expect(controller.state.canScrollStart, isTrue);
      expect(intents, greaterThan(0));

      final rect = tester.getRect(find.byType(DMessageScrollerViewport));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: rect.center,
          scrollDelta: const Offset(0, 40),
        ),
      );
      await tester.pump();
      expect(intents, greaterThan(1));
      expect(tester.takeException(), isNull);
    },
  );
}

class _MutableTranscript extends StatefulWidget {
  const _MutableTranscript({
    super.key,
    required this.controller,
    this.scrollController,
    this.initialIds = const [],
    this.autoScroll = false,
    this.initial = DMessageScrollerInitialPosition.end,
  });

  final DMessageScrollerController controller;
  final ScrollController? scrollController;
  final List<String> initialIds;
  final bool autoScroll;
  final DMessageScrollerInitialPosition initial;

  @override
  State<_MutableTranscript> createState() => _MutableTranscriptState();
}

class _MutableTranscriptState extends State<_MutableTranscript> {
  late List<String> ids = [...widget.initialIds];
  final Map<String, double> heights = {};
  final Set<String> anchors = {};

  void replace(List<String> value) => setState(() => ids = [...value]);

  void append(String id, {bool anchor = false, double? height}) => setState(() {
    ids.add(id);
    if (anchor) anchors.add(id);
    if (height != null) heights[id] = height;
  });

  void prepend(List<String> value, {required List<double> heights}) =>
      setState(() {
        ids.insertAll(0, value);
        for (var index = 0; index < value.length; index++) {
          this.heights[value[index]] = heights[index];
        }
      });

  void setHeight(String id, double height) =>
      setState(() => heights[id] = height);

  @override
  Widget build(BuildContext context) => DMessageScrollerProvider(
    controller: widget.controller,
    autoScroll: widget.autoScroll,
    initialPosition: widget.initial,
    child: DMessageScroller(
      children: [
        DMessageScrollerViewport(
          scrollController: widget.scrollController,
          content: DMessageScrollerContent(
            children: [
              for (final id in ids)
                DMessageScrollerItem(
                  key: ValueKey(id),
                  messageId: id,
                  scrollAnchor: anchors.contains(id),
                  child: SizedBox(
                    height: heights[id] ?? 72,
                    child: Text('Message $id'),
                  ),
                ),
            ],
          ),
        ),
        const DMessageScrollerButton(),
      ],
    ),
  );
}
