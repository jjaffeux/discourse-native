import 'dart:ui' as ui;
import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/keyboard_navigation.dart';
import 'package:discourse_native/src/styleguide/examples/switch_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    ThemeData? theme,
    bool rtl = false,
    bool reduced = false,
    double scale = 1,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reduced,
          textScaler: TextScaler.linear(scale),
        ),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: Center(child: SizedBox(width: 240, child: child)),
          ),
        ),
      ),
    ),
  );

  testWidgets('desktop rows are intrinsic and touch rows retain 48px targets', (
    tester,
  ) async {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      final touch =
          platform == TargetPlatform.android || platform == TargetPlatform.iOS;
      for (final card in [false, true]) {
        for (final description in [false, true]) {
          var changes = 0;
          await mount(
            tester,
            DSwitchTile(
              value: false,
              onChanged: (_) => changes++,
              leading: true,
              choiceCard: card,
              title: const Text('Title'),
              subtitle: description ? const Text('Description') : null,
            ),
            theme: AppTheme.light.copyWith(platform: platform),
          );
          await tester.pumpAndSettle();
          final height = tester.getSize(find.byType(DSwitchTile)).height;
          final intrinsic = card
              ? (description ? 65.0 : 42.0)
              : (description ? 42.25 : 18.4);
          expect(height, closeTo(touch && intrinsic < 48 ? 48 : intrinsic, .3));
          await tester.tapAt(
            tester.getBottomLeft(find.byType(DSwitchTile)) +
                const Offset(4, -2),
          );
          expect(changes, 1);
        }
      }
    }
  });

  testWidgets(
    'exterior rings leave translucent track and card interiors unchanged',
    (tester) async {
      final strategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
      for (final dark in [false, true]) {
        for (final card in [false, true]) {
          final focus = FocusNode();
          final boundary = GlobalKey();
          final base = dark ? AppTheme.dark : AppTheme.light;
          final tokens = DTokens.fromTheme(base).copyWith(
            colors: base.colorScheme.copyWith(
              outlineVariant: const Color(0x337733aa),
              primary: const Color(0x809944cc),
            ),
          );
          Future<List<int>> pixels(bool invalid, bool focused) async {
            await mount(
              tester,
              RepaintBoundary(
                key: boundary,
                child: ColoredBox(
                  color: tokens.background,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: card
                        ? DSwitchTile(
                            value: false,
                            onChanged: (_) {},
                            choiceCard: true,
                            invalid: invalid,
                            focusNode: focus,
                            title: const Text('Card'),
                          )
                        : DSwitch(
                            value: false,
                            onChanged: (_) {},
                            invalid: invalid,
                            focusNode: focus,
                          ),
                  ),
                ),
              ),
              theme: base.copyWith(
                platform: TargetPlatform.macOS,
                extensions: [tokens],
              ),
            );
            if (focused) {
              focus.requestFocus();
            } else {
              focus.unfocus();
            }
            await tester.pumpAndSettle();
            final container = find.descendant(
              of: find.byType(DSwitch),
              matching: find.byType(AnimatedContainer),
            );
            final bounds = tester.getRect(
              card ? container.first : container.last,
            );
            final origin = tester.getTopLeft(find.byKey(boundary));
            final samples = [
              card
                  ? Offset(bounds.center.dx, bounds.bottom - 5)
                  : Offset(bounds.right - 5, bounds.center.dy),
              Offset(bounds.center.dx, bounds.top - 2),
            ];
            return (await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 2);
              final data = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              final result = <int>[];
              for (final sample in samples) {
                final point = (sample - origin) * 2;
                final index =
                    (point.dy.floor() * image.width + point.dx.floor()) * 4;
                result.addAll(data.buffer.asUint8List(index, 4));
              }
              image.dispose();
              return result;
            }))!;
          }

          final normal = await pixels(false, false);
          final focused = await pixels(false, true);
          expect(
            focused.take(4),
            normal.take(4),
            reason: 'focus must not tint interior: dark=$dark card=$card',
          );
          expect(
            focused.skip(4),
            isNot(normal.skip(4)),
            reason: 'focus ring remains visible outside',
          );
          final invalid = await pixels(true, false);
          expect(
            invalid.take(4),
            normal.take(4),
            reason: 'invalid must not tint interior: dark=$dark card=$card',
          );
          if (!card) expect(invalid.skip(4), isNot(normal.skip(4)));
          await tester.pumpWidget(const SizedBox());
          focus.dispose();
        }
      }
    },
  );

  testWidgets(
    'uncontrolled switch toggles through pointer keyboard and semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final focus = FocusNode();
      addTearDown(focus.dispose);
      final changes = <bool>[];
      await mount(
        tester,
        DSwitch(
          focusNode: focus,
          semanticLabel: 'Airplane',
          onChanged: changes.add,
        ),
      );
      await tester.tap(find.byType(DSwitch));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(
        tester
                .getSemantics(find.byType(DSwitch))
                .getSemanticsData()
                .flagsCollection
                .isToggled ==
            Tristate.isTrue,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final node = tester.getSemantics(find.byType(DSwitch));
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(changes, [true, false, true, false]);
      semantics.dispose();
    },
  );

  testWidgets(
    'controlled edits wait for parent and disabled read-only reject edits',
    (tester) async {
      var calls = 0;
      await mount(tester, DSwitch(value: false, onChanged: (_) => calls++));
      await tester.tap(find.byType(DSwitch));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        tester
                .getSemantics(find.byType(DSwitch))
                .getSemanticsData()
                .flagsCollection
                .isToggled ==
            Tristate.isTrue,
        isFalse,
      );
      for (final readonly in [false, true]) {
        await mount(
          tester,
          DSwitch(
            value: true,
            enabled: readonly,
            readOnly: readonly,
            onChanged: (_) => calls++,
          ),
        );
        await tester.tap(find.byType(DSwitch));
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(calls, 1);
      }
    },
  );

  testWidgets('exact track thumb and directional travel retain 48px targets', (
    tester,
  ) async {
    for (final small in [false, true]) {
      for (final rtl in [false, true]) {
        var checked = false;
        late StateSetter update;
        await mount(
          tester,
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return DSwitch(
                size: small ? DSwitchSize.small : DSwitchSize.standard,
                value: checked,
                onChanged: (v) => setState(() => checked = v),
              );
            },
          ),
          rtl: rtl,
          reduced: true,
        );
        final track = find.descendant(
          of: find.byType(DSwitch),
          matching: find.byType(AnimatedContainer),
        );
        final thumb = find.descendant(
          of: track,
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == (small ? 12 : 16),
          ),
        );
        expect(tester.getSize(track), Size(small ? 24 : 32, small ? 14 : 18.4));
        expect(tester.getSize(thumb), Size.square(small ? 12 : 16));
        final start = tester.getCenter(thumb).dx;
        update(() => checked = true);
        await tester.pump();
        expect(
          tester.getCenter(thumb).dx - start,
          closeTo((small ? 10 : 14) * (rtl ? -1 : 1), .001),
        );
        final target = find.descendant(
          of: find.byType(DSwitch),
          matching: find.byType(GestureDetector),
        );
        expect(tester.getSize(target).height, 48);
      }
    }
  });

  testWidgets(
    'form validates saves resets and follows external controlled changes',
    (tester) async {
      final form = GlobalKey<FormState>();
      final field = GlobalKey<FormFieldState<bool>>();
      bool? saved;
      await mount(
        tester,
        Form(
          key: form,
          child: DSwitchFormField(
            key: field,
            title: const Text('Accept'),
            validator: (v) => v == true ? null : 'Required',
            onSaved: (v) => saved = v,
          ),
        ),
      );
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(form.currentState!.validate(), isTrue);
      form.currentState!.save();
      expect(saved, true);
      form.currentState!.reset();
      await tester.pump();
      expect(field.currentState!.value, false);
      var value = true;
      late StateSetter update;
      await mount(
        tester,
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return Form(
              key: form,
              child: DSwitchFormField(
                key: field,
                value: value,
                title: const Text('Controlled'),
                onChanged: (v) => setState(() => value = v),
              ),
            );
          },
        ),
      );
      expect(field.currentState!.value, true);
      update(() => value = false);
      await tester.pump();
      expect(field.currentState!.value, false);
      update(() => value = true);
      await tester.pump();
      form.currentState!.reset();
      await tester.pump();
      expect(value, false);
      expect(field.currentState!.value, false);
    },
  );

  testWidgets(
    'tile label has one switch semantic action and keyboard blocks pane navigation',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final focus = FocusNode();
      addTearDown(focus.dispose);
      late BuildContext page;
      var changes = 0;
      await mount(
        tester,
        Builder(
          builder: (context) {
            page = context;
            return DSwitchTile(
              value: false,
              focusNode: focus,
              onChanged: (_) => changes++,
              title: const Text('Share'),
              subtitle: const Text('Across devices'),
            );
          },
        ),
      );
      await tester.tap(find.text('Share'));
      await tester.pump();
      expect(changes, 1);
      expect(navigationShortcutsAllowed(page, activation: true), isFalse);
      final node = tester.getSemantics(find.byType(DSwitch));
      expect(node.label, contains('Share'));
      expect(node.label, contains('Across devices'));
      expect(
        node.getSemanticsData().flagsCollection.isToggled != Tristate.none,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      expect(focus.hasFocus, isFalse);
      focus.requestFocus(); // Borrowed node remains usable after removal.
      semantics.dispose();
    },
  );

  testWidgets(
    'live palette updates artwork without resetting uncontrolled value',
    (tester) async {
      for (final theme in [
        AppTheme.light,
        AppTheme.dark,
        ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple)),
      ]) {
        await mount(tester, const DSwitch(initialValue: true), theme: theme);
        final track = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byType(DSwitch),
            matching: find.byType(AnimatedContainer),
          ),
        );
        final context = tester.element(find.byType(DSwitch));
        expect(
          (track.decoration! as BoxDecoration).color,
          DTokens.of(context).primary,
        );
        expect(
          tester
                  .getSemantics(find.byType(DSwitch))
                  .getSemanticsData()
                  .flagsCollection
                  .isToggled ==
              Tristate.isTrue,
          isTrue,
        );
      }
    },
  );

  testWidgets(
    'controlled reset waits for acceptance in semantics validation and save',
    (tester) async {
      final form = GlobalKey<FormState>();
      final field = GlobalKey<FormFieldState<bool>>();
      var accepted = true;
      bool? requested;
      bool? saved;
      late StateSetter update;
      await mount(
        tester,
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return Form(
              key: form,
              child: DSwitchFormField(
                key: field,
                value: accepted,
                initialValue: false,
                title: const Text('Controlled reset'),
                onChanged: (next) => requested = next,
                validator: (next) => next == true ? null : 'Required',
                onSaved: (next) => saved = next,
              ),
            );
          },
        ),
      );
      form.currentState!.reset();
      await tester.pump();
      expect(requested, false);
      expect(field.currentState!.value, true);
      expect(
        tester
            .getSemantics(find.byType(DSwitch))
            .getSemanticsData()
            .flagsCollection
            .isToggled,
        Tristate.isTrue,
      );
      expect(form.currentState!.validate(), true);
      form.currentState!.save();
      expect(saved, true);
      update(() => accepted = requested!);
      await tester.pump();
      expect(field.currentState!.value, false);
      expect(
        tester
            .getSemantics(find.byType(DSwitch))
            .getSemanticsData()
            .flagsCollection
            .isToggled,
        Tristate.isFalse,
      );
      expect(form.currentState!.validate(), false);
      form.currentState!.save();
      expect(saved, false);
    },
  );

  testWidgets(
    'invalid ring is explicit and disabled label opacity is applied once',
    (tester) async {
      await mount(
        tester,
        const DSwitchTile(
          value: false,
          onChanged: null,
          invalid: true,
          title: DLabel(enabled: false, child: Text('Unavailable')),
        ),
      );
      final track = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byType(DSwitch),
              matching: find.byType(AnimatedContainer),
            )
            .last,
      );
      final ring = track.foregroundDecoration! as BoxDecoration;
      expect((ring.border! as Border).top.width, 3);
      expect(
        tester
            .getSemantics(find.byType(DSwitch))
            .getSemanticsData()
            .validationResult,
        SemanticsValidationResult.invalid,
      );
      final opacities = tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byType(DSwitch),
              matching: find.byType(Opacity),
            ),
          )
          .map((w) => w.opacity);
      expect(opacities.where((v) => v == 0.5), hasLength(1));
    },
  );

  testWidgets(
    'choice card hover and keyboard focus match wrapper and track rings',
    (tester) async {
      final strategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await mount(
        tester,
        DSwitchTile(
          value: true,
          onChanged: (_) {},
          choiceCard: true,
          focusNode: focus,
          title: const Text('Card'),
        ),
      );
      final containers = find.descendant(
        of: find.byType(DSwitch),
        matching: find.byType(AnimatedContainer),
      );
      final tokens = DTokens.of(tester.element(find.byType(DSwitch)));
      BoxDecoration card() =>
          tester.widget<AnimatedContainer>(containers.first).decoration!
              as BoxDecoration;
      expect(card().color, tokens.primary.withValues(alpha: .05));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Card')));
      await tester.pumpAndSettle();
      expect(card().color, tokens.muted.withValues(alpha: .5));
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(
        ((tester
                            .widget<AnimatedContainer>(containers.first)
                            .foregroundDecoration!
                        as BoxDecoration)
                    .border!
                as Border)
            .top
            .width,
        3,
      );
      expect(
        ((tester
                            .widget<AnimatedContainer>(containers.last)
                            .foregroundDecoration!
                        as BoxDecoration)
                    .border!
                as Border)
            .top
            .width,
        3,
      );
      await mouse.removePointer();
    },
  );

  testWidgets(
    'input surface stays distinct from border and preserves translucent alpha',
    (tester) async {
      for (final dark in [false, true]) {
        final base = dark ? AppTheme.dark : AppTheme.light;
        final tokens = DTokens.fromTheme(base).copyWith(
          border: const Color(0x66448822),
          colors: base.colorScheme.copyWith(
            outlineVariant: const Color(0x337733aa),
            error: const Color(0x80dd2211),
          ),
        );
        await mount(
          tester,
          const DSwitch(initialValue: false, invalid: true),
          theme: base.copyWith(extensions: [tokens]),
        );
        await tester.pumpAndSettle();
        final track = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byType(DSwitch),
            matching: find.byType(AnimatedContainer),
          ),
        );
        final decoration = track.decoration! as BoxDecoration;
        expect(
          decoration.color,
          tokens.colors.outlineVariant.withValues(
            alpha: tokens.colors.outlineVariant.a * (dark ? .8 : 1),
          ),
        );
        expect(decoration.color, isNot(tokens.border));
        expect(
          (decoration.border! as Border).top.color,
          tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? .5 : 1),
          ),
        );
        expect(
          ((track.foregroundDecoration! as BoxDecoration).border! as Border)
              .top
              .color,
          tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? .4 : .2),
          ),
        );
      }
    },
  );

  testWidgets(
    'choice card live radius and translucent selected hover focus tokens follow source',
    (tester) async {
      final strategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      for (final dark in [false, true]) {
        final base = dark ? AppTheme.dark : AppTheme.light;
        for (final radius in [0.0, 6.0, 18.0]) {
          final tokens = DTokens.fromTheme(base).copyWith(
            radius: radius,
            border: const Color(0x66551122),
            muted: const Color(0x4033aabb),
            colors: base.colorScheme.copyWith(
              primary: const Color(0x809944cc),
              outlineVariant: const Color(0x3333aa99),
            ),
          );
          await mount(
            tester,
            DSwitchTile(
              value: true,
              onChanged: (_) {},
              choiceCard: true,
              focusNode: focus,
              title: const Text('Card'),
            ),
            theme: base.copyWith(extensions: [tokens]),
          );
          await tester.pumpAndSettle();
          final containers = find.descendant(
            of: find.byType(DSwitch),
            matching: find.byType(AnimatedContainer),
          );
          BoxDecoration card() =>
              tester.widget<AnimatedContainer>(containers.first).decoration!
                  as BoxDecoration;
          expect(card().borderRadius, BorderRadius.circular(radius));
          expect(
            card().color,
            tokens.primary.withValues(
              alpha: tokens.primary.a * (dark ? .1 : .05),
            ),
          );
          expect(
            (card().border! as Border).top.color,
            tokens.primary.withValues(
              alpha: tokens.primary.a * (dark ? .2 : .3),
            ),
          );
          await mouse.moveTo(tester.getCenter(find.text('Card')));
          await tester.pumpAndSettle();
          expect(
            card().color,
            tokens.muted.withValues(alpha: tokens.muted.a * .5),
          );
          focus.requestFocus();
          await tester.pumpAndSettle();
          expect((card().border! as Border).top.color, tokens.focusRing);
          expect(
            ((tester
                                .widget<AnimatedContainer>(containers.first)
                                .foregroundDecoration!
                            as BoxDecoration)
                        .border!
                    as Border)
                .top
                .color,
            tokens.focusRing.withValues(alpha: tokens.focusRing.a * .5),
          );
          focus.unfocus();
          await mouse.moveTo(Offset.zero);
          await tester.pumpAndSettle();
        }
        final tokens = DTokens.fromTheme(
          base,
        ).copyWith(border: const Color(0x66551122));
        await mount(
          tester,
          DSwitchTile(
            value: false,
            onChanged: (_) {},
            choiceCard: true,
            title: const Text('Unchecked'),
          ),
          theme: base.copyWith(extensions: [tokens]),
        );
        final card =
            tester
                    .widget<AnimatedContainer>(
                      find
                          .descendant(
                            of: find.byType(DSwitch),
                            matching: find.byType(AnimatedContainer),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration;
        expect((card.border! as Border).top.color, tokens.border);
      }
      await mouse.removePointer();
    },
  );

  testWidgets(
    'choice-card title leading and invalid description match measured source',
    (tester) async {
      await mount(
        tester,
        DSwitchTile(
          choiceCard: true,
          invalid: true,
          value: false,
          onChanged: (_) {},
          title: const Text('Title'),
          subtitle: const Text('One\nTwo'),
        ),
      );
      expect(tester.getSize(find.byType(DSwitchTile)).height, 86);
      final titleStyle = tester
          .renderObject<RenderParagraph>(find.text('Title'))
          .text
          .style!;
      final descriptionStyle = tester
          .renderObject<RenderParagraph>(find.text('One\nTwo'))
          .text
          .style!;
      expect(titleStyle.fontSize! * titleStyle.height!, 20);
      expect(
        titleStyle.color,
        DTokens.of(tester.element(find.byType(DSwitchTile))).destructive,
      );
      expect(
        descriptionStyle.color,
        DTokens.of(tester.element(find.byType(DSwitchTile))).mutedForeground,
      );
    },
  );

  for (final example in switchExamples.examples) {
    testWidgets('${example.title} wraps at narrow width large text and RTL', (
      tester,
    ) async {
      await mount(
        tester,
        SingleChildScrollView(child: Builder(builder: example.builder)),
        rtl: true,
        scale: 2,
        reduced: true,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
