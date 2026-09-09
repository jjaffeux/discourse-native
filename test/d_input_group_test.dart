import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('touch keeps 48px hit bounds around compact 32px artwork', (
    tester,
  ) async {
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
    expect(tester.getSize(find.byType(DInputGroup)).height, 48);
    final decorated = tester.widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byType(DInputGroup),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(decorated, isNotEmpty);
    expect(decorated.first.constraints, const BoxConstraints(minHeight: 32));

    final bounds = tester.getRect(find.byType(DInputGroup));
    await tester.tapAt(bounds.topCenter + const Offset(0, 2));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('inline input keeps compact 32px grouped surface', (
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

    expect(tester.getSize(find.byType(DInputGroup)).height, 32);
    expect(tester.getSize(find.byType(EditableText)).height, 20);
  });

  testWidgets('editor focus repaints the shared group ring', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      host(
        DInputGroup(
          children: [
            DInputGroupInput(focusNode: focus, semanticLabel: 'Query'),
            const DInputGroupAddon(child: Icon(Icons.search)),
          ],
        ),
      ),
    );
    await tester.pump();

    AnimatedContainer surface() => tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(DInputGroup),
        matching: find.byType(AnimatedContainer),
      ),
    );

    final unfocusedDecoration = surface().foregroundDecoration;
    focus.requestFocus();
    await tester.pump();
    await tester.pump();

    expect(focus.hasFocus, isTrue);
    expect(surface().foregroundDecoration, isNot(same(unfocusedDecoration)));
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

  testWidgets(
    'joined input action preserves independent semantics and actions',
    (tester) async {
      final handle = tester.ensureSemantics();
      var submitted = '';
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                DInputGroup(
                  semanticLabel: 'Search group',
                  children: [
                    DInputGroupInput(
                      hintText: 'Type to search...',
                      semanticLabel: 'Search query',
                      onChanged: (value) => submitted = value,
                    ),
                    DInputGroupAddon(
                      alignment: DInputGroupAddonAlignment.inlineEnd,
                      child: DInputGroupButton(
                        label: const Text('Search'),
                        semanticLabel: 'Search',
                        onPressed: () =>
                            setState(() => submitted = 'searched $submitted'),
                      ),
                    ),
                  ],
                ),
                Text(submitted),
              ],
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'widgets');
      await tester.tap(find.text('Search'));
      await tester.pump();

      expect(find.text('searched widgets'), findsOneWidget);
      final editor = tester.getSemantics(find.byType(EditableText));
      expect(editor.label, startsWith('Search query'));
      expect(editor.getSemanticsData().flagsCollection.isTextField, isTrue);
      final button = tester.getSemantics(find.byType(DButton));
      expect(button.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(button.label, contains('Search'));
      handle.dispose();
    },
  );

  testWidgets('form reset and validation stay owned by grouped control', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final form = GlobalKey<FormState>();
    String? saved;
    await tester.pumpWidget(
      host(
        Form(
          key: form,
          child: DInputGroup(
            invalid: true,
            children: [
              DInputGroupInput(
                initialValue: 'initial',
                semanticLabel: 'Username',
                isRequired: true,
                validator: (value) => value!.trim().isEmpty ? 'Required' : null,
                onSaved: (value) => saved = value,
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
    form.currentState!.save();
    expect(saved, 'jane');
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
                DInputGroupInput(
                  semanticLabel: 'بحث',
                  isRequired: true,
                  invalid: true,
                ),
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
    expect(padding.padding, const EdgeInsets.fromLTRB(6, 5, 6, 5));
  });

  testWidgets('keycap addons use the reduced inset and offset radius', (
    tester,
  ) async {
    final tokens = AppTheme.light.extension<DTokens>()!.copyWith(radius: 10);
    await tester.pumpWidget(
      host(
        theme: AppTheme.light.copyWith(extensions: [tokens]),
        DInputGroup(
          children: [
            DInputGroupInput(hintText: 'Search...', semanticLabel: 'Search'),
            const DInputGroupAddon(
              key: ValueKey('direct'),
              alignment: DInputGroupAddonAlignment.inlineEnd,
              children: [DKbd('⌘'), DKbd('K')],
            ),
            const DInputGroupAddon(
              key: ValueKey('grouped'),
              child: DShortcutKeycaps(
                platform: TargetPlatform.linux,
                listenToKeyboard: false,
                shortcut: DShortcut(
                  SingleActivator(LogicalKeyboardKey.keyK, control: true),
                ),
              ),
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
    BorderRadiusGeometry? keycapRadius(Finder keycap) =>
        (tester
                    .widget<AnimatedContainer>(
                      find.descendant(
                        of: keycap,
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration!
                as BoxDecoration)
            .borderRadius;
    expect(
      addonPadding(const ValueKey('direct')),
      const EdgeInsetsDirectional.only(end: 5.6, top: 6, bottom: 6),
    );
    expect(
      addonPadding(const ValueKey('grouped')),
      const EdgeInsetsDirectional.only(start: 5.6, top: 6, bottom: 6),
    );
    final command = find.widgetWithText(DKbd, '⌘');
    final directK = find.descendant(
      of: find.byKey(const ValueKey('direct')),
      matching: find.widgetWithText(DKbd, 'K'),
    );
    expect(keycapRadius(command), BorderRadius.circular(5));
    expect(keycapRadius(directK), BorderRadius.circular(5));
    expect(
      keycapRadius(find.widgetWithText(DKbd, 'Ctrl')),
      BorderRadius.circular(6),
    );
    expect(tester.getTopLeft(directK).dx - tester.getTopRight(command).dx, 8);
  });
}
