import 'dart:async';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:test/test.dart';

CookingSnapshot snapshot({
  String site = 'a',
  String account = 'alice',
  Map<String, Object?> emoji = const {},
  Map<String, Object?> oneboxes = const {},
}) => CookingSnapshot(
  siteId: site,
  accountId: account,
  baseUrl: 'https://$site.example',
  customEmoji: emoji,
  oneboxes: oneboxes,
);
CookingRequest request(
  String raw, {
  CookingProfile profile = CookingProfile.post,
  CookingSnapshot? context,
}) =>
    CookingRequest(raw: raw, profile: profile, snapshot: context ?? snapshot());

void main() {
  test('main isolate handles timer while worker parses heavy input', () async {
    final service = OfflineCookingService();
    addTearDown(service.dispose);
    expect(await service.start(), isTrue);
    final cook = service.cook(
      request('**markdown** :smile: @missing\n\n' * 1500),
    );
    final first = await Future.any<String>([
      cook.then((_) => 'cook'),
      Future<String>.delayed(Duration.zero, () => 'timer'),
    ]);
    expect(first, 'timer');
    await cook;
  });
  group('persistent worker corpus', () {
    late OfflineCookingService service;
    setUp(() => service = OfflineCookingService());
    tearDown(() => service.dispose());

    test('common markdown, protected text, emoji and BBCode plugin', () async {
      final result = await service.cook(
        request(
          '**bold** and *italic*\n\n`**protected** :smile:`\n\n:smile:\n\n[spoiler]secret[/spoiler]',
        ),
      );
      expect(result.failure, isNull);
      expect(result.html, contains('<strong>bold</strong>'));
      expect(result.html, contains('<em>italic</em>'));
      expect(result.html, contains('<code>**protected** :smile:</code>'));
      expect(result.html, contains('emoji'));
      expect(result.html, contains('spoiler'));
      expect(result.memoryUsageBytes, greaterThan(0));
    });

    test('post and chat select different heading rules', () async {
      final post = await service.cook(request('# title'));
      final chat = await service.cook(
        request('# title', profile: CookingProfile.chat),
      );
      expect(post.html, contains('<h1'));
      expect(chat.html, isNot(contains('<h1')));
      expect(chat.html, contains('# title'));
    });

    test('missing metadata stays readable without host APIs', () async {
      final result = await service.cook(
        request(
          '@unknown #unknown\n\n![missing](upload://notknown.png)\n\nhttps://missing.example/topic',
        ),
      );
      expect(result.failure, isNull);
      expect(result.html, contains('unknown'));
      expect(result.html, contains('missing'));
      expect(result.html, contains('https://missing.example/topic'));
    });

    test(
      'final policy strips executable cached html_raw onebox hoists',
      () async {
        const url = 'https://hostile.example/';
        final result = await service.cook(
          request(
            url,
            context: snapshot(
              oneboxes: {
                url:
                    '<aside class="onebox"><script>alert(1)</script><img src="https://safe.example/a" onerror="alert(2)"><iframe src="https://evil.example"></iframe><a href="javascript:alert(3)">safe text</a></aside>',
              },
            ),
          ),
        );
        expect(result.failure, isNull);
        expect(result.html, contains('safe text'));
        expect(
          result.html,
          isNot(
            matches(
              RegExp(
                r'<script|<iframe|onerror|javascript:',
                caseSensitive: false,
              ),
            ),
          ),
        );
      },
    );

    test('site and account context cannot leak between requests', () async {
      final a = snapshot(
        emoji: {'private_emoji': 'https://a.example/private.png'},
      );
      final b = snapshot(site: 'b', account: 'bob');
      final first = await service.cook(request(':private_emoji:', context: a));
      final second = await service.cook(request(':private_emoji:', context: b));
      final third = await service.cook(
        request(':private_emoji:', context: snapshot(account: 'charlie')),
      );
      expect(first.html, contains('private.png'));
      expect(second.html, isNot(contains('private.png')));
      expect(third.html, isNot(contains('private.png')));
      expect(second.html, contains(':private_emoji:'));
    });
  });

  test('limits reject raw and snapshot bytes before starting', () async {
    final service = OfflineCookingService(
      limits: const CookingLimits(maxRawCodeUnits: 5, maxRequestBytes: 1024),
    );
    addTearDown(service.dispose);
    expect(
      (await service.cook(request('<script>'))).failure,
      CookingFailure.inputLimit,
    );
    expect(
      (await service.cook(
        request('ok', context: snapshot(emoji: {'large': 'x' * 2048})),
      )).failure,
      CookingFailure.inputLimit,
    );
    expect(service.startupMicroseconds, 0);
  });

  test('pending work is bounded while worker starts', () async {
    final service = OfflineCookingService(
      limits: const CookingLimits(maxPending: 1),
    );
    addTearDown(service.dispose);
    final first = service.cook(request('first'));
    final second = await service.cook(request('second'));
    expect(second.failure, CookingFailure.busy);
    expect((await first).failure, isNull);
  });

  test('worker enforces execution deadline with a readable timeout', () async {
    final service = OfflineCookingService(
      limits: const CookingLimits(executionTimeout: Duration(milliseconds: 1)),
    );
    addTearDown(service.dispose);
    expect(await service.start(), isTrue);
    final result = await service.cook(request('**bounded work** ' * 1000));
    expect(result.failure, CookingFailure.timeout);
    expect(result.html, startsWith('<pre>'));
  });

  test('output error is readable and next cook recovers on fresh VM', () async {
    final service = OfflineCookingService(
      limits: const CookingLimits(maxOutputBytes: 256),
    );
    addTearDown(service.dispose);
    final failed = await service.cook(request('x' * 500));
    expect(failed.failure, CookingFailure.outputLimit);
    expect(failed.html, startsWith('<pre>'));
    expect((await service.cook(request('ok'))).html, contains('<p>ok</p>'));
  });

  test('dispose resolves all admitted queued callers', () async {
    final service = OfflineCookingService();
    expect(await service.start(), isTrue);
    final pending = List.generate(4, (i) => service.cook(request('queued $i')));
    // Let each cook continuation send its request without yielding to events.
    await Future<void>.value();
    await service.dispose();
    for (final result in await Future.wait(pending)) {
      expect(result.failure, CookingFailure.disposed);
    }
  });

  test(
    'dispose during startup resolves callers and remains idempotent',
    () async {
      final service = OfflineCookingService();
      final pending = service.cook(request('<unsafe>'));
      await service.dispose();
      expect((await pending).failure, CookingFailure.disposed);
      await service.dispose();
      expect(await service.start(), isFalse);
      expect(
        (await service.cook(request('later'))).failure,
        CookingFailure.disposed,
      );
    },
  );
}
