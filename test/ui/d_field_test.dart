import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  Widget child, {
  double width = 500,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: direction,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'label focuses the borrowed editor and metadata preserves editing semantics',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          host(
            DField(
              invalid: true,
              children: [
                DFieldLabel(
                  focusNode: focus,
                  excludeSemantics: true,
                  child: const Text('Email'),
                ),
                DFieldControl(
                  label: 'Email',
                  description: 'Used for receipts.',
                  errors: const ['Enter a valid email.'],
                  required: true,
                  child: TextField(focusNode: focus),
                ),
                const DFieldDescription(child: Text('Used for receipts.')),
                const DFieldError(errors: ['Enter a valid email.']),
              ],
            ),
          ),
        );
        await tester.tap(find.text('Email'));
        await tester.pump();
        expect(focus.hasFocus, isTrue);
        await tester.enterText(find.byType(TextField), 'reader@example.test');
        await tester.pump();
        final node = tester.getSemantics(find.byType(DFieldControl));
        expect(node.label, 'Email');
        expect(node.hint, 'Used for receipts.\nEnter a valid email.');
        expect(node.value, 'reader@example.test');
        expect(node.getSemanticsData().flagsCollection.isTextField, isTrue);
        expect(
          node.getSemanticsData().flagsCollection.isRequired,
          ui.Tristate.isTrue,
        );
        expect(
          node.getSemanticsData().validationResult,
          SemanticsValidationResult.invalid,
        );
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.setText),
          isTrue,
        );
        await tester.pumpWidget(host(const SizedBox()));
        focus.requestFocus();
        expect(focus.debugLabel, isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'responsive reflow preserves editor value focus and Form reset ownership',
    (tester) async {
      final form = GlobalKey<FormState>();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      String? saved;
      Widget content(double width) => host(
        Form(
          key: form,
          child: DFieldGroup(
            children: [
              DField(
                orientation: DFieldOrientation.responsive,
                children: [
                  const DFieldContent(
                    children: [
                      DFieldLabel(child: Text('Name')),
                      DFieldDescription(child: Text('Your full name')),
                    ],
                  ),
                  DFieldControl(
                    label: 'Name',
                    child: TextFormField(
                      focusNode: focus,
                      initialValue: 'Original',
                      validator: (value) => value!.isEmpty ? 'Required' : null,
                      onSaved: (value) => saved = value,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        width: width,
      );
      await tester.pumpWidget(content(500));
      expect(
        tester.getTopLeft(find.byType(TextFormField)).dx,
        greaterThan(tester.getTopLeft(find.text('Name')).dx),
      );
      await tester.enterText(find.byType(TextFormField), 'Changed');
      await tester.pumpWidget(content(320));
      expect(
        tester.getTopLeft(find.byType(TextFormField)).dy,
        greaterThan(tester.getBottomLeft(find.text('Your full name')).dy),
      );
      expect(find.text('Changed'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      expect(form.currentState!.validate(), isTrue);
      form.currentState!.save();
      expect(saved, 'Changed');
      form.currentState!.reset();
      await tester.pump();
      expect(find.text('Original'), findsOneWidget);
    },
  );

  testWidgets(
    'choice card activates once from label or control and keeps one keyboard owner',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var value = false;
      var activations = 0;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              void toggle() => setState(() {
                value = !value;
                activations++;
              });
              return DFieldLabel.choice(
                selected: value,
                onPressed: toggle,
                child: DField(
                  orientation: DFieldOrientation.horizontal,
                  children: [
                    const DFieldContent(
                      children: [
                        DFieldTitle(
                          excludeSemantics: true,
                          child: Text('Kubernetes'),
                        ),
                        DFieldDescription(child: Text('Run GPU workloads.')),
                      ],
                    ),
                    DFieldControl(
                      label: 'Kubernetes',
                      expand: false,
                      child: Checkbox(
                        value: value,
                        focusNode: focus,
                        onChanged: (_) => toggle(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Kubernetes'));
      await tester.pump();
      expect(value, isTrue);
      expect(activations, 1);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(value, isFalse);
      expect(activations, 2);
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(value, isTrue);
      expect(activations, 3);
    },
  );

  testWidgets(
    'disabled fieldset blocks label and control interaction without disposing focus',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var changed = false;
      await tester.pumpWidget(
        host(
          DFieldSet(
            enabled: false,
            children: [
              DFieldLabel.choice(
                selected: false,
                onPressed: () => changed = true,
                child: DField(
                  children: [
                    DFieldControl(
                      label: 'Disabled',
                      child: Checkbox(
                        focusNode: focus,
                        value: false,
                        onChanged: (_) => changed = true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.byType(Checkbox), warnIfMissed: false);
      focus.requestFocus();
      await tester.pump();
      expect(changed, isFalse);
      expect(focus.hasFocus, isFalse);
      final disabledOpacity = tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byType(DFieldLabel),
              matching: find.byType(Opacity),
            ),
          )
          .singleWhere((widget) => widget.opacity == 0.5);
      expect(
        find.descendant(
          of: find.byWidget(disabledOpacity),
          matching: find.byType(DecoratedBox),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'errors deduplicate ignore missing messages and custom content wins',
    (tester) async {
      await tester.pumpWidget(
        host(const DFieldError(errors: [null, '', 'First', 'First', 'Second'])),
      );
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Second')).dy -
            tester.getBottomLeft(find.text('First')).dy,
        4,
      );
      await tester.pumpWidget(
        host(const DFieldError(errors: ['Hidden'], child: Text('Custom'))),
      );
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('Hidden'), findsNothing);
      await tester.pumpWidget(host(const DFieldError(errors: [null, ''])));
      expect(tester.getSize(find.byType(DFieldError)).height, 0);
    },
  );

  testWidgets(
    'field gaps and typography match registry while RTL large text wraps',
    (tester) async {
      const content = DFieldGroup(
        children: [
          DField(
            children: [
              DFieldLabel(child: Text('First label')),
              SizedBox(height: 32),
              DFieldDescription(child: Text('First description')),
            ],
          ),
          DFieldSeparator(child: Text('Or continue with')),
          DField(
            children: [
              DFieldLabel(child: Text('Second label')),
              SizedBox(height: 32),
            ],
          ),
        ],
      );
      await tester.pumpWidget(host(content));
      expect(
        tester.getTopLeft(find.text('First description')).dy -
            tester
                .getBottomLeft(
                  find
                      .byWidgetPredicate((w) => w is SizedBox && w.height == 32)
                      .first,
                )
                .dy,
        8,
      );
      final labelStyle = DefaultTextStyle.of(
        tester.element(find.text('First label')),
      ).style;
      expect(labelStyle.fontSize, 14);
      expect(labelStyle.height, 1.375);
      expect(labelStyle.fontWeight, FontWeight.w500);
      await tester.pumpWidget(
        host(content, width: 180, scale: 2, direction: TextDirection.rtl),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(DFieldSeparator)).height,
        greaterThan(20),
      );
    },
  );
  testWidgets(
    'only direct nested groups use 16px and empty errors add no gap',
    (tester) async {
      await tester.pumpWidget(
        host(
          const DFieldGroup(
            children: [
              DFieldGroup(
                children: [Text('Direct first'), Text('Direct last')],
              ),
              DFieldSet(
                children: [
                  DFieldGroup(
                    children: [Text('Wrapped first'), Text('Wrapped last')],
                  ),
                ],
              ),
              DField(
                children: [
                  Text('Visible'),
                  DFieldError(errors: []),
                ],
              ),
            ],
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Direct last')).dy -
            tester.getBottomLeft(find.text('Direct first')).dy,
        16,
      );
      expect(
        tester.getTopLeft(find.text('Wrapped last')).dy -
            tester.getBottomLeft(find.text('Wrapped first')).dy,
        20,
      );
      expect(
        tester.getSize(find.byType(DField)).height,
        tester.getSize(find.text('Visible')).height,
      );
    },
  );

  testWidgets(
    'choice focus paints only outside and live selected alpha remains multiplicative',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final previous = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = previous);
      final boundary = GlobalKey();
      Widget card(Color primary) {
        final theme = ThemeData.light();
        final tokens = DTokens.fromTheme(theme).copyWith(
          colors: theme.colorScheme.copyWith(primary: primary),
          radius: 10,
        );
        return host(
          RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DFieldLabel.choice(
                  selected: true,
                  onPressed: () {},
                  child: Focus(
                    focusNode: focus,
                    child: const SizedBox(height: 40),
                  ),
                ),
              ),
            ),
          ),
          width: 200,
          theme: theme.copyWith(extensions: [tokens]),
        );
      }

      Future<List<int>> pixel(int x, int y) async =>
          (await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final offset = (y * image.width + x) * 4;
            final result = data!.buffer.asUint8List(offset, 4).toList();
            image.dispose();
            return result;
          }))!;

      await tester.pumpWidget(card(const Color(0x800000ff)));
      final inside = await pixel(100, 30);
      expect(inside[0], closeTo(249, 1));
      expect(inside[2], 255);
      final outside = await pixel(100, 10);
      focus.requestFocus();
      await tester.pump();
      expect(await pixel(100, 30), inside);
      expect(await pixel(100, 10), isNot(outside));
      await tester.pumpWidget(card(const Color(0x80ff0000)));
      await tester.pumpAndSettle();
      expect((await pixel(100, 30))[0], 255);
      expect((await pixel(100, 30))[2], closeTo(249, 1));
    },
  );
}
