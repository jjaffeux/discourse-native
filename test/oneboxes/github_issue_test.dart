import 'package:discourse_native/src/shell/oneboxes/github/github.dart';
import 'package:discourse_native/src/shell/oneboxes/github/issue/block.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/shell/relative_time.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

/// Shaped after `githubissue.mustache`, with a close date and two labels.
const String issueOnebox = '''
<aside class="onebox githubissue" data-onebox-src="https://github.com/discourse/discourse/issues/12345">
  <header class="source">
    <img src="https://cdn.example.com/github.png" class="site-icon" width="16" height="16">
    <a href="https://github.com/discourse/discourse/issues/12345" target="_blank" rel="noopener">github.com/discourse/discourse</a>
  </header>
  <article class="onebox-body">
    <div class="github-row">
      <div class="github-icon-container" title="Issue" data-github-private-repo="false">
        <svg width="60" height="60" class="github-icon" viewBox="0 0 14 16" version="1.1" aria-hidden="true"><path d="M7 2.3z"></path></svg>
      </div>
      <div class="github-info-container">
        <h4>
          <a href="https://github.com/discourse/discourse/issues/12345" target="_blank" rel="noopener">Bug: the thing breaks (#12345)</a>
        </h4>
        <div class="github-info">
          <div class="date">
            Opened <span class="discourse-local-date" data-format="ll" data-date="2026-07-01" data-time="09:00:00" data-timezone="UTC">09:00AM - 01 Jul 26 UTC</span>
          </div>
          <div class="date">
            Closed <span class="discourse-local-date" data-format="ll" data-date="2026-07-20" data-time="12:30:00" data-timezone="UTC">12:30PM - 20 Jul 26 UTC</span>
          </div>
          <div class="user">
            <a href="https://github.com/octocat" target="_blank" rel="noopener">
              <img alt="" src="https://avatars.githubusercontent.com/u/1?v=4" class="onebox-avatar-inline" width="20" height="20">
              octocat
            </a>
          </div>
        </div>
        <div class="labels">
          <span style="display:inline-block;margin-top:2px;background-color: #B8B8B8;padding: 2px;border-radius: 4px;color: #fff;margin-left: 3px;">bug</span>
          <span style="display:inline-block;margin-top:2px;background-color: #B8B8B8;padding: 2px;border-radius: 4px;color: #fff;margin-left: 3px;">regression</span>
        </div>
      </div>
    </div>
    <div class="github-row">
      <p class="github-body-container">Steps to reproduce the breakage.</p>
    </div>
  </article>
</aside>
''';

GithubIssueData parse(String source) =>
    GithubIssueData.from(html.parse(source).querySelector('aside.onebox')!);

void main() {
  group('GithubIssueData', () {
    test('reads title, dates, user, labels and body', () {
      final data = parse(issueOnebox);

      expect(data.title, 'Bug: the thing breaks (#12345)');
      expect(
        data.titleUrl,
        'https://github.com/discourse/discourse/issues/12345',
      );
      expect(data.openedVerb, 'Opened');
      expect(data.openedAt, DateTime.utc(2026, 7, 1, 9));
      expect(data.closedVerb, 'Closed');
      expect(data.closedAt, DateTime.utc(2026, 7, 20, 12, 30));
      expect(data.userLogin, 'octocat');
      expect(data.labels, ['bug', 'regression']);
      expect(data.body, 'Steps to reproduce the breakage.');
    });
  });

  group('GithubIssueOnebox', () {
    testWidgets('draws title, labels and the issue glyph', (tester) async {
      final aside = html.parse(issueOnebox).querySelector('aside.onebox')!;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(child: oneboxWidgetBuilder(aside)!),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Bug: the thing breaks (#12345)'), findsOneWidget);
      expect(find.text('bug'), findsOneWidget);
      expect(find.text('regression'), findsOneWidget);
      expect(find.text('octocat'), findsOneWidget);
      expect(
        find.text('Opened ${relativeTime(DateTime.utc(2026, 7, 1, 9))}'),
        findsOneWidget,
      );
      expect(
        find.text('Closed ${relativeTime(DateTime.utc(2026, 7, 20, 12, 30))}'),
        findsOneWidget,
      );

      final icon = tester.widget<DIcon>(
        find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == githubIssueIcon,
        ),
      );
      expect(icon.icon, githubIssueIcon);
    });
  });
}
