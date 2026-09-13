import 'package:http/http.dart' as http;

import '../models/discover_site.dart';
import '../models/json.dart';
import 'discourse_transport.dart';

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

  Future<List<DiscoverSite>> load() {
    final sites = _sites;
    if (sites != null) return Future.value(sites);
    return _pending ??= _load();
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
      );
      if (json['topics'] is! List) {
        throw const FormatException('Missing Discover communities.');
      }
      return _sites = List.unmodifiable([
        for (final entry in jsonArray(json['topics']).take(50))
          if (entry is Map<String, dynamic>) ?DiscoverSite.tryParse(entry),
      ]);
    } finally {
      _pending = null;
    }
  }

  void dispose() => _transport.close();
}
