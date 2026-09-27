import 'dart:io';
import 'dart:math';

import 'package:discourse_native/src/models/forum_theme_share.dart';
import 'package:discourse_native/src/plugins/chat/chat_transcript.dart';
import 'package:discourse_native/src/plugins/discourse_github/oneboxes/commit/block.dart';
import 'package:discourse_native/src/plugins/discourse_github/oneboxes/issue/block.dart';
import 'package:discourse_native/src/plugins/discourse_github/oneboxes/pr/block.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_widget.dart';
import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/shell/cooked_details.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/cooked_spoiler.dart';
import 'package:discourse_native/src/shell/cooked_table.dart';
import 'package:discourse_native/src/shell/cooked_todos.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_native/src/shell/image_grid.dart';
import 'package:discourse_native/src/shell/inline_code.dart';
import 'package:discourse_native/src/shell/inline_video.dart';
import 'package:discourse_native/src/shell/lightbox.dart';
import 'package:discourse_native/src/shell/mention.dart';
import 'package:discourse_native/src/shell/oneboxes/audio.dart';
import 'package:discourse_native/src/shell/oneboxes/discourse/category/block.dart';
import 'package:discourse_native/src/shell/oneboxes/discourse/topic/block.dart';
import 'package:discourse_native/src/shell/oneboxes/discourse/user/block.dart';
import 'package:discourse_native/src/shell/oneboxes/embedded.dart';
import 'package:discourse_native/src/shell/oneboxes/forum_theme.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/shell/oneboxes/reddit.dart';
import 'package:discourse_native/src/shell/oneboxes/twitter.dart';
import 'package:discourse_native/src/shell/quote.dart';
import 'package:discourse_native/src/shell/youtube_video.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// Tags, classes and attributes taken from the markup these builders read, so
/// a generated fragment is a plausible mangling of a cooked post rather than
/// arbitrary HTML the builders would decline on the first check.
const _tags = [
  'aside',
  'article',
  'div',
  'span',
  'a',
  'p',
  'img',
  'blockquote',
  'header',
  'h3',
  'h4',
  'pre',
  'code',
  'ul',
  'li',
  'table',
  'thead',
  'tbody',
  'tr',
  'th',
  'td',
  'strong',
  'br',
  'details',
  'summary',
  'iframe',
  'script',
  'audio',
  'video',
  'source',
];

const _classes = [
  'onebox',
  'onebox-body',
  'onebox-avatar',
  'source',
  'site-icon',
  'github-row',
  'github-icon-container',
  'github-info-container',
  'branches',
  'user-avatar',
  'thumbnail',
  'lightbox-wrapper',
  'lightbox',
  'meta',
  'informations',
  'quote',
  'title',
  'badge-wrapper',
  'badge-category',
  'subcategory',
  'category-title',
  'user-card',
  'names',
  'bio',
  'discourse-local-date',
  'mention',
  'hashtag-cooked',
  'emoji',
  'emoji-only',
  'd-image-grid',
  'd-image-grid-column',
  'image-wrapper',
  'lang-ruby',
  'hljs',
  'highlight',
  'chat-transcript',
  'expand-post',
  'avatar',
  'stats',
  'twitterstatus',
  'tweet-description',
  'quoted',
  'reddit-onebox',
  'youtube-onebox',
  'youtube-thumbnail',
  'video-placeholder-container',
  'video-container',
  'spoiler',
  'chcklst-box',
  'checked',
];

const _attributes = [
  'href',
  'src',
  'title',
  'alt',
  'width',
  'height',
  'data-date',
  'data-time',
  'data-timezone',
  'data-recurring',
  'data-format',
  'data-orig-src',
  'data-download-href',
  'data-type',
  'data-slug',
  'data-id',
  'data-ref',
  'data-topic',
  'data-post',
  'data-username',
  'data-name',
  'data-email',
  'colspan',
  'rel',
  'target',
  'lang',
  'style',
  'aria-label',
  'data-onebox-src',
  'data-original-href',
  'data-video-src',
  'data-thumbnail-src',
  'data-code-wrap',
  'poster',
  'open',
];

const _values = [
  '',
  '1',
  '-1',
  '0',
  'https://example.com/t/x/1',
  '/uploads/default/original/1X/a.png',
  'not a url',
  '2020-01-01',
  '12:00',
  'Europe/Paris',
  '1.weeks',
  'YYYY-MM-DD',
  '9999999999999999999999',
  '😀',
  'category',
  'tag',
  'room',
  'user',
];

/// Skeletons of the markup each builder claims, so the generator spends its
/// budget inside the parsers rather than on their first `localName` check.
/// Every attribute and child below is dropped or replaced at random, which is
/// the point: what has to hold is that a half-written one is declined, not
/// that a well-formed one is drawn.
const _skeletons = [
  '<img class="emoji" src="@SRC" alt="@V" title="@V">',
  '<img class="emoji only-emoji" src="@SRC">',
  '<a class="hashtag-cooked" href="@SRC" data-type="@V" data-slug="@V">'
      '<span class="hashtag-icon-placeholder"></span><span>@V</span></a>',
  '<a class="mention" href="@SRC">@@V</a>',
  '<a class="mention-group" href="@SRC">@@V</a>',
  '<div class="lightbox-wrapper"><a class="lightbox" href="@SRC" '
      'data-download-href="@SRC" title="@V">'
      '<img src="@SRC" width="@V" height="@V" data-orig-src="@SRC"></a></div>',
  '<a class="lightbox" href="@SRC"><img src="@SRC" width="@V" height="@V">'
      '</a>',
  '<div class="d-image-grid" data-mode="@V"><div class="d-image-grid-column">'
      '<img src="@SRC" width="@V" height="@V"></div>'
      '<div class="d-image-grid-column"><img src="@SRC"></div></div>',
  '<span class="discourse-local-date" data-date="@V" data-time="@V" '
      'data-timezone="@V" data-recurring="@V" data-format="@V">@V</span>',
  '<pre data-code-wrap="@V"><code class="lang-@V">@V</code></pre>',
  '<code>@V</code>',
  '<aside class="quote" data-post="@V" data-topic="@V" data-username="@V">'
      '<div class="title"><img class="avatar" src="@SRC">@V</div>'
      '<blockquote>@V</blockquote></aside>',
  '<blockquote>@V</blockquote>',
  '<div class="chat-transcript" data-username="@V" data-datetime="@V">'
      '<div class="chat-transcript-user">'
      '<div class="chat-transcript-user-avatar">'
      '<img class="avatar" src="@SRC"></div>'
      '<div class="chat-transcript-username">@V</div>'
      '<div class="chat-transcript-datetime"><a href="@SRC" title="@V">'
      '</a></div><a class="chat-transcript-channel" href="@SRC">@V</a>'
      '</div><div class="chat-transcript-messages"><p>@V</p></div></div>',
  '<aside class="onebox @V"><header class="source">'
      '<img class="site-icon" src="@SRC"><a href="@SRC" target="_blank">@V</a>'
      '</header><article class="onebox-body"><img class="thumbnail" src="@SRC">'
      '<h3><a href="@SRC">@V</a></h3><p>@V</p></article></aside>',
  '<aside class="onebox githubpullrequest"><article class="onebox-body">'
      '<div class="github-row"><div class="github-icon-container"></div>'
      '<div class="github-info-container"><h4><a href="@SRC">@V</a></h4>'
      '<div class="branches">@V</div><div class="labels"><span>@V</span></div>'
      '</div></div><div class="github-row"><span class="user-avatar">'
      '<img src="@SRC"></span><span>@V</span></div></article></aside>',
  '<aside class="onebox githubissue"><article class="onebox-body">'
      '<div class="github-row"><h4><a href="@SRC">@V</a></h4>'
      '<div class="date">@V</div></div></article></aside>',
  '<aside class="onebox githubcommit"><article class="onebox-body">'
      '<div class="github-row"><h4><a href="@SRC">@V</a></h4>'
      '<span class="user-avatar"><img src="@SRC"></span>'
      '<span class="added">+@V</span><span class="removed">-@V</span>'
      '</div></article></aside>',
  '<aside class="onebox discoursetopic"><article class="onebox-body">'
      '<img class="thumbnail onebox-avatar" src="@SRC">'
      '<h3><a href="@SRC">@V</a></h3><div class="badge-wrapper">'
      '<span class="badge-category">@V</span></div>'
      '<div class="tags"><span>@V</span></div></article></aside>',
  '<aside class="onebox category-onebox"><article class="onebox-body">'
      '<h3><a href="@SRC">@V</a></h3><div class="subcategory">@V</div>'
      '<p>@V</p></article></aside>',
  // Core's discourse_user_onebox template.
  '<aside class="onebox"><article class="onebox-body user-onebox">'
      '<img alt="" width="@V" height="@V" src="@SRC" class="avatar">'
      '<h3><a href="@SRC">@@V</a></h3><div><span class="full-name">@V</span>'
      '<span class="location"><svg class="fa d-icon d-icon-location-dot '
      'svg-icon" xmlns="http://www.w3.org/2000/svg">'
      '<use href="#location-dot"></use></svg>@V</span>'
      '<span><a href="@SRC">@V</a></span></div><p>@V</p>'
      '<div class="user-onebox--joined">@V</div></article>'
      '<div class="clearfix"></div></aside>',
  // Core's twitterstatus template inside the onebox layout.
  '<aside class="onebox twitterstatus" '
      'data-onebox-src="https://x.com/@V/status/@V"><header class="source">'
      '<a href="@SRC" target="_blank" rel="noopener">@V</a></header>'
      '<article class="onebox-body">'
      '<img src="@SRC" class="thumbnail onebox-avatar" alt="">'
      '<h4><a href="@SRC" target="_blank" rel="noopener">@V</a></h4>'
      '<div class="twitter-screen-name">'
      '<a href="@SRC" target="_blank" rel="noopener">@@V</a></div>'
      '<div class="tweet"><span class="is-reply">'
      '<svg class="fa d-icon d-icon-reply svg-icon svg-string" '
      'xmlns="http://www.w3.org/2000/svg"><use href="#reply"></use></svg>'
      '</span><span class="tweet-description">@V</span>'
      '<div class="quoted"><a class="quoted-link" href="@SRC">'
      '<p class="quoted-title">@V <span>@@V</span></p></a><div>@V</div></div>'
      '</div><div class="date">'
      '<a href="@SRC" class="timestamp" target="_blank" rel="noopener">@V</a>'
      '<span class="like">@V</span><span class="retweet">@V</span></div>'
      '</article></aside>',
  // An uploaded audio file, and core's AudioOnebox, which differs only in
  // dropping `preload` and `data-orig-src`.
  '<audio preload="metadata" controls>'
      '<source src="@SRC" data-orig-src="@SRC"><a href="@SRC">@V</a></audio>',
  // RedditMediaOnebox.
  '<iframe class="reddit-onebox" src="https://embed.reddit.com/r/@V/comments/'
      '@V/@V/?embed=true&amp;ref_source=embed&amp;ref=share" width="640" '
      'height="@V" allowfullscreen></iframe>',
  // Core's iframe oneboxes share VimeoOnebox's shape.
  '<iframe class="vimeo-onebox" src="@SRC" data-original-href="@SRC" '
      'frameborder="0" allowfullscreen></iframe>',
  // AsciinemaOnebox, core's only script onebox.
  '<script type="text/javascript" src="https://asciinema.org/a/@V.js" '
      'id="asciicast-@V" async></script>',
  // A shared forum theme is an ordinary fence in its own language.
  '<pre data-code-wrap="${ForumThemeShare.language}">'
      '<code class="lang-${ForumThemeShare.language}">@V</code></pre>',
  // YoutubeOnebox for a video: the hidden thumbnail, then the player.
  '<img class="youtube-thumbnail onebox" style="display: none;" src="@SRC">'
      '<iframe src="https://www.youtube.com/embed/@V?feature=oembed&amp;'
      'wmode=opaque" width="480" height="360" frameborder="0" allowfullscreen '
      'class="youtube-onebox"></iframe>',
  // An uploaded video once PrettyText has found its thumbnail.
  '<div class="video-placeholder-container" data-video-src="@SRC" '
      'data-orig-src="@SRC" data-thumbnail-src="@SRC"></div>',
  // The block and inline wraps of spoiler-alert, then discourse-details.
  '<div class="spoiler"><p>@V</p></div>',
  '<span class="spoiler">@V</span>',
  '<details open=""><summary>@V</summary><p>@V</p></details>',
  // A Markdown table in core's wrapper.
  '<div class="md-table"><table><thead><tr><th>@V</th><th>@V</th></tr>'
      '</thead><tbody><tr><td>@V</td><td>@V</td></tr></tbody></table></div>',
  // Checklist boxes starting list items, then lines of a paragraph.
  '<ul><li><span class="chcklst-box fa fa-square-o" data-chk-src="@V">'
      '</span> @V</li><li><span class="chcklst-box checked fa '
      'fa-square-check-o"></span> @V</li></ul>',
  '<p><span class="chcklst-box checked permanent fa fa-square-check"></span> '
      '@V<br><span class="chcklst-box fa fa-square-o"></span> @V</p>',
];

/// Removes one attribute, one child element, or one closing tag from [markup].
/// Cooked HTML this client cannot read is exactly the case being tested, and
/// the interesting near-misses are one edit away from the real thing.
String _mangle(Random random, String markup) {
  switch (random.nextInt(6)) {
    case 0:
      return markup.replaceFirst(RegExp(r'\s[a-z-]+="[^"]*"'), '');
    case 1:
      return markup.replaceFirst(RegExp(r'<[a-z0-9]+[^>]*>'), '');
    case 2:
      return markup.replaceFirst(RegExp(r'</[a-z0-9]+>'), '');
    case 3:
      return markup.replaceAll(RegExp(r'class="[^"]*"'), 'class=""');
    case 4:
      return markup.replaceAll('>@V<', '><');
    default:
      return markup;
  }
}

String _skeleton(Random random) {
  var markup = _skeletons[random.nextInt(_skeletons.length)];
  while (markup.contains('@SRC')) {
    markup = markup.replaceFirst(
      '@SRC',
      _values[random.nextInt(_values.length)],
    );
  }
  while (markup.contains('@V')) {
    markup = markup.replaceFirst('@V', _values[random.nextInt(_values.length)]);
  }
  return random.nextInt(3) == 0 ? _mangle(random, markup) : markup;
}

String _fragment(Random random, int depth) {
  final buffer = StringBuffer();
  final count = random.nextInt(depth > 2 ? 2 : 4);
  for (var i = 0; i < count; i++) {
    switch (random.nextInt(6)) {
      case 0:
        buffer.write(_values[random.nextInt(_values.length)]);
        continue;
      case 1:
      case 2:
      case 3:
        buffer.write(_skeleton(random));
        continue;
    }
    final tag = _tags[random.nextInt(_tags.length)];
    buffer.write('<$tag');
    if (random.nextBool()) {
      final classes = [
        for (var c = random.nextInt(3); c > 0; c--)
          _classes[random.nextInt(_classes.length)],
      ];
      buffer.write(' class="${classes.join(' ')}"');
    }
    for (var a = random.nextInt(3); a > 0; a--) {
      final name = _attributes[random.nextInt(_attributes.length)];
      final value = _values[random.nextInt(_values.length)];
      buffer.write(' $name="$value"');
    }
    buffer.write('>');
    buffer.write(_fragment(random, depth + 1));
    buffer.write('</$tag>');
  }
  return buffer.toString();
}

Iterable<dom.Element> _descendants(dom.Element root) sync* {
  yield root;
  for (final child in root.children) {
    yield* _descendants(child);
  }
}

const _builders = [
  'todo',
  'spoiler',
  'emoji',
  'mention',
  'hashtag',
  'imageGrid',
  'lightbox',
  'inlineVideo',
  'youtubeVideo',
  'onebox',
  'quote',
  'details',
  'table',
  'codeBlock',
  'inlineCode',
  'chatTranscript',
  'localDate',
  // What the onebox dispatcher hands an element to before its engines. Any
  // generic card reaches `onebox`, so that says nothing about these.
  'onebox forumTheme',
  'onebox audio',
  'onebox reddit',
  'onebox embedded iframe',
  'onebox embedded script',
];

/// The engines behind the onebox dispatcher and the GitHub plugin, by the
/// name each file declares them under.
final _oneboxEngines = {
  'twitterBlock': twitterBlock,
  'discourseTopicBlock': discourseTopicBlock,
  'discourseUserBlock': discourseUserBlock,
  'discourseCategoryBlock': discourseCategoryBlock,
};
final _githubOneboxEngines = {
  'githubPullRequestBlock': githubPullRequestBlock,
  'githubIssueBlock': githubIssueBlock,
  'githubCommitBlock': githubCommitBlock,
};

/// What `CookedHtml`'s own builders and the onebox dispatcher answer with, one
/// widget each. The plugin builders probed here are not in its chain.
const _drawn = [
  'DCheckbox',
  // Spoilers and details both.
  'DAccordion<int>',
  'EmojiImage',
  'MentionPill',
  'HashtagPill',
  'ImageGridMosaic',
  'LightboxThumbnail',
  'InlineVideo',
  'YoutubeVideo',
  'OneboxCard',
  // A shared theme that does not decode.
  'DAlert',
  'AudioOnebox',
  // Reddit's embed; other iframes wait behind `EmbeddedOnebox`'s card.
  'DEmbed',
  'EmbeddedOnebox',
  'TwitterOnebox',
  'DiscourseTopicOnebox',
  'DiscourseUserOnebox',
  'DiscourseCategoryOnebox',
  'QuoteBlock',
  '_CookedTable',
  'CodeBlock',
  'InlineCode',
];

final _builderCall = RegExp(r'\b(\w+WidgetBuilder)\(');

Widget _nested(BuildContext context, String html) => const SizedBox.shrink();

void main() {
  final localDateFormatter = LocalDateFormatter(
    environment: LocalDateEnvironment.instance,
  );

  // Cooked HTML is the site's, not this client's, and a builder that throws
  // while reading it does not lose one onebox — `HtmlWidget` calls these from
  // inside `build`, so the exception replaces the whole post, and in a topic
  // list preview the whole row. Every builder must decline markup it does not
  // recognise by answering null.
  test('no cooked-markup builder throws on markup it did not expect', () {
    final random = Random(20260823);
    const site = 'https://example.com';
    final failures = <String, String>{};

    final built = <String, int>{};
    void probe(String label, Object? Function() body, dom.Element element) {
      try {
        if (body() != null) built[label] = (built[label] ?? 0) + 1;
      } catch (error) {
        failures.putIfAbsent(
          label,
          () => '$label threw $error on ${element.outerHtml}',
        );
      }
    }

    for (var run = 0; run < 1500; run++) {
      final fragment = html.parseFragment(_fragment(random, 0));
      for (final root in fragment.children) {
        for (final element in _descendants(root)) {
          probe(
            'todo',
            () => cookedTodoWidgetBuilder(
              element,
              style: null,
              contentBuilder: (html, style) => const SizedBox.shrink(),
            ),
            element,
          );
          probe(
            'spoiler',
            () => cookedSpoilerWidgetBuilder(element, contentBuilder: _nested),
            element,
          );
          probe(
            'inlineVideo',
            () => inlineVideoWidgetBuilder(element, siteUrl: site),
            element,
          );
          probe(
            'youtubeVideo',
            () => youtubeVideoWidgetBuilder(element, siteUrl: site),
            element,
          );
          probe(
            'details',
            () => cookedDetailsWidgetBuilder(element, contentBuilder: _nested),
            element,
          );
          probe(
            'table',
            () => cookedTableWidgetBuilder(element, cellBuilder: _nested),
            element,
          );
          probe(
            'onebox',
            () => oneboxWidgetBuilder(element, siteUrl: site),
            element,
          );
          probe(
            'onebox forumTheme',
            () => forumThemeOneboxWidgetBuilder(element, siteUrl: site),
            element,
          );
          probe(
            'onebox audio',
            () => audioOneboxWidgetBuilder(element, siteUrl: site),
            element,
          );
          probe(
            'onebox reddit',
            () => redditOneboxWidgetBuilder(element, siteUrl: site),
            element,
          );
          probe(
            'onebox embedded ${element.localName}',
            () => embeddedOneboxWidgetBuilder(element, siteUrl: site),
            element,
          );
          // Engines are only handed an onebox aside, as the dispatchers do.
          if (element.localName == 'aside' &&
              element.classes.contains('onebox')) {
            for (final MapEntry(key: name, value: engine)
                in _oneboxEngines.entries) {
              if (!engine.matches(element)) continue;
              probe(
                'onebox $name',
                () => engine.build(element, OneboxData.from(element), site),
                element,
              );
            }
            for (final MapEntry(key: name, value: engine)
                in _githubOneboxEngines.entries) {
              if (!engine.matches(element)) continue;
              probe(
                'onebox $name',
                () =>
                    engine.build(element, OneboxData.from(element), site, null),
                element,
              );
            }
          }
          probe(
            'quote',
            () => quoteWidgetBuilder(element, siteUrl: site),
            element,
          );
          probe(
            'chatTranscript',
            () => chatTranscriptWidgetBuilder(element, siteUrl: site),
            element,
          );
          probe(
            'imageGrid',
            () => imageGridWidgetBuilder(element, siteUrl: site),
            element,
          );
          probe(
            'lightbox',
            () => lightboxWidgetBuilder(element, siteUrl: site),
            element,
          );
          probe('codeBlock', () => codeBlockWidgetBuilder(element), element);
          probe(
            'inlineCode',
            () => inlineCodeWidgetBuilder(element, null),
            element,
          );
          probe(
            'mention',
            () => mentionWidgetBuilder(element, null, siteUrl: site),
            element,
          );
          probe(
            'hashtag',
            () => hashtagWidgetBuilder(element, null, siteUrl: site),
            element,
          );
          probe(
            'emoji',
            () => emojiWidgetBuilder(element, site, null),
            element,
          );
          probe(
            'localDate',
            () => localDateWidgetBuilder(
              element,
              siteUrl: site,
              formatter: localDateFormatter,
            ),
            element,
          );
        }
      }
    }

    expect(failures.values, isEmpty);
    // A guard that stops matching would leave its parser untested while the
    // test still passed, so the generated corpus has to keep reaching all of
    // them. The seed is fixed, so these counts are not a race.
    expect(
      built.keys,
      unorderedEquals([
        ..._builders,
        for (final name in _oneboxEngines.keys) 'onebox $name',
        for (final name in _githubOneboxEngines.keys) 'onebox $name',
      ]),
    );
  });
  // The probes are a second list of what `CookedHtml` and the onebox
  // dispatchers call, and a second copy drifts: a builder added to one of
  // those chains would go unprobed, with the test above still green.
  test('every builder the cooked-markup chains call is probed', () {
    final probed = {
      for (final match in _builderCall.allMatches(
        File('test/cooked_markup_totality_test.dart').readAsStringSync(),
      ))
        match.group(1)!,
      ..._oneboxEngines.keys,
      ..._githubOneboxEngines.keys,
    };
    final called = <String>{};
    for (final path in const [
      'lib/src/shell/cooked_html.dart',
      'lib/src/shell/oneboxes/onebox.dart',
      'lib/src/plugins/discourse_github/discourse_github_plugin.dart',
    ]) {
      final source = File(path).readAsStringSync();
      called.addAll(_builderCall.allMatches(source).map((m) => m.group(1)!));
      for (final list in RegExp(
        r'_engines = \[([^\]]*)\]',
      ).allMatches(source)) {
        called.addAll(
          RegExp(r'\w+').allMatches(list.group(1)!).map((m) => m.group(0)!),
        );
      }
    }
    // The scan reads source text, so one that stopped matching would pass
    // while checking nothing.
    expect(called.length, greaterThan(20));
    expect(
      called.difference(probed),
      isEmpty,
      reason: 'give these a skeleton the corpus reaches, and probe them above',
    );
  });
  // A builder that answers null has declined; a builder that answers a widget
  // has promised one that draws. Those are different claims, and only the
  // first was being made here — the corpus never reached a frame, so nothing
  // said the widget a half-written onebox produces survives being laid out and
  // painted. Two widths, because the narrow one is where a fixed-size lead
  // image or a row of pills has nowhere to go.
  testWidgets('generated cooked fragments lay out at wide and narrow widths', (
    tester,
  ) async {
    final random = Random(20260823);
    const site = 'https://example.com';
    final failures = <String, Object>{};
    final drawn = <String>{};
    final current = ValueNotifier<({String html, int round, double width})>((
      html: '',
      round: -1,
      width: 600,
    ));
    addTearDown(current.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder(
              valueListenable: current,
              builder: (context, value, child) => SizedBox(
                width: value.width,
                child: value.html.isEmpty
                    ? const SizedBox.shrink()
                    : KeyedSubtree(
                        // Keep each generated post independent while retaining
                        // the identical shell around the whole corpus.
                        key: ValueKey(value.round),
                        child: CookedHtml(html: value.html, siteUrl: site),
                      ),
              ),
            ),
          ),
        ),
      ),
    );

    for (var round = 0; round < 600; round++) {
      final html = _fragment(random, 0);
      if (html.isEmpty) continue;
      current.value = (
        html: html,
        round: round,
        width: round.isEven ? 600 : 200,
      );
      await tester.pump();
      Object? thrown = tester.takeException();
      if (thrown == null) {
        // Artwork arrives asynchronously; the frame it lands on is another
        // chance to throw.
        await tester.pump(const Duration(milliseconds: 16));
        thrown = tester.takeException();
      }
      if (thrown != null) failures[html] = thrown;
      drawn.addAll(tester.allWidgets.map((widget) => '${widget.runtimeType}'));
    }

    await tester.pumpWidget(const SizedBox.shrink());
    tester.takeException();
    expect(failures, isEmpty);
    // Reaching a builder above says nothing about this shorter corpus drawing
    // what it answers with, and a layout never drawn is never checked.
    expect(drawn, containsAll(_drawn));
  });
}
