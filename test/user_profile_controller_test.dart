import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/models/user_profile.dart';
import 'package:discourse_native/src/shell/user_profile_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://one.example';
const _otherUrl = 'https://two.example';
const _site = DiscourseInstance(
  url: _siteUrl,
  title: 'One',
  user: DiscourseUser(username: 'reader'),
);
const _visitor = DiscourseInstance(url: _siteUrl, title: 'One');
const _other = DiscourseInstance(url: _otherUrl, title: 'Two');

UserProfile _profile(String username, {String? bio, bool hidden = false}) =>
    UserProfile(
      card: UserCard(username: username),
      bioCooked: bio,
      hidden: hidden,
    );

final class _ProfileRequest {
  _ProfileRequest(this.siteUrl, this.username, this.apiKey);

  final String siteUrl;
  final String username;
  final String? apiKey;
  final Completer<UserProfile> result = Completer<UserProfile>();
}

final class _GatedProfilesApi implements UserProfilesApi {
  final List<_ProfileRequest> requests = [];

  @override
  Future<UserProfile> userProfile({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  }) {
    final request = _ProfileRequest(siteUrl, username, apiKey);
    requests.add(request);
    return request.result.future;
  }
}

final class _Keys implements SiteApiKeyReader {
  _Keys([this.key = 'key']);

  final String? key;

  @override
  Future<String?> apiKeyFor(String siteUrl) async => key;
}

final class _GatedKeys implements SiteApiKeyReader {
  final List<Completer<String?>> results = [];

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    final result = Completer<String?>();
    results.add(result);
    return result.future;
  }
}

({
  _GatedProfilesApi api,
  SiteLifecycle lifecycle,
  UserProfileController controller,
})
_harness({SiteApiKeyReader? credentials}) {
  final api = _GatedProfilesApi();
  final lifecycle = SiteLifecycle();
  final controller = UserProfileController(
    api: api,
    credentials: credentials ?? _Keys(),
    lifecycle: lifecycle,
  );
  addTearDown(controller.dispose);
  return (api: api, lifecycle: lifecycle, controller: controller);
}

void main() {
  test('a profile loads once and is found under any casing', () async {
    final (:api, :controller, lifecycle: _) = _harness();
    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(controller.stateFor(_siteUrl, 'sam'), isNull);
    final load = controller.load(_site, 'Sam');
    await pumpEventQueue();
    expect(controller.stateFor(_siteUrl, 'sam'), isA<UserProfileLoading>());
    api.requests.single.result.complete(_profile('Sam', bio: '<p>Hi</p>'));
    await load;

    expect(api.requests.single.username, 'Sam');
    expect(api.requests.single.apiKey, 'key');
    expect(
      controller.stateFor(_siteUrl, 'SAM'),
      isA<UserProfileLoaded>().having(
        (state) => state.profile.bioCooked,
        'bio',
        '<p>Hi</p>',
      ),
    );
    expect(notifications, 2);

    await controller.load(_site, 'sam');
    expect(api.requests, hasLength(1));
  });

  test('a visitor with no key still asks a public site', () async {
    final (:api, :controller, lifecycle: _) = _harness(
      credentials: _Keys(null),
    );

    final load = controller.load(_visitor, 'sam');
    await pumpEventQueue();
    expect(api.requests.single.apiKey, isNull);
    api.requests.single.result.complete(_profile('sam'));
    await load;

    expect(controller.stateFor(_siteUrl, 'sam'), isA<UserProfileLoaded>());
  });

  test('a hidden profile is its own state and keeps its identity', () async {
    final (:api, :controller, lifecycle: _) = _harness();

    final load = controller.load(_site, 'quiet');
    await pumpEventQueue();
    api.requests.single.result.complete(_profile('quiet', hidden: true));
    await load;

    expect(
      controller.stateFor(_siteUrl, 'quiet'),
      isA<UserProfileHidden>().having(
        (state) => state.profile.card.username,
        'username',
        'quiet',
      ),
    );
  });

  for (final (name, error, matcher) in <(String, Object, Matcher)>[
    (
      'a 404 is a missing person',
      const SiteLookupException(
        SiteLookupFailure.unreachable,
        _siteUrl,
        statusCode: 404,
      ),
      isA<UserProfileMissing>(),
    ),
    (
      'a refusal is forbidden',
      const SiteLookupException(
        SiteLookupFailure.notDiscourse,
        _siteUrl,
        statusCode: 403,
      ),
      isA<UserProfileForbidden>(),
    ),
    (
      'an unreachable site names its host',
      const SiteLookupException(SiteLookupFailure.unreachable, _siteUrl),
      isA<UserProfileFailed>().having(
        (state) => state.message,
        'message',
        "Couldn't reach one.example.",
      ),
    ),
    (
      'any other failure names the person',
      StateError('decode'),
      isA<UserProfileFailed>().having(
        (state) => state.message,
        'message',
        "Couldn't load @sam.",
      ),
    ),
  ]) {
    test(name, () async {
      final (:api, :controller, lifecycle: _) = _harness();

      final load = controller.load(_site, 'sam');
      await pumpEventQueue();
      api.requests.single.result.completeError(error);
      await load;

      expect(controller.stateFor(_siteUrl, 'sam'), matcher);
    });
  }

  test(
    'a retry replaces a failure and a failed refresh keeps the page',
    () async {
      final (:api, :controller, lifecycle: _) = _harness();

      final first = controller.load(_site, 'sam');
      await pumpEventQueue();
      api.requests.last.result.completeError(
        const SiteLookupException(SiteLookupFailure.unreachable, _siteUrl),
      );
      await first;
      expect(controller.stateFor(_siteUrl, 'sam'), isA<UserProfileFailed>());

      final retry = controller.load(_site, 'sam', refresh: true);
      await pumpEventQueue();
      expect(controller.stateFor(_siteUrl, 'sam'), isA<UserProfileLoading>());
      api.requests.last.result.complete(_profile('sam', bio: 'first'));
      await retry;

      final refresh = controller.load(_site, 'sam', refresh: true);
      await pumpEventQueue();
      expect(controller.stateFor(_siteUrl, 'sam'), isA<UserProfileLoaded>());
      api.requests.last.result.completeError(
        const SiteLookupException(SiteLookupFailure.unreachable, _siteUrl),
      );
      await refresh;
      expect(
        controller.stateFor(_siteUrl, 'sam'),
        isA<UserProfileLoaded>().having(
          (state) => state.profile.bioCooked,
          'bio',
          'first',
        ),
      );

      final gone = controller.load(_site, 'sam', refresh: true);
      await pumpEventQueue();
      api.requests.last.result.completeError(
        const SiteLookupException(
          SiteLookupFailure.unreachable,
          _siteUrl,
          statusCode: 404,
        ),
      );
      await gone;
      expect(controller.stateFor(_siteUrl, 'sam'), isA<UserProfileMissing>());
    },
  );

  test('people and forums are held apart', () async {
    final (:api, :controller, lifecycle: _) = _harness();

    final loads = [
      controller.load(_site, 'sam'),
      controller.load(_site, 'alice'),
      controller.load(_other, 'sam'),
    ];
    await pumpEventQueue();
    api.requests[2].result.complete(_profile('sam', bio: 'two'));
    api.requests[1].result.complete(_profile('alice', bio: 'alice'));
    api.requests[0].result.complete(_profile('sam', bio: 'one'));
    await Future.wait(loads);

    String? bio(String site, String username) =>
        (controller.stateFor(site, username) as UserProfileLoaded)
            .profile
            .bioCooked;
    expect(bio(_siteUrl, 'sam'), 'one');
    expect(bio(_siteUrl, 'alice'), 'alice');
    expect(bio(_otherUrl, 'sam'), 'two');
  });

  test(
    'a response for the former account cannot replace the newer one',
    () async {
      final (:api, :controller, :lifecycle) = _harness();
      var notifications = 0;

      final former = controller.load(_site, 'sam');
      await pumpEventQueue();
      lifecycle.invalidate(_siteUrl);
      expect(controller.stateFor(_siteUrl, 'sam'), isNull);

      final current = controller.load(_site, 'sam');
      await pumpEventQueue();
      api.requests.last.result.complete(_profile('sam', bio: 'current'));
      await current;

      controller.addListener(() => notifications++);
      api.requests.first.result.complete(_profile('sam', bio: 'former'));
      await former;

      expect(
        controller.stateFor(_siteUrl, 'sam'),
        isA<UserProfileLoaded>().having(
          (state) => state.profile.bioCooked,
          'bio',
          'current',
        ),
      );
      expect(notifications, 0);
    },
  );

  test(
    'a failure for the former account cannot replace the newer one',
    () async {
      final (:api, :controller, :lifecycle) = _harness();

      final former = controller.load(_site, 'sam');
      await pumpEventQueue();
      lifecycle.invalidate(_siteUrl);
      final current = controller.load(_site, 'sam');
      await pumpEventQueue();
      api.requests.last.result.complete(_profile('sam', bio: 'current'));
      await current;
      api.requests.first.result.completeError(
        const SiteLookupException(
          SiteLookupFailure.unreachable,
          _siteUrl,
          statusCode: 404,
        ),
      );
      await former;

      expect(controller.stateFor(_siteUrl, 'sam'), isA<UserProfileLoaded>());
    },
  );

  test('a response after the lease retires is dropped', () async {
    final (:api, :controller, :lifecycle) = _harness();

    final load = controller.load(_site, 'sam');
    await pumpEventQueue();
    lifecycle.invalidate(_siteUrl);
    api.requests.single.result.complete(_profile('sam'));
    await load;

    expect(controller.stateFor(_siteUrl, 'sam'), isNull);
  });

  test('rotation while the key is read sends no request', () async {
    final credentials = _GatedKeys();
    final (:api, :controller, :lifecycle) = _harness(credentials: credentials);

    final load = controller.load(_site, 'sam');
    await pumpEventQueue();
    lifecycle.invalidate(_siteUrl);
    credentials.results.single.complete('former-key');
    await load;

    expect(api.requests, isEmpty);
    expect(controller.stateFor(_siteUrl, 'sam'), isNull);
  });

  test('retirement drops a loaded profile and tells listeners', () async {
    final (:api, :controller, :lifecycle) = _harness();
    final load = controller.load(_site, 'sam');
    await pumpEventQueue();
    api.requests.single.result.complete(_profile('sam'));
    await load;
    var notifications = 0;
    controller.addListener(() => notifications++);

    lifecycle.invalidate(_siteUrl);

    expect(controller.stateFor(_siteUrl, 'sam'), isNull);
    expect(notifications, 1);
  });

  test('a response after disposal is dropped', () async {
    final api = _GatedProfilesApi();
    final controller = UserProfileController(
      api: api,
      credentials: _Keys(),
      lifecycle: SiteLifecycle(),
    );

    final load = controller.load(_site, 'sam');
    await pumpEventQueue();
    controller.dispose();
    api.requests.single.result.complete(_profile('sam'));

    await expectLater(load, completes);
  });
}
