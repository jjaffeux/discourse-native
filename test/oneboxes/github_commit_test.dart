import 'package:discourse_native/src/plugins/discourse_github/discourse_github_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_github/oneboxes/commit/block.dart';
import 'package:discourse_native/src/plugins/discourse_github/oneboxes/github.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_cooked_time_parser.dart';
import 'package:discourse_native/src/shell/cooked_dom.dart';
import 'package:discourse_native/src/shell/relative_time.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

final _cookedTimeParser = LocalDatesCookedTimeParser(
  formatter: LocalDateFormatter(environment: LocalDateEnvironment.instance),
);

GithubCommitData parse(String source) => GithubCommitData.from(
  html.parse(source).querySelector('aside.onebox')!,
  cookedTimeParser: _cookedTimeParser,
);

void main() {
  test('deep GitHub markup is parsed without recursive traversal', () {
    const depth = 1000;
    final nested =
        '${List.filled(depth, '<span>').join()}'
        'deep body'
        '${List.filled(depth, '</span>').join()}';
    final document = html.parse(
      '<article><div class="github-body-container">$nested</div></article>',
    );
    final article = document.querySelector('article')!;

    expect(githubBody(article), 'deep body');
    expect(
      descendantWhere(article, (element) => element.text == 'deep body'),
      isNotNull,
    );
    expect(
      descendantsWhere(article, (element) => element.localName == 'span'),
      hasLength(depth),
    );
  });

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

    test('keeps the card metadata when cooked-time parsing is absent', () {
      final aside = html.parse(commitOnebox).querySelector('aside.onebox')!;
      final data = GithubCommitData.from(aside, cookedTimeParser: null);

      expect(data.committedVerb, 'Committed');
      expect(data.committedAt, isNull);
      expect(data.authorLogin, 'octocat');
      expect(data.additions, 12);
      expect(data.deletions, 3);
    });
  });

  group('GithubCommitOnebox', () {
    testWidgets('draws the commit card', (tester) async {
      final aside = html.parse(commitOnebox).querySelector('aside.onebox')!;
      const accent = Color(0xFF7B5FE2);
      const highlight = Color(0xFFFFFF4D);
      final theme = AppTheme.light.copyWith(
        colorScheme: AppTheme.light.colorScheme.copyWith(
          primary: accent,
          tertiary: highlight,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DiscourseGithubPlugin(
                cookedTimeParser: _cookedTimeParser,
              ).cookedElement(null, aside)!,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('Ship Linux as a .deb from an apt repository'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.text('Ship Linux as a .deb from an apt repository'),
            )
            .style
            ?.color,
        accent,
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

      final icon = tester.widget<GithubOneboxIcon>(
        find.byType(GithubOneboxIcon),
      );
      expect(icon.icon, githubCommitIcon);
      expect(icon.color, theme.discourse.primaryHigh);
      expect(tester.getSize(find.byType(SvgPicture)), githubLegacyIconSize);
    });

    testWidgets('metadata links are named and keyboard operable', (
      tester,
    ) async {
      const authorUrl = 'https://github.com/octocat';
      const countsUrl =
          'https://github.com/discourse/discourse/commit/9b6ee3f#files';
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
              body: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GithubUser(
                      login: 'octocat',
                      avatarUrl: null,
                      url: authorUrl,
                    ),
                    SizedBox(width: 20),
                    GithubLineCounts(
                      additions: 12,
                      deletions: 3,
                      url: countsUrl,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final author = find.bySemanticsLabel('octocat');
        final counts = find.bySemanticsLabel('12 additions, 3 deletions');
        expect(author, findsOneWidget);
        expect(counts, findsOneWidget);
        for (final target in [author, counts]) {
          expect(
            tester.getSemantics(target),
            isSemantics(
              isLink: true,
              isButton: false,
              isFocusable: true,
              hasTapAction: true,
              hasFocusAction: true,
            ),
          );
          final ink = find.descendant(
            of: target,
            matching: find.byType(InkWell),
          );
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
          expect(tester.getSize(target).height, lessThan(44));
        }

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          tester.getSemantics(author),
          isSemantics(isFocusable: true, isFocused: true),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          tester.getSemantics(counts),
          isSemantics(isFocusable: true, isFocused: true),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();

        expect(launched, [authorUrl, countsUrl]);
      } finally {
        semantics.dispose();
      }
    });
  });
}
