import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class _ColorShell extends ShellController {
  _ColorShell()
    : super(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
  @override
  bool supportsComposerColors(String siteUrl) => true;
}

final toolbar = find.byKey(const ValueKey('composer-selection-toolbar'));

Future<ComposerController> pumpEditor(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.macOS,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  bool supportsColors = false,
}) async {
  final composer = ComposerController(
    const ComposerTarget(
      siteUrl: 'https://example.com',
      topicId: 7,
      slug: 'topic',
      topicTitle: 'Topic',
    ),
  );
  addTearDown(composer.dispose);
  final app = MaterialApp(
    theme: AppTheme.dark.copyWith(platform: platform),
    home: MediaQuery(
      data: MediaQueryData(
        size: tester.view.physicalSize / tester.view.devicePixelRatio,
        textScaler: TextScaler.linear(scale),
      ),
      child: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 180, 16, 16),
            child: ComposerEditor(
              composer: composer,
              hintText: 'Write a reply…',
              textStyle: AppTheme.dark.textTheme.bodyLarge,
              hintStyle: AppTheme.dark.textTheme.bodyLarge,
            ),
          ),
        ),
      ),
    ),
  );
  final shell = supportsColors ? _ColorShell() : null;
  if (shell != null) addTearDown(shell.dispose);
  await tester.pumpWidget(
    shell == null ? app : ShellScope(controller: shell, child: app),
  );
  composer.text.value = const TextEditingValue(
    text: 'format me please',
    selection: TextSelection(baseOffset: 0, extentOffset: 6),
  );
  composer.focus.requestFocus();
  await tester.pumpAndSettle();
  return composer;
}

Future<void> action(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: toolbar, matching: find.byTooltip(label)),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('colors are hidden without the server plugin', (tester) async {
    await pumpEditor(tester);
    expect(find.byTooltip('Color'), findsNothing);
  });

  testWidgets(
    'Escape closes the color palette and keeps the selection usable',
    (tester) async {
      final composer = await pumpEditor(tester, supportsColors: true);
      await action(tester, 'Color');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('composer-color-palette')),
        findsNothing,
      );
      expect(toolbar, findsOneWidget);
      expect(composer.text.selection.textInside(composer.text.text), 'format');
      await action(tester, 'Bold');
      expect(composer.text.text, '**format** me please');
    },
  );

  testWidgets(
    'color choices preserve selection, remember recents, reset and undo',
    (tester) async {
      final composer = await pumpEditor(tester, supportsColors: true);
      await action(tester, 'Color');
      expect(find.text('Recently used'), findsNothing);
      await tester.tap(
        find.byTooltip('Text color: Red'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(composer.text.text, '[color=#d75c55]format[/color] me please');
      expect(
        find.byKey(const ValueKey('composer-color-palette')),
        findsNothing,
      );
      expect(composer.text.selection.textInside(composer.text.text), 'format');
      await action(tester, 'Color');
      expect(find.text('Recently used'), findsOneWidget);
      expect(find.byTooltip('Text color: Red'), findsNWidgets(2));
      await tester.tap(
        find.byTooltip('Background color: Green'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(
        composer.text.text,
        '[color=#d75c55][bgcolor=#244c39]format[/bgcolor][/color] me please',
      );
      await action(tester, 'Color');
      await tester.tap(
        find.byTooltip('Text color: Blue'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(composer.text.text, contains('[color=#4d94d5]'));
      expect(composer.text.text, isNot(contains('#d75c55')));
      expect(composer.text.text, contains('[bgcolor=#244c39]'));
      await action(tester, 'Color');
      await tester.tap(
        find.byTooltip('Text color: Default'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(composer.text.text, '[bgcolor=#244c39]format[/bgcolor] me please');
      expect(composer.history.undo(), isTrue);
      await tester.pumpAndSettle();
      expect(composer.text.text, contains('[color=#4d94d5]'));
      await action(tester, 'Clear formatting');
      expect(composer.text.text, 'format me please');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selection menu applies formats, clears them and supports undo', (
    tester,
  ) async {
    final composer = await pumpEditor(tester);
    expect(toolbar, findsOneWidget);
    await action(tester, 'Underline');
    expect(composer.text.text, '<ins>format</ins> me please');
    await action(tester, 'Strikethrough');
    expect(composer.text.text, '<ins>~~format~~</ins> me please');
    await action(tester, 'Clear formatting');
    expect(composer.text.text, 'format me please');
    expect(composer.text.selection.textInside(composer.text.text), 'format');
    expect(composer.history.undo(), isTrue);
    expect(composer.text.text, '<ins>~~format~~</ins> me please');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline code toggles on and off for selected text', (
    tester,
  ) async {
    final composer = await pumpEditor(tester);
    await action(tester, 'Inline code');
    expect(composer.text.text, '`format` me please');
    await action(tester, 'Inline code');
    expect(composer.text.text, 'format me please');
  });

  testWidgets('Escape dismisses until the selection changes', (tester) async {
    final composer = await pumpEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(toolbar, findsNothing);
    composer.text.selection = const TextSelection(
      baseOffset: 7,
      extentOffset: 9,
    );
    await tester.pumpAndSettle();
    expect(toolbar, findsOneWidget);
    composer.text.selection = const TextSelection.collapsed(offset: 9);
    await tester.pumpAndSettle();
    expect(toolbar, findsNothing);
  });

  for (final (label, tag) in const [
    ('Superscript', 'sup'),
    ('Subscript', 'sub'),
    ('Keyboard key', 'kbd'),
  ]) {
    testWidgets('more formatting renders and undoes $label', (tester) async {
      final composer = await pumpEditor(tester);
      await action(tester, 'More formatting');
      await tester.tap(find.text(label), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(composer.text.text, '<$tag>format</$tag> me please');
      expect(composer.text.selection.textInside(composer.text.text), 'format');
      if (tag == 'kbd') {
        expect(find.byType(DKbd), findsOneWidget);
      } else {
        expect(find.text('f'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('f')).style!.fontSize,
          lessThan(14),
        );
      }
      expect(find.text(label), findsNothing);
      expect(composer.history.undo(), isTrue);
      await tester.pumpAndSettle();
      expect(composer.text.text, 'format me please');
      expect(find.byType(DKbd), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'link dialog retains selected text while the selection menu closes',
    (tester) async {
      final composer = await pumpEditor(tester);
      await action(tester, 'Link');
      expect(find.text('Insert link'), findsWidgets);
      expect(find.byType(DDialogContent), findsOneWidget);
      expect(composer.text.selection.textInside(composer.text.text), 'format');
      await tester.enterText(
        find.byKey(const ValueKey('composer-link-url')),
        'https://example.org',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-link-insert')));
      await tester.pumpAndSettle();
      expect(composer.text.text, '[format](https://example.org) me please');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fits a narrow touch viewport with large RTL text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpEditor(
      tester,
      platform: TargetPlatform.iOS,
      scale: 2,
      direction: TextDirection.rtl,
      supportsColors: true,
    );
    final rect = tester.getRect(toolbar);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
    await action(tester, 'Bold');
    await action(tester, 'Color');
    final palette = tester.getRect(
      find.byKey(const ValueKey('composer-color-palette')),
    );
    expect(palette.left, greaterThanOrEqualTo(0));
    expect(palette.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });
}
