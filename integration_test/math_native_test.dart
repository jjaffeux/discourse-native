import 'dart:convert';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_math/math_composer.dart';
import 'package:discourse_native/src/plugins/discourse_math/math_composer_card.dart';
import 'package:discourse_native/src/plugins/discourse_math/math_settings.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  Future<void> rendered(WidgetTester tester, String source) async {
    for (var i = 0; i < 250 && find.text(source).evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    expect(
      find.text(source),
      findsNothing,
      reason: 'The real native engine must replace its loading/source fallback',
    );
    expect(tester.takeException(), isNull);
  }

  for (final configuration in <DMathConfiguration>[
    const DMathJax(),
    const DMathJax(output: DMathJaxOutput.svg),
    const DMathKatex(),
  ]) {
    testWidgets(
      'live platform math renders ${configuration.runtimeType} ${configuration is DMathJax ? configuration.output : ""}',
      (tester) async {
        const source = r'\frac{a}{b}';
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Center(
                child: DMath(
                  expression: const DMathExpression(source),
                  configuration: configuration,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await rendered(tester, source);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
  for (final (name, initial, source, card, dark) in [
    ('standalone inline', r'$2x + 3 = 12$', '2x + 3 = 12', false, true),
    ('reported inline sentence', r'with. $x$', 'x', false, false),
    ('prose', r'Before $\frac{a}{b}$ after', r'\frac{a}{b}', false, false),
    ('dark display', r'$$2x + 3 = 12$$', '2x + 3 = 12', true, true),
    (
      'display',
      'Before\n\n\$\$\n\\frac{a}{b}\n\$\$\n\nAfter',
      r'\frac{a}{b}',
      true,
      false,
    ),
    ('list inline', r'- $\frac{a}{b}$', r'\frac{a}{b}', false, false),
    (
      'details inline',
      '[details="Math"]\n\$\\frac{a}{b}\$\n[/details]',
      r'\frac{a}{b}',
      false,
      false,
    ),
    ('list display', r'- $$\frac{a}{b}$$', r'\frac{a}{b}', true, false),
  ]) {
    testWidgets(
      'clicking rendered $name math opens the editor in a native view',
      (tester) async {
        final state = ComposerPluginState(
          siteSettings: PluginData.none.withValue(
            mathSettingsKey,
            const MathSettings(enabled: true),
          ),
        );
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
            slug: 'math',
            topicTitle: 'Math',
          ),
          syntaxPolicies: [policy],
          pluginStateReader: () => state,
        );
        composer.text.value = TextEditingValue(
          text: initial,
          selection: TextSelection.collapsed(offset: initial.length),
        );
        final editor = SizedBox(
          width: 700,
          height: 450,
          child: ComposerEditor(
            composer: composer,
            hintText: 'Reply',
            textStyle: const TextStyle(fontSize: 16, height: 1.5),
            hintStyle: null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: Scaffold(
              body: dark
                  ? DCard(
                      backgroundColor: const Color(0xff20242a),
                      child: editor,
                    )
                  : editor,
            ),
          ),
        );
        await tester.pump();
        await rendered(tester, source);
        expect(
          find.byType(MathComposerCard),
          card ? findsOneWidget : findsNothing,
        );
        if (card) {
          expect(find.text('Math expression'), findsNothing);
          expect(find.byTooltip('Copy source'), findsNothing);
          expect(find.byTooltip('More options'), findsNothing);
        }
        final webView = tester.widget<WebViewWidget>(
          find.byType(WebViewWidget),
        );
        final webController = webView.platform.params.controller;
        if (dark) {
          final surface = card
              ? tester
                    .widgetList<Material>(
                      find.descendant(
                        of: find.byType(MathComposerCard),
                        matching: find.byType(Material),
                      ),
                    )
                    .first
                    .color!
              : const Color(0xff20242a);
          final canvasColor =
              'rgb(${(surface.r * 255).round()}, ${(surface.g * 255).round()}, ${(surface.b * 255).round()})';
          final result = await webController.runJavaScriptReturningResult(
            '''JSON.stringify({
                width:document.getElementById('math').getBoundingClientRect().width,
                height:document.getElementById('math').getBoundingClientRect().height,
                background:getComputedStyle(document.body).backgroundColor,
                foreground:getComputedStyle(document.getElementById('math')).color
              })''',
          );
          final canvas = jsonDecode(result as String) as Map<String, dynamic>;
          expect(canvas['width'], greaterThan(card ? 100 : 60));
          final math = tester.widget<DMath>(find.byType(DMath));
          expect(canvas['height'], lessThan(card ? math.fontSize! * 3 : 30));
          expect(
            tester.getSize(find.byType(WebViewWidget)).height,
            greaterThanOrEqualTo(canvas['height'] as num),
          );
          expect(canvas['background'], canvasColor);
          expect(canvas['foreground'], isNot(canvas['background']));
        }
        await webController.runJavaScript(
          "document.getElementById('math').click()",
        );
        await tester.pumpAndSettle();
        final input = find.descendant(
          of: find.byType(DTextarea),
          matching: find.byType(EditableText),
        );
        expect(input, findsOneWidget);
        await tester.enterText(input, r'\sqrt{x}');
        await tester.tap(find.widgetWithText(DButton, 'Apply'));
        await tester.pumpAndSettle();
        expect(composer.text.text, initial.replaceFirst(source, r'\sqrt{x}'));
        await rendered(tester, r'\sqrt{x}');
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        composer.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
