import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _source = 'Before\n\n![Coast|640x320](upload://coast)\n\nAfter';
final _toolbar = find.byKey(const ValueKey('composer-image-toolbar'));
final _description = find.descendant(
  of: find.byKey(const ValueKey('composer-image-description')),
  matching: find.byType(EditableText),
);

Finder _action(String label) => find.descendant(
  of: _toolbar,
  matching: find.byWidgetPredicate(
    (widget) => widget is DButton && widget.tooltip == label,
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'mobile image controls replace the toolbar and edit without losing focus',
    (tester) async {
      final composer = await _pump(tester, width: 320);
      expect(
        find.byKey(const ValueKey('composer-toolbar-bar')),
        findsOneWidget,
      );
      await tester.tap(find.byType(ComposerImagePreview));
      await tester.pumpAndSettle();

      expect(_toolbar, findsOneWidget);
      expect(find.byKey(const ValueKey('composer-toolbar-bar')), findsNothing);
      expect(find.byKey(const ValueKey('composer-mention')), findsNothing);
      expect(find.byType(DPopoverContent), findsNothing);
      expect(tester.getRect(_toolbar).bottom, lessThanOrEqualTo(550));
      for (final label in ['Decrease image size', 'Delete image', 'Done']) {
        expect(_action(label).hitTestable(), findsOneWidget);
        expect(
          tester.getRect(_toolbar).contains(tester.getCenter(_action(label))),
          isTrue,
        );
      }
      expect(
        tester.widget<DButton>(_action('Increase image size')).onPressed,
        isNull,
      );

      await tester.enterText(_description, 'Morning coast');
      await tester.pumpAndSettle();
      expect(composer.text.imageBlocks.single.alt, 'Morning coast');
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

      await tester.tap(_action('Done'));
      await tester.pumpAndSettle();
      expect(_toolbar, findsNothing);
      expect(
        find.byKey(const ValueKey('composer-toolbar-bar')),
        findsOneWidget,
      );
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
    'description switches with the image and removal restores formatting',
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

      await tester.tap(find.byType(ComposerImagePreview).last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(_description).controller.text,
        'Second',
      );
      await tester.tap(_action('Delete image'));
      await tester.pumpAndSettle();
      expect(composer.text.imageBlocks.single.alt, 'Updated first');
      expect(_toolbar, findsNothing);
      expect(
        find.byKey(const ValueKey('composer-toolbar-bar')),
        findsOneWidget,
      );
      expect(composer.focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'nested images use the shared toolbar and clear it when details collapse',
    (tester) async {
      final composer = await _pump(
        tester,
        source:
            '[details="Photos"]\n![Coast|160x80](upload://coast)\n[/details]\n',
      );
      await tester.tap(find.byType(ComposerImagePreview));
      await tester.pumpAndSettle();
      expect(_toolbar, findsOneWidget);
      expect(find.byType(DPopoverContent), findsNothing);
      await tester.enterText(_description, 'Inside details');
      await tester.pumpAndSettle();
      expect(composer.raw, contains('![Inside details|'));
      await tester.tap(find.byKey(const ValueKey('details-disclosure')));
      await tester.pumpAndSettle();
      expect(_toolbar, findsNothing);
      expect(
        find.byKey(const ValueKey('composer-toolbar-bar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('image toolbar stays usable with large text', (tester) async {
    await _pump(tester, width: 320, textScaler: const TextScaler.linear(1.5));
    await tester.tap(find.byType(ComposerImagePreview));
    await tester.pumpAndSettle();
    for (final label in ['Decrease image size', 'Delete image', 'Done']) {
      expect(_action(label).hitTestable(), findsOneWidget);
      expect(
        tester.getRect(_toolbar).contains(tester.getCenter(_action(label))),
        isTrue,
      );
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('desktop image controls remain in their popover', (tester) async {
    await _pump(tester, width: 900);
    await tester.tap(find.byType(ComposerImagePreview));
    await tester.pumpAndSettle();
    expect(_toolbar, findsNothing);
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
    const ComposerTarget(
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
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.viewInsets = FakeViewPadding(
    bottom: 250 * tester.view.devicePixelRatio,
  );
  addTearDown(tester.view.resetViewInsets);
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
