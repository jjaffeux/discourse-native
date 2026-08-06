@Tags(['live'])
library;

import 'dart:io';

import 'package:discourse_native/src/data/avatar_loader.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/secure_store.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => HttpOverrides.global = null);

  test('resolves meta.discourse.org for real', () async {
    final site = await DiscourseApi().lookup('meta.discourse.org');
    // ignore: avoid_print
    print('RESOLVED: ${site.toJson()}');
    expect(site.url, 'https://meta.discourse.org');
    expect(site.apiVersion, greaterThanOrEqualTo(2));
  });

  test('follows the http -> https redirect', () async {
    final site = await DiscourseApi().lookup('http://meta.discourse.org');
    // ignore: avoid_print
    print('REDIRECTED TO: ${site.url}');
    expect(site.url, 'https://meta.discourse.org');
  });

  liveAuthUrl();
  liveFeeds();
  livePaging();
  liveAvatars();
  liveTopic();

  test('rejects a non-Discourse host', () async {
    await expectLater(
      DiscourseApi().lookup('example.com'),
      throwsA(isA<SiteLookupException>()),
    );
  });
}

/// Confirms a real Discourse accepts the handshake parameters we send —
/// notably that our PEM encoding and scope list are ones it will parse.
void liveAuthUrl() {
  test('meta accepts our user-api-key request', () async {
    final pair = AuthKeyPair.generate();
    final url = const UserApiKeyProtocol().authUrl(
      siteUrl: 'https://meta.discourse.org',
      publicKeyPem: pair.publicPem,
      nonce: SecureStore.randomToken(),
      clientId: SecureStore.randomToken(),
      applicationName: 'Discourse Native (test)',
    );

    final client = HttpClient();
    final request = await client.getUrl(url);
    request.followRedirects = false;
    final response = await request.close();
    await response.drain<void>();

    // Signed out, Discourse stashes the destination and sends us to /login.
    // A 400/403 would mean it rejected our parameters.
    // ignore: avoid_print
    print(
      'AUTH URL STATUS: ${response.statusCode} -> '
      '${response.headers.value('location')}',
    );
    expect(response.statusCode, anyOf(200, 302));
    expect(response.statusCode, isNot(403));
  });
}

/// Parses meta's real payloads, which is the only way to catch a field name
/// that differs from what the fixtures assume.
void liveFeeds() {
  test('parses meta latest.json', () async {
    final list = await DiscourseApi().topicList(
      siteUrl: 'https://meta.discourse.org',
      path: '/latest.json',
    );

    expect(list.topics, isNotEmpty);
    final withTitle = list.topics.where((t) => t.title.isNotEmpty);
    expect(withTitle.length, list.topics.length);
    expect(list.topics.every((t) => t.id > 0), isTrue);
    expect(list.topics.every((t) => t.slug.isNotEmpty), isTrue);
    // Avatars must have resolved to absolute URLs.
    final avatars = list.topics.expand((t) => t.posterAvatars);
    expect(avatars, isNotEmpty);
    expect(avatars.every((a) => a.startsWith('http')), isTrue);

    final sample = list.topics.first;
    // ignore: avoid_print
    print(
      'TOPIC: ${sample.title} | replies ${sample.replyCount} | '
      'views ${sample.views} | cat ${sample.categoryId} | '
      'bumped ${sample.bumpedAt} | avatars ${sample.posterAvatars.length}',
    );
  });

  test('parses meta categories.json including subcategories', () async {
    final categories = await DiscourseApi().categories(
      siteUrl: 'https://meta.discourse.org',
    );

    expect(categories.length, greaterThan(11));
    expect(categories.every((c) => c.name.isNotEmpty), isTrue);
    expect(categories.every((c) => c.colorValue != 0), isTrue);
    // ignore: avoid_print
    print(
      'CATEGORIES: ${categories.length}, e.g. '
      '${categories.take(3).map((c) => "${c.name}#${c.color}").join(", ")}',
    );
  });
}

/// Confirms real pagination: the URL rewrite works and page two is different
/// content, not the same page served again.
void livePaging() {
  test('pages through meta latest', () async {
    final api = DiscourseApi();
    final first = await api.topicList(
      siteUrl: 'https://meta.discourse.org',
      path: '/latest.json',
    );

    expect(first.nextPagePath, isNotNull);
    // ignore: avoid_print
    print('NEXT PAGE: ${first.moreTopicsUrl} -> ${first.nextPagePath}');
    expect(first.nextPagePath, contains('.json'));

    final second = await api.topicList(
      siteUrl: 'https://meta.discourse.org',
      path: first.nextPagePath!,
    );

    expect(second.topics, isNotEmpty);
    final firstIds = first.topics.map((t) => t.id).toSet();
    final fresh = second.topics.where((t) => !firstIds.contains(t.id));
    // ignore: avoid_print
    print('PAGE 2: ${second.topics.length} topics, ${fresh.length} new');
    expect(fresh, isNotEmpty, reason: 'page two should not repeat page one');
  });
}

/// Discourse serves some avatars as SVG from a `.png` URL, which is why
/// avatars go through AvatarLoader instead of NetworkImage.
void liveAvatars() {
  test('detects meta serving an SVG avatar from a .png url', () async {
    final loader = AvatarLoader();
    final result = await loader.load(
      'https://meta.discourse.org/user_avatar/meta.discourse.org/discourse/90/148734_2.png',
    );

    expect(result, isNotNull);
    // ignore: avoid_print
    print('AVATAR: ${result!.bytes.length} bytes, isSvg=${result.isSvg}');
    expect(result.isSvg, isTrue, reason: 'the .png url serves image/svg+xml');
  });

  test('loads an ordinary raster avatar through its redirects', () async {
    final loader = AvatarLoader();
    final result = await loader.load(
      'https://meta.discourse.org/user_avatar/meta.discourse.org/codinghorror/90/5297_2.png',
    );

    expect(result, isNotNull, reason: 'a normal avatar must still load');
    // ignore: avoid_print
    print(
      'RASTER AVATAR: ${result!.bytes.length} bytes, isSvg=${result.isSvg}',
    );
    expect(result.isSvg, isFalse);
    expect(result.bytes.length, greaterThan(1000));
  });
}

/// Parses a real topic and pages its posts by id.
void liveTopic() {
  test('loads a meta topic and its remaining posts', () async {
    final api = DiscourseApi();
    final list = await api.topicList(
      siteUrl: 'https://meta.discourse.org',
      path: '/latest.json',
    );
    final busy = list.topics.firstWhere((t) => t.postsCount > 25);

    final fetched = await api.topic(
      siteUrl: 'https://meta.discourse.org',
      slug: busy.slug,
      id: busy.id,
    );
    final topic = fetched.detail;

    expect(fetched.posts, isNotEmpty);
    expect(fetched.posts.every((p) => p.cooked.isNotEmpty), isTrue);
    expect(fetched.posts.every((p) => p.username.isNotEmpty), isTrue);
    expect(topic.stream.length, greaterThan(fetched.posts.length));
    // ignore: avoid_print
    print(
      'TOPIC "${topic.title}": ${fetched.posts.length} of '
      '${topic.stream.length} posts, first by ${fetched.posts.first.username}',
    );

    // What the app does with a payload: file the posts under their own ids and
    // page by asking the stream which ids are still missing.
    final store = Store();
    store.putAll('https://meta.discourse.org', fetched.posts);

    List<int> pending() => [
      for (final id in topic.stream)
        if (store.read<Post>('https://meta.discourse.org', id) == null) id,
    ];

    expect(pending(), isNotEmpty);

    final more = await api.posts(
      siteUrl: 'https://meta.discourse.org',
      topicId: topic.id,
      ids: pending().take(5).toList(),
    );

    expect(more, hasLength(5));
    store.putAll('https://meta.discourse.org', more);

    final loaded = [
      for (final id in topic.stream)
        if (store.read<Post>('https://meta.discourse.org', id) != null) id,
    ];
    expect(loaded.length, fetched.posts.length + 5);
    // In stream order, which is post order, not the order they arrived in.
    final numbers = [
      for (final id in loaded)
        store.read<Post>('https://meta.discourse.org', id)!.postNumber,
    ];
    expect(numbers, orderedEquals([...numbers]..sort()));
    // ignore: avoid_print
    print('AFTER PAGING: ${loaded.length} posts, pending=${pending().length}');
  });
}
