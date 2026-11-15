import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../foundation/private_file_document.dart';

/// How one owner's pending work crosses the file boundary.
///
/// [decode] reads what an earlier build or a damaged write left behind, so it
/// answers null for anything it cannot use instead of throwing, and applies
/// the owner's bounds to what it keeps.
final class SiteOutboxCodec<T extends Object> {
  const SiteOutboxCodec({required this.encode, required this.decode});

  /// A JSON-encodable value whose encoding is the same for equal entries.
  final Object Function(T entries) encode;
  final T? Function(Object? json) decode;
}

/// User work a site has not accepted yet, kept per site for one account so it
/// outlives the process.
///
/// Each owner has its own file and holds the truth in memory; the file is the
/// copy a relaunch starts from. Operations commit in the order they were
/// called, so an owner that calls [restore] before its first [save] never
/// overwrites what an earlier session left. Entries are user content: the
/// file is owner-only and never leaves [PrivateFileDocument].
///
/// Nothing here throws. A file that is damaged or written by another format
/// version is discarded, and a storage failure only costs durability.
final class SiteOutbox<T extends Object> {
  SiteOutbox({required this._file, required this.codec});

  static const formatVersion = 1;

  final PrivateFileResolver _file;
  final SiteOutboxCodec<T> codec;

  late final _document = PrivateFileDocument<Map<String, _Section>>(
    target: _file,
    empty: () => {},
    decode: _decode,
    encode: _encode,
    setAsideUndecodable: _discard,
  );

  /// The entries held for [account], or null when there are none. Entries
  /// held for any other account are removed: they belong to nobody who can
  /// still send them.
  Future<T?> restore(String siteUrl, String account) async {
    try {
      return await _document.update<T?>((sites) {
        final held = sites[siteUrl];
        if (held == null) return PrivateFileResult<T?>(null);
        final entries = held.account == account
            ? codec.decode(held.entries)
            : null;
        if (entries == null) sites.remove(siteUrl);
        return PrivateFileResult<T?>(entries);
      });
    } catch (_) {
      return null;
    }
  }

  /// Replaces what is held for [siteUrl] with [entries], or with nothing, and
  /// answers whether the file now says so. An owner whose next step is only
  /// safe once an entry is gone waits for that answer.
  Future<bool> save(String siteUrl, String account, T? entries) async {
    try {
      final encoded = entries == null ? null : codec.encode(entries);
      await _document.update((sites) {
        if (encoded == null) {
          sites.remove(siteUrl);
        } else {
          sites[siteUrl] = _Section(account, encoded);
        }
        return PrivateFileResult.done;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> forget(String siteUrl) async {
    try {
      await _document.update((sites) {
        sites.remove(siteUrl);
        return PrivateFileResult.done;
      });
    } catch (_) {}
  }

  /// The sites that hold entries for some account.
  Future<Set<String>> sites() async {
    try {
      return await _document.read(
        (sites) => PrivateFileResult(sites.keys.toSet()),
      );
    } catch (_) {
      return const {};
    }
  }

  static Map<String, _Section> _decode(String contents) {
    final Object? json;
    try {
      json = jsonDecode(contents);
    } on FormatException {
      return {};
    }
    if (json is! Map ||
        json['version'] != formatVersion ||
        json['sites'] is! Map) {
      return {};
    }
    final sites = <String, _Section>{};
    for (final entry in (json['sites'] as Map).entries) {
      final siteUrl = entry.key;
      final section = entry.value;
      if (siteUrl is! String || section is! Map) continue;
      if (section['account'] case final String account) {
        sites[siteUrl] = _Section(account, section['entries']);
      }
    }
    return sites;
  }

  static String _encode(Map<String, _Section> sites) => jsonEncode({
    'version': formatVersion,
    'sites': {
      for (final entry in sites.entries)
        entry.key: {
          'account': entry.value.account,
          'entries': entry.value.entries,
        },
    },
  });

  /// A set-aside copy would keep message text that nothing reads again and
  /// that forgetting its site could no longer reach.
  static void _discard(File damaged) {
    try {
      damaged.deleteSync();
    } on FileSystemException {
      // The copy is already owner-only.
    }
  }
}

final class _Section {
  const _Section(this.account, this.entries);

  final String account;

  /// Kept as decoded JSON so one owner's bounds never rewrite a section it
  /// was not asked about.
  final Object? entries;
}
