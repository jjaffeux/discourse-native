import 'dart:ui' show SemanticsAction, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('matches documented size, orientation, and media geometry', (
    tester,
  ) async {
    for (final size in DAttachmentSize.values) {
      await tester.pumpWidget(_app(_attachment(size: size)));
      final media = tester.getSize(find.byKey(const ValueKey('media')));
      expect(media.width, switch (size) {
        DAttachmentSize.regular => 40,
        DAttachmentSize.small => 32,
        DAttachmentSize.extraSmall => 28,
      });
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
      const Size(94, 94),
    );
  });

  testWidgets('all lifecycle states expose visible information beyond color', (
    tester,
  ) async {
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
      expect(tester.takeException(), isNull);
    }
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
        Center(
          child: DAttachment(
            width: 320,
            children: [
              const DAttachmentMedia(child: Icon(Icons.description_outlined)),
              const DAttachmentContent(
                key: ValueKey('content'),
                children: [DAttachmentTitle(child: Text('report.pdf'))],
              ),
              const DAttachmentActions(
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
  String description = 'PDF · 2 MB',
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
      children: [
        DAttachmentTitle(child: Text(title)),
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
