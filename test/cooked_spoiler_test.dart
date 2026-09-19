import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/inline_code.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

Widget _body(
  String html, {
  PluginRegistry? registry,
  ValueChanged<SelectedContent?>? onSelection,
  bool narrow = false,
}) => MaterialApp(
  theme: narrow ? AppTheme.dark : AppTheme.light,
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: narrow ? 280 : 700,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(narrow ? 2 : 1)),
          child: Directionality(
            textDirection: narrow ? TextDirection.rtl : TextDirection.ltr,
            child: SingleChildScrollView(
              child: SelectionArea(
                onSelectionChanged: onSelection,
                child: CookedHtml(
                  html: html,
                  registry: registry,
                  siteUrl: 'https://example.test/forum',
                  textStyle: const TextStyle(fontSize: 19, height: 1.6),
                  linkStyle: const TextStyle(color: Colors.red),
                  buildAsync: false,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _reveal(WidgetTester tester, {int index = 0}) async {
  await tester.tap(find.text('Spoiler').at(index));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('conceals descendants before plugin/media construction', (
    tester,
  ) async {
    final media = _ObservedMedia();
    final registry = PluginRegistry([media]);
    await tester.pumpWidget(
      _body(
        '<p>Visible</p><div class="spoiler"><p>Secret <code>code</code></p><img src="https://media.test/secret.png"></div>',
        registry: registry,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DAccordion<int>), findsOneWidget);
    expect(find.byType(InlineCode), findsNothing);
    expect(media.builds, 0);
    await _reveal(tester);
    expect(find.byType(InlineCode), findsOneWidget);
    expect(media.builds, 1);
    expect(find.text('Mounted media'), findsOneWidget);
    final nested = tester.widgetList<HtmlWidget>(find.byType(HtmlWidget)).last;
    expect(nested.baseUrl, Uri.parse('https://example.test/forum'));
    expect(nested.textStyle?.fontSize, 19);
    expect(nested.textStyle?.height, 1.6);
    final cooked = tester.widgetList<CookedHtml>(find.byType(CookedHtml)).last;
    expect(cooked.registry, same(registry));
    expect(cooked.linkStyle?.color, Colors.red);
    await _reveal(tester);
    expect(find.text('Mounted media'), findsNothing);
    expect(find.byType(InlineCode), findsNothing);
  });

  testWidgets(
    'nested spoilers reveal independently and reset with changed source',
    (tester) async {
      const markup =
          '<div class="spoiler"><p>Outer secret</p><span class="spoiler">Inner secret</span></div>';
      await tester.pumpWidget(_body(markup));
      await tester.pumpAndSettle();
      expect(find.text('Spoiler'), findsOneWidget);
      await _reveal(tester);
      expect(find.text('Spoiler'), findsNWidgets(2));
      expect(find.text('Inner secret', findRichText: true), findsNothing);
      await _reveal(tester, index: 1);
      expect(find.text('Inner secret', findRichText: true), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Inner secret', findRichText: true), findsNothing);
      expect(find.text('Outer secret', findRichText: true), findsOneWidget);
      await tester.pumpWidget(
        _body(markup.replaceFirst('Outer secret', 'Replacement secret')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Replacement secret', findRichText: true), findsNothing);
      expect(find.text('Spoiler'), findsOneWidget);
      await _reveal(tester);
      expect(
        find.text('Replacement secret', findRichText: true),
        findsOneWidget,
      );
    },
  );

  testWidgets('closed secrets are absent from selection and accessibility', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    String? selected;
    await tester.pumpWidget(
      _body(
        '<p>Public prefix</p><div class="spoiler"><p>Concealed phrase</p></div><p>Public suffix</p>',
        onSelection: (content) => selected = content?.plainText,
      ),
    );
    await tester.pumpAndSettle();
    Future<void> selectAll() async {
      tester
          .state<SelectionAreaState>(find.byType(SelectionArea))
          .selectableRegion
          .selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
    }

    String semanticsTree() => tester
        .binding
        .renderViews
        .single
        .owner!
        .semanticsOwner!
        .rootSemanticsNode!
        .toStringDeep();
    await selectAll();
    expect(selected, contains('Public prefix'));
    expect(selected, isNot(contains('Concealed phrase')));
    expect(semanticsTree(), isNot(contains('Concealed phrase')));
    await _reveal(tester);
    await selectAll();
    expect(selected, contains('Concealed phrase'));
    expect(semanticsTree(), contains('Concealed phrase'));
    await _reveal(tester);
    await selectAll();
    expect(selected, isNot(contains('Concealed phrase')));
    expect(semanticsTree(), isNot(contains('Concealed phrase')));
    semantics.dispose();
  });

  testWidgets('inline spoilers and nested details fit narrow RTL large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _body(
        '<p>Before <span class="spoiler"><strong>Hidden inline text</strong><details><summary>Details inside</summary><p>Nested details body</p></details></span> after</p>',
        narrow: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Hidden inline text', findRichText: true),
      findsNothing,
    );
    await _reveal(tester);
    expect(
      find.textContaining('Hidden inline text', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Nested details body', findRichText: true), findsNothing);
    await tester.tap(find.text('Details inside'));
    await tester.pumpAndSettle();
    expect(
      find.text('Nested details body', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

final class _ObservedMedia implements SitePlugin, CookedElementPlugin {
  var builds = 0;
  @override
  String get name => 'spoiler-test-media';
  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) {
    if (element.localName != 'img') return null;
    builds++;
    return const Text('Mounted media');
  }
}
