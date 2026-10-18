import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_mermaid/mermaid_composer.dart';
import 'package:discourse_native/src/shell/composer/block_selection.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/embedded_editor.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all/webview_all.dart';

import 'support/fake_media_webview.dart';

const _blocks = {
  'mermaid': '```mermaid\nflowchart TD\n  A --> B\n```',
  'table': '| Name | Value |\n| --- | --- |\n| First | One |\n| Second | Two |',
  'code': '```dart\nvoid main() {\n  print("Hello");\n}\n```',
  'details': '[details="Summary" open]\nRich **body** content.\n[/details]',
  'list': '- First **item**\n- Second item',
};
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

void main() {
  for (final block in _blocks.entries) {
    testWidgets(
      '${block.key} reuses embedded artwork while the composer scrolls',
      (tester) async {
        final phone = defaultTargetPlatform == TargetPlatform.iOS;
        tester.view.physicalSize = Size(phone ? 390 : 900, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final previousPlatform =
            WebViewPlatform.instance ?? FakeMediaWebViewPlatform();
        final platform = FakeMediaWebViewPlatform();
        WebViewPlatform.instance = platform;
        addTearDown(() => WebViewPlatform.instance = previousPlatform);
        late final ComposerController composer;
        composer = ComposerController(
          const ComposerTarget(
            siteUrl: 'https://example.test',
            topicId: 1,
            slug: 'topic',
            topicTitle: 'Topic',
          ),
          syntaxPolicies: [MermaidComposerPolicy(() => composer)],
        );
        addTearDown(composer.dispose);
        final source = 'Before\n\n${block.value}\n\n${'After\n\n' * 40}'
            .trimRight();
        final outerScroll = ScrollController();
        addTearDown(outerScroll.dispose);
        composer.text.value = TextEditingValue(
          text: source,
          selection: const TextSelection.collapsed(offset: 0),
        );
        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: _Assets(),
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: phone ? 390 : 760,
                    height: 420,
                    child: SingleChildScrollView(
                      controller: outerScroll,
                      physics: phone
                          ? null
                          : const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        height: phone ? null : 420,
                        child: ComposerEditor(
                          composer: composer,
                          expands: !phone,
                          hintText: 'Reply',
                          textStyle: const TextStyle(fontSize: 16, height: 1.5),
                          hintStyle: null,
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
        if (block.key == 'mermaid') {
          platform.controllers.single.channels['NativeMermaid']!
              .onMessageReceived(
                JavaScriptMessage(
                  message: jsonEncode({
                    'type': 'rendered',
                    'width': 600,
                    'height': 300,
                    'png': _png,
                  }),
                ),
              );
        }
        await tester.pumpAndSettle();
        if (block.key == 'mermaid') {
          expect(find.byType(Image), findsOneWidget);
          expect(find.byType(WebViewWidget), findsNothing);
        }
        final embedded = find.byType(ComposerEmbeddedEditor);
        expect(embedded, findsWidgets);
        final artwork = <RenderObject>{};
        void collect(RenderObject object) {
          artwork.add(object);
          object.visitChildren(collect);
        }

        for (final element in embedded.evaluate()) {
          collect(element.findRenderObject()!);
        }
        // Include the component's selection surface as well as its editors.
        // Some cards already cache their body through an opacity layer, while
        // their surrounding outline and layout still repaint on every scroll.
        for (final element
            in find
                .ancestor(
                  of: embedded,
                  matching: find.byType(ComposerBlockSelection),
                )
                .evaluate()) {
          collect(element.findRenderObject()!);
        }
        final elements = find
            .descendant(
              of: embedded,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is DMermaidEditor ||
                    widget is DCodeEditor ||
                    widget is DInput ||
                    widget is ComposerEditor ||
                    widget is OverlayPortal,
              ),
            )
            .evaluate()
            .toSet();
        final scroll = phone
            ? outerScroll
            : composer.text.imageScrollController!;
        final extent = scroll.position.maxScrollExtent;
        final viewport = scroll.position.viewportDimension;
        expect(extent, greaterThan(100));
        final rebuilt = <Element>[];
        final painted = <RenderObject>[];
        final previousPaint = debugOnProfilePaint;
        final previousBuild = debugOnRebuildDirtyWidget;
        debugOnProfilePaint = (object) {
          previousPaint?.call(object);
          if (artwork.contains(object)) painted.add(object);
        };
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          previousBuild?.call(element, builtOnce);
          if (elements.contains(element)) rebuilt.add(element);
        };
        try {
          for (final delta in [24.0, 24.0, -24.0, -24.0]) {
            final before = scroll.offset;
            scroll.position.pointerScroll(delta);
            await tester.pump();
            await tester.pump();
            expect(scroll.offset, closeTo(before + delta, .01));
          }
        } finally {
          debugOnProfilePaint = previousPaint;
          debugOnRebuildDirtyWidget = previousBuild;
        }
        expect(scroll.position.maxScrollExtent, extent);
        expect(scroll.position.viewportDimension, viewport);
        expect(composer.raw, source);
        expect(
          rebuilt,
          isEmpty,
          reason: 'Scrolling must retain embedded editors.',
        );
        expect(
          painted,
          isEmpty,
          reason:
              '${block.key}: ${painted.length} embedded paint calls during scrolling',
        );
        if (block.key == 'table' && !phone) {
          final trigger = find.byWidgetPredicate(
            (widget) => widget is DButton && widget.tooltip == 'Row 1 actions',
          );
          await tester.tap(trigger);
          await tester.pumpAndSettle();
          final popup = find.byType(DPopoverContent);
          expect(popup, findsOneWidget);
          final before = tester.getRect(popup);
          scroll.position.pointerScroll(12);
          await tester.pumpAndSettle();
          expect(tester.getRect(popup).top, closeTo(before.top - 12, .01));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.iOS,
      }),
    );
  }
}

class _Assets extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async => '';

  @override
  Future<ByteData> load(String key) => rootBundle.load(key);
}
