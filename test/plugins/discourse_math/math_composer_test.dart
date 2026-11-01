import 'dart:async';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_math/math_composer.dart';
import 'package:discourse_native/src/plugins/discourse_math/math_composer_card.dart';
import 'package:discourse_native/src/plugins/discourse_math/math_settings.dart';
import 'package:discourse_native/src/plugins/discourse_math/math_source.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Future<ComposerController> pump(
    WidgetTester tester,
    String source, {
    double width = 700,
    bool dark = false,
    double textScale = 1,
  }) async {
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
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox(
            width: width,
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
  test('standalone math is a block without changing display semantics', () {
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
    for (final source in [
      r'$x$',
      r'\(x\)',
      r'%x%',
      '  \$x\$  ',
      'Before\r\n\r\n\$x\$\r\n\r\nAfter',
    ]) {
      final projection = policy.parse(source).single;
      expect(
        projection,
        isA<ComposerAtomicSelectionProjection>(),
        reason: source,
      );
      expect(projection.source, contains('x'));
      final spans = scanMath(
        source,
        const MathSettings(enabled: true, asciiMath: true),
      );
      expect(spans.single.expression.display, isFalse);
    }
    for (final source in [
      r'Before $x$ after',
      r'$x$ and $y$',
      r'Before \(x\)',
      r'%x% after',
    ]) {
      for (final projection in policy.parse(source)) {
        expect(
          projection,
          isNot(isA<ComposerBlockSyntaxProjection>()),
          reason: source,
        );
      }
    }
  });
  test(
    'card trailing gap preserves line endings and existing following text',
    () {
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
      for (final newline in ['\n', '\r\n']) {
        final source = 'Before$newline$newline\$x\$';
        final projection = policy.parse(source).single;
        final moved = projection.moveCaretAfter(TextEditingValue(text: source));
        expect(moved.text, '$source$newline');
        expect(
          moved.selection,
          TextSelection.collapsed(offset: source.length + newline.length),
        );
        final followed = '$source${newline}After';
        final existing = policy
            .parse(followed)
            .single
            .moveCaretAfter(TextEditingValue(text: followed));
        expect(existing.text, followed);
        expect(
          existing.selection,
          TextSelection.collapsed(offset: source.length + newline.length),
        );
      }
    },
  );
  testWidgets(
    'read-only card keeps Copy source and disables edit and deletion',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SizedBox(
              width: 320,
              child: MathComposerCard(
                expression: DMathExpression('x'),
                configuration: DMathJax(),
                expressions: [DMathExpression('x')],
                expressionIndex: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<DButton>(
              find.byWidgetPredicate(
                (widget) => widget is DButton && widget.tooltip == 'Edit math',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DDropdownMenuItem>(
              find.widgetWithText(DDropdownMenuItem, 'Copy source'),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<DDropdownMenuItem>(
              find.widgetWithText(DDropdownMenuItem, 'Delete'),
            )
            .onPressed,
        isNull,
      );
      await finish(tester);
    },
  );
  testWidgets(
    'standalone card has its own source actions while prose stays inline',
    (tester) async {
      final composer = await pump(tester, r'$x$');
      expect(find.byType(MathComposerCard), findsOneWidget);
      expect(find.text('Math expression'), findsOneWidget);
      expect(
        tester.widget<DMath>(find.byType(DMath)).expression.display,
        isFalse,
      );
      expect(tester.widget<DMath>(find.byType(DMath)).onEdit, isNull);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Copy source'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(composer.text.text, isEmpty);
      expect(composer.history.undo(), isTrue);
      await tester.pumpAndSettle();
      expect(composer.text.text, r'$x$');
      composer.text.value = const TextEditingValue(text: r'Before $x$ after');
      await tester.pumpAndSettle();
      expect(find.byType(MathComposerCard), findsNothing);
      expect(find.byTooltip('Edit math'), findsOneWidget);
      await finish(tester);
    },
  );
  testWidgets('card Copy source copies the equation without its delimiters', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final composer = await pump(tester, r'$\frac{a}{b}$');
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy source'));
    await tester.pumpAndSettle();
    expect(copied, r'\frac{a}{b}');
    expect(composer.text.text, r'$\frac{a}{b}$');
    await finish(tester);
  });
  for (final source in [r'- $x$', '[details="Math"]\n\$x\$\n[/details]']) {
    testWidgets('nested card Delete owns only its local equation: $source', (
      tester,
    ) async {
      final composer = await pump(tester, source);
      expect(find.byType(MathComposerCard), findsOneWidget);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(composer.text.text, source.replaceFirst(r'$x$', ''));
      expect(composer.history.undo(), isTrue);
      await tester.pumpAndSettle();
      expect(composer.text.text, source);
      await finish(tester);
    });
  }
  for (final source in [r'$x$', '\$\$\nx\n\$\$']) {
    testWidgets('card is selected and deleted as one component: $source', (
      tester,
    ) async {
      final composer = await pump(tester, 'Before\n\n$source\n\nAfter');
      composer.requestFocus();
      composer.text.selection = const TextSelection.collapsed(offset: 8);
      await tester.pump();
      expect(
        composer.text.selection,
        TextSelection(baseOffset: 8, extentOffset: 8 + source.length),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(composer.text.text, 'Before\n\nAfter');
      expect(composer.history.undo(), isTrue);
      await tester.pumpAndSettle();
      expect(composer.text.text, 'Before\n\n$source\n\nAfter');
      await finish(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
    testWidgets(
      'Right and Enter create a following paragraph without opening hidden source: $source',
      (tester) async {
        final composer = await pump(tester, source);
        composer.requestFocus();
        composer.text.selection = const TextSelection.collapsed(offset: 0);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(composer.text.text, source);
        expect(
          composer.text.selection,
          TextSelection.collapsed(offset: source.length),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(composer.text.text, '$source\n\n');
        expect(
          composer.text.selection,
          TextSelection.collapsed(offset: source.length + 2),
        );
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: '$source\n\nAfter',
            selection: TextSelection.collapsed(offset: source.length + 7),
          ),
        );
        await tester.pumpAndSettle();
        expect(composer.text.text, '$source\n\nAfter');
        expect(find.byType(MathComposerCard), findsOneWidget);
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );
  }
  for (final (source, expected) in [
    ('Before\n\n\$x\$\n\nAfter', 'Before\n\nAfter'),
    ('Before\r\n\r\n\$x\$\r\n\r\nAfter', 'Before\r\n\r\nAfter'),
    ('Before\n\$x\$\nAfter', 'Before\nAfter'),
    ('\$x\$\n\nAfter', 'After'),
    ('Before\n\n\$x\$', 'Before'),
    ('Before\n\n\n\$x\$\n\n\nAfter', 'Before\n\n\n\nAfter'),
    ('Before\n\n \t\$x\$ \t\n\nAfter', 'Before\n\nAfter'),
  ]) {
    testWidgets(
      'Delete removes only the card and its duplicated separator: $source',
      (tester) async {
        final composer = await pump(tester, source);
        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(composer.text.text, expected);
        expect(composer.history.undo(), isTrue);
        await tester.pumpAndSettle();
        expect(composer.text.text, source);
        await finish(tester);
      },
    );
  }
  testWidgets('native replacement cannot overwrite part of card source', (
    tester,
  ) async {
    const source = 'Before\n\n\$x+1\$\n\nAfter';
    final composer = await pump(tester, source);
    composer.requestFocus();
    const caret = 13;
    composer.text.selection = const TextSelection.collapsed(offset: caret);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: source.replaceRange(caret - 2, caret, 'z'),
        selection: const TextSelection.collapsed(offset: caret - 1),
      ),
    );
    await tester.pump();
    expect(composer.text.text, source);
    await finish(tester);
  });
  testWidgets('host block moves keep the card source and undo intact', (
    tester,
  ) async {
    const source = 'Before\n\n\$x\$\n\nAfter';
    final composer = await pump(tester, source);
    final blocks = composer.blocks;
    final math = blocks.index.blocks.singleWhere(
      (block) => block.source == r'$x$',
    );
    expect(math.movable, isTrue);
    expect(
      blocks.moveTo(0, blockId: math.id, expectedRevision: blocks.revision),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(composer.text.text, '\$x\$\n\nBefore\n\nAfter');
    expect(find.byType(MathComposerCard), findsOneWidget);
    expect(composer.history.undo(), isTrue);
    await tester.pumpAndSettle();
    expect(composer.text.text, source);
    await finish(tester);
  });
  testWidgets('adjacent cards retain source and distinct actions', (
    tester,
  ) async {
    const source = '\$x\$\n\n\$y\$';
    final composer = await pump(tester, source);
    expect(find.byType(MathComposerCard), findsNWidgets(2));
    final cards = tester.getRect(find.byType(MathComposerCard).first);
    final second = tester.getRect(find.byType(MathComposerCard).last);
    expect(cards.bottom, lessThanOrEqualTo(second.top));
    await tester.tap(find.byTooltip('Edit math').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(DTextarea),
        matching: find.byType(EditableText),
      ),
      'z',
    );
    await tester.tap(find.widgetWithText(DButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(composer.text.text, '\$x\$\n\n\$z\$');
    await finish(tester);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'narrow math card supports large text and source fallback, dark=$dark',
      (tester) async {
        await pump(
          tester,
          r'$\frac{-b \pm \sqrt{b^2-4ac}}{2a}$',
          width: 320,
          dark: dark,
          textScale: 1.7,
        );
        expect(find.text('Math expression'), findsOneWidget);
        expect(find.byTooltip('Edit math'), findsOneWidget);
        expect(find.byTooltip('More options'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );
  }
  for (final source in [
    r'Before $x$ after',
    r'Before \(x\) after',
    r'Before %x% after',
    r'- $x$',
    '[details="Math"]\n\$x\$\n[/details]',
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
        expect(composer.history.undo(), isTrue);
        await tester.pumpAndSettle();
        expect(composer.text.text, source);
        await finish(tester);
      },
    );
  }
  for (final source in [r'- $x$', '[details="Math"]\n\$x\$\n[/details]']) {
    testWidgets('retired nested editor cannot apply stale math: $source', (
      tester,
    ) async {
      final composer = await pump(tester, source);
      await tester.tap(find.byTooltip('Edit math'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(DTextarea),
          matching: find.byType(EditableText),
        ),
        'y',
      );
      composer.text.text = 'Replacement draft';
      await tester.pump();
      await tester.tap(find.widgetWithText(DButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(composer.text.text, 'Replacement draft');
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
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
    expect(composer.text.text, r'Before $ x+1 $');
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
  testWidgets('Insert retains significant escaped terminal space', (
    tester,
  ) async {
    final composer = await pump(tester, 'abc ');
    final pending = insertMath(
      tester.element(find.byType(ComposerEditor)),
      composer,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(DTextarea),
        matching: find.byType(EditableText),
      ),
      r'x\ ',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(DButton, 'Insert'));
    await tester.pumpAndSettle();
    await pending;
    expect(composer.text.text, r'abc $x\ $');
    await finish(tester);
  });
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
