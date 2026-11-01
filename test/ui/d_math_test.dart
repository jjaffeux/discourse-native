import 'dart:async';
import 'dart:convert';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all/webview_all.dart';
import '../support/fake_media_webview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeMediaWebViewPlatform platform;
  late WebViewPlatform? previous;
  setUp(() {
    previous = WebViewPlatform.instance ?? FakeMediaWebViewPlatform();
    platform = FakeMediaWebViewPlatform();
    WebViewPlatform.instance = platform;
  });
  tearDown(() {
    WebViewPlatform.instance = previous;
  });
  Widget host({
    String source = r'\frac{a}{b}',
    bool display = false,
    VoidCallback? edit,
  }) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 320,
          child: DMath(
            expression: DMathExpression(source, display: display),
            configuration: const DMathJax(),
            onEdit: edit,
          ),
        ),
      ),
    ),
  );
  void send(
    Map<String, Object?> data, {
    FakeMediaWebViewController? controller,
  }) => (controller ?? platform.controllers.last).channels['NativeMath']!
      .onMessageReceived(
        JavaScriptMessage(message: jsonEncode({'v': 1, ...data})),
      );
  test('exact engines and bootstrap are Flutter assets', () async {
    const prefix = 'packages/discourse_native/src/ui/assets/math';
    expect(
      await rootBundle.loadString('$prefix/index.html'),
      contains('Content-Security-Policy'),
    );
    expect(
      await rootBundle.loadString('$prefix/mathjax/tex-mml-chtml.js'),
      isNotEmpty,
    );
    expect(
      await rootBundle.loadString('$prefix/katex/dist/katex.min.js'),
      contains('0.16.27'),
    );
  });
  testWidgets('empty math retains source without allocating a renderer', (
    tester,
  ) async {
    await tester.pumpWidget(host(source: '  '));
    await tester.pump();
    expect(platform.controllers, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('source stays visible until current bounded result arrives', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pump();
    expect(find.text(r'\frac{a}{b}'), findsOneWidget);
    expect(
      platform.controllers.single.assets.single,
      endsWith('/math/index.html'),
    );
    send({'type': 'ready'});
    await tester.pump();
    expect(
      platform.controllers.single.scripts.single,
      contains('window.renderMath('),
    );
    send({
      'type': 'result',
      'generation': 0,
      'width': 50,
      'height': 30,
      'baseline': 22,
    });
    await tester.pump();
    expect(find.text(r'\frac{a}{b}'), findsOneWidget);
    send({
      'type': 'result',
      'generation': 1,
      'width': 50,
      'height': 30,
      'baseline': 40,
    });
    await tester.pump();
    expect(find.text(r'\frac{a}{b}'), findsOneWidget);
    send({
      'type': 'result',
      'generation': 1,
      'width': 50,
      'height': 30,
      'baseline': 22,
    });
    await tester.pump();
    expect(find.text(r'\frac{a}{b}'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(platform.controllers.single.channels, isEmpty);
  });
  testWidgets('source update retires old view and rejects late callbacks', (
    tester,
  ) async {
    await tester.pumpWidget(host(source: 'a'));
    await tester.pump();
    final first = platform.controllers.single;
    final callback = first.channels['NativeMath']!.onMessageReceived;
    await tester.pumpWidget(host(source: 'b'));
    await tester.pump();
    callback(
      JavaScriptMessage(
        message: jsonEncode({
          'v': 1,
          'type': 'result',
          'generation': 1,
          'width': 50,
          'height': 30,
          'baseline': 22,
        }),
      ),
    );
    await tester.pump();
    expect(find.text('b'), findsOneWidget);
    expect(first.channels, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('disposal during setup removes late channel and document', (
    tester,
  ) async {
    final gate = Completer<void>();
    platform.nextGate = (
      MediaWebViewConfigurationStage.background,
      gate.future,
    );
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(platform.controllers.single.channels, isEmpty);
    expect(platform.controllers.single.assets, isEmpty);
  });
  testWidgets(
    'inline and display expose the Native pencil action without overflow',
    (tester) async {
      var edits = 0;
      for (final display in [false, true]) {
        await tester.pumpWidget(host(display: display, edit: () => edits++));
        await tester.pump();
        await tester.tap(find.byTooltip('Edit math'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(edits, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets('native expansion uses the selected engine zoom factor', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pump();
    send({'type': 'ready'});
    await tester.pump();
    final original = platform.controllers.single;
    final request =
        jsonDecode(
              original.scripts.single.substring(
                'window.renderMath('.length,
                original.scripts.single.length - 2,
              ),
            )
            as Map<String, dynamic>;
    send({'type': 'zoom', 'generation': 1, 'scale': 2.5});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final expanded = tester.widgetList<DMath>(find.byType(DMath)).last;
    expect(expanded.fontSize, (request['fontSize'] as num) * 2.5);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
    'completed visible equations release startup admission for every remaining equation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Wrap(
              children: [
                for (var i = 0; i < 84; i++)
                  SizedBox(
                    width: 50,
                    height: 30,
                    child: DMath(
                      expression: DMathExpression('x=$i'),
                      configuration: const DMathJax(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(platform.controllers, hasLength(16));
      final completed = <FakeMediaWebViewController>{};
      for (var batch = 0; batch < 7; batch++) {
        for (final controller in platform.controllers.toList()) {
          if (!completed.add(controller)) continue;
          send({
            'type': 'result',
            'generation': 1,
            'width': 50,
            'height': 30,
            'baseline': 22,
          }, controller: controller);
        }
        await tester.pump();
        await tester.pump();
      }
      expect(platform.controllers, hasLength(84));
      for (var i = 0; i < 84; i++) {
        expect(find.text('x=$i'), findsNothing);
      }
      expect(
        platform.controllers.every((view) => view.channels.isNotEmpty),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets('scrolling retires offscreen views and admits later equations', (
    tester,
  ) async {
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            width: 300,
            child: ListView(
              controller: scroll,
              children: [
                for (var i = 0; i < 24; i++)
                  SizedBox(
                    height: 100,
                    child: DMath(
                      expression: DMathExpression('x=$i'),
                      configuration: const DMathJax(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final initial = platform.controllers.toList();
    expect(initial.length, lessThanOrEqualTo(5));
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(platform.controllers.length, greaterThan(initial.length));
    expect(initial.every((view) => view.channels.isEmpty), isTrue);
    expect(
      platform.controllers.where((view) => view.channels.isNotEmpty).length,
      lessThanOrEqualTo(5),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    scroll.dispose();
  });
  testWidgets('ordinary long documents retain the selected equation', (
    tester,
  ) async {
    final expressions = [for (var i = 0; i < 200; i++) DMathExpression('x=$i')];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DMath(
            expression: expressions[150],
            context: expressions,
            contextIndex: 150,
            configuration: const DMathJax(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    send({'type': 'ready'});
    await tester.pump();
    expect(platform.controllers.single.scripts.single, contains('x=150'));
    expect(platform.controllers.single.scripts.single, contains('x=199'));
    expect(platform.controllers.single.scripts.single, contains('x=0'));
    send({
      'type': 'result',
      'generation': 1,
      'width': 50,
      'height': 30,
      'baseline': 22,
    });
    await tester.pump();
    expect(find.text('x=150'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
