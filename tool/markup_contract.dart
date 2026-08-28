/// Checks the markup contracts against discourse/discourse.
///
/// Native renderers depend on exact shapes in Discourse's cooked HTML. None of
/// those shapes are versioned or announced, so this discovers owner-local
/// contract catalogs, fetches their upstream sources, and diffs them against
/// the snapshots declared by each owner.
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
final class MarkupContract {
  const MarkupContract({
    required this.name,
    required this.snapshot,
    required this.readers,
    required this.watched,
    required this.catalog,
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

  /// Owner-local declaration which supplied this contract.
  final String catalog;
}

const int markupContractCatalogSchemaVersion = 1;
const String _coreCatalogRoot = 'tool/markup_contracts';
const String _pluginRoot = 'lib/src/plugins';

/// Discovers core catalogs and optional feature catalogs without teaching the
/// runner any feature ids or upstream paths.
Future<List<MarkupContract>> loadMarkupContracts({
  Directory? repository,
}) async {
  final root = repository ?? Directory.current;
  final catalogs = <File>[];
  await _addCatalogsUnder(
    Directory.fromUri(root.uri.resolve('$_coreCatalogRoot/')),
    catalogs,
  );

  final plugins = Directory.fromUri(root.uri.resolve('$_pluginRoot/'));
  if (await plugins.exists()) {
    final owners = await plugins
        .list(followLinks: false)
        .where((entity) => entity is Directory)
        .cast<Directory>()
        .toList();
    owners.sort((left, right) => left.path.compareTo(right.path));
    for (final owner in owners) {
      final catalog = File.fromUri(
        owner.uri.resolve('tool/markup_contract.json'),
      );
      if (await catalog.exists()) catalogs.add(catalog);
    }
  }

  catalogs.sort((left, right) => left.path.compareTo(right.path));
  final contracts = <MarkupContract>[];
  final names = <String>{};
  final watched = <String>{};
  final snapshotTargets = <String>{};
  for (final catalog in catalogs) {
    for (final contract in await _readCatalog(root, catalog)) {
      if (!names.add(contract.name)) {
        throw FormatException(
          'duplicate markup contract name ${contract.name}',
          catalog.path,
        );
      }
      for (final path in contract.watched) {
        if (!watched.add(path)) {
          throw FormatException(
            'upstream path is claimed by more than one contract: $path',
            catalog.path,
          );
        }
        final snapshotTarget =
            '${contract.snapshot}${Platform.pathSeparator}${_flatten(path)}';
        if (!snapshotTargets.add(snapshotTarget)) {
          throw FormatException(
            'upstream paths flatten to the same snapshot file: $path',
            catalog.path,
          );
        }
      }
      contracts.add(contract);
    }
  }
  return List.unmodifiable(contracts);
}

Future<void> _addCatalogsUnder(Directory directory, List<File> output) async {
  if (!await directory.exists()) return;
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is File &&
        entity.uri.pathSegments.last == 'markup_contract.json') {
      output.add(entity);
    } else if (entity is Directory) {
      final catalog = File.fromUri(entity.uri.resolve('markup_contract.json'));
      if (await catalog.exists()) output.add(catalog);
    }
  }
}

Future<List<MarkupContract>> _readCatalog(
  Directory repository,
  File catalog,
) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(await catalog.readAsString());
  } on Object catch (error) {
    throw FormatException('could not decode catalog: $error', catalog.path);
  }
  if (decoded is! Map<String, Object?> ||
      decoded['schemaVersion'] != markupContractCatalogSchemaVersion ||
      decoded['contracts'] is! List<Object?>) {
    throw FormatException('invalid markup contract catalog', catalog.path);
  }

  final result = <MarkupContract>[];
  for (final entry in decoded['contracts']! as List<Object?>) {
    if (entry is! Map<String, Object?> ||
        entry['name'] is! String ||
        entry['snapshot'] is! String ||
        entry['readers'] is! String ||
        entry['watched'] is! List<Object?>) {
      throw FormatException('invalid markup contract entry', catalog.path);
    }
    final name = entry['name']! as String;
    final snapshot = entry['snapshot']! as String;
    final readers = entry['readers']! as String;
    final watched = entry['watched']! as List<Object?>;
    if (!_safeSegment(name) ||
        !_safeRelativePath(snapshot) ||
        readers.trim().isEmpty ||
        watched.isEmpty ||
        watched.any((path) => path is! String || !_safeRelativePath(path))) {
      throw FormatException('unsafe markup contract entry', catalog.path);
    }
    final snapshotDirectory = Directory.fromUri(
      catalog.parent.uri.resolve('$snapshot/'),
    );
    if (!await _within(repository, snapshotDirectory)) {
      throw FormatException(
        'snapshot must stay inside the repository',
        catalog.path,
      );
    }
    result.add(
      MarkupContract(
        name: name,
        snapshot: snapshotDirectory.path,
        readers: readers,
        watched: List.unmodifiable(watched.cast<String>()),
        catalog: _relativePath(repository, catalog),
      ),
    );
  }
  return result;
}

bool _safeSegment(String value) =>
    value.isNotEmpty && !value.contains('/') && !value.contains('\\');

bool _safeRelativePath(String value) =>
    value.isNotEmpty &&
    !value.startsWith('/') &&
    !value.contains('\\') &&
    !value.contains('%') &&
    !value.contains('?') &&
    !value.contains('#') &&
    !value.contains(':') &&
    !value
        .split('/')
        .any((part) => part.isEmpty || part == '.' || part == '..');

Future<bool> _within(Directory root, FileSystemEntity entity) async {
  try {
    final resolvedRoot = await root.resolveSymbolicLinks();
    var candidate = entity.absolute.path;
    while (true) {
      final type = await FileSystemEntity.type(candidate, followLinks: false);
      if (type != FileSystemEntityType.notFound) {
        final resolved = switch (type) {
          FileSystemEntityType.directory => await Directory(
            candidate,
          ).resolveSymbolicLinks(),
          FileSystemEntityType.file => await File(
            candidate,
          ).resolveSymbolicLinks(),
          FileSystemEntityType.link => await Link(
            candidate,
          ).resolveSymbolicLinks(),
          _ => candidate,
        };
        return _pathWithin(resolvedRoot, resolved);
      }
      final parent = File(candidate).parent.path;
      if (parent == candidate) return false;
      candidate = parent;
    }
  } on FileSystemException {
    return false;
  }
}

bool _pathWithin(String root, String candidate) {
  if (candidate == root) return true;
  final prefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  return candidate.startsWith(prefix);
}

String _relativePath(Directory root, FileSystemEntity entity) {
  final rootPath = root.absolute.path.endsWith(Platform.pathSeparator)
      ? root.absolute.path
      : '${root.absolute.path}${Platform.pathSeparator}';
  return entity.absolute.path.substring(rootPath.length);
}

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
    final contracts = await loadMarkupContracts();
    if (contracts.isEmpty) {
      stderr.writeln('no markup contract catalogs were found');
      return 2;
    }
    for (final contract in contracts) {
      final result = await _check(client, contract, update: update);
      // A path that has moved (2) beats drift (1): the check could not be run
      // at all, and reporting "no drift" for the rest would be a lie.
      if (result > worst) worst = result;
    }
  } on Object catch (error) {
    stderr.writeln('markup contracts could not be checked: $error');
    return 2;
  } finally {
    client.close();
  }
  return worst;
}

Future<int> _check(
  HttpClient client,
  MarkupContract contract, {
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
