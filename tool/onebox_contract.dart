/// Checks the onebox markup contract against discourse/discourse.
///
/// `lib/src/shell/onebox.dart` renders oneboxes natively, which means it
/// depends on the shape of the HTML Discourse emits — `aside.onebox`, the
/// `header.source` / `article.onebox-body` envelope, `img.site-icon`,
/// `img.thumbnail`. None of that is versioned or announced, so this fetches the
/// upstream sources and diffs them against the copies under
/// `tool/onebox_snapshot/`.
///
/// It is a drift detector, not a source of styling: Discourse's SCSS cannot be
/// applied by the HTML renderer this app uses. When it fails, read the diff and
/// decide whether the parser needs to change.
///
///   dart run tool/onebox_contract.dart            # check, exit 1 on drift
///   dart run tool/onebox_contract.dart --update   # accept upstream as current
library;

import 'dart:convert';
import 'dart:io';

/// Upstream paths that describe the markup the parser reads.
const List<String> watched = [
  // The envelope shared by every onebox engine.
  'lib/onebox/templates/_layout.mustache',
  // The engine behind the overwhelming majority of oneboxes.
  'lib/onebox/templates/allowlistedgeneric.mustache',
  // A representative engine with its own body shape (avatar, no thumbnail).
  'lib/onebox/templates/twitterstatus.mustache',
  // The `<pre><code><ol class="lines">` shape CodeBlock reads.
  'lib/onebox/templates/githubblob.mustache',
  // Where the class names the parser matches on are given meaning.
  'app/assets/stylesheets/common/base/onebox.scss',
  // Post-processing that rewrites onebox markup after the template runs.
  'lib/cooked_processor_mixin.rb',
];

const String branch = 'main';
const String rawBase = 'https://raw.githubusercontent.com/discourse/discourse';

final Directory snapshotDir = Directory('tool/onebox_snapshot');

Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

Future<int> _run(List<String> args) async {
  final update = args.contains('--update');
  final client = HttpClient();
  final drifted = <String>[];

  try {
    for (final path in watched) {
      final upstream = await _fetch(client, path);
      if (upstream == null) {
        stderr.writeln('could not fetch $path — is it still at that path?');
        return 2;
      }

      final local = File('${snapshotDir.path}/${_flatten(path)}');
      final current = local.existsSync() ? local.readAsStringSync() : null;
      if (current == upstream) continue;

      drifted.add(path);
      if (update) {
        local.parent.createSync(recursive: true);
        local.writeAsStringSync(upstream);
      }
    }
  } finally {
    client.close();
  }

  if (drifted.isEmpty) {
    stdout.writeln('onebox contract unchanged (${watched.length} files)');
    return 0;
  }

  if (update) {
    stdout.writeln('updated snapshot:');
    for (final path in drifted) {
      stdout.writeln('  $path');
    }
    stdout.writeln(
      '\nReview `git diff tool/onebox_snapshot` before committing.',
    );
    return 0;
  }

  stderr.writeln('onebox markup changed upstream:');
  for (final path in drifted) {
    stderr.writeln('  $branch/$path');
  }
  stderr.writeln(
    '\nCheck whether lib/src/shell/onebox.dart still parses it, then run:\n'
    '  dart run tool/onebox_contract.dart --update',
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
