import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/discourse_github/discourse_github_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_github/oneboxes/github.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What `InlineOneboxer` leaves in the cooked HTML once it has fetched a
/// title for a link that did not sit alone on its line.
const String prTitle =
    'Add the thing - Pull Request #30604 - discourse/discourse - GitHub';
const String prUrl = 'https://github.com/discourse/discourse/pull/30604';
const String prInline =
    '<a class="inline-onebox --gh-status-merged" href="$prUrl">'
    '$prTitle</a>';

const String issueTitle =
    'Bug: the thing breaks - Issue #12345 - discourse/discourse - GitHub';
const String issueInline =
    '<a class="inline-onebox" '
    'href="https://github.com/discourse/discourse/issues/12345">'
    '$issueTitle</a>';

const String topicTitle = 'Some topic - post 4 by martin';
const String topicInline =
    '<a class="inline-onebox" href="/t/some-topic/123/4">'
    '$topicTitle</a>';

Future<void> pumpCooked(WidgetTester tester, String html) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CookedHtml(
            html: html,
            registry: const PluginRegistry([DiscourseGithubPlugin()]),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

RichText paragraphContaining(WidgetTester tester, String text) => tester
    .widgetList<RichText>(find.byType(RichText))
    .singleWhere((widget) => widget.text.toPlainText().contains(text));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ordinary inline oneboxes remain flowing anchor text', (
    tester,
  ) async {
    await pumpCooked(
      tester,
      '<p>Before $issueInline and $topicInline after.</p>',
    );

    final paragraph = paragraphContaining(tester, 'Before');
    expect(
      paragraph.text.toPlainText(),
      'Before $issueTitle and $topicTitle after.',
    );
  });

  testWidgets('a pull request adds only its status glyph as a widget', (
    tester,
  ) async {
    await pumpCooked(tester, '<p>$prInline</p>');

    final icon = tester.widget<DIcon>(
      find.byWidgetPredicate(
        (widget) => widget is DIcon && widget.icon == githubPrMergedIcon,
      ),
    );
    expect(icon.color, GithubPrStatus.merged.color);

    final paragraph = paragraphContaining(tester, prTitle);
    expect(paragraph.text.toPlainText(), '\u{fffc}$prTitle');
  });

  testWidgets('starts on the preceding prose line and wraps by words', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(350, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpCooked(
      tester,
      '<p>but this one $prInline is too big for now</p>',
    );

    final paragraph = paragraphContaining(tester, 'but this one');
    final plainText = paragraph.text.toPlainText();
    expect(plainText, 'but this one \u{fffc}$prTitle is too big for now');

    final render = tester.renderObject<RenderParagraph>(
      find.byWidget(paragraph),
    );
    TextBox wordBox(String word) {
      final start = plainText.indexOf(word);
      return render
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + word.length),
          )
          .first;
    }

    expect(wordBox('Add').top, wordBox('one').top);
    expect(wordBox('GitHub').top, greaterThan(wordBox('Add').top));
  });

  testWidgets('the flowing title and status glyph activate the same link', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final launched = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') {
        launched.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await pumpCooked(tester, '<p>$prInline</p>');

    final paragraph = paragraphContaining(tester, prTitle);
    final plainText = paragraph.text.toPlainText();
    final titleStart = plainText.indexOf('Add');
    final render = tester.renderObject<RenderParagraph>(
      find.byWidget(paragraph),
    );
    final titleBox = render
        .getBoxesForSelection(
          TextSelection(baseOffset: titleStart, extentOffset: titleStart + 3),
        )
        .first;
    await tester.tapAt(render.localToGlobal(titleBox.toRect().center));
    await tester.pumpAndSettle();
    expect(launched, [prUrl]);

    launched.clear();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is DIcon && widget.icon == githubPrMergedIcon,
      ),
    );
    await tester.pumpAndSettle();
    expect(launched, [prUrl]);
  });

  testWidgets('the flowing title remains a named semantic link', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpCooked(tester, '<p>$prInline</p>');

    // RenderParagraph may put newlines in the semantics label where the title
    // wrapped visually.
    final target = find.semantics.byLabel(
      RegExp(r'Add the thing.*discourse/discourse.*GitHub', dotAll: true),
    );
    expect(target, findsOneWidget);
    final data = target.evaluate().single.getSemanticsData();
    expect(data.flagsCollection.isLink, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });
}
