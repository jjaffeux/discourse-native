import 'package:flutter/widgets.dart';

import '../../plugin_api/plugin_registry.dart';
import '../../plugins/discourse_github/discourse_github_plugin.dart';
import '../../plugins/discourse_github/oneboxes/github.dart';
import '../../plugins/discourse_lazy_videos/discourse_lazy_videos_plugin.dart';
import '../../plugins/local_dates/local_date.dart';
import '../../plugins/local_dates/local_date_environment.dart';
import '../../plugins/local_dates/local_dates_cooked_time_parser.dart';
import '../../shell/cooked_html.dart';
import 'onebox_event_sample.dart';

@immutable
class OneboxSample {
  const OneboxSample({
    required this.id,
    required this.name,
    required this.description,
    required this.keywords,
    required this.states,
  });

  final String id;
  final String name;
  final String description;
  final String keywords;
  final List<OneboxSampleState> states;
}

@immutable
class OneboxSampleState {
  const OneboxSampleState(this.label, this.builder);

  final String label;
  final WidgetBuilder builder;
}

const _site = 'https://meta.discourse.org';
const _github = 'https://github.com/discourse/discourse';
const _prUrl = '$_github/pull/30604';
const _photo =
    'https://flutter.github.io/assets-for-api-docs/assets/widgets/owl.jpg';
const _avatar = 'https://avatars.githubusercontent.com/u/3220138?s=120';
const _video =
    'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';
const _redditPost =
    'https://embed.reddit.com/r/FlutterDev/comments/w8ssuy/airdash_new_free_and_open_source_flutter_app_for';

final _registry = PluginRegistry([
  DiscourseGithubPlugin(
    cookedTimeParser: LocalDatesCookedTimeParser(
      formatter: LocalDateFormatter(environment: LocalDateEnvironment.instance),
    ),
  ),
  const DiscourseLazyVideosPlugin(),
]);

OneboxSampleState _cooked(String label, String html) => OneboxSampleState(
  label,
  (_) => CookedHtml(
    html: html,
    siteUrl: _site,
    registry: _registry,
    buildAsync: false,
  ),
);

/// Samples follow the markup contracts consumed by CookedHtml and its plugins.
/// Keep provider-specific variations here so the gallery and its coverage use
/// the same inventory. Providers without a dedicated renderer use Generic link.
final oneboxSamples = <OneboxSample>[
  OneboxSample(
    id: 'generic',
    name: 'Generic link',
    description:
        'The shared card used by providers without a dedicated renderer.',
    keywords: 'web website article fallback unknown provider open graph',
    states: [
      _cooked('Text', _generic()),
      _cooked('Thumbnail', _generic(thumbnail: true)),
      _cooked('Long content', _generic(long: true)),
      _cooked(
        'Minimal',
        _box(
          'allowlistedgeneric',
          'https://www.discourse.org',
          '<h3><a href="https://www.discourse.org">Discourse</a></h3>',
        ),
      ),
    ],
  ),
  OneboxSample(
    id: 'discourse-topic',
    name: 'Discourse topic',
    description:
        'A topic from another Discourse site, with categories and tags.',
    keywords: 'forum external topic discussion category tags',
    states: [
      _cooked('With metadata', _topic()),
      _cooked('Thumbnail', _topic(thumbnail: true)),
      _cooked('Long excerpt', _topic(long: true)),
      _cooked('Minimal', _topic(minimal: true)),
    ],
  ),
  OneboxSample(
    id: 'discourse-local-topic',
    name: 'Discourse local topic',
    description: 'A same-site topic link renders as a quote of its first post.',
    keywords: 'forum internal same site quote first post',
    states: [
      _cooked('Excerpt', _localTopic()),
      _cooked('Formatted content', _localTopic(formatted: true)),
    ],
  ),
  OneboxSample(
    id: 'discourse-user',
    name: 'Discourse user',
    description: 'A profile with a biography, location, website and join date.',
    keywords: 'forum profile user member avatar biography',
    states: [
      _cooked('Profile', _user()),
      _cooked('Avatar', _user(avatar: true)),
      _cooked('Long biography', _user(long: true)),
      _cooked('Minimal', _user(minimal: true)),
    ],
  ),
  OneboxSample(
    id: 'discourse-category',
    name: 'Discourse category',
    description:
        'A category summary with its color and optional subcategories.',
    keywords: 'forum category subcategories description',
    states: [
      _cooked('Subcategories', _category()),
      _cooked('Description only', _category(children: false)),
      _cooked('Minimal', _category(children: false, minimal: true)),
    ],
  ),
  OneboxSample(
    id: 'github-pr',
    name: 'GitHub pull request',
    description:
        'Pull request status, branches, author, changes and linked comments.',
    keywords:
        'github pr pull request draft open approved review merged closed commit comment discussion',
    states: [
      for (final status in GithubPrStatus.values)
        _cooked(_statusLabel(status), _pullRequest(status)),
      for (final kind in ['Comment', 'Commit', 'Discussion'])
        _cooked(kind, _pullRequestLink(kind)),
    ],
  ),
  OneboxSample(
    id: 'github-issue',
    name: 'GitHub issue',
    description: 'Issue dates, author, labels and description.',
    keywords: 'github bug issue open closed labels',
    states: [
      _cooked('Open', _issue()),
      _cooked('Closed', _issue(closed: true)),
      _cooked('Minimal', _issue(minimal: true)),
    ],
  ),
  OneboxSample(
    id: 'github-commit',
    name: 'GitHub commit',
    description: 'Commit message, author and addition/deletion counts.',
    keywords: 'github git commit diff additions deletions',
    states: [
      _cooked('Summary', _commit()),
      _cooked('With body', _commit(body: true)),
      _cooked('Minimal', _commit(minimal: true)),
    ],
  ),
  OneboxSample(
    id: 'github-file',
    name: 'GitHub file',
    description:
        'The generic onebox card with the native numbered code renderer.',
    keywords: 'github blob file code source snippet lines',
    states: [_cooked('Code', _file()), _cooked('Line range', _file(start: 42))],
  ),
  OneboxSample(
    id: 'reddit',
    name: 'Reddit',
    description:
        'Live post and comment embeds, with loading, retry and open-link controls. Requires a network connection.',
    keywords: 'reddit social post comment iframe embed subreddit',
    states: [
      _cooked(
        'Post',
        '<iframe class="reddit-onebox" src="$_redditPost/?embed=true&amp;ref_source=embed&amp;ref=share" height="500"></iframe>',
      ),
      _cooked(
        'Comment',
        '<iframe class="reddit-onebox" src="$_redditPost/ihrafxr/?embed=true&amp;ref_source=embed&amp;ref=share&amp;showmedia=false&amp;showmore=false&amp;depth=1&amp;context=1" height="300"></iframe>',
      ),
    ],
  ),
  OneboxSample(
    id: 'twitter',
    name: 'Twitter / X',
    description:
        'The generic card recognizes the provider’s avatar-style thumbnail.',
    keywords: 'twitter x social tweet status avatar fallback',
    states: [
      _cooked('Text', _twitter()),
      _cooked('Avatar', _twitter(avatar: true)),
    ],
  ),
  OneboxSample(
    id: 'inline',
    name: 'Inline link',
    description: 'Resolved titles stay inline with the surrounding paragraph.',
    keywords: 'inline link title resolved loading unavailable fallback',
    states: [
      _cooked(
        'Resolved',
        '<p>Read <a class="inline-onebox" href="https://www.discourse.org">Discourse: a place for your community</a> and join the discussion.</p>',
      ),
      _cooked(
        'Long title',
        '<p>Read <a class="inline-onebox" href="https://www.discourse.org">Building a welcoming community with thoughtful conversations, useful resources and space for everyone</a> before posting.</p>',
      ),
      _cooked(
        'Loading',
        '<p><a class="inline-onebox-loading" href="https://www.discourse.org">https://www.discourse.org</a></p>',
      ),
      _cooked(
        'Unavailable',
        '<p><a class="onebox" href="https://www.discourse.org">https://www.discourse.org</a></p>',
      ),
    ],
  ),
  OneboxSample(
    id: 'github-pr-inline',
    name: 'GitHub pull request (inline)',
    description:
        'The title wraps naturally while a status glyph prefixes the link.',
    keywords: 'github inline pr pull request status glyph',
    states: [
      for (final status in GithubPrStatus.values)
        _cooked(
          _statusLabel(status),
          '<p>See <a class="inline-onebox --gh-status-${_statusClass(status)}" href="$_prUrl">Improve the native topic reader (#30604)</a> for the latest changes.</p>',
        ),
    ],
  ),
  OneboxSample(
    id: 'youtube',
    name: 'YouTube',
    description:
        'Lazy video and legacy iframe markup share the native player. Press Play to load it.',
    keywords: 'youtube video media lazy iframe embed playlist timestamp',
    states: [
      _cooked('Video', _youtube()),
      _cooked('Start time', _youtube(start: 42)),
      _cooked(
        'Legacy iframe',
        '<iframe class="youtube-onebox" src="https://www.youtube.com/embed/aqz-KE-bpKQ"></iframe>',
      ),
      _cooked(
        'Playlist',
        '<iframe class="youtube-onebox" src="https://www.youtube.com/embed/videoseries?list=PL4cUxeGkcC9jLYyp2Aoh6hcWuxFDX6PBJ"></iframe>',
      ),
    ],
  ),
  OneboxSample(
    id: 'video',
    name: 'Uploaded video',
    description:
        'Video oneboxes share the native poster, playback and download controls.',
    keywords: 'uploaded video mp4 media poster thumbnail playback',
    states: [
      _cooked('No poster', _uploadedVideo()),
      _cooked('Poster', _uploadedVideo(poster: true)),
      _cooked(
        'Video element',
        '<div class="onebox video-onebox"><video controls width="640" height="360" title="A bee on a flower"><source src="$_video" type="video/mp4"></video></div>',
      ),
    ],
  ),
  OneboxSample(
    id: 'event',
    name: 'Discourse event',
    description:
        'The event card used by hydrated event topic oneboxes, with local attendance controls.',
    keywords: 'discourse event calendar rsvp attendance pending error closed',
    states: [
      for (final state in OneboxEventState.values)
        OneboxSampleState(state.label, (_) => OneboxEventSample(state: state)),
    ],
  ),
];

String _box(String classes, String url, String body, {String? siteName}) =>
    '''
<aside class="onebox $classes" data-onebox-src="$url">
  ${siteName == null ? '' : '<header class="source"><a href="$url">$siteName</a></header>'}
  <article class="onebox-body">$body</article>
</aside>''';

String _generic({bool thumbnail = false, bool long = false}) => _box(
  'allowlistedgeneric',
  'https://www.discourse.org',
  '''${thumbnail ? '<img class="thumbnail" src="$_photo" width="240" height="120">' : ''}
<h3><a href="https://www.discourse.org">${long ? 'Build a welcoming home for every conversation in your community' : 'A home for your community'}</a></h3>
<p>Discourse brings people together through meaningful conversations.${long ? ' Share ideas, ask questions, discover useful resources and keep the conversation going. ' * 4 : ''}</p>''',
  siteName: 'discourse.org',
);

String _topic({
  bool thumbnail = false,
  bool long = false,
  bool minimal = false,
}) => _box(
  'discoursetopic',
  '$_site/t/welcome-to-discourse/1',
  '''${thumbnail ? '<img class="thumbnail" src="$_photo" width="240" height="120">' : ''}
<h3><a href="$_site/t/welcome-to-discourse/1">Welcome to Discourse</a></h3>
${minimal ? '' : '''<div class="topic-category"><span class="badge-wrapper"><span class="badge-category-bg" style="background-color: #0088CC"></span><span class="category-name">Community</span></span><div class="discourse-tags"><span class="discourse-tag">native</span><span class="discourse-tag">design</span></div></div>
<p>A place to introduce yourself, ask questions and share what you are building.${long ? ' We are exploring new ways to make conversations feel at home on every device.' * 10 : ''}</p>'''}''',
  siteName: 'Discourse Meta',
);

String _localTopic({bool formatted = false}) =>
    '''
<aside class="quote" data-post="1" data-topic="1">
  <div class="title"><div class="quote-title__text-content"><a href="$_site/t/welcome-to-discourse/1">Welcome to Discourse</a></div></div>
  <blockquote><p>Welcome to our community. This is the first post in the topic.</p>${formatted ? '<p>Start with <strong>a quick introduction</strong>, then:</p><ul><li>Read the guidelines.</li><li>Share what you are building.</li></ul>' : ''}</blockquote>
</aside>''';

String _user({bool avatar = false, bool long = false, bool minimal = false}) =>
    '''
<aside class="onebox" data-onebox-src="$_site/u/community">
  <article class="onebox-body user-onebox">
    ${avatar ? '<img class="avatar" src="$_avatar" width="120" height="120">' : ''}
    <h3><a href="$_site/u/community">@community</a></h3>
    ${minimal ? '' : '''<div><span class="full-name">Community Builder</span><span class="location"><svg class="d-icon-location-dot"></svg>Paris, France</span><span><svg class="d-icon-earth-americas"></svg><a href="https://www.discourse.org">discourse.org</a></span></div>
    <p>Helping people find their place in the conversation.${long ? ' I enjoy welcoming new members, sharing ideas and making software easier to use.' * 8 : ''}</p>
    <div class="user-onebox--joined">Joined community on 1 January 2020</div>'''}
  </article>
</aside>''';

String _category({bool children = true, bool minimal = false}) =>
    '''
<aside class="onebox category-onebox" style="box-shadow: -5px 0px #0088CC" data-onebox-src="$_site/c/feature/2">
  <article class="onebox-body category-onebox-body">
    <h3><a href="$_site/c/feature/2"><span class="badge-category__name">Feature</span></a></h3>
    ${minimal ? '' : '<div class="description"><p>Ideas and suggestions for the next version of Discourse.</p></div>'}
    ${children ? '<div class="subcategories"><span class="subcategory"><span class="badge-category-bg" style="background-color: #BF3B7B"></span><span class="category-name">Design</span></span><span class="subcategory"><span class="badge-category-bg" style="background-color: #00AA66"></span><span class="category-name">Documentation</span></span></div>' : ''}
  </article>
</aside>''';

String _statusClass(GithubPrStatus status) =>
    status == GithubPrStatus.changesRequested
    ? 'changes_requested'
    : status.name;

String _statusLabel(GithubPrStatus status) => switch (status) {
  GithubPrStatus.draft => 'Draft',
  GithubPrStatus.open => 'Open',
  GithubPrStatus.approved => 'Approved',
  GithubPrStatus.changesRequested => 'Changes requested',
  GithubPrStatus.merged => 'Merged',
  GithubPrStatus.closed => 'Closed',
};

String _date(String verb, {int day = 1}) =>
    '<div class="date">$verb <span class="discourse-local-date" data-date="2026-09-${day.toString().padLeft(2, '0')}" data-time="10:00:00" data-timezone="UTC">September $day, 2026</span></div>';
const _githubUser =
    '<div class="user"><a href="https://github.com/discourse">discourse</a></div>';
const _lines =
    '<div class="lines"><a href="$_prUrl/files"><span class="added">+123</span> <span class="removed">-45</span></a></div>';

String _pullRequest(GithubPrStatus status) => _box(
  'githubpullrequest',
  _prUrl,
  '''<div class="github-row --gh-status-${_statusClass(status)}">
  <div class="github-icon-container" title="Pull request"></div>
  <div class="github-info-container">
    <h4><a href="$_prUrl">Improve the native topic reader (#30604)</a></h4>
    <div class="branches"><code>main</code> ← <code>native-reader</code></div>
    <div class="github-info">${_date(switch (status) {
    GithubPrStatus.merged => 'Merged',
    GithubPrStatus.closed => 'Closed',
    _ => 'Opened',
  })}$_githubUser$_lines</div>
  </div>
</div><div class="github-row"><p class="github-body-container">Keep conversations readable and navigation close at hand.</p></div>''',
  siteName: 'github.com/discourse/discourse',
);

String _pullRequestLink(String kind) => _box(
  'githubpullrequest',
  '$_prUrl#issuecomment-1',
  '''<div class="github-row"><div class="github-icon-container" title="$kind"></div>
<div class="github-info-container"><h4><a href="$_prUrl#issuecomment-1">$kind on Improve the native topic reader</a></h4>
<div class="github-info">$kind by discourse</div></div></div>
<p class="github-body-container">The keyboard navigation looks good. Ready for another review.</p>''',
  siteName: 'github.com/discourse/discourse',
);

String _issue({bool closed = false, bool minimal = false}) => _box(
  'githubissue',
  '$_github/issues/12345',
  '''<div class="github-row"><div class="github-info-container">
<h4><a href="$_github/issues/12345">Keep the selected topic visible (#12345)</a></h4>
${minimal ? '' : '''<div class="github-info">${_date('Opened')}${closed ? _date('Closed', day: 12) : ''}$_githubUser</div>
<div class="labels"><span>bug</span><span>navigation</span></div>'''}
</div></div>${minimal ? '' : '<p class="github-body-container">The topic list should retain its scroll position when returning from a conversation.</p>'}''',
  siteName: 'github.com/discourse/discourse',
);

String _commit({bool body = false, bool minimal = false}) => _box(
  'githubcommit',
  '$_github/commit/9b6ee3f',
  '''<div class="github-row"><div class="github-info-container">
<h4><a href="$_github/commit/9b6ee3f">Improve keyboard navigation</a></h4>
${minimal ? '' : '<div class="github-info">${_date('Committed')}$_githubUser$_lines</div>'}
</div></div>${body ? '<p class="github-body-container">Restore focus to the selected topic after closing the reader.</p>' : ''}''',
  siteName: 'github.com/discourse/discourse',
);

String _file({int start = 1}) => _box(
  'githubblob',
  '$_github/blob/main/lib/example.rb',
  '''<h3><a href="$_github/blob/main/lib/example.rb">lib/example.rb</a></h3>
<pre class="onebox"><code class="lang-rb"><ol class="code" start="$start"><li>class Conversation</li><li>  def welcome(name)</li><li>    "Hello, #{name}!"</li><li>  end</li><li>end</li></ol></code></pre>''',
  siteName: 'github.com/discourse/discourse',
);

String _twitter({bool avatar = false}) => _box(
  'twitterstatus',
  'https://x.com/discourse',
  '''${avatar ? '<img class="onebox-avatar" src="$_avatar" width="120" height="120">' : ''}
<h3><a href="https://x.com/discourse">Discourse (@discourse)</a></h3>
<p>Good conversations deserve a place to grow. What is your community building today?</p>''',
  siteName: 'X / Twitter',
);

String _youtube({int start = 0}) =>
    '''
<div class="youtube-onebox lazy-video-container" data-provider-name="youtube"
  data-video-id="aqz-KE-bpKQ" data-video-title="Big Buck Bunny" data-video-start-time="$start">
  <a class="video-thumbnail" href="https://www.youtube.com/watch?v=aqz-KE-bpKQ&amp;t=${start}s">
    <img class="youtube-thumbnail" src="https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg">
  </a>
</div>''';

String _uploadedVideo({bool poster = false}) =>
    '''
<div class="video-placeholder-container" data-video-src="$_video"
  data-video-title="A bee on a flower" data-video-width="640" data-video-height="360"
  ${poster ? 'data-thumbnail-src="https://flutter.github.io/assets-for-api-docs/assets/widgets/owl.jpg"' : ''}></div>''';
