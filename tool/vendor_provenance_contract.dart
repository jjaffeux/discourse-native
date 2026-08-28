/// Verifies owner-declared vendored packages against their published archives.
///
/// Each plugin keeps its package identity, vendor path, checksum, and reviewed
/// patch inventory beside its own source. This root runner knows only how to
/// validate that generic provenance contract.
///
///   dart run tool/vendor_provenance_contract.dart
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

const int vendorContractSchemaVersion = 1;
const String _pluginRoot = 'lib/src/plugins';
const int _tarBlockSize = 512;
const int _maximumMetadataBytes = 1024 * 1024;
const int _maximumArchiveBytes = 64 * 1024 * 1024;

final class VendorProvenanceContract {
  const VendorProvenanceContract({
    required this.name,
    required this.package,
    required this.version,
    required this.vendorPath,
    required this.patchManifest,
    required this.catalog,
  });

  final String name;
  final String package;
  final String version;
  final String vendorPath;
  final String patchManifest;
  final String catalog;

  Uri get metadataUri =>
      Uri.https('pub.dev', '/api/packages/$package/versions/$version');

  Uri get archiveUri =>
      Uri.https('pub.dev', '/api/archives/$package-$version.tar.gz');
}

enum VendorDifferenceKind { added, modified, removed }

final class VendorComparison {
  VendorComparison({
    required Map<String, VendorDifferenceKind> differences,
    required Iterable<String> undocumentedDifferences,
    required Iterable<String> documentedFilesWithoutDifference,
  }) : differences = Map.unmodifiable(differences),
       undocumentedDifferences = List.unmodifiable(undocumentedDifferences),
       documentedFilesWithoutDifference = List.unmodifiable(
         documentedFilesWithoutDifference,
       );

  final Map<String, VendorDifferenceKind> differences;
  final List<String> undocumentedDifferences;
  final List<String> documentedFilesWithoutDifference;

  bool get matchesDocumentedInventory =>
      undocumentedDifferences.isEmpty &&
      documentedFilesWithoutDifference.isEmpty;
}

Future<void> main() async {
  exitCode = await runVendorProvenanceContracts();
}

Future<List<VendorProvenanceContract>> loadVendorProvenanceContracts({
  Directory? repository,
}) async {
  final root = repository ?? Directory.current;
  final plugins = Directory.fromUri(root.uri.resolve('$_pluginRoot/'));
  if (!await plugins.exists()) return const [];

  final owners = await plugins
      .list(followLinks: false)
      .where((entity) => entity is Directory)
      .cast<Directory>()
      .toList();
  owners.sort((left, right) => left.path.compareTo(right.path));
  final contracts = <VendorProvenanceContract>[];
  final names = <String>{};
  final packages = <String>{};
  for (final owner in owners) {
    final catalog = File.fromUri(
      owner.uri.resolve('tool/vendor_contract.json'),
    );
    if (!await catalog.exists()) continue;
    final contract = await _readVendorContract(root, catalog);
    if (!names.add(contract.name)) {
      throw FormatException('duplicate vendor contract name', contract.name);
    }
    if (!packages.add(contract.package)) {
      throw FormatException(
        'more than one owner claims ${contract.package}',
        contract.catalog,
      );
    }
    contracts.add(contract);
  }
  return List.unmodifiable(contracts);
}

Future<VendorProvenanceContract> _readVendorContract(
  Directory repository,
  File catalog,
) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(await catalog.readAsString());
  } on Object catch (error) {
    throw FormatException('could not decode vendor contract: $error');
  }
  if (decoded is! Map<String, Object?> ||
      decoded['schemaVersion'] != vendorContractSchemaVersion) {
    throw FormatException('invalid vendor contract', catalog.path);
  }
  final name = decoded['name'];
  final package = decoded['package'];
  final version = decoded['version'];
  final vendorPath = decoded['vendorPath'];
  final patchManifest = decoded['patchManifest'];
  if (name is! String ||
      name.trim().isEmpty ||
      package is! String ||
      !_safePackageName(package) ||
      version is! String ||
      !_safeVersion(version) ||
      vendorPath is! String ||
      !_safeRepositoryPath(vendorPath) ||
      patchManifest is! String ||
      !_safeRepositoryPath(patchManifest)) {
    throw FormatException('invalid vendor contract fields', catalog.path);
  }
  final vendor = Directory.fromUri(repository.uri.resolve(vendorPath));
  final patches = File.fromUri(repository.uri.resolve(patchManifest));
  if (!await _within(repository, vendor) ||
      !await _within(repository, patches)) {
    throw FormatException(
      'vendor contract escaped the repository',
      catalog.path,
    );
  }
  return VendorProvenanceContract(
    name: name,
    package: package,
    version: version,
    vendorPath: vendor.path,
    patchManifest: patches.path,
    catalog: _relativePath(repository, catalog),
  );
}

bool _safePackageName(String value) => RegExp(r'^[a-z0-9_]+$').hasMatch(value);

bool _safeVersion(String value) =>
    value.isNotEmpty && !value.contains('/') && !value.contains('\\');

bool _safeRepositoryPath(String value) =>
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

Future<int> runVendorProvenanceContracts() async {
  try {
    final contracts = await loadVendorProvenanceContracts();
    if (contracts.isEmpty) {
      stderr.writeln('no owner-local vendor contracts were found');
      return 2;
    }
    var worst = 0;
    for (final contract in contracts) {
      final result = await runVendorProvenanceContract(contract);
      if (result > worst) worst = result;
    }
    return worst;
  } on Object catch (error) {
    stderr.writeln('vendor provenance contracts could not be checked: $error');
    return 2;
  }
}

Future<int> runVendorProvenanceContract(
  VendorProvenanceContract contract,
) async {
  try {
    final patches = await File(contract.patchManifest).readAsString();
    final documentedSha256 = parseDocumentedArchiveSha256(patches);
    final documentedPatches = parseDocumentedPatchInventory(patches);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);

    late final Uint8List metadataBytes;
    late final Uint8List archiveBytes;
    try {
      metadataBytes = await _download(
        client,
        contract.metadataUri,
        maximumBytes: _maximumMetadataBytes,
      );
      final metadata = _readMetadata(metadataBytes);
      if (metadata.version != contract.version ||
          metadata.archiveUrl != contract.archiveUri.toString()) {
        throw FormatException(
          'pub.dev returned an unexpected archive for '
          '${contract.package} ${contract.version}',
        );
      }
      if (metadata.archiveSha256 != documentedSha256) {
        throw FormatException(
          'PATCHES.md pins $documentedSha256, but pub.dev publishes '
          '${metadata.archiveSha256}',
        );
      }
      archiveBytes = await _download(
        client,
        contract.archiveUri,
        maximumBytes: _maximumArchiveBytes,
      );
    } finally {
      client.close(force: true);
    }

    final actualSha256 = sha256Hex(archiveBytes);
    if (actualSha256 != documentedSha256) {
      throw FormatException(
        'downloaded archive SHA-256 was $actualSha256; '
        'expected $documentedSha256',
      );
    }

    final baseline = decodeTarGzipFiles(archiveBytes);
    final vendor = await readDirectoryFiles(Directory(contract.vendorPath));
    final comparison = compareVendorFiles(
      baseline: baseline,
      vendor: vendor,
      documentedPatches: documentedPatches,
    );

    stdout.writeln('archive SHA-256 verified: $documentedSha256');
    if (comparison.matchesDocumentedInventory) {
      stdout.writeln(
        '${contract.name} matches its published archive '
        'plus ${documentedPatches.length} documented patch files',
      );
      return 0;
    }

    if (comparison.undocumentedDifferences.isNotEmpty) {
      stderr.writeln('undocumented vendored differences:');
      for (final path in comparison.undocumentedDifferences) {
        stderr.writeln('  ${comparison.differences[path]!.name}: $path');
      }
    }
    if (comparison.documentedFilesWithoutDifference.isNotEmpty) {
      stderr.writeln('documented patch files that match the archive:');
      for (final path in comparison.documentedFilesWithoutDifference) {
        stderr.writeln('  $path');
      }
    }
    stderr.writeln(
      'Review the archive diff and update ${contract.patchManifest} only when '
      'the '
      'vendored change is intentional.',
    );
    return 1;
  } on Object catch (error) {
    stderr.writeln('${contract.name} contract could not be checked: $error');
    return 2;
  }
}

VendorComparison compareVendorFiles({
  required Map<String, List<int>> baseline,
  required Map<String, List<int>> vendor,
  required Set<String> documentedPatches,
}) {
  final differences = SplayTreeMap<String, VendorDifferenceKind>();
  final paths = SplayTreeSet<String>()
    ..addAll(baseline.keys)
    ..addAll(vendor.keys);

  for (final path in paths) {
    final baselineBytes = baseline[path];
    final vendorBytes = vendor[path];
    if (baselineBytes == null) {
      differences[path] = VendorDifferenceKind.added;
    } else if (vendorBytes == null) {
      differences[path] = VendorDifferenceKind.removed;
    } else if (!_bytesEqual(baselineBytes, vendorBytes)) {
      differences[path] = VendorDifferenceKind.modified;
    }
  }

  final undocumented = differences.keys
      .where((path) => !documentedPatches.contains(path))
      .toList(growable: false);
  final unchangedDocumented =
      documentedPatches
          .where((path) => !differences.containsKey(path))
          .toList(growable: false)
        ..sort();
  return VendorComparison(
    differences: differences,
    undocumentedDifferences: undocumented,
    documentedFilesWithoutDifference: unchangedDocumented,
  );
}

String parseDocumentedArchiveSha256(String markdown) {
  final matches = RegExp(
    r'^- Archive SHA-256: `([0-9a-f]{64})`[ \t]*$',
    multiLine: true,
  ).allMatches(markdown).toList(growable: false);
  if (matches.length != 1) {
    throw const FormatException(
      'PATCHES.md must document exactly one lowercase archive SHA-256',
    );
  }
  return matches.single.group(1)!;
}

Set<String> parseDocumentedPatchInventory(String markdown) {
  final paths = SplayTreeSet<String>();
  for (final match in RegExp(
    r'^- `([^`\r\n]+)`[ \t]*$',
    multiLine: true,
  ).allMatches(markdown)) {
    final path = match.group(1)!;
    _validateRelativePath(path);
    if (!paths.add(path)) {
      throw FormatException('duplicate documented patch file: $path');
    }
  }
  if (paths.isEmpty) {
    throw const FormatException('PATCHES.md documents no patch files');
  }
  return Set.unmodifiable(paths);
}

String sha256Hex(List<int> bytes) {
  final digest = SHA256Digest().process(Uint8List.fromList(bytes));
  return digest.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

Map<String, Uint8List> decodeTarGzipFiles(Uint8List archiveBytes) {
  final tarBytes = Uint8List.fromList(gzip.decode(archiveBytes));
  final files = <String, Uint8List>{};
  var offset = 0;
  var terminalBlocks = 0;
  String? pendingLongName;

  while (offset + _tarBlockSize <= tarBytes.length) {
    final header = Uint8List.sublistView(
      tarBytes,
      offset,
      offset + _tarBlockSize,
    );
    offset += _tarBlockSize;
    if (header.every((byte) => byte == 0)) {
      terminalBlocks++;
      if (terminalBlocks == 2) {
        if (pendingLongName != null) {
          throw const FormatException('GNU tar long name has no entry');
        }
        if (tarBytes.skip(offset).any((byte) => byte != 0)) {
          throw const FormatException('non-zero data after tar terminator');
        }
        return Map.unmodifiable(files);
      }
      continue;
    }
    if (terminalBlocks != 0) {
      throw const FormatException('incomplete tar terminator');
    }
    if (_readTarString(header, 257, 6) != 'ustar') {
      throw const FormatException('archive is not a USTAR package');
    }

    final size = _readTarOctal(header, 124, 12);
    final paddedSize =
        ((size + _tarBlockSize - 1) ~/ _tarBlockSize) * _tarBlockSize;
    if (offset + paddedSize > tarBytes.length) {
      throw const FormatException('truncated tar entry');
    }

    final type = header[156];
    if (type == 0x4c) {
      if (pendingLongName != null) {
        throw const FormatException('nested GNU tar long names');
      }
      pendingLongName = _readTarLongName(
        Uint8List.sublistView(tarBytes, offset, offset + size),
      );
      _validateRelativePath(pendingLongName);
      offset += paddedSize;
      continue;
    }

    final name = _readTarString(header, 0, 100);
    final prefix = _readTarString(header, 345, 155);
    final path = pendingLongName ?? (prefix.isEmpty ? name : '$prefix/$name');
    pendingLongName = null;
    _validateRelativePath(path);
    if (type == 0 || type == 0x30) {
      if (files.containsKey(path)) {
        throw FormatException('duplicate archive file: $path');
      }
      files[path] = Uint8List.fromList(
        Uint8List.sublistView(tarBytes, offset, offset + size),
      );
    } else if (type != 0x35) {
      throw FormatException(
        'unsupported tar entry type ${String.fromCharCode(type)}: $path',
      );
    }
    offset += paddedSize;
  }
  throw const FormatException('tar archive has no complete terminator');
}

Future<Map<String, Uint8List>> readDirectoryFiles(
  Directory root, {
  Set<String> excludedPaths = const {},
}) async {
  final absoluteRoot = root.absolute.path;
  final prefix = '$absoluteRoot${Platform.pathSeparator}';
  final files = <String, Uint8List>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is Directory) continue;
    if (entity is! File) {
      throw FormatException('unsupported vendored file type: ${entity.path}');
    }
    if (!entity.absolute.path.startsWith(prefix)) {
      throw FormatException('vendored file escaped its root: ${entity.path}');
    }
    final path = entity.absolute.path
        .substring(prefix.length)
        .replaceAll(Platform.pathSeparator, '/');
    _validateRelativePath(path);
    if (!excludedPaths.contains(path)) {
      files[path] = await entity.readAsBytes();
    }
  }
  return Map.unmodifiable(files);
}

({String version, String archiveUrl, String archiveSha256}) _readMetadata(
  Uint8List bytes,
) {
  final Object? decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('pub.dev metadata was not an object');
  }
  final version = decoded['version'];
  final archiveUrl = decoded['archive_url'];
  final archiveSha256 = decoded['archive_sha256'];
  if (version is! String || archiveUrl is! String || archiveSha256 is! String) {
    throw const FormatException('pub.dev metadata omitted archive identity');
  }
  return (
    version: version,
    archiveUrl: archiveUrl,
    archiveSha256: archiveSha256,
  );
}

Future<Uint8List> _download(
  HttpClient client,
  Uri uri, {
  required int maximumBytes,
}) async {
  if (uri.scheme != 'https' || uri.host != 'pub.dev') {
    throw ArgumentError.value(uri, 'uri', 'Only official pub.dev HTTPS URLs');
  }
  final request = await client.getUrl(uri).timeout(const Duration(seconds: 30));
  request.followRedirects = false;
  request.headers.set(
    HttpHeaders.userAgentHeader,
    'discourse-native-vendor-provenance-contract',
  );
  final response = await request.close().timeout(const Duration(seconds: 30));
  if (response.statusCode != HttpStatus.ok) {
    await response.drain<void>();
    throw HttpException(
      'pub.dev returned HTTP ${response.statusCode}',
      uri: uri,
    );
  }

  final buffer = BytesBuilder(copy: false);
  await for (final chunk in response.timeout(const Duration(seconds: 30))) {
    if (buffer.length + chunk.length > maximumBytes) {
      throw HttpException('pub.dev response exceeded $maximumBytes bytes');
    }
    buffer.add(chunk);
  }
  return buffer.takeBytes();
}

String _readTarString(Uint8List header, int start, int length) {
  var end = start;
  final limit = start + length;
  while (end < limit && header[end] != 0) {
    end++;
  }
  return utf8.decode(Uint8List.sublistView(header, start, end));
}

String _readTarLongName(Uint8List bytes) {
  final terminator = bytes.indexOf(0);
  final end = terminator < 0 ? bytes.length : terminator;
  if (end < 1) {
    throw const FormatException('invalid GNU tar long name');
  }
  return utf8.decode(Uint8List.sublistView(bytes, 0, end));
}

int _readTarOctal(Uint8List header, int start, int length) {
  final encoded = _readTarString(header, start, length).trim();
  if (encoded.isEmpty || !RegExp(r'^[0-7]+$').hasMatch(encoded)) {
    throw FormatException('invalid tar size: $encoded');
  }
  return int.parse(encoded, radix: 8);
}

void _validateRelativePath(String path) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.contains('\\') ||
      path
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw FormatException('unsafe package path: $path');
  }
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
