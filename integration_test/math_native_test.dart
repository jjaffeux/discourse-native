import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_math/math_composer.dart';
import 'package:discourse_native/src/plugins/discourse_math/math_settings.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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
  testWidgets(
    'production composer pencil applies source with a real native math view',
    (tester) async {
      const initial = r'Before $\frac{a}{b}$ after';
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
      composer.text.value = const TextEditingValue(
        text: initial,
        selection: TextSelection.collapsed(offset: initial.length),
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
      await rendered(tester, r'\frac{a}{b}');
      await tester.tap(find.byTooltip('Edit math'));
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.byType(DTextarea),
        matching: find.byType(EditableText),
      );
      expect(input, findsOneWidget);
      await tester.enterText(input, r'\sqrt{x}');
      await tester.tap(find.widgetWithText(DButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(composer.text.text, r'Before $\sqrt{x}$ after');
      await rendered(tester, r'\sqrt{x}');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      composer.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
