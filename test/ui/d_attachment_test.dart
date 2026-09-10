import 'dart:ui' show SemanticsAction, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('matches documented padding, size, and orientation geometry', (
    tester,
  ) async {
    for (final size in DAttachmentSize.values) {
      await tester.pumpWidget(
        _app(
          _attachment(
            size: size,
            description: size == DAttachmentSize.extraSmall
                ? null
                : 'PDF · 2 MB',
          ),
        ),
      );
      final attachment = tester.getRect(find.byType(DAttachment));
      final media = tester.getRect(find.byKey(const ValueKey('media')));
      final content = tester.getRect(find.byKey(const ValueKey('content')));
      final expectedMediaWidth = switch (size) {
        DAttachmentSize.regular => 40,
        DAttachmentSize.small => 32,
        DAttachmentSize.extraSmall => 28,
      };
      final expectedPadding = switch (size) {
        DAttachmentSize.regular => 8,
        DAttachmentSize.small => 6,
        DAttachmentSize.extraSmall => 4,
      };
      final expectedGap = switch (size) {
        DAttachmentSize.regular => 8,
        DAttachmentSize.small => 10,
        DAttachmentSize.extraSmall => 6,
      };
      final expectedHeight = switch (size) {
        DAttachmentSize.regular => 58,
        DAttachmentSize.small => 47,
        DAttachmentSize.extraSmall => 38,
      };
      expect(media.width, expectedMediaWidth);
      expect(media.left - attachment.left, expectedPadding + 1);
      expect(content.left - media.right, expectedGap);
      expect(attachment.height, expectedHeight);
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(
      _app(
        _attachment(
          orientation: DAttachmentOrientation.vertical,
          mediaVariant: DAttachmentMediaVariant.image,
        ),
      ),
    );
    expect(tester.getSize(find.byType(DAttachment)).width, 96);
    expect(
      tester.getSize(find.byKey(const ValueKey('media'))),
      const Size(78, 78),
    );
  });

  testWidgets('all lifecycle states expose visible information beyond color', (
    tester,
  ) async {
    double? attachmentHeight;
    for (final state in DAttachmentState.values) {
      final description = switch (state) {
        DAttachmentState.idle => 'Ready to upload',
        DAttachmentState.uploading => 'Uploading · 64%',
        DAttachmentState.processing => 'Processing document',
        DAttachmentState.error => 'Upload failed. Try again.',
        DAttachmentState.done => 'Uploaded · 1.8 MB',
      };
      await tester.pumpWidget(
        _app(_attachment(state: state, description: description)),
      );
      expect(find.text(description), findsOneWidget);
      final shimmer = tester.widget<DMarkerContent>(
        find.byType(DMarkerContent),
      );
      expect(
        shimmer.shimmer,
        state == DAttachmentState.uploading ||
            state == DAttachmentState.processing,
      );
      final renderedHeight = tester.getSize(find.byType(DAttachment)).height;
      attachmentHeight ??= renderedHeight;
      expect(renderedHeight, attachmentHeight);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('uploading and processing titles animate their shimmer', (
    tester,
  ) async {
    for (final state in [
      DAttachmentState.uploading,
      DAttachmentState.processing,
    ]) {
      await tester.pumpWidget(
        _app(
          _attachment(
            state: state,
            title: state == DAttachmentState.uploading
                ? 'design-system.zip'
                : 'market-research.pdf',
            description: state == DAttachmentState.uploading
                ? 'Uploading · 64%'
                : 'Processing document',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ShaderMask), findsOneWidget, reason: state.name);
      expect(tester.binding.hasScheduledFrame, isTrue, reason: state.name);
    }

    await tester.pumpWidget(
      _app(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: DAttachment(
            state: DAttachmentState.uploading,
            children: [
              DAttachmentContent(
                children: [
                  DAttachmentTitle(child: Text('design-system.zip')),
                  DAttachmentDescription(child: Text('Uploading · 64%')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('idle ready-to-upload state paints a dashed border', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _attachment(
          state: DAttachmentState.idle,
          title: 'selected-file.pdf',
          description: 'Ready to upload',
        ),
      ),
    );

    final dashedBorder = find.descendant(
      of: find.byType(DAttachment),
      matching: find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.foregroundPainter != null,
      ),
    );
    expect(dashedBorder, findsOneWidget);
    expect(
      dashedBorder,
      paints
        ..path()
        ..path()
        ..path(),
    );

    await tester.pumpWidget(
      _app(
        _attachment(
          state: DAttachmentState.done,
          title: 'selected-file.pdf',
          description: 'Uploaded',
        ),
      ),
    );
    expect(
      tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(DAttachment),
              matching: find.byType(CustomPaint),
            ),
          )
          .where((paint) => paint.foregroundPainter != null),
      isEmpty,
    );
  });

  testWidgets(
    'trigger and actions remain independently clickable and focusable',
    (tester) async {
      var opens = 0;
      var removes = 0;
      await tester.pumpWidget(
        _app(
          Center(
            child: DAttachment(
              width: 320,
              children: [
                const DAttachmentMedia(child: Icon(Icons.description_outlined)),
                const DAttachmentContent(
                  children: [
                    DAttachmentTitle(child: Text('report.pdf')),
                    DAttachmentDescription(child: Text('PDF · 2 MB')),
                  ],
                ),
                DAttachmentActions(
                  children: [
                    DAttachmentAction(
                      icon: const Icon(Icons.close),
                      tooltip: 'Remove report.pdf',
                      onPressed: () => removes++,
                    ),
                  ],
                ),
                DAttachmentTrigger(
                  semanticLabel: 'Open report.pdf',
                  isLink: true,
                  onPressed: () => opens++,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Remove report.pdf'));
      expect((opens, removes), (0, 1));
      await tester.tapAt(tester.getCenter(find.byType(DAttachment)));
      expect((opens, removes), (1, 1));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(opens + removes, 4);

      final semantics = tester.getSemantics(find.byType(DAttachment));
      expect(
        semantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      expect(find.bySemanticsLabel('Open report.pdf'), findsOneWidget);
      expect(find.bySemanticsLabel('Remove report.pdf'), findsOneWidget);
    },
  );

  testWidgets('horizontal actions reserve only their rendered button width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Center(
          child: DAttachment(
            width: 320,
            children: [
              DAttachmentMedia(child: Icon(Icons.description_outlined)),
              DAttachmentContent(
                key: ValueKey('content'),
                children: [DAttachmentTitle(child: Text('report.pdf'))],
              ),
              DAttachmentActions(
                children: [
                  DAttachmentAction(
                    icon: Icon(Icons.copy),
                    tooltip: 'Copy report.pdf',
                    onPressed: _noop,
                  ),
                  DAttachmentAction(
                    icon: Icon(Icons.close),
                    tooltip: 'Remove report.pdf',
                    onPressed: _noop,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final actions = tester.getRect(find.byType(DAttachmentActions));
    final content = tester.getRect(find.byKey(const ValueKey('content')));
    expect(actions.width, 44);
    expect(actions.left - content.right, greaterThanOrEqualTo(8));
  });

  testWidgets('disabled action and trigger announce disabled and stay inert', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const DAttachment(
          children: [
            DAttachmentContent(
              children: [DAttachmentTitle(child: Text('locked.pdf'))],
            ),
            DAttachmentActions(
              children: [
                DAttachmentAction(
                  icon: Icon(Icons.close),
                  tooltip: 'Remove locked.pdf',
                  onPressed: null,
                ),
              ],
            ),
            DAttachmentTrigger(
              semanticLabel: 'Open locked.pdf',
              onPressed: null,
            ),
          ],
        ),
      ),
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Open locked.pdf'))
          .getSemanticsData()
          .flagsCollection
          .isEnabled,
      Tristate.isFalse,
    );
    await tester.tap(find.text('locked.pdf'), warnIfMissed: false);
    await tester.tap(
      find.bySemanticsLabel('Remove locked.pdf'),
      warnIfMissed: false,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'touch actions keep 48px targets without changing media artwork',
    (tester) async {
      await tester.pumpWidget(
        _app(_attachment(withAction: true), platform: TargetPlatform.android),
      );
      expect(
        tester.getSize(find.byType(DAttachmentAction)),
        const Size(48, 48),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('media'))),
        const Size(40, 40),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'presentational group scrolls from keyboard and borrows resources',
    (tester) async {
      final controller = ScrollController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 240,
            child: DAttachmentGroup(
              controller: controller,
              focusNode: focusNode,
              semanticLabel: 'Project attachments',
              children: [
                for (var i = 0; i < 4; i++)
                  _attachment(width: 200, title: 'file-$i'),
              ],
            ),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(controller.offset, controller.position.maxScrollExtent);

      await tester.pumpWidget(_app(const SizedBox()));
      expect(controller.hasClients, isFalse);
      focusNode.requestFocus();
      expect(focusNode.canRequestFocus, isTrue);
    },
  );

  testWidgets('group pointer drag settles to the documented item snap', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 240,
          child: DAttachmentGroup(
            controller: controller,
            children: [
              for (var i = 0; i < 4; i++)
                _attachment(width: 256, title: 'file-$i'),
            ],
          ),
        ),
      ),
    );
    await tester.drag(find.byType(DAttachmentGroup), const Offset(-190, 0));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(268, 1));
  });

  testWidgets(
    'large text, narrow width, RTL, and live theme changes stay valid',
    (tester) async {
      var dark = false;
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return _app(
              MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SizedBox(
                    width: 260,
                    child: _attachment(
                      width: double.infinity,
                      title: 'تقرير-طويل-جداً-للمبيعات.pdf',
                      description: 'فشل التحميل. حاول مرة أخرى.',
                      state: DAttachmentState.error,
                      withAction: true,
                    ),
                  ),
                ),
              ),
              dark: dark,
            );
          },
        ),
      );
      final before = tester.getSize(find.byType(DAttachment));
      update(() => dark = true);
      await tester.pump();
      expect(tester.getSize(find.byType(DAttachment)), before);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _attachment({
  DAttachmentState state = DAttachmentState.done,
  DAttachmentSize size = DAttachmentSize.regular,
  DAttachmentOrientation orientation = DAttachmentOrientation.horizontal,
  DAttachmentMediaVariant mediaVariant = DAttachmentMediaVariant.icon,
  double? width,
  String title = 'report.pdf',
  String? description = 'PDF · 2 MB',
  bool withAction = false,
}) => DAttachment(
  width: width,
  state: state,
  size: size,
  orientation: orientation,
  children: [
    DAttachmentMedia(
      key: const ValueKey('media'),
      variant: mediaVariant,
      child: mediaVariant == DAttachmentMediaVariant.image
          ? const ColoredBox(color: Colors.blue)
          : const Icon(Icons.description_outlined),
    ),
    DAttachmentContent(
      key: const ValueKey('content'),
      children: [
        DAttachmentTitle(child: Text(title)),
        if (description != null)
          DAttachmentDescription(child: Text(description)),
      ],
    ),
    if (withAction)
      const DAttachmentActions(
        children: [
          DAttachmentAction(
            icon: Icon(Icons.close),
            tooltip: 'Remove report.pdf',
            onPressed: _noop,
          ),
        ],
      ),
  ],
);

void _noop() {}

Widget _app(
  Widget child, {
  TargetPlatform platform = TargetPlatform.macOS,
  bool dark = false,
}) => MaterialApp(
  theme: ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    platform: platform,
    extensions: [
      DTokens.fromTheme(
        ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          platform: platform,
        ),
      ),
    ],
  ),
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);
