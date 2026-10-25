import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pixel_samples.dart';

Widget host(
  Widget child, {
  double width = 360,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  ThemeData? theme,
}) => MaterialApp(
  theme: (theme ?? AppTheme.light).copyWith(platform: TargetPlatform.macOS),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: direction,
        child: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  ),
);

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('fixed viewport scrolls editor and addons at scale $scale', (
      tester,
    ) async {
      final text = TextEditingController(
        text: List.generate(12, (i) => 'Line $i').join('\n'),
      );
      addTearDown(text.dispose);
      await tester.pumpWidget(
        host(
          DInputGroup(
            viewportHeight: 112,
            children: [
              DInputGroupTextarea(controller: text, maxLines: null),
              const DInputGroupAddon(
                alignment: DInputGroupAddonAlignment.blockStart,
                child: Text('Tokens'),
              ),
            ],
          ),
          width: 260,
          scale: scale,
        ),
      );
      await tester.pumpAndSettle();
      final group = find.byType(DInputGroup);
      final bounds = tester.getRect(group);
      expect(bounds.height, 112);
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(DScrollArea),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      expect(position.maxScrollExtent, greaterThan(0));
      await tester.drag(find.byType(DScrollArea), const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(tester.getRect(group), bounds);
      text.text = 'Short';
      await tester.pumpAndSettle();
      expect(tester.getRect(group), bounds);
      expect(position.pixels, 0);
      await tester.tapAt(bounds.bottomLeft + const Offset(20, -8));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('addon focuses the editor while its button stays independent', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var presses = 0;
    await tester.pumpWidget(
      host(
        DInputGroup(
          children: [
            DInputGroupInput(focusNode: focus, semanticLabel: 'Query'),
            const DInputGroupAddon(child: Icon(Icons.search)),
            DInputGroupAddon(
              alignment: DInputGroupAddonAlignment.inlineEnd,
              child: DInputGroupButton.icon(
                icon: const Icon(Icons.clear),
                tooltip: 'Clear query',
                onPressed: () => presses++,
              ),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    focus.unfocus();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.clear));
    expect(presses, 1);
    expect(focus.hasFocus, isFalse);
  });

  testWidgets('custom control borrows focus and reports invalid state', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        DInputGroup(
          semanticLabel: 'Custom message group',
          children: [
            DInputGroupControl(
              focusNode: focus,
              invalid: true,
              multiline: true,
              builder: (context, node) => TextField(
                focusNode: node,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration.collapsed(
                  hintText: 'Custom message',
                ),
              ),
            ),
            const DInputGroupAddon(
              alignment: DInputGroupAddonAlignment.blockEnd,
              child: DInputGroupText(Text('Third-party editor')),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(tester.getSize(find.byType(DInputGroup)).height, greaterThan(64));
    final group = tester.getSemantics(find.byType(DInputGroup));
    expect(group.label, contains('Custom message group'));
    expect(
      group.getSemanticsData().validationResult,
      SemanticsValidationResult.invalid,
    );
    handle.dispose();
  });

  testWidgets('adapted Native editors consume group padding only once', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final semantics = tester.ensureSemantics();
    const editorKey = ValueKey('adapted-editor');
    await tester.pumpWidget(
      host(
        DInputGroup(
          children: [
            DInputGroupControl(
              focusNode: focus,
              invalid: true,
              multiline: true,
              builder: (context, node) => DInput(
                key: editorKey,
                borderless: true,
                maxLines: null,
                focusNode: node,
              ),
            ),
            const DInputGroupAddon(
              alignment: DInputGroupAddonAlignment.blockEnd,
              child: Text('Focus editor'),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getRect(find.byType(EditableText)),
      tester.getRect(find.byKey(editorKey)),
    );
    expect(
      tester
          .getSemantics(find.byType(DInputGroup))
          .getSemanticsData()
          .validationResult,
      SemanticsValidationResult.invalid,
    );
    await tester.tap(find.text('Focus editor'));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), 'Draft');
    await tester.pump();
    expect(
      tester
          .getSemantics(find.byType(DInputGroup))
          .getSemanticsData()
          .validationResult,
      SemanticsValidationResult.invalid,
    );
    semantics.dispose();
  });

  testWidgets('touch hit bounds match the mobile artwork', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: DInputGroup(
                children: [
                  DInputGroupInput(focusNode: focus, hintText: 'Touch input'),
                  const DInputGroupAddon(child: Icon(Icons.search)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(DInputGroup)).height, 30);
    final decorated = tester.widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byType(DInputGroup),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(decorated, isNotEmpty);
    expect(decorated.first.constraints, const BoxConstraints(minHeight: 30));

    final bounds = tester.getRect(find.byType(DInputGroup));
    await tester.tapAt(bounds.topCenter + const Offset(0, 2));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('inline input keeps the regular grouped surface height', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        DInputGroup(
          children: [
            DInputGroupInput(hintText: 'Search...', semanticLabel: 'Search'),
            const DInputGroupAddon(child: Icon(Icons.search)),
          ],
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(DInputGroup)).height,
      DControlStyle.regularHeight,
    );
    expect(tester.getSize(find.byType(EditableText)).height, 19);
  });

  testWidgets('inline addons hug their edges and leave width to the editor', (
    tester,
  ) async {
    const startKey = ValueKey('start-addon');
    const endKey = ValueKey('end-addon');
    await tester.pumpWidget(
      host(
        DInputGroup(
          children: [
            DInputGroupInput(hintText: 'Search...', semanticLabel: 'Search'),
            const DInputGroupAddon(key: startKey, child: Icon(Icons.search)),
            const DInputGroupAddon(
              key: endKey,
              alignment: DInputGroupAddonAlignment.inlineEnd,
              child: DKbd('/'),
            ),
          ],
        ),
      ),
    );

    final group = tester.getRect(find.byType(DInputGroup));
    final start = tester.getRect(find.byKey(startKey));
    final end = tester.getRect(find.byKey(endKey));
    expect(start.left - group.left, lessThan(16));
    expect(group.right - end.right, lessThan(16));
    expect(
      tester.getSize(find.byType(DInputGroupInput)).width,
      greaterThan(280),
    );
  });

  testWidgets('editor focus repaints the shared group ring', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    const boundaryKey = ValueKey('input-group-focus-pixels');
    final base = AppTheme.light;
    final tokens = base.extension<DTokens>()!.copyWith(
      colors: base.colorScheme.copyWith(primary: const Color(0x800000ff)),
    );
    await tester.pumpWidget(
      host(
        RepaintBoundary(
          key: boundaryKey,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: DInputGroup(
              children: [
                DInputGroupInput(focusNode: focus, semanticLabel: 'Query'),
                const DInputGroupAddon(child: Icon(Icons.search)),
              ],
            ),
          ),
        ),
        theme: base.copyWith(extensions: [tokens]),
      ),
    );
    await tester.pumpAndSettle();
    final boundary = find.byKey(boundaryKey);
    final bounds = tester.getRect(find.byType(DInputGroup));
    final top = bounds.topCenter - tester.getRect(boundary).topLeft;
    Future<List<Color>> pixels() => samplePixels(tester, boundary, [
      top + const Offset(0, -1.5),
      top + const Offset(0, -4.5),
    ]);
    expect(focus.hasFocus, isFalse);
    expect((await pixels()).map((color) => color.toARGB32() >>> 24), [0, 0]);
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(tester.getRect(find.byType(DInputGroup)), bounds);
    final focused = await pixels();
    expect(focused.first.toARGB32(), 0x400000ff);
    expect(focused.last.toARGB32() >>> 24, 0);
    focus.unfocus();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect((await pixels()).map((color) => color.toARGB32() >>> 24), [0, 0]);
  });

  testWidgets('group-level disabled state disables and dims its editor', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      host(
        DInputGroup(
          enabled: false,
          children: [
            DInputGroupInput(focusNode: focus, semanticLabel: 'Query'),
            const DInputGroupAddon(child: Icon(Icons.search)),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byType(DInputGroup),
              matching: find.byType(Opacity),
            ),
          )
          .single
          .opacity,
      .5,
    );
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isFalse);
  });

  testWidgets('form reset and validation stay owned by grouped control', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(
      host(
        Form(
          key: form,
          child: DInputGroup(
            invalid: true,
            children: [
              DInput(
                initialValue: 'initial',
                semanticLabel: 'Username',
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
              const DInputGroupAddon(
                alignment: DInputGroupAddonAlignment.inlineEnd,
                child: DInputGroupText(Text('@company.com')),
              ),
            ],
          ),
        ),
      ),
    );

    final initialHeight = tester.getSize(find.byType(DInputGroup)).height;
    await tester.enterText(find.byType(TextField), '');
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    await tester.pump();
    expect(tester.getSize(find.byType(DInputGroup)).height, initialHeight);
    expect(find.text('Required'), findsNothing);
    expect(
      tester
          .getSemantics(find.byType(DInputGroup))
          .getSemanticsData()
          .validationResult,
      SemanticsValidationResult.invalid,
    );
    await tester.enterText(find.byType(TextField), 'jane');
    expect(form.currentState!.validate(), isTrue);
    form.currentState!.reset();
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'initial',
    );
    semantics.dispose();
  });

  testWidgets(
    'block textarea supports footer actions without flex assertions',
    (tester) async {
      var posted = false;
      await tester.pumpWidget(
        host(
          DInputGroup(
            children: [
              DInputGroupTextarea(
                hintText: 'Write a message...',
                semanticLabel: 'Message',
                minLines: 2,
              ),
              DInputGroupAddon(
                alignment: DInputGroupAddonAlignment.blockEnd,
                child: Row(
                  children: [
                    const Expanded(child: Text('0/280')),
                    DInputGroupButton(
                      label: const Text('Post'),
                      onPressed: () => posted = true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(DInputGroup)).height, greaterThan(64));
      await tester.tap(find.text('Post'));
      expect(posted, isTrue);
    },
  );

  testWidgets('invalid text field semantics stay bounded in RTL at 200%', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        Column(
          children: [
            DInputGroup(
              invalid: true,
              children: [
                DInputGroupInput(semanticLabel: 'بحث', invalid: true),
                const DInputGroupAddon(child: Text('١٢ نتيجة')),
              ],
            ),
            TextButton(onPressed: () {}, child: const Text('خارج')),
          ],
        ),
        scale: 2,
        direction: TextDirection.rtl,
      ),
    );

    final editor = tester.getSemantics(find.byType(EditableText));
    expect(editor.label, 'بحث');
    expect(
      editor.getSemanticsData().validationResult,
      SemanticsValidationResult.invalid,
    );
    final outside = tester.getSemantics(find.byType(TextButton));
    expect(outside.getSemanticsData().flagsCollection.isTextField, isFalse);
    handle.dispose();
  });

  testWidgets('custom control uses addon-aware joined padding', (tester) async {
    const controlKey = ValueKey('custom-control');
    await tester.pumpWidget(
      host(
        DInputGroup(
          children: [
            const DInputGroupAddon(child: Text('@')),
            DInputGroupControl(
              builder: (context, focusNode) =>
                  const SizedBox(key: controlKey, height: 20),
            ),
            const DInputGroupAddon(
              alignment: DInputGroupAddonAlignment.inlineEnd,
              child: Text('.com'),
            ),
          ],
        ),
      ),
    );

    final padding = tester.widget<Padding>(
      find
          .ancestor(of: find.byKey(controlKey), matching: find.byType(Padding))
          .first,
    );
    expect(padding.padding, const EdgeInsets.fromLTRB(6, 1, 6, 1));
  });

  testWidgets('block addons keep base padding at their inner edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        DInputGroup(
          children: [
            DInputGroupInput(semanticLabel: 'Name'),
            const DInputGroupAddon(
              key: ValueKey('block-start'),
              alignment: DInputGroupAddonAlignment.blockStart,
              child: Text('First name'),
            ),
            const DInputGroupAddon(
              key: ValueKey('block-end'),
              alignment: DInputGroupAddonAlignment.blockEnd,
              child: Text('Required'),
            ),
          ],
        ),
      ),
    );

    EdgeInsetsGeometry addonPadding(Key key) => tester
        .widget<Padding>(
          find
              .descendant(of: find.byKey(key), matching: find.byType(Padding))
              .first,
        )
        .padding;
    expect(
      addonPadding(const ValueKey('block-start')),
      const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 6),
    );
    expect(
      addonPadding(const ValueKey('block-end')),
      const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 8),
    );
  });
}
