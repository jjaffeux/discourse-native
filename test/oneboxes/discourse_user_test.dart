import 'package:discourse_native/src/shell/oneboxes/discourse/user/block.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

const String userOnebox = '''
<aside class="onebox" data-onebox-src="https://meta.discourse.org/u/octocat">
  <article class="onebox-body user-onebox">
    <img src="/user_avatar/meta.discourse.org/octocat/120/42.png" class="avatar" width="120" height="120" alt="">
    <h3><a href="https://meta.discourse.org/u/octocat">@octocat</a></h3>
    <div>
      <span class="full-name">Octo Cat</span>
      <span class="location">
        <svg class="fa d-icon d-icon-location-dot svg-icon" xmlns="http://www.w3.org/2000/svg"><use href="#location-dot"></use></svg>
        GitHub HQ
      </span>
      <span>
        <svg class="fa d-icon d-icon-earth-americas svg-icon" xmlns="http://www.w3.org/2000/svg"><use href="#earth-americas"></use></svg>
        <a href="https://github.com">github.com</a>
      </span>
    </div>
    <p>Here to help.</p>
    <div class="user-onebox--joined">Joined community on 1 January 2020</div>
  </article>
  <div class="clearfix"></div>
</aside>
''';

DiscourseUserData parse(String source) =>
    DiscourseUserData.from(html.parse(source).querySelector('aside.onebox')!);

void main() {
  test('deep user markup parses without recursive DOM traversal', () {
    const depth = 1000;
    final nested =
        '${List.filled(depth, '<div>').join()}'
        '<div class="user-onebox"><h3><a href="/u/deep">'
        '@deep</a></h3></div>'
        '${List.filled(depth, '</div>').join()}';

    final aside = html
        .parse('<aside class="onebox">$nested</aside>')
        .querySelector('aside.onebox')!;

    expect(discourseUserBlock.matches(aside), isTrue);
    expect(DiscourseUserData.from(aside).username, 'deep');
  });

  group('DiscourseUserData', () {
    test('reads the profile the template wrote', () {
      final data = parse(userOnebox);

      expect(data.username, 'octocat');
      expect(
        data.avatarUrl,
        '/user_avatar/meta.discourse.org/octocat/120/42.png',
      );
      expect(data.name, 'Octo Cat');
      expect(data.location, 'GitHub HQ');
      expect(data.websiteName, 'github.com');
      expect(data.websiteUrl, 'https://github.com');
      expect(data.bio, 'Here to help.');
      expect(data.joined, 'Joined community on 1 January 2020');
    });
  });

  group('DiscourseUserOnebox', () {
    testWidgets('draws the profile card', (tester) async {
      final aside = html.parse(userOnebox).querySelector('aside.onebox')!;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(child: oneboxWidgetBuilder(aside)!),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('octocat'), findsOneWidget);
      expect(find.text('Octo Cat'), findsOneWidget);
      expect(find.text('GitHub HQ'), findsOneWidget);
      expect(find.text('github.com'), findsOneWidget);
      expect(find.text('Here to help.'), findsOneWidget);
      expect(find.text('Joined community on 1 January 2020'), findsOneWidget);
    });

    testWidgets('website is a named compact keyboard link', (tester) async {
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

      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: DiscourseUserOnebox(
                data: DiscourseUserData(
                  username: 'octocat',
                  avatarUrl: null,
                  name: 'Octo Cat',
                  location: 'GitHub HQ',
                  websiteName: 'github.com',
                  websiteUrl: 'https://github.com',
                  bio: null,
                  joined: null,
                ),
              ),
            ),
          ),
        );

        final target = find.bySemanticsLabel('github.com');
        expect(target, findsOneWidget);
        expect(tester.getSize(target).height, lessThan(44));
        expect(
          tester.getSemantics(target),
          isSemantics(
            label: 'github.com',
            isLink: true,
            isButton: false,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );
        final ink = find.descendant(of: target, matching: find.byType(InkWell));
        expect(ink, findsOneWidget);
        expect(
          tester.widget<InkWell>(ink).mouseCursor,
          SystemMouseCursors.click,
        );
        expect(tester.widget<InkWell>(ink).hoverColor, Colors.transparent);
        expect(
          tester.widget<InkWell>(ink).focusColor,
          Theme.of(tester.element(target)).shell.hover,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          tester.getSemantics(target),
          isSemantics(isFocusable: true, isFocused: true),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(launched, ['https://github.com']);
      } finally {
        semantics.dispose();
      }
    });
  });
}
