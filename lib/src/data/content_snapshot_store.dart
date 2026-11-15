import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../foundation/private_file_document.dart';

typedef ContentSnapshotDirectory = FutureOr<Directory> Function();

/// How much of a forum one account's snapshot may keep.
///
/// Five public first pages of thirty topics were 37 to 79 KB and twelve topic
/// opening windows 18 to 142 KB (`docs/offline-snapshots.md`). The defaults
/// hold the lists a reader moves between and the last few conversations. The
/// byte bounds matter more than the counts: one very long topic is refused
/// rather than allowed to push out everything else.
final class ContentSnapshotLimits {
  const ContentSnapshotLimits({
    this.feeds = 8,
    this.topics = 12,
    this.entryBytes = 512 * 1024,
    this.totalBytes = 3 * 1024 * 1024,
  }) : assert(feeds > 0),
       assert(topics > 0),
       assert(entryBytes > 0),
       assert(totalBytes >= entryBytes);

  final int feeds;
  final int topics;

  /// The largest single response kept. A larger one is not truncated, because
  /// part of a response does not parse; it is left out.
  final int entryBytes;

  /// The response bytes one account may keep on a forum. The file is somewhat
  /// larger: each response is stored as a JSON string, which escapes it.
  final int totalBytes;
}

/// The last content one account saw on each forum, kept across launches.
///
/// Each forum has one owner-only document holding the account it belongs to,
/// the first page of the lists that account visited and the topics it opened
/// last, as the responses the site sent. Nothing here is authoritative: every
/// read is followed by a request, and a document this version cannot read, or
/// one written for another account, is treated as absent and replaced by the
/// next write.
///
/// Saves are held in memory and committed together after [writeDelay], so a
/// burst of list refreshes costs one write. Scrolling never saves.
final class ContentSnapshotStore {
  ContentSnapshotStore({
    required this._directory,
    this.limits = const ContentSnapshotLimits(),
    this.writeDelay = const Duration(seconds: 3),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const int formatVersion = 1;
  static const String directoryName = 'content-snapshots';

  final ContentSnapshotDirectory _directory;
  final ContentSnapshotLimits limits;
  final Duration writeDelay;
  final DateTime Function() _clock;

  /// Kept for the life of the store, unlike [_sites]: a forum's deletion and
  /// the next account's first read must queue behind one another.
  final Map<String, PrivateFileDocument<_SnapshotFile>> _documents = {};
  final Map<String, _SiteSnapshots> _sites = {};
  final Set<Future<void>> _writes = {};

  Future<String?> readFeed(
    String siteUrl,
    String account,
    String destinationId,
    String path,
  ) async {
    final entry = (await _contents(siteUrl, account))?.feeds[destinationId];
    return entry != null && entry.path == path ? entry.wire : null;
  }

  Future<String?> readTopic(String siteUrl, String account, int topicId) async {
    return (await _contents(siteUrl, account))?.topics[topicId]?.wire;
  }

  void saveFeed(
    String siteUrl,
    String account,
    String destinationId,
    String path, {
    required String wire,
    required int bytes,
  }) => _save(siteUrl, account, bytes, (contents) {
    final held = contents.feeds.remove(destinationId);
    contents.feeds[destinationId] = _Entry(
      wire: wire,
      bytes: bytes,
      savedAt: _clock().millisecondsSinceEpoch,
      path: path,
    );
    return held?.wire != wire || held?.path != path;
  });

  void saveTopic(
    String siteUrl,
    String account,
    int topicId, {
    required String wire,
    required int bytes,
  }) => _save(siteUrl, account, bytes, (contents) {
    final held = contents.topics.remove(topicId);
    contents.topics[topicId] = _Entry(
      wire: wire,
      bytes: bytes,
      savedAt: _clock().millisecondsSinceEpoch,
    );
    return held?.wire != wire;
  });

  /// Deletes what [siteUrl] kept, for whichever account. Saves accepted before
  /// this call are dropped, including one whose write has already begun: the
  /// deletion commits behind it.
  Future<void> forget(String siteUrl) {
    _sites.remove(siteUrl)?.retire();
    return _track(_document(siteUrl).delete());
  }

  /// Commits what is waiting on [writeDelay]. The OS may suspend the process
  /// before the timer fires.
  Future<void> flush() async {
    // A save is applied once its forum's file has been read.
    await Future.wait([for (final site in _sites.values) ?site.loaded]);
    for (final site in _sites.values.toList()) {
      site.timer?.cancel();
      site.timer = null;
      _write(site);
    }
    while (_writes.isNotEmpty) {
      await Future.wait(_writes.toList());
    }
  }

  PrivateFileDocument<_SnapshotFile> _document(String siteUrl) =>
      _documents.putIfAbsent(
        siteUrl,
        () => PrivateFileDocument<_SnapshotFile>(
          target: () async => File(
            '${(await _directory()).path}/'
            '${Uri.encodeComponent(siteUrl)}.json',
          ),
          empty: _SnapshotFile.new,
          // Parsing is left to the reader. A commit replaces the whole
          // document, and has no use for the megabytes it is replacing.
          decode: (contents) => _SnapshotFile()..text = contents,
          encode: (file) => file.text ?? '',
          snapshot: (file) => file.revision,
        ),
      );

  _SiteSnapshots _site(String siteUrl) =>
      _sites.putIfAbsent(siteUrl, () => _SiteSnapshots(siteUrl));

  Future<_Contents?> _contents(String siteUrl, String account) async {
    final site = _site(siteUrl);
    await (site.loaded ??= _load(site));
    final contents = site.contents;
    if (!identical(_sites[siteUrl], site) || contents == null) return null;
    return contents.account == account ? contents : null;
  }

  Future<void> _load(_SiteSnapshots site) async {
    _Contents? stored;
    try {
      final text = await _document(
        site.siteUrl,
      ).read((file) => PrivateFileResult(file.text));
      if (text != null && text.isNotEmpty) {
        stored = await _SnapshotCodecs.decode(text);
      }
    } catch (_) {
      // An unreadable snapshot is a missing one. The next save replaces it.
    }
    if (!site.retired) site.contents = stored ?? _Contents('');
  }

  void _save(
    String siteUrl,
    String account,
    int bytes,
    bool Function(_Contents contents) put,
  ) {
    if (bytes > limits.entryBytes) return;
    final site = _site(siteUrl);
    // A save waits for the file it will replace. Otherwise the first response
    // of a launch would commit alone and drop every other entry the account
    // had kept.
    unawaited(
      (site.loaded ??= _load(site)).then((_) {
        if (!identical(_sites[siteUrl], site) || site.retired) return;
        var contents = site.contents;
        if (contents == null || contents.account != account) {
          // Another account's content is replaced, never merged into.
          contents = site.contents = _Contents(account);
          site.dirty = true;
        }
        if (put(contents)) site.dirty = true;
        _trim(contents);
        if (!site.dirty || site.timer != null) return;
        site.timer = Timer(writeDelay, () {
          site.timer = null;
          _write(site);
        });
      }),
    );
  }

  void _trim(_Contents contents) {
    while (contents.feeds.length > limits.feeds) {
      contents.feeds.remove(contents.feeds.keys.first);
    }
    while (contents.topics.length > limits.topics) {
      contents.topics.remove(contents.topics.keys.first);
    }
    // Topics go first: a list is what a launch shows before anything is
    // tapped, and one list stands in for many conversations.
    while (contents.bytes > limits.totalBytes) {
      if (contents.topics.isNotEmpty) {
        contents.topics.remove(contents.topics.keys.first);
      } else if (contents.feeds.length > 1) {
        contents.feeds.remove(contents.feeds.keys.first);
      } else {
        break;
      }
    }
  }

  void _write(_SiteSnapshots site) {
    final contents = site.contents;
    if (!site.dirty || contents == null || site.retired) return;
    site.dirty = false;
    final encoding = _SnapshotCodecs.encode(contents);
    final write = _track(() async {
      try {
        final text = await encoding;
        final document = _document(site.siteUrl);
        Future<void> commit() => document.update((file) {
          // Decided inside the transaction: a forum forgotten while its text
          // was being encoded must not be written back.
          if (!site.retired) {
            file
              ..text = text
              ..revision = Object();
          }
          return PrivateFileResult.done;
        });
        try {
          await commit();
        } on FileSystemException {
          // A file that cannot be read as text cannot be replaced through a
          // transaction that reads it first. Nothing in it is wanted.
          await document.delete();
          await commit();
        }
      } catch (_) {
        // The snapshot is a convenience. A full or read-only disk costs the
        // next launch its head start and nothing else.
      }
    }());
    unawaited(write);
  }

  Future<void> _track(Future<void> write) {
    late final Future<void> tracked;
    tracked = write.whenComplete(() => _writes.remove(tracked));
    _writes.add(tracked);
    return tracked;
  }
}

final class _SiteSnapshots {
  _SiteSnapshots(this.siteUrl);

  final String siteUrl;
  Future<void>? loaded;
  _Contents? contents;
  Timer? timer;
  bool dirty = false;
  bool retired = false;

  void retire() {
    retired = true;
    timer?.cancel();
    timer = null;
    contents = null;
    dirty = false;
  }
}

final class _SnapshotFile {
  String? text;
  Object revision = const Object();
}

final class _Entry {
  const _Entry({
    required this.wire,
    required this.bytes,
    required this.savedAt,
    this.path,
  });

  final String wire;
  final int bytes;
  final int savedAt;
  final String? path;
}

/// Both maps iterate oldest first; saving an entry again moves it to the end.
final class _Contents {
  _Contents(this.account);

  final String account;
  final Map<String, _Entry> feeds = {};
  final Map<int, _Entry> topics = {};

  int get bytes =>
      feeds.values.fold(0, (sum, entry) => sum + entry.bytes) +
      topics.values.fold(0, (sum, entry) => sum + entry.bytes);

  int get chars =>
      feeds.values.fold(0, (sum, entry) => sum + entry.wire.length) +
      topics.values.fold(0, (sum, entry) => sum + entry.wire.length);

  Map<String, Object?> toJson() => {
    'version': ContentSnapshotStore.formatVersion,
    'account': account,
    'feeds': [
      for (final MapEntry(:key, :value) in feeds.entries)
        {
          'destination': key,
          'path': value.path,
          'savedAt': value.savedAt,
          'bytes': value.bytes,
          'wire': value.wire,
        },
    ],
    'topics': [
      for (final MapEntry(:key, :value) in topics.entries)
        {
          'id': key,
          'savedAt': value.savedAt,
          'bytes': value.bytes,
          'wire': value.wire,
        },
    ],
  };
}

/// Answers null for anything this version did not write, whatever its shape.
_Contents? _decodeContents(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic> ||
      decoded['version'] != ContentSnapshotStore.formatVersion) {
    return null;
  }
  final account = decoded['account'];
  final feeds = decoded['feeds'];
  final topics = decoded['topics'];
  if (account is! String || feeds is! List || topics is! List) return null;
  final contents = _Contents(account);
  for (final value in feeds) {
    if (value case {
      'destination': final String destination,
      'path': final String path,
      'savedAt': final int savedAt,
      'bytes': final int bytes,
      'wire': final String wire,
    }) {
      contents.feeds[destination] = _Entry(
        wire: wire,
        bytes: bytes,
        savedAt: savedAt,
        path: path,
      );
    } else {
      return null;
    }
  }
  for (final value in topics) {
    if (value case {
      'id': final int id,
      'savedAt': final int savedAt,
      'bytes': final int bytes,
      'wire': final String wire,
    }) {
      contents.topics[id] = _Entry(wire: wire, bytes: bytes, savedAt: savedAt);
    } else {
      return null;
    }
  }
  return contents;
}

/// The closures sent to a worker are built here so that they capture their
/// argument and nothing else from the store.
abstract final class _SnapshotCodecs {
  /// Below this many UTF-16 units a codec costs less than starting an isolate
  /// for it, the threshold network responses already use.
  static const int _inlineLimit = 64 * 1024;

  static Future<String> encode(_Contents contents) {
    final json = contents.toJson();
    if (contents.chars <= _inlineLimit) {
      return Future.sync(() => jsonEncode(json));
    }
    return Isolate.run(
      () => jsonEncode(json),
      debugName: 'content-snapshot-codec',
    );
  }

  static Future<_Contents?> decode(String text) {
    if (text.length <= _inlineLimit) {
      return Future.sync(() => _decodeContents(text));
    }
    return Isolate.run(
      () => _decodeContents(text),
      debugName: 'content-snapshot-codec',
    );
  }
}
