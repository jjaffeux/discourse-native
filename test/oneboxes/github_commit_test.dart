import 'package:discourse_native/src/shell/oneboxes/github/commit/block.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/shell/relative_time.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

/// Shaped after `githubcommit.mustache`.
const String commitOnebox = '''
<aside class="onebox githubcommit" data-onebox-src="https://github.com/discourse/discourse/commit/9b6ee3f">
  <header class="source">
    <img src="https://cdn.example.com/github.png" class="site-icon" width="16" height="16">
    <a href="https://github.com/discourse/discourse/commit/9b6ee3f" target="_blank" rel="noopener">github.com/discourse/discourse</a>
  </header>
  <article class="onebox-body">
    <div class="github-row">
      <div class="github-icon-container" title="Commit">
        <svg width="60" height="60" class="github-icon" viewBox="0 0 14 16" version="1.1" aria-hidden="true"><path d="M10.86 7z"></path></svg>
      </div>
      <div class="github-info-container">
        <h4>
          <a href="https://github.com/discourse/discourse/commit/9b6ee3f" target="_blank" rel="noopener">Ship Linux as a .deb from an apt repository</a>
        </h4>
        <div class="github-info">
          <div class="date">
            Committed <span class="discourse-local-date" data-format="ll" data-date="2026-07-30" data-time="16:45:00" data-timezone="UTC">04:45PM - 30 Jul 26 UTC</span>
          </div>
          <div class="user">
            <a href="https://github.com/octocat" target="_blank" rel="noopener">
              <img alt="" src="https://avatars.githubusercontent.com/u/1?v=4" class="onebox-avatar-inline" width="20" height="20">
              octocat
            </a>
          </div>
          <div class="lines" title="changed 2 files with 12 additions and 3 deletions">
            <a href="https://github.com/discourse/discourse/commit/9b6ee3f" target="_blank" rel="noopener">
              <span class="added">+12</span>
              <span class="removed">-3</span>
            </a>
          </div>
        </div>
      </div>
    </div>
  </article>
</aside>
''';

GithubCommitData parse(String source) =>
    GithubCommitData.from(html.parse(source).querySelector('aside.onebox')!);

void main() {
  group('GithubCommitData', () {
    test('reads title, date, author and diff counts', () {
      final data = parse(commitOnebox);

      expect(data.title, 'Ship Linux as a .deb from an apt repository');
      expect(
        data.titleUrl,
        'https://github.com/discourse/discourse/commit/9b6ee3f',
      );
      expect(data.committedVerb, 'Committed');
      expect(data.committedAt, DateTime.utc(2026, 7, 30, 16, 45));
      expect(data.authorLogin, 'octocat');
      expect(data.additions, 12);
      expect(data.deletions, 3);
      expect(data.body, isNull);
    });
  });

  group('GithubCommitOnebox', () {
    testWidgets('draws the commit card', (tester) async {
      final aside = html.parse(commitOnebox).querySelector('aside.onebox')!;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(child: oneboxWidgetBuilder(aside)!),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('Ship Linux as a .deb from an apt repository'),
        findsOneWidget,
      );
      expect(find.text('octocat'), findsOneWidget);
      expect(find.text('+12'), findsOneWidget);
      expect(find.text('−3'), findsOneWidget);
      expect(
        find.text(
          'Committed ${relativeTime(DateTime.utc(2026, 7, 30, 16, 45))}',
        ),
        findsOneWidget,
      );
    });
  });
}
