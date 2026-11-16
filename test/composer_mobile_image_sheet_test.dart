import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/shell/composer/components/image.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _source = 'Before\n\n![Coast|640x320](upload://coast)\n\nAfter';
final _sheet = find.byKey(const ValueKey('composer-image-sheet'));
final _done = find.descendant(of: _sheet, matching: find.byTooltip('Done'));
final _composerToolbar = find.byKey(const ValueKey('composer-toolbar-bar'));
final _description = find.descendant(
  of: find.byKey(const ValueKey('composer-image-description')),
  matching: find.byType(EditableText),
);

Finder _action(String label) => find.descendant(
  of: _sheet,
  matching: find.byWidgetPredicate(
    (widget) => widget is DButton && widget.tooltip == label,
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'mobile image sheet keeps undo and redo controls in place',
    (tester) async {
      final composer = await _pump(tester, width: 320);
      await tester.tap(find.byType(ComposerImagePreview));
      await tester.pumpAndSettle();
      expect(tester.widget<DButton>(_action('Undo')).onPressed, isNull);
      expect(tester.widget<DButton>(_action('Redo')).onPressed, isNull);
      await tester.tap(_action('Decrease image size'));
      await tester.pumpAndSettle();
      expect(composer.text.imageBlocks.single.scale, 75);
      expect(_action('Undo').hitTestable(), findsOneWidget);
      expect(
        (tester.widget<DButton>(_action('Undo')).icon as DIcon).icon,
        DIcons.arrowRotateLeft,
      );
      await tester.tap(_action('Undo'));
      await tester.pumpAndSettle();
      expect(composer.raw, _source);
      expect(_sheet, findsOneWidget);
      final redo = _action('Redo');
      expect(redo.hitTestable(), findsOneWidget);
      expect(
        (tester.widget<DButton>(redo).icon as DIcon).icon,
        DIcons.arrowRotateRight,
      );
      await tester.tap(redo);
      await tester.pumpAndSettle();
      expect(composer.text.imageBlocks.single.scale, 75);
      expect(composer.focus.hasFocus, isFalse);
      expect(tester.widget<DButton>(redo).onPressed, isNull);
      await tester.tap(_done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_sheet, findsOneWidget);
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
      expect(
        find.byKey(const ValueKey('composer-undo')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'image sheet stays above the keyboard and keeps focus while editing',
    (tester) async {
      final composer = await _pump(tester, width: 320);
      expect(_composerToolbar, findsOneWidget);
      await tester.tap(find.byType(ComposerImagePreview));
      await tester.pumpAndSettle();

      expect(_sheet, findsOneWidget);
      expect(_composerToolbar, findsOneWidget);
      expect(_composerToolbar.hitTestable(), findsNothing);
      expect(
        tester.widget<EditableText>(_description).focusNode.hasFocus,
        isFalse,
      );
      expect(find.byType(DPopoverContent), findsNothing);
      await tester.tap(_description);
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pumpAndSettle();
      for (final action in [
        _action('Decrease image size'),
        _action('Delete image'),
        _done,
      ]) {
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.getRect(action).bottom, lessThanOrEqualTo(550));
        expect(
          tester.getRect(_sheet).contains(tester.getCenter(action)),
          isTrue,
        );
      }
      expect(
        tester.widget<DButton>(_action('Increase image size')).onPressed,
        isNull,
      );

      await tester.enterText(_description, 'Morning coast ');
      await tester.pumpAndSettle();
      expect(composer.text.imageBlocks.single.alt, 'Morning coast');
      expect(
        tester.widget<EditableText>(_description).controller.text,
        'Morning coast ',
      );
      expect(
        tester.widget<EditableText>(_description).focusNode.hasFocus,
        isTrue,
      );
      expect(composer.text.keyboardSelectedImage, isNotNull);

      const altValue = TextEditingValue(
        text: 'Morning coast view',
        selection: TextSelection.collapsed(offset: 18),
        composing: TextRange(start: 14, end: 18),
      );
      tester.testTextInput.updateEditingValue(altValue);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(_description).controller.value,
        altValue,
      );
      expect(composer.text.imageBlocks.single.alt, 'Morning coast view');

      await tester.tap(_action('Undo'));
      await tester.pumpAndSettle();
      final restored = composer.text.imageBlocks.single.alt;
      expect(restored, isNot('Morning coast view'));
      expect(
        tester.widget<EditableText>(_description).controller.text,
        restored,
      );
      await tester.tap(_action('Redo'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(_description).controller.text,
        'Morning coast view',
      );

      await tester.tap(_action('Decrease image size'));
      await tester.pumpAndSettle();
      expect(composer.text.imageBlocks.single.scale, 75);
      expect(
        tester.widget<EditableText>(_description).focusNode.hasFocus,
        isTrue,
      );
      await tester.tap(_action('Decrease image size'));
      await tester.pumpAndSettle();
      expect(composer.text.imageBlocks.single.scale, 50);
      expect(
        tester.widget<DButton>(_action('Decrease image size')).onPressed,
        isNull,
      );
      await tester.tap(_action('Increase image size'));
      await tester.pumpAndSettle();
      expect(composer.text.imageBlocks.single.scale, 75);

      await tester.tap(_done);
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
      expect(_composerToolbar, findsOneWidget);
      expect(composer.focus.hasFocus, isTrue);
      expect(composer.text.keyboardSelectedImage, isNull);
      expect(composer.text.imageBlocks.single.alt, 'Morning coast view');
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'reopening targets the tapped image and removal returns to the composer',
    (tester) async {
      final composer = await _pump(
        tester,
        source:
            '![First|160x80](upload://same)\n\n![Second|160x80](upload://same)\n',
      );
      await tester.tap(find.byType(ComposerImagePreview).first);
      await tester.pumpAndSettle();
      await tester.enterText(_description, 'Updated first');
      await tester.pumpAndSettle();
      expect(composer.text.imageBlocks.first.alt, 'Updated first');
      expect(composer.text.imageBlocks.last.alt, 'Second');

      await tester.tap(_done);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ComposerImagePreview).last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(_description).controller.text,
        'Second',
      );
      await tester.tap(_action('Delete image'));
      await tester.pumpAndSettle();
      expect(composer.text.imageBlocks.single.alt, 'Updated first');
      expect(_sheet, findsNothing);
      expect(_composerToolbar, findsOneWidget);
      expect(composer.focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('nested image edits survive a swipe dismissal', (tester) async {
    final composer = await _pump(
      tester,
      source:
          '[details="Photos"]\n![Coast|160x80](upload://coast)\n[/details]\n',
    );
    await tester.tap(find.byType(ComposerImagePreview));
    await tester.pumpAndSettle();
    expect(_sheet, findsOneWidget);
    expect(find.byType(DPopoverContent), findsNothing);
    await tester.enterText(_description, 'Inside details');
    await tester.pumpAndSettle();
    expect(composer.raw, contains('![Inside details|'));
    final handle = find.descendant(
      of: _sheet,
      matching: find.byKey(const ValueKey('sheet-drag-handle')),
    );
    await tester.drag(handle, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(composer.raw, contains('![Inside details|'));
    expect(_composerToolbar, findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('image sheet stays usable with large text', (tester) async {
    await _pump(tester, width: 320, textScaler: const TextScaler.linear(1.5));
    await tester.tap(find.byType(ComposerImagePreview));
    await tester.pumpAndSettle();
    for (final action in [
      _action('Decrease image size'),
      _action('Delete image'),
      _done,
    ]) {
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.getRect(_sheet).contains(tester.getCenter(action)), isTrue);
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('desktop image controls remain in their popover', (tester) async {
    await _pump(tester, width: 900);
    await tester.tap(find.byType(ComposerImagePreview));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(find.byType(DPopoverContent), findsOneWidget);
    expect(find.byTooltip('Save alt text'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

Future<ComposerController> _pump(
  WidgetTester tester, {
  String source = _source,
  double width = 390,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final composer = ComposerController(
    const ReplyComposerTarget(
      privateMessageTopic: false,
      siteUrl: 'https://meta.discourse.org',
      topicId: 7,
      slug: 'a-real-topic',
      topicTitle: 'A real topic',
    ),
  )..text.text = source;
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  addTearDown(composer.dispose);
  addTearDown(shell.dispose);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark.copyWith(
        platform: debugDefaultTargetPlatformOverride,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: ShellScope(
        controller: shell,
        child: Scaffold(body: ComposerPanel(composer: composer, height: 550)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return composer;
}
