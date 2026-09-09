import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/avatar_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Avatar registers all frozen composition examples', () {
    expect(componentExamples['avatar'], same(avatarExamples));
    expect(avatarExamples.examples.map((e) => e.title), [
      'Basic and composition',
      'Badge and badge with icon',
      'Avatar group, count and icon',
      'Group actions',
      'Sizes',
      'Image loading and error',
      'Dropdown',
      'RTL',
    ]);
  });
  testWidgets('touch group actions keep separate 48px targets', (tester) async {
    final example = avatarExamples.examples.firstWhere(
      (e) => e.title == 'Group actions',
    );
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: platform),
          home: Scaffold(
            body: SizedBox(
              width: 216,
              child: Builder(builder: example.builder),
            ),
          ),
        ),
      );
      expect(find.byType(DAvatarGroup), findsNothing);
      final buttons = find.byType(DButton);
      expect(buttons, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        final bounds = tester.getRect(buttons.at(i));
        expect(bounds.width, greaterThanOrEqualTo(48));
        expect(bounds.height, greaterThanOrEqualTo(48));
        if (i > 0) {
          expect(bounds.overlaps(tester.getRect(buttons.at(i - 1))), isFalse);
        }
      }
      await tester.tap(buttons.at(1));
      await tester.pump();
      expect(find.text('Lee selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('group buttons retain separate names, actions and focus stops', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final example = avatarExamples.examples.firstWhere(
        (e) => e.title == 'Group actions',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(body: Builder(builder: example.builder)),
        ),
      );
      expect(find.byType(DButton), findsNWidgets(3));
      for (final name in ['Chris', 'Lee', 'Evil Rabbit']) {
        expect(find.bySemanticsLabel('Open $name'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('$name selected'), findsOneWidget);
      }
      await tester.tap(find.bySemanticsLabel('Open Chris'));
      await tester.pumpAndSettle();
      expect(find.text('Chris selected'), findsOneWidget);
      expect(find.text('Evil Rabbit selected'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });
  testWidgets(
    'nested avatar menu closes before its dialog and restores focus',
    (tester) async {
      final outerFocus = FocusNode();
      addTearDown(outerFocus.dispose);
      final example = avatarExamples.examples.firstWhere(
        (e) => e.title == 'Dropdown',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: DDialog<void>(
              finalFocusNode: outerFocus,
              trigger: DDialogTrigger(
                builder: (context, open) => DButton(
                  focusNode: outerFocus,
                  label: const Text('Open dialog'),
                  onPressed: open,
                ),
              ),
              content: DDialogContent(
                children: [
                  const DDialogTitle(child: Text('Member dialog')),
                  Builder(builder: example.builder),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DDropdownMenuTrigger));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsNothing);
      expect(find.text('Member dialog'), findsOneWidget);
      expect(
        tester
            .widget<DButton>(
              find.descendant(
                of: find.byType(DDropdownMenuTrigger),
                matching: find.byType(DButton),
              ),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Member dialog'), findsNothing);
      expect(outerFocus.hasFocus, isTrue);
    },
  );
  testWidgets('all examples fit narrow 200 percent RTL and live palettes', (
    tester,
  ) async {
    for (final example in avatarExamples.examples) {
      for (final theme in [
        AppTheme.light,
        AppTheme.dark,
        StyleguideTheme.forest.resolve(AppTheme.light),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: 216,
                      child: Builder(builder: example.builder),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.takeException(), isNull, reason: example.title);
      }
    }
  });
  testWidgets('menu trigger owns keyboard focus and restores after Escape', (
    tester,
  ) async {
    final example = avatarExamples.examples.firstWhere(
      (e) => e.title == 'Dropdown',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Builder(builder: example.builder)),
      ),
    );
    final button = tester.widget<DButton>(find.byType(DButton));
    button.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(button.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings selected'), findsOneWidget);
  });
  testWidgets(
    'avatar trigger preserves readable fallback geometry at 200 percent',
    (tester) async {
      final example = avatarExamples.examples.firstWhere(
        (e) => e.title == 'Dropdown',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Builder(builder: example.builder),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(DAvatar)), const Size.square(64));
      expect(tester.getSize(find.byType(DButton)), const Size.square(64));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'dropdown uses the accepted final owners and reference geometry',
    (tester) async {
      final example = avatarExamples.examples.firstWhere(
        (e) => e.title == 'Dropdown',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(body: Builder(builder: example.builder)),
        ),
      );

      expect(find.byType(MenuAnchor), findsNothing);
      expect(find.byType(MenuItemButton), findsNothing);
      expect(find.byType(DDropdownMenu), findsOneWidget);
      expect(find.byType(DDropdownMenuTrigger), findsOneWidget);
      final content = tester
          .widget<DDropdownMenu>(find.byType(DDropdownMenu))
          .content;
      expect(content.width, 128);
      expect(content.align, DPopoverAlign.start);

      final trigger = tester.widget<DButton>(find.byType(DButton));
      expect(trigger.variant, DButtonVariant.ghost);
      expect(trigger.size, DButtonSize.regular);
      expect(trigger.hasPopup, isTrue);
      expect(trigger.label, isA<DAvatar>());
      expect(trigger.borderRadius, BorderRadius.circular(999));
      expect(tester.getSize(find.byType(DButton)), const Size.square(32));

      await tester.tap(find.byType(DButton));
      await tester.pumpAndSettle();
      expect(find.byType(DDropdownMenuGroup), findsNWidgets(2));
      expect(find.byType(DDropdownMenuSeparator), findsOneWidget);
      final logout = tester.widget<DDropdownMenuItem>(
        find.ancestor(
          of: find.text('Log out'),
          matching: find.byType(DDropdownMenuItem),
        ),
      );
      expect(logout.variant, DDropdownMenuItemVariant.destructive);
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(find.text('Log out selected'), findsOneWidget);

      await tester.tap(find.byType(DButton));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);
      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsNothing);
    },
  );
  testWidgets(
    'image selection survives environment changes and resets by key',
    (tester) async {
      final example = avatarExamples.examples.firstWhere(
        (e) => e.title == 'Image loading and error',
      );
      Future<void> pump({bool changed = false, int reset = 0}) =>
          tester.pumpWidget(
            MaterialApp(
              theme: changed ? AppTheme.dark : AppTheme.light,
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(changed ? 2 : 1),
                    disableAnimations: changed,
                  ),
                  child: Directionality(
                    textDirection: changed
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: SizedBox(
                      width: changed ? 216 : 600,
                      child: KeyedSubtree(
                        key: ValueKey(reset),
                        child: Builder(builder: example.builder),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
      await pump();
      await tester.tap(find.text('No image'));
      await tester.pump();
      await pump(changed: true);
      await tester.pumpAndSettle();
      expect(find.text('Image: absent'), findsOneWidget);
      await pump(changed: true, reset: 1);
      await tester.pump();
      expect(find.text('Image: absent'), findsNothing);
    },
  );
}
