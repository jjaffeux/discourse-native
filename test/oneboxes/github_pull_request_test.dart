import 'dart:ui' as ui;

import 'package:discourse_native/src/plugins/discourse_github/discourse_github_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_github/oneboxes/github.dart';
import 'package:discourse_native/src/plugins/discourse_github/oneboxes/pr/block.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_cooked_time_parser.dart';
import 'package:discourse_native/src/shell/relative_time.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

const String prOnebox = '''
<aside class="onebox githubpullrequest" data-onebox-src="https://github.com/discourse/discourse/pull/30604">
  <header class="source">
    <img src="https://cdn.example.com/github.png" class="site-icon" width="16" height="16">
    <a href="https://github.com/discourse/discourse/pull/30604" target="_blank" rel="noopener">github.com/discourse/discourse</a>
  </header>
  <article class="onebox-body">
    <div class="github-row --gh-status-merged" data-github-private-repo="false">
      <div class="github-icon-container" title="Merged">
        <svg width="60" height="60" class="github-icon" viewBox="0 0 12 16" version="1.1" aria-hidden="true"><path d="M11 11.28V5z"></path></svg>
      </div>
      <div class="github-info-container">
        <h4>
          <a href="https://github.com/discourse/discourse/pull/30604" target="_blank" rel="noopener">Add the thing (#30604)</a>
        </h4>
        <div class="branches">
          <code>main</code> ← <code>the-thing</code>
        </div>
        <div class="github-info">
          <div class="date">
            Merged <span class="discourse-local-date" data-format="ll" data-date="2026-08-01" data-time="10:24:00" data-timezone="UTC">10:24AM - 01 Aug 26 UTC</span>
          </div>
          <div class="user">
            <a href="https://github.com/octocat" target="_blank" rel="noopener">
              <img alt="" src="https://avatars.githubusercontent.com/u/1?v=4" class="onebox-avatar-inline" width="20" height="20">
              octocat
            </a>
          </div>
          <div class="lines" title="changed 3 files with 123 additions and 45 deletions">
            <a href="https://github.com/discourse/discourse/pull/30604/files" target="_blank" rel="noopener">
              <span class="added">+123</span>
              <span class="removed">-45</span>
            </a>
          </div>
        </div>
      </div>
    </div>
    <div class="github-row">
      <p class="github-body-container">This adds the thing we talked about.<span class="show-more-container"><a href="https://github.com/discourse/discourse/pull/30604" target="_blank" rel="noopener" class="show-more">…</a></span><span class="excerpt hidden">And here is the elided remainder.</span></p>
    </div>
  </article>
</aside>
''';

const String prCommentOnebox = '''
<aside class="onebox githubpullrequest" data-onebox-src="https://github.com/discourse/discourse/pull/30604#issuecomment-99">
  <article class="onebox-body">
    <div class="github-row" data-github-private-repo="false">
      <div class="github-icon-container" title="Comment">
        <svg width="60" height="60" class="github-icon" viewBox="0 0 16 16"><path d="M1.5 2.75z"></path></svg>
      </div>
      <div class="github-info-container">
        <h4>
          Comment by
          <a href="https://github.com/octocat" target="_blank" rel="noopener">
            <img alt="" src="https://avatars.githubusercontent.com/u/1?v=4" class="onebox-avatar-inline" width="20" height="20">
            octocat
          </a> - <a href="https://github.com/discourse/discourse/pull/30604#issuecomment-99" target="_blank" rel="noopener">Add the thing</a>
        </h4>
        <div class="branches">
          <code>main</code> ← <code>the-thing</code>
        </div>
        <div class="github-info">
          <span>
            Comment by
            <a href="https://github.com/octocat" target="_blank" rel="noopener">octocat</a>
          </span>
        </div>
      </div>
    </div>
  </article>
</aside>
''';

final _cookedTimeParser = LocalDatesCookedTimeParser(
  formatter: LocalDateFormatter(environment: LocalDateEnvironment.instance),
);

GithubPullRequestData parse(String source) => GithubPullRequestData.from(
  html.parse(source).querySelector('aside.onebox')!,
  cookedTimeParser: _cookedTimeParser,
);

void main() {
  group('GithubPullRequestData', () {
    test('reads the grid the template lays out', () {
      final data = parse(prOnebox);

      expect(data.title, 'Add the thing (#30604)');
      expect(
        data.titleUrl,
        'https://github.com/discourse/discourse/pull/30604',
      );
      expect(data.status, GithubPrStatus.merged);
      expect(data.baseLabel, 'main');
      expect(data.headLabel, 'the-thing');
      expect(data.dateVerb, 'Merged');
      expect(data.date, DateTime.utc(2026, 8, 1, 10, 24));
      expect(data.userLogin, 'octocat');
      expect(
        data.userAvatarUrl,
        'https://avatars.githubusercontent.com/u/1?v=4',
      );
      expect(data.userUrl, 'https://github.com/octocat');
      expect(data.additions, 123);
      expect(data.deletions, 45);
      expect(data.infoText, isNull);
    });

    test('keeps the body but not the show-more link or the hidden excerpt', () {
      final data = parse(prOnebox);

      expect(data.body, 'This adds the thing we talked about.');
    });

    test('a deep link reads its single run of text', () {
      final data = parse(prCommentOnebox);

      expect(data.status, isNull);
      expect(data.iconVariant, 'Comment');
      expect(data.date, isNull);
      expect(data.userLogin, isNull);
      expect(data.infoText, contains('Comment by'));
    });

    test('the status decides the glyph', () {
      expect(parse(prOnebox).icon, githubPrMergedIcon);
      expect(parse(prCommentOnebox).icon, githubCommentIcon);
    });
  });

  group('GithubPullRequestOnebox', () {
    testWidgets('draws the card the web draws', (tester) async {
      final aside = html.parse(prOnebox).querySelector('aside.onebox')!;
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

      expect(find.text('Add the thing (#30604)'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Add the thing (#30604)')).style?.color,
        accent,
      );
      expect(find.text('github.com/discourse/discourse'), findsOneWidget);
      expect(find.textContaining('main', findRichText: true), findsOneWidget);
      expect(find.textContaining('+123', findRichText: true), findsOneWidget);
      expect(find.textContaining('−45', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('octocat', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('Merged ${relativeTime(DateTime.utc(2026, 8, 1, 10, 24))}'),
        findsOneWidget,
      );
      expect(find.text('This adds the thing we talked about.'), findsOneWidget);

      final icon = tester.widget<GithubOneboxIcon>(
        find.byType(GithubOneboxIcon),
      );
      expect(icon.icon, githubPrMergedIcon);
      expect(icon.color, GithubPrStatus.merged.color);
      expect(icon.isPrStatus, isTrue);
      expect(
        tester.getSize(find.byType(GithubOneboxIcon)),
        githubPrStatusSlotSize,
      );
      expect(tester.getSize(find.byType(SvgPicture)), githubPrStatusIconSize);
      expect(githubPrStatusIconSize.aspectRatio, 1);
      expect(
        tester.widget<SvgPicture>(find.byType(SvgPicture)).fit,
        BoxFit.contain,
      );
    });

    testWidgets('uses core legacy size and primary-high without a status', (
      tester,
    ) async {
      final aside = html
          .parse(prOnebox.replaceFirst(' --gh-status-merged', ''))
          .querySelector('aside.onebox')!;
      final theme = AppTheme.dark;

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: DiscourseGithubPlugin(
              cookedTimeParser: _cookedTimeParser,
            ).cookedElement(null, aside)!,
          ),
        ),
      );
      await tester.pump();

      final icon = tester.widget<GithubOneboxIcon>(
        find.byType(GithubOneboxIcon),
      );
      expect(icon.icon, githubPullRequestIcon);
      expect(icon.color, theme.discourse.primaryHigh);
      expect(icon.isPrStatus, isFalse);
      expect(tester.getSize(find.byType(SvgPicture)), githubLegacyIconSize);
    });

    testWidgets('does not overflow in an exceptionally narrow post column', (
      tester,
    ) async {
      final aside = html.parse(prOnebox).querySelector('aside.onebox')!;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 96,
                  child: DiscourseGithubPlugin(
                    cookedTimeParser: _cookedTimeParser,
                  ).cookedElement(null, aside)!,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('paints the requested Lucide icon color', (tester) async {
      const boundaryKey = ValueKey('github-icon-paint');
      const color = Color(0xFF2A6CD6);

      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: GithubOneboxIcon(
                icon: githubPullRequestIcon,
                color: color,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final pixels = (await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return data!.buffer.asUint8List();
        } finally {
          image.dispose();
        }
      }))!;

      var foundTint = false;
      var foundBlack = false;
      final argb = color.toARGB32();
      final expectedRed = (argb >> 16) & 0xFF;
      final expectedGreen = (argb >> 8) & 0xFF;
      final expectedBlue = argb & 0xFF;
      for (var offset = 0; offset < pixels.length; offset += 4) {
        final alpha = pixels[offset + 3];
        if (alpha == 0) continue;
        final red = pixels[offset];
        final green = pixels[offset + 1];
        final blue = pixels[offset + 2];
        foundTint |=
            red == expectedRed &&
            green == expectedGreen &&
            blue == expectedBlue;
        foundBlack |= red == 0 && green == 0 && blue == 0;
      }

      expect(foundTint, isTrue);
      expect(foundBlack, isFalse);
    });
  });
}
