import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/discourse_placeholder/discourse_placeholder_module.dart';
import 'package:discourse_native/src/plugins/discourse_placeholder/placeholder_session.dart';
import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _site = 'https://example.com';
const _topic = PluginContainingTopic(id: 7, slug: 'example', archived: false);
const _input =
    '<div class="d-wrap" data-wrap="placeholder" data-key="HOST" data-default="example.com" data-description="Your server"><p>Used in <strong>commands</strong>.</p></div>';
const _select =
    '<p><span class="d-wrap" data-wrap="placeholder" data-key="COUNTRY" data-default="US" data-defaults="FR,US" data-description="Choose a country"></span></p>';

void main() {
  late InstalledPlugins installed;
  late PluginSession session;
  late MemoryPlaceholderPersistence store;
  var user = 1;
  setUp(() {
    user = 1;
    store = MemoryPlaceholderPersistence();
    installed = PluginInstaller.install(
      PluginManifest([DiscoursePlaceholderModule(persistence: store)]),
    );
    session = installed.openSession(
      PluginHostBindings([
        PluginHostPort<PluginUserIdReader>(corePluginUserPort, (_) => user),
      ]),
    );
  });
  tearDown(() async {
    await session.close();
    await installed.close();
  });

  Future<void> pump(
    WidgetTester tester,
    String cooked, {
    bool transform = true,
    bool? buildAsync,
    double width = 700,
    double scale = 1,
    bool rtl = false,
    bool dark = false,
    GlobalKey? capture,
  }) async {
    final post = Post(
      id: 22,
      postNumber: 1,
      username: 'author',
      cooked: cooked,
    );
    Widget render(BuildContext context, String displayed) => CookedHtml(
      html: displayed,
      siteUrl: _site,
      post: post,
      containingTopic: _topic,
      buildAsync: buildAsync ?? CookedHtml.buildsAsynchronously(cooked),
    );
    await tester.pumpWidget(
      PluginScope(
        session: session,
        registry: installed.registry,
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
            body: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: SingleChildScrollView(
                  child: RepaintBoundary(
                    key: capture,
                    child: SizedBox(
                      width: width,
                      child: Builder(
                        builder: (context) => transform
                            ? installed.registry.transformPostBody(
                                context,
                                _site,
                                post,
                                topic: _topic,
                                builder: render,
                              )
                            : render(context, cooked),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    if (!(buildAsync ?? CookedHtml.buildsAsynchronously(cooked))) {
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'typing preserves focus, cursor and IME while updating copied code',
    (tester) async {
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
      const cooked =
          '$_input<pre><code class="lang-bash">ssh =HOST=</code></pre>';
      await pump(tester, cooked);
      expect(find.byType(DInput), findsOneWidget);
      expect(
        tester.widget<DInput>(find.byType(DInput)).controller!.text,
        'example.com',
      );
      await tester.enterText(find.byType(DInput), 'server.test');
      final input = tester.widget<DInput>(find.byType(DInput));
      input.controller!.value = const TextEditingValue(
        text: 'server.test',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 6),
      );
      await tester.pump(const Duration(milliseconds: 151));
      await tester.pumpAndSettle();
      expect(input.focusNode!.hasFocus, isTrue);
      expect(input.controller!.selection.baseOffset, 4);
      expect(
        input.controller!.value.composing,
        const TextRange(start: 0, end: 6),
      );
      await tester.tap(find.byKey(const ValueKey('code-block-copy')));
      await tester.pumpAndSettle();
      expect(copied, 'ssh server.test');
      await tester.enterText(find.byType(DInput), '');
      await tester.pump(const Duration(milliseconds: 151));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CodeBlock>(find.byType(CodeBlock)).data.text,
        'ssh example.com',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'updated links use the existing launcher and reject unsafe schemes',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final launched = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      const cooked =
          '<span class="d-wrap" data-wrap="placeholder" data-key="URL"></span>'
          '<p><a href="=URL=">Open server</a></p>';
      await pump(tester, cooked);
      for (final value in [
        'https://example.org/first',
        'https://example.org/next',
        'javascript:alert(1)',
      ]) {
        await tester.enterText(find.byType(DInput), value);
        await tester.pump(const Duration(milliseconds: 151));
        await tester.pumpAndSettle();
        await tester.tapAt(
          tester.getTopLeft(find.text('Open server', findRichText: true)) +
              const Offset(12, 10),
        );
        await tester.pumpAndSettle();
      }
      expect(launched, [
        'https://example.org/first',
        'https://example.org/next',
      ]);
    },
  );

  testWidgets(
    'post edits replace removed fields and apply new defaults without stale controllers',
    (tester) async {
      await pump(tester, '$_input<p>=HOST=</p>');
      await tester.enterText(find.byType(DInput), 'held');
      await tester.pump(const Duration(milliseconds: 151));
      await pump(
        tester,
        '<div class="d-wrap" data-wrap="placeholder" data-key="NAME" data-default="Reader"></div><p>Hello =NAME=</p>',
      );
      expect(
        tester.widget<DInput>(find.byType(DInput)).controller!.text,
        'Reader',
      );
      expect(find.text('Hello Reader', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
      await pump(tester, '<p>No fields remain</p>');
      expect(find.byType(DInput), findsNothing);
      expect(find.text('No fields remain', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dropdown changes substitution and a remount restores both fields',
    (tester) async {
      const cooked = '$_input$_select<p>=HOST= / =COUNTRY=</p>';
      await pump(tester, cooked);
      await tester.enterText(find.byType(DInput), 'saved');
      await tester.tap(find.byType(DSelect<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('FR').last);
      await tester.pump(const Duration(milliseconds: 151));
      await tester.pumpAndSettle();
      expect(find.text('saved / FR', findRichText: true), findsOneWidget);
      await session.require(placeholderSessionService).flush();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await pump(tester, cooked);
      expect(
        tester.widget<DInput>(find.byType(DInput)).controller!.text,
        'saved',
      );
      expect(
        tester.widget<DSelect<String>>(find.byType(DSelect<String>)).value,
        'FR',
      );
      user = 2;
      await pump(tester, cooked);
      expect(
        tester.widget<DInput>(find.byType(DInput)).controller!.text,
        'example.com',
      );
      expect(
        tester.widget<DSelect<String>>(find.byType(DSelect<String>)).value,
        'US',
      );
    },
  );

  testWidgets(
    'nested quoted fields use the owning post, standalone rendering stays inert',
    (tester) async {
      const cooked =
          '<aside class="quote no-group"><blockquote>$_input<p>=HOST=</p></blockquote></aside><p>Outside: =HOST=</p>';
      await pump(tester, cooked);
      expect(find.byType(DInput), findsOneWidget);
      await tester.enterText(find.byType(DInput), 'nested');
      await tester.pump(const Duration(milliseconds: 151));
      await tester.pumpAndSettle();
      expect(find.text('Outside: nested', findRichText: true), findsOneWidget);
      await pump(tester, cooked, transform: false);
      expect(find.byType(DInput), findsNothing);
      expect(find.text('Outside: =HOST=', findRichText: true), findsOneWidget);
    },
  );

  testWidgets(
    'large asynchronous bodies keep the active field through replacement',
    (tester) async {
      final cooked = '$_input<p>=HOST=</p><!--${'padding ' * 1600}-->';
      await pump(tester, cooked, buildAsync: true);
      // The HTML worker is independently scheduled; wait on the actual field.
      for (var i = 0; i < 100 && find.byType(DInput).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.byType(DInput), findsOneWidget);
      await tester.enterText(find.byType(DInput), 'large-body');
      final focus = tester.widget<DInput>(find.byType(DInput)).focusNode!;
      await tester.pump(const Duration(milliseconds: 151));
      for (
        var i = 0;
        i < 100 &&
            find.text('large-body', findRichText: true).evaluate().length < 2;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('large-body', findRichText: true), findsNWidgets(2));
      expect(focus.hasFocus, isTrue);
    },
  );

  testWidgets(
    'responsive fields remain usable with large text, RTL and both palettes',
    (tester) async {
      const cooked =
          '$_input$_select<h2>Connect to =HOST=</h2><pre><code class="lang-bash">ssh =HOST=</code></pre>';
      final semantics = tester.ensureSemantics();

      for (final variant in [
        (width: 700.0, scale: 1.0, rtl: false, dark: false),
        (width: 320.0, scale: 2.0, rtl: true, dark: true),
      ]) {
        final capture = GlobalKey();
        await pump(
          tester,
          cooked,
          width: variant.width,
          scale: variant.scale,
          rtl: variant.rtl,
          dark: variant.dark,
          capture: capture,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(DInput), findsOneWidget);
        expect(find.byType(DSelect<String>), findsOneWidget);
        expect(find.bySemanticsLabel('HOST'), findsWidgets);
        if (Platform.environment['PLACEHOLDER_RENDER_DIR'] case final path?) {
          final boundary =
              capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(path).create(recursive: true);
            await File(
              '$path/${variant.dark ? 'dark-rtl-large' : 'light'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      semantics.dispose();
    },
  );
}
