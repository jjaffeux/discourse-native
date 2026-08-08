import 'package:discourse_native/src/shell/oneboxes/discourse/user/block.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

/// Shaped after `discourse_user_onebox.mustache`, the markup
/// `Oneboxer.local_user_html` renders for a profile link that sits alone on
/// its line.
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
  });
}
