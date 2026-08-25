/// Checks the markup contracts against discourse/discourse.
///
/// Several things here are drawn natively from Discourse's cooked HTML rather
/// than from its stylesheet, which means they depend on the exact shape of the
/// markup it emits. None of that is versioned or announced, so this fetches
/// the upstream sources and diffs them against the copies under
/// `tool/*_snapshot/`.
///
/// It is a drift detector, not a source of styling: Discourse's SCSS cannot be
/// applied by the HTML renderer this app uses. When it fails, read the diff and
/// decide whether a parser needs to change.
///
///   dart run tool/markup_contract.dart            # check, exit 1 on drift
///   dart run tool/markup_contract.dart --update   # accept upstream as current
library;

import 'dart:convert';
import 'dart:io';

/// One thing whose markup we copy, and where to look when it moves.
class Contract {
  const Contract({
    required this.name,
    required this.snapshot,
    required this.readers,
    required this.watched,
  });

  final String name;

  /// Where the copies live.
  final String snapshot;

  /// What to re-read when this drifts. Named per contract, because "check
  /// whether the onebox parsers still handle it" is wrong advice for a
  /// hashtag.
  final String readers;

  /// Upstream paths that describe the markup those readers read.
  final List<String> watched;
}

const List<Contract> contracts = [
  Contract(
    name: 'onebox',
    snapshot: 'tool/onebox_snapshot',
    readers: 'lib/src/shell/oneboxes/',
    watched: oneboxWatched,
  ),
  Contract(
    name: 'hashtag',
    snapshot: 'tool/hashtag_snapshot',
    readers: 'lib/src/shell/hashtag.dart and lib/src/shell/mention.dart',
    watched: hashtagWatched,
  ),
  Contract(
    name: 'poll',
    snapshot: 'tool/poll_snapshot',
    readers: 'lib/src/plugins/poll/ and lib/src/shell/cooked_html.dart',
    watched: pollWatched,
  ),
  Contract(
    name: 'local-dates',
    snapshot: 'tool/local_dates_snapshot',
    readers: 'lib/src/plugins/local_dates/ and lib/src/shell/cooked_html.dart',
    watched: localDatesWatched,
  ),
];

/// The BBCode generator, Markdown cooker, cooked behavior transformer, and
/// formatter whose source/dataset contracts the native codec mirrors.
const List<String> localDatesWatched = [
  'plugins/discourse-local-dates/assets/javascripts/lib/'
      'local-date-markup-generator.js',
  'plugins/discourse-local-dates/assets/javascripts/lib/discourse-markdown/'
      'discourse-local-dates.js',
  'plugins/discourse-local-dates/assets/javascripts/initializers/'
      'discourse-local-dates.js',
  'plugins/discourse-local-dates/assets/javascripts/lib/'
      'local-date-builder.js',
];

/// The server-cooked poll skeleton and the web client code that claims it by
/// `data-poll-name` and replaces it with the personalised poll from post JSON.
///
/// The native client deliberately depends on the same seam: the Markdown
/// plugin supplies only title/option fallback markup, while `post.polls` is
/// matched by name rather than by the poll's position in the document.
const List<String> pollWatched = [
  // Writes `.poll`, `data-poll-name`, title/options, option digests, and the
  // non-authoritative zero-voter skeleton that native rendering must ignore.
  'plugins/poll/assets/javascripts/lib/discourse-markdown/poll.js',
  // Finds outer cooked polls, excludes blockquotes, looks up structured polls
  // by `dataset.pollName`, and replaces matched skeletons with the live UI.
  'plugins/poll/assets/javascripts/discourse/initializers/extend-for-poll.gjs',
];

/// The `a.hashtag-cooked` and `a.mention` markup, the `@mixin mention` that
/// gives it its shape, and the endpoints the composer completes against.
///
/// Worth watching closely for one reason in particular: the `<svg>` inside a
/// cooked hashtag is a *placeholder* — always `square-full`, whatever the type
/// — which the web client replaces at runtime from the `data-` attributes.
/// `hashtag.dart` reads the attributes and ignores the svg, and would draw a
/// filled square on every tag on the site if that ever stopped being true.
const List<String> hashtagWatched = [
  // Where the cooked anchor and its `data-` attributes are written, and the
  // allow-list that decides which of them survive sanitising.
  'frontend/discourse-markdown-it/src/features/hashtag-autocomplete.js',
  'frontend/discourse-markdown-it/src/features/mentions.js',
  // The pattern that decides what a mention *is*, which the one in
  // `markdown_highlight.dart` is transcribed from. Its tail is the part that
  // matters: a name may not end in a dot, a dash or an underscore, so
  // `thanks @sam.` mentions `sam` and not `sam.`.
  'frontend/pretty-text/addon/mentions.js',
  // Which tokens Discourse's own post-processing rules — mentions, hashtags
  // and emoji — are run over, which is what decides that a backslash does not
  // stop any of them: `textReplace` visits `text` tokens of the *finished*
  // inline pass, by which point `\@sam` is the text `@sam`. `_escapes` in
  // `markdown_highlight.dart` binds only the rules above that one.
  'frontend/pretty-text/addon/text-replace.js',
  'frontend/discourse-markdown-it/src/features/text-post-process.js',
  // The third thing that rides `textPostProcess`, and the only one whose
  // matcher is a trie walk rather than a pattern: `getEmojiName` bounds the
  // name and refuses a shortcode whose opening colon has an ordinary
  // character before it, which is what keeps `10:30:45` from holding one.
  'frontend/discourse-markdown-it/src/features/emoji.js',
  // What turns a `span.mention` into an anchor, and what an unresolved one
  // stays as.
  'lib/pretty_text.rb',
  // The shape of a hashtag item: ref vs slug, the colours array, style_type.
  'app/services/hashtag_autocomplete_service.rb',
  'app/services/category_hashtag_data_source.rb',
  'app/services/tag_hashtag_data_source.rb',
  // The endpoints the composer asks, including the required `order` param.
  'app/controllers/hashtags_controller.rb',
  // Where the pill gets its shape, and the two stylesheets that apply it.
  'app/assets/stylesheets/common/foundation/mixins.scss',
  'app/assets/stylesheets/common/components/hashtag.scss',
];

/// Upstream paths that describe the markup the onebox parsers read.
const List<String> oneboxWatched = [
  // The envelope shared by every onebox engine.
  'lib/onebox/templates/_layout.mustache',
  // The engine behind the overwhelming majority of oneboxes.
  'lib/onebox/templates/allowlistedgeneric.mustache',
  // A representative engine with its own body shape (avatar, no thumbnail).
  'lib/onebox/templates/twitterstatus.mustache',
  // The `<pre><code><ol class="lines">` shape CodeBlock reads.
  'lib/onebox/templates/githubblob.mustache',
  // The GitHub engines with native bodies under oneboxes/github/.
  'lib/onebox/templates/githubissue.mustache',
  'lib/onebox/templates/githubpullrequest.mustache',
  'lib/onebox/templates/githubcommit.mustache',
  'lib/onebox/templates/github/github_body.mustache',
  // The internal oneboxes under oneboxes/discourse/ — a topic elsewhere,
  // and a same-site topic (rendered as a quote), user, and category.
  'lib/onebox/templates/discoursetopic.mustache',
  'lib/onebox/templates/discourse_topic_onebox.mustache',
  'lib/onebox/templates/discourse_user_onebox.mustache',
  'lib/onebox/templates/discourse_category_onebox.mustache',
  // The `--gh-status-*` classes and their colors, read by the pull request
  // oneboxes and their inline variants.
  'plugins/discourse-github/assets/stylesheets/common/github-pr-status.scss',
  // Core's direct iframe fallback and the default lazy-video replacement are
  // both parsed by youtube_video.dart. The component files define the data
  // attributes, time conversion and iframe parameters mirrored natively.
  'lib/onebox/engine/youtube_onebox.rb',
  'plugins/discourse-lazy-videos/lib/discourse_lazy_videos/lazy_youtube.rb',
  'plugins/discourse-lazy-videos/assets/javascripts/lib/'
      'lazy-video-attributes.js',
  'plugins/discourse-lazy-videos/assets/javascripts/discourse/components/'
      'lazy-video.gjs',
  'plugins/discourse-lazy-videos/assets/javascripts/discourse/components/'
      'lazy-iframe.gjs',
  'plugins/discourse-lazy-videos/assets/stylesheets/lazy-videos.scss',
  // Chat wraps the same top-level lazy container in a collapser on the web.
  // Native intentionally recognises the same marker but keeps it full-width.
  'plugins/chat/assets/javascripts/discourse/components/'
      'chat-message-collapser.gjs',
  // Where the class names the parsers match on are given meaning.
  'app/assets/stylesheets/common/base/onebox.scss',
  // Post-processing that rewrites onebox markup after the template runs,
  // including the resolution of `a.inline-onebox-loading` anchors.
  'lib/cooked_processor_mixin.rb',
  // What an inline onebox lookup returns — title, and css_class for engines
  // that advertise one.
  'lib/inline_oneboxer.rb',
  // Which markup the internal handlers emit for local links.
  'lib/oneboxer.rb',
];

const String branch = 'main';
const String rawBase = 'https://raw.githubusercontent.com/discourse/discourse';

Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

Future<int> _run(List<String> args) async {
  final update = args.contains('--update');
  final client = HttpClient();

  var worst = 0;
  try {
    for (final contract in contracts) {
      final result = await _check(client, contract, update: update);
      // A path that has moved (2) beats drift (1): the check could not be run
      // at all, and reporting "no drift" for the rest would be a lie.
      if (result > worst) worst = result;
    }
  } finally {
    client.close();
  }
  return worst;
}

Future<int> _check(
  HttpClient client,
  Contract contract, {
  required bool update,
}) async {
  final drifted = <String>[];

  for (final path in contract.watched) {
    final upstream = await _fetch(client, path);
    if (upstream == null) {
      stderr.writeln(
        'could not fetch $path — is it still at that path?\n'
        'Upstream moves files: the JS lives under frontend/ now.',
      );
      return 2;
    }

    final local = File('${contract.snapshot}/${_flatten(path)}');
    final current = local.existsSync() ? local.readAsStringSync() : null;
    if (current == upstream) continue;

    drifted.add(path);
    if (update) {
      local.parent.createSync(recursive: true);
      local.writeAsStringSync(upstream);
    }
  }

  if (drifted.isEmpty) {
    stdout.writeln(
      '${contract.name} contract unchanged '
      '(${contract.watched.length} files)',
    );
    return 0;
  }

  if (update) {
    stdout.writeln('updated ${contract.name} snapshot:');
    for (final path in drifted) {
      stdout.writeln('  $path');
    }
    stdout.writeln(
      '\nReview `git diff ${contract.snapshot}` before '
      'committing.',
    );
    return 0;
  }

  stderr.writeln('${contract.name} markup changed upstream:');
  for (final path in drifted) {
    stderr.writeln('  $branch/$path');
  }
  stderr.writeln(
    '\nCheck whether ${contract.readers} still reads it, then run:\n'
    '  dart run tool/markup_contract.dart --update',
  );
  return 1;
}

Future<String?> _fetch(HttpClient client, String path) async {
  final request = await client.getUrl(Uri.parse('$rawBase/$branch/$path'));
  final response = await request.close();
  if (response.statusCode != 200) {
    await response.drain<void>();
    return null;
  }
  return response.transform(utf8.decoder).join();
}

/// Upstream paths become flat filenames so the snapshot stays one directory.
String _flatten(String path) => path.replaceAll('/', '__');
