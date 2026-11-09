import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final compactBeforeFocus in [false, true]) {
    for (final reduced in [false, true]) {
      testWidgets(
        'focus hides navigation without a keyboard inset and restores scroll state ($compactBeforeFocus, $reduced)',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(390, 844));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final focus = FocusNode();
          final text = TextEditingController(text: 'Keep this draft');
          final scroll = ScrollController(initialScrollOffset: 500);
          addTearDown(focus.dispose);
          addTearDown(text.dispose);
          addTearDown(scroll.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(390, 844),
                  padding: const EdgeInsets.only(bottom: 34),
                  disableAnimations: reduced,
                ),
                child: DScrollChrome(
                  identity: 'chat',
                  floatingFooter: true,
                  footerBuilder: (_) => SizedBox(
                    height: 96,
                    child: DButton(
                      key: const ValueKey('navigation'),
                      onPressed: () {},
                      label: const Text('Navigation'),
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          key: const ValueKey('messages'),
                          controller: scroll,
                          itemCount: 100,
                          itemExtent: 50,
                          itemBuilder: (_, index) => Text('Message $index'),
                        ),
                      ),
                      DComposerDock(
                        builder: (_, compact) => DCard(
                          spacing: 0,
                          child: DInputGroup(
                            key: const ValueKey('composer'),
                            compact: compact,
                            action: DButton.iconOnly(
                              key: const ValueKey('send'),
                              icon: const DIcon(DIcons.paperPlane),
                              tooltip: 'Send',
                              onPressed: () {},
                            ),
                            children: [
                              DInputGroupTextarea(
                                focusNode: focus,
                                controller: text,
                                minLines: compact ? 1 : 3,
                                maxLines: compact ? 1 : 3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (compactBeforeFocus) {
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: tester.getCenter(
                  find.byKey(const ValueKey('messages')),
                ),
                scrollDelta: const Offset(0, 160),
              ),
            );
            await tester.pumpAndSettle();
          }
          final composer = find.byKey(const ValueKey('composer'));
          final navigation = find.byKey(const ValueKey('navigation'));
          final chrome = DScrollChrome.maybeOf(tester.element(composer))!;
          final fraction = chrome.hiddenFraction;
          final navigationTop = tester.getTopLeft(navigation).dy;
          expect(
            tester.widget<DInputGroup>(composer).compact,
            compactBeforeFocus,
          );
          expect(navigation.hitTestable(), findsOneWidget);
          // Hardware-keyboard focus must hide chrome before any IME inset exists.
          expect(MediaQuery.viewInsetsOf(tester.element(composer)).bottom, 0);
          focus.requestFocus();
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          expect(navigation.hitTestable(), findsNothing);
          if (!reduced) {
            expect(
              tester.getTopLeft(navigation).dy,
              greaterThan(navigationTop),
            );
            expect(tester.getTopLeft(navigation).dy, lessThan(844));
          }
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(navigation).dy, 844);
          expect(tester.widget<DInputGroup>(composer).compact, isFalse);
          expect(
            find.byKey(const ValueKey('send')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.getRect(composer).bottom, 844 - 34 - 6);
          expect(chrome.hiddenFraction, fraction);
          expect(text.text, 'Keep this draft');
          focus.unfocus();
          await tester.pumpAndSettle();
          expect(navigation.hitTestable(), findsOneWidget);
          expect(
            tester.widget<DInputGroup>(composer).compact,
            compactBeforeFocus,
          );
          expect(chrome.hiddenFraction, fraction);
          expect(text.text, 'Keep this draft');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final folded in [false, true]) {
    testWidgets(
      'navigation and composer return with a retracting keyboard (folded: $folded)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final focus = FocusNode();
        final text = TextEditingController();
        final scroll = ScrollController(initialScrollOffset: 500);
        addTearDown(focus.dispose);
        addTearDown(text.dispose);
        addTearDown(scroll.dispose);
        Widget app({double keyboard = 0}) => MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              padding: EdgeInsets.only(bottom: keyboard > 0 ? 0 : 34),
              viewPadding: const EdgeInsets.only(bottom: 34),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: DScrollChrome(
              identity: 'chat',
              floatingFooter: true,
              // The real bar is shorter while a keyboard hides the safe inset.
              footerBuilder: (_) => SizedBox(
                key: const ValueKey('navigation'),
                height: keyboard > 3.5 ? 76 : 92,
              ),
              // The shell's scaffold stands the body on the keyboard.
              child: Padding(
                padding: EdgeInsets.only(bottom: keyboard),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        key: const ValueKey('messages'),
                        controller: scroll,
                        itemCount: 100,
                        itemExtent: 50,
                        itemBuilder: (_, index) => Text('Message $index'),
                      ),
                    ),
                    DComposerDock(
                      builder: (_, compact) => DCard(
                        spacing: 0,
                        child: DInputGroup(
                          key: const ValueKey('composer'),
                          compact: compact,
                          children: [
                            DInputGroupTextarea(
                              focusNode: focus,
                              controller: text,
                              minLines: 1,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        if (folded) {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: tester.getCenter(
                find.byKey(const ValueKey('messages')),
              ),
              scrollDelta: const Offset(0, 160),
            ),
          );
          await tester.pumpAndSettle();
        }
        final composer = find.byKey(const ValueKey('composer'));
        final navigation = find.byKey(const ValueKey('navigation'));
        double navigationTop() => tester.getTopLeft(navigation).dy;
        final restingComposer = tester.getRect(composer);
        final restingNavigationTop = navigationTop();

        focus.requestFocus();
        await tester.pumpWidget(app(keyboard: 336));
        await tester.pumpAndSettle();
        final focusedComposer = tester.getRect(composer);
        expect(navigationTop(), 844);

        // A held keyboard that changes height is not leaving.
        await tester.pumpWidget(app(keyboard: 290));
        await tester.pumpAndSettle();
        expect(navigationTop(), 844);
        expect(tester.getRect(composer).bottom, 844 - 290 - 6);

        // Focus can move on while the keyboard stays for the next field.
        focus.unfocus();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(navigationTop(), 844);
        expect(tester.getRect(composer).bottom, 844 - 290 - 6);

        await tester.pumpWidget(app(keyboard: 280));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(navigationTop(), lessThan(844));
        expect(tester.widget<DInputGroup>(composer).compact, folded);
        if (folded) {
          expect(
            tester.getRect(composer).left,
            greaterThan(focusedComposer.left),
          );
          expect(
            tester.getRect(composer).right,
            lessThan(focusedComposer.right),
          );
        } else {
          expect(tester.getRect(composer).bottom, lessThan(844 - 280 - 6));
        }

        // A retraction as an iPhone reports it, one sample every 50ms.
        var composerBottom = tester.getRect(composer).bottom;
        for (final inset in <double>[133, 63, 25, 9, 3.4, 1.2, 0]) {
          await tester.pumpWidget(app(keyboard: inset));
          await tester.pump(const Duration(milliseconds: 50));
          final bottom = tester.getRect(composer).bottom;
          expect(bottom, greaterThanOrEqualTo(composerBottom - .01));
          composerBottom = bottom;
        }
        await tester.pumpAndSettle();
        expect(navigationTop(), restingNavigationTop);
        expect(tester.getRect(composer), restingComposer);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final reduced in [false, true]) {
    for (final direction in TextDirection.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'composer dock retains editing state, safe area and visible hits ($reduced, $direction, $scale)',
          (tester) async {
            await tester.binding.setSurfaceSize(const Size(390, 844));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final text = TextEditingController(text: 'Retained draft');
            final scroll = ScrollController(initialScrollOffset: 500);
            addTearDown(text.dispose);
            addTearDown(scroll.dispose);
            var sent = 0;
            Widget app({double keyboard = 0}) => MaterialApp(
              theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(390, 844),
                  padding: const EdgeInsets.only(bottom: 34),
                  viewInsets: EdgeInsets.only(bottom: keyboard),
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: reduced,
                ),
                child: Directionality(
                  textDirection: direction,
                  child: DScrollChrome(
                    identity: 'conversation',
                    floatingFooter: true,
                    footerBuilder: (_) => SizedBox(
                      height: 96,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SizedBox(
                          width: 48,
                          height: 96,
                          child: DButton(
                            key: const ValueKey('navigation'),
                            label: const Text('Navigation'),
                            onPressed: () {},
                          ),
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            key: const ValueKey('messages'),
                            controller: scroll,
                            itemCount: 100,
                            itemExtent: 50,
                            itemBuilder: (_, index) => Text('Message $index'),
                          ),
                        ),
                        DComposerDock(
                          builder: (_, compact) => DCard(
                            spacing: 0,
                            child: DInputGroup(
                              key: const ValueKey('composer'),
                              compact: compact,
                              borderless: true,
                              action: DButton.iconOnly(
                                key: const ValueKey('send'),
                                icon: const DIcon(DIcons.paperPlane),
                                tooltip: 'Send',
                                onPressed: () => sent++,
                              ),
                              children: [
                                DInputGroupTextarea(
                                  controller: text,
                                  minLines: compact ? 1 : 3,
                                  maxLines: compact ? 1 : 3,
                                ),
                                DInputGroupAddon(
                                  alignment: DInputGroupAddonAlignment.blockEnd,
                                  child: DButton.iconOnly(
                                    key: const ValueKey('tool'),
                                    icon: const DIcon(DIcons.plus),
                                    tooltip: 'Add',
                                    onPressed: () {},
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpWidget(app());
            await tester.pumpAndSettle();
            final composer = find.byKey(const ValueKey('composer'));
            final editor = find.byType(EditableText);
            final original = tester.state<EditableTextState>(editor);
            text.selection = const TextSelection(
              baseOffset: 2,
              extentOffset: 8,
            );
            final open = tester.getRect(composer);
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: tester.getCenter(
                  find.byKey(const ValueKey('messages')),
                ),
                scrollDelta: const Offset(0, 160),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));
            final moving = tester.getRect(composer);
            await tester.pumpAndSettle();
            final compact = tester.getRect(composer);
            expect(tester.widget<DInputGroup>(composer).compact, isTrue);
            expect(compact.height, lessThan(open.height));
            // Beside the folded circle in the screen's corner: 13.32 in at
            // 48 across, 11.71 at the larger text's 59, then the circle and 8.
            final corner = scale == 1 ? 13.3225 : 11.7116;
            final circle = 48 + (scale - 1) * 11;
            expect(compact.bottom, closeTo(844 - corner, .001));
            // Larger text keeps the line's own height past the circle's.
            expect(compact.height, scale == 1 ? circle : greaterThan(circle));
            if (direction == TextDirection.ltr) {
              expect(compact.left, closeTo(corner + circle + 8, .001));
              expect(compact.right, closeTo(390 - corner, .001));
            } else {
              expect(compact.right, closeTo(390 - corner - circle - 8, .001));
              expect(compact.left, closeTo(corner, .001));
            }
            if (!reduced) expect(moving.bottom, lessThan(compact.bottom));
            expect(tester.state<EditableTextState>(editor), same(original));
            expect(
              text.selection,
              const TextSelection(baseOffset: 2, extentOffset: 8),
            );
            expect(
              find.byKey(const ValueKey('tool')).hitTestable(),
              findsNothing,
            );
            await tester.tap(find.byKey(const ValueKey('send')));
            expect(sent, 1);
            expect(text.text, 'Retained draft');
            // Keyboard appearance and editor focus both restore the full surface.
            await tester.pumpWidget(app(keyboard: 300));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('navigation')).hitTestable(),
              findsNothing,
            );
            expect(
              tester.getTopLeft(find.byKey(const ValueKey('navigation'))).dy,
              844,
            );
            expect(tester.widget<DInputGroup>(composer).compact, isFalse);
            expect(
              find.byKey(const ValueKey('tool')).hitTestable(),
              findsOneWidget,
            );
            await tester.tap(editor);
            await tester.pumpAndSettle();
            expect(
              tester.widget<EditableText>(editor).focusNode.hasFocus,
              isTrue,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
