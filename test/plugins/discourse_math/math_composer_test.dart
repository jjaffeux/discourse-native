import 'dart:async';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_math/math_composer.dart';
import 'package:discourse_native/src/plugins/discourse_math/math_settings.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all/webview_all.dart';
import '../../support/fake_media_webview.dart';

void main() {
  final settings = PluginData.none.withValue(
    mathSettingsKey,
    const MathSettings(enabled: true, asciiMath: true),
  );
  final state = ComposerPluginState(siteSettings: settings);
  late WebViewPlatform previous;
  setUp(() {
    previous = WebViewPlatform.instance ?? FakeMediaWebViewPlatform();
    WebViewPlatform.instance = FakeMediaWebViewPlatform();
  });
  tearDown(() => WebViewPlatform.instance = previous);
  Future<ComposerController> pump(WidgetTester tester, String source) async {
    late ComposerController composer;
    final policy = MathComposerPolicy(
      ComposerSyntaxPolicyContext(
        siteUrl: 'https://example.test',
        isPluginTarget: false,
        isEdit: false,
        initialState: state,
        readState: () => state,
        readEditor: () => composer,
      ),
    );
    composer = ComposerController(
      const ReplyComposerTarget(
        privateMessageTopic: false,
        siteUrl: 'https://example.test',
        topicId: 1,
        slug: 'topic',
        topicTitle: 'Topic',
      ),
      syntaxPolicies: [policy],
      pluginStateReader: () => state,
    );
    addTearDown(composer.dispose);
    composer.text.value = TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: source.length),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 450,
            child: ComposerEditor(
              composer: composer,
              hintText: 'Reply',
              textStyle: const TextStyle(fontSize: 16, height: 1.5),
              hintStyle: null,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return composer;
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  test('interactive inline projections do not acquire block layout', () {
    final policy = MathComposerPolicy(
      ComposerSyntaxPolicyContext(
        siteUrl: 'https://example.test',
        isPluginTarget: false,
        isEdit: false,
        initialState: state,
        readState: () => state,
        readEditor: () => throw StateError('not read while parsing'),
      ),
    );
    final inline = policy.parse(r'Before $x$ after').single;
    expect(inline, isA<ComposerInteractiveSyntaxProjection>());
    expect(inline, isNot(isA<ComposerBlockSyntaxProjection>()));
    final block = policy.parse('\$\$\nx\n\$\$').single;
    expect(block, isA<ComposerBlockSyntaxProjection>());
  });
  for (final source in [
    r'Before $x$ after',
    r'Before \(x\) after',
    r'Before %x% after',
    'Before\n\n\$\$\nx\n\$\$\n\nAfter',
  ]) {
    testWidgets(
      'pencil Apply preserves notation and surrounding text: $source',
      (tester) async {
        final composer = await pump(tester, source);
        await tester.tap(find.byTooltip('Edit math'));
        await tester.pumpAndSettle();
        final input = find.descendant(
          of: find.byType(DTextarea),
          matching: find.byType(EditableText),
        );
        expect(input, findsOneWidget);
        await tester.enterText(input, 'y+1');
        await tester.tap(find.widgetWithText(DButton, 'Apply'));
        await tester.pumpAndSettle();
        expect(composer.text.text, source.replaceFirst('x', 'y+1'));
        await finish(tester);
      },
    );
  }
  testWidgets('Cancel and stale Apply do not change source', (tester) async {
    final composer = await pump(tester, r'$x$');
    await tester.tap(find.byTooltip('Edit math'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(DTextarea),
        matching: find.byType(EditableText),
      ),
      'y',
    );
    await tester.tap(find.widgetWithText(DButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(composer.text.text, r'$x$');
    await tester.tap(find.byTooltip('Edit math'));
    await tester.pumpAndSettle();
    composer.text.text = r'$new$';
    await tester.tap(find.widgetWithText(DButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(composer.text.text, r'$new$');
    await finish(tester);
  });
  testWidgets('Insert defaults to inline in prose and rejects empty source', (
    tester,
  ) async {
    final composer = await pump(tester, 'Before');
    unawaited(
      insertMath(tester.element(find.byType(ComposerEditor)), composer),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<DToggle>(find.byType(DToggle)).pressed, isFalse);
    final button = tester.widget<DButton>(
      find.widgetWithText(DButton, 'Insert'),
    );
    expect(button.onPressed, isNull);
    await tester.enterText(
      find.descendant(
        of: find.byType(DTextarea),
        matching: find.byType(EditableText),
      ),
      ' x+1 ',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(DButton, 'Insert'));
    await tester.pumpAndSettle();
    expect(composer.text.text, r'Before $x+1$');
    await finish(tester);
  });
  testWidgets('Insert defaults to display on a whitespace-only line', (
    tester,
  ) async {
    final composer = await pump(tester, 'Before\n\n');
    unawaited(
      insertMath(tester.element(find.byType(ComposerEditor)), composer),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<DToggle>(find.byType(DToggle)).pressed, isTrue);
    await tester.enterText(
      find.descendant(
        of: find.byType(DTextarea),
        matching: find.byType(EditableText),
      ),
      'x+1',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(DButton, 'Insert'));
    await tester.pumpAndSettle();
    expect(composer.text.text, contains('\$\$\nx+1\n\$\$'));
    await finish(tester);
  });
  testWidgets(
    'empty insertion at offset zero and multiline inline validation',
    (tester) async {
      final composer = await pump(tester, '');
      unawaited(
        insertMath(tester.element(find.byType(ComposerEditor)), composer),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DTextarea), findsOneWidget);
      await tester.tap(find.byType(DToggle));
      await tester.pump();
      await tester.enterText(
        find.descendant(
          of: find.byType(DTextarea),
          matching: find.byType(EditableText),
        ),
        'x\ny',
      );
      await tester.pump();
      expect(
        tester
            .widget<DButton>(find.widgetWithText(DButton, 'Insert'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.widgetWithText(DButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(composer.text.text, isEmpty);
      await finish(tester);
    },
  );
  testWidgets('unchanged Apply retains significant escaped trailing space', (
    tester,
  ) async {
    const source = r'$x \ $';
    final composer = await pump(tester, source);
    await tester.tap(find.byTooltip('Edit math'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(composer.text.text, source);
    await finish(tester);
  });
}
