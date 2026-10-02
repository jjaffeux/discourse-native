import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/shell/oneboxes/twitter.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

const _url = 'https://twitter.com/rezoundous/status/2101937724252967330';
const _quotedUrl = 'https://x.com/OfficialLoganK/status/2101900000000000000';
const _markup =
    '''
<aside class="onebox twitterstatus" data-onebox-src="$_url">
  <header class="source"><a href="$_url">twitter.com</a></header>
  <article class="onebox-body">
    <img src="https://cdn.example.com/avatar.jpg" class="thumbnail onebox-avatar" width="48" height="48">
    <h4><a href="$_url">Tyler</a></h4>
    <div class="twitter-screen-name"><a href="$_url">@rezoundous</a></div>
    <div class="tweet">
      <span class="tweet-description">bro just dropped Gemini's system prompt<br><a href="https://example.com/prompt">Read the prompt</a></span>
      <div class="quoted">
        <a class="quoted-link" href="$_quotedUrl">
          <p class="quoted-title">Logan Kilpatrick <span>@OfficialLoganK</span></p>
        </a>
        <div>you are going to fail, so <strong>fail while daring greatly</strong></div>
      </div>
    </div>
    <div class="date">
      <a href="$_url" class="timestamp">9:33 AM · Sep 21, 2026</a>
      <span class="like"><svg aria-hidden="true"></svg> 12K </span>
      <span class="retweet"><svg aria-hidden="true"></svg> 24 </span>
    </div>
  </article>
</aside>
''';

TwitterOneboxData _parse(String source) {
  final element = html.parseFragment(source).children.single;
  return TwitterOneboxData.from(element, OneboxData.from(element))!;
}

Widget _host({
  String markup = _markup,
  ThemeData? theme,
  double width = 550,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: (theme ?? AppTheme.light).copyWith(platform: TargetPlatform.macOS),
  home: Scaffold(
    body: Directionality(
      textDirection: direction,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: CookedHtml(html: markup, buildAsync: false),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test('reads the Discourse template without consuming caller-owned nodes', () {
    final element = html.parseFragment(_markup).children.single;
    final original = element.outerHtml;
    final data = TwitterOneboxData.from(element, OneboxData.from(element))!;
    expect(data.name, 'Tyler');
    expect(data.handle, 'rezoundous');
    expect(data.profileUrl, 'https://x.com/rezoundous');
    expect(data.url, _url);
    expect(data.statusId, '2101937724252967330');
    expect(data.avatarUrl, 'https://cdn.example.com/avatar.jpg');
    expect(data.timestamp, '9:33 AM · Sep 21, 2026');
    expect(data.likes, '12K');
    expect(data.reposts, '24');
    expect(data.bodyHtml, contains('<br>'));
    expect(data.bodyHtml, contains('https://example.com/prompt'));
    expect(data.bodyHtml, isNot(contains('quoted-title')));
    expect(data.quote!.name, 'Logan Kilpatrick');
    expect(data.quote!.handle, 'OfficialLoganK');
    expect(data.quote!.url, _quotedUrl);
    expect(data.quote!.bodyHtml, contains('<strong>'));
    expect(element.outerHtml, original);
  });

  test('accepts sparse markup and reply state without inventing counts', () {
    final data = _parse('''
<aside class="onebox twitterstatus"><article class="onebox-body">
  <div class="tweet"><span class="is-reply"></span>
    <span class="tweet-description">A reply</span>
  </div>
</article></aside>''');
    expect(data.isReply, isTrue);
    expect(data.name, 'Post on X');
    expect(data.handle, isNull);
    expect(data.timestamp, isNull);
    expect(data.url, isNull);
    expect(data.statusId, isNull);
    expect(data.likes, isNull);
    expect(data.reposts, isNull);
    expect(data.quote, isNull);
  });

  test('unrecognized Twitter markup retains the generic fallback', () {
    final element = html
        .parseFragment('''
<aside class="onebox twitterstatus" data-onebox-src="$_url">
  <article class="onebox-body"><p>An older post body</p></article>
</aside>''')
        .children
        .single;
    expect(oneboxWidgetBuilder(element), isA<OneboxCard>());
    expect(OneboxData.from(element).bodyHtml, contains('An older post body'));
  });

  test('only valid post destinations and handles receive X actions', () {
    for (final url in [
      'javascript:alert(1)',
      'https://twitter.com.example.com/user/status/1',
      'https://user@x.com/user/status/1',
      'https://x.com/user',
      'https://x.com/user/status/not-a-number',
    ]) {
      expect(_parse(_markup.replaceAll(_url, url)).url, isNull);
    }
    for (final host in ['x.com', 'www.x.com', 'mobile.twitter.com']) {
      final data = _parse(_markup.replaceAll('twitter.com', host));
      expect(data.url, contains(host));
      expect(data.statusId, '2101937724252967330');
    }
    expect(
      _parse(_markup.replaceAll('@rezoundous', '@bad/handle')).handle,
      isNull,
    );
  });

  test('malformed UTF-8 post destinations do not receive X actions', () {
    for (final url in [
      'https://x.com/%FF/status/123',
      'https://twitter.com/%C3%28/status/123',
    ]) {
      final data = _parse(
        _markup.replaceAll(_url, url).replaceAll(_quotedUrl, url),
      );
      expect(data.url, isNull);
      expect(data.statusId, isNull);
      expect(data.quote!.url, isNull);
      expect(data.quote!.statusId, isNull);
    }
  });

  test('public onebox data safely reads only valid provider status IDs', () {
    for (final url in [
      null,
      'https://[invalid',
      'https://x.com/user',
      'https://x.com/user/status/not-a-number',
      'https://example.com/user/status/123',
      'https://x.com/%FF/status/123',
    ]) {
      final data = TwitterOneboxData(
        name: 'Author',
        bodyHtml: 'Post',
        url: url,
      );
      expect(data.statusId, isNull, reason: 'Invalid destination: $url');
    }
    for (final url in [
      _url,
      'https://x.com/%72ezoundous/status/2101937724252967330/?s=20#post',
    ]) {
      final data = TwitterOneboxData(
        name: 'Author',
        bodyHtml: 'Post',
        url: url,
      );
      expect(data.statusId, '2101937724252967330');
      expect(
        _parse(_markup.replaceAll(_url, url)).url,
        Uri.parse(url).toString(),
      );
    }
  });

  testWidgets('cooked Twitter posts tolerate malformed encoded usernames', (
    tester,
  ) async {
    for (final url in [
      'https://x.com/%FF/status/123',
      'https://twitter.com/%C3%28/status/123',
    ]) {
      await tester.pumpWidget(
        _host(
          markup: _markup.replaceAll(_url, url).replaceAll(_quotedUrl, url),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TwitterOnebox), findsOneWidget);
      expect(find.text('Tyler'), findsOneWidget);
      expect(
        find.textContaining('Read the prompt', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('12K'), findsOneWidget);
      expect(find.text('Read replies'), findsNothing);
      expect(find.text('Reply'), findsNothing);
      final likes = tester.widget<DButton>(
        find.ancestor(of: find.text('12K'), matching: find.byType(DButton)),
      );
      expect(likes.onPressed, isNull);
    }
  });

  testWidgets(
    'cooked posts render full-width text and a separate quoted card',
    (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      expect(find.byType(TwitterOnebox), findsOneWidget);
      expect(find.byType(OneboxCard), findsNothing);
      expect(find.byType(DCard), findsNWidgets(2));
      expect(find.text('twitter.com'), findsNothing);
      expect(find.text('Tyler'), findsOneWidget);
      expect(find.text('@rezoundous'), findsOneWidget);
      expect(find.text('Logan Kilpatrick  @OfficialLoganK'), findsOneWidget);
      expect(find.text('12K'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
      expect(find.text('Read replies'), findsOneWidget);
      expect(find.textContaining('119 replies'), findsNothing);
      expect(tester.getSize(find.byType(DAvatar)), const Size.square(48));
      final body = find.byWidgetPredicate(
        (widget) => widget is CookedHtml && widget.html.startsWith('bro just'),
      );
      expect(
        tester.getTopLeft(body).dx,
        tester.getTopLeft(find.byType(DAvatar)).dx,
      );
      expect(tester.getSize(body).width, 518);
      expect(
        find.textContaining('fail while daring greatly', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('palette follows live light and dark theme changes', (
    tester,
  ) async {
    for (final (theme, background, foreground, border) in [
      (
        AppTheme.light,
        const Color(0xffffffff),
        const Color(0xff0f1419),
        const Color(0xffcfd9de),
      ),
      (
        AppTheme.dark,
        const Color(0xff15202b),
        const Color(0xfff7f9f9),
        const Color(0xff425364),
      ),
      (
        AppTheme.light,
        const Color(0xffffffff),
        const Color(0xff0f1419),
        const Color(0xffcfd9de),
      ),
    ]) {
      await tester.pumpWidget(_host(theme: theme));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(DCard).first);
      final tokens = DTokens.of(context);
      expect(tokens.background, background);
      expect(tokens.foreground, foreground);
      expect(tokens.border, border);
      final surface = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(DCard).first,
              matching: find.byType(Material),
            )
            .first,
      );
      expect(surface.color, background);
      expect(tester.takeException(), isNull);
    }
  });

  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets(
        'narrow post at ${scale}x in ${direction.name} stays bounded',
        (tester) async {
          tester.view.physicalSize = const Size(320, 1800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            _host(
              width: 288,
              scale: scale,
              direction: direction,
              theme: AppTheme.dark,
              markup: _markup.replaceFirst(
                '>Tyler<',
                '>A longer author display name<',
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final element in find.byType(DButton).evaluate()) {
            final rect = tester.getRect(find.byWidget(element.widget));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(288));
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'author, quote, body and post actions keep their own destinations',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger = tester.binding.defaultBinaryMessenger;
      final launched = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      for (final label in [
        'Tyler',
        'Follow',
        'Logan Kilpatrick  @OfficialLoganK',
        'Read the prompt',
        '9:33 AM · Sep 21, 2026',
        '12K',
        'Reply',
        'Read replies',
      ]) {
        if (label == 'Read the prompt') {
          await tester.tapOnText(find.textRange.ofSubstring(label));
          await tester.pumpAndSettle();
          continue;
        }
        final target = find.text(label).last;
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }
      expect(launched, [
        'https://x.com/rezoundous',
        'https://x.com/intent/follow?screen_name=rezoundous',
        _quotedUrl,
        'https://example.com/prompt',
        _url,
        'https://x.com/intent/like?tweet_id=2101937724252967330',
        'https://x.com/intent/tweet?in_reply_to=2101937724252967330',
        _url,
      ]);
    },
  );

  testWidgets('copy reports success only after writing the exact link', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    final copied = <String>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      final copy = find.bySemanticsLabel('Copy link');
      expect(
        tester.getSemantics(copy),
        isSemantics(isButton: true, hasTapAction: true, isFocusable: true),
      );
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(copied, [_url]);
      expect(find.text('Copied!'), findsOneWidget);
      await tester.pumpWidget(
        _host(
          markup: _markup.replaceAll(_url, 'https://x.com/rezoundous/status/2'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Copied!'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });
}
