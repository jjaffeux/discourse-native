import 'dart:convert';

import 'package:discourse_native/src/data/discover_sites.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

DiscoverSites emptyDiscoverSites() => DiscoverSites(
  client: MockClient(
    (_) async => http.Response(jsonEncode({'topics': <Object?>[]}), 200),
  ),
);

Map<String, Object?> discoverEntry(int index) => {
  'title': 'Community $index',
  'featured_link': 'https://community$index.example',
};
