import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:http/http.dart' as http;

import '../models/json.dart';
import 'discourse_transport.dart';
import 'discover_site.dart';

class DiscoverSites {
  DiscoverSites({http.Client? client})
    : _transport = DiscourseTransport.create(
        client: client,
        maxResponseBytes: 2 * 1024 * 1024,
      );

  static const siteUrl = 'https://discover.discourse.com';
  static const browseUrl = 'https://discover.discourse.org';
  final DiscourseTransport _transport;
  List<DiscoverSite>? _sites;
  Future<List<DiscoverSite>>? _pending;
  final _disposed = Completer<void>();

  Future<List<DiscoverSite>> load() {
    if (_disposed.isCompleted) {
      return Future.error(StateError('Discover sites is disposed.'));
    }
    final sites = _sites;
    if (sites != null) return Future.value(sites);
    if (_pending case final pending?) return pending;
    final loading = Completer<List<DiscoverSite>>();
    _pending = loading.future;
    loading.complete(_load());
    return loading.future;
  }

  Future<List<DiscoverSite>> _load() async {
    try {
      final json = await _transport.getObject(
        Uri.parse('$siteUrl/search.json').replace(
          queryParameters: {
            'q': '#discover #locale-en order:featured',
            'page': '1',
          },
        ),
        siteUrl: siteUrl,
        abortTrigger: _disposed.future,
      );
      if (_disposed.isCompleted) {
        throw StateError('Discover sites is disposed.');
      }
      if (json['topics'] is! List) {
        throw FormatException(appL10n.missingDiscoverCommunities);
      }
      return _sites = List.unmodifiable([
        for (final entry in jsonArray(json['topics']).take(50))
          if (entry is Map<String, dynamic>) ?DiscoverSite.tryParse(entry),
      ]);
    } finally {
      _pending = null;
    }
  }

  void dispose() {
    if (_disposed.isCompleted) return;
    _disposed.complete();
    _transport.close();
  }
}
