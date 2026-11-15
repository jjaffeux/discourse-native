import 'dart:convert';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/own_avatar_overrides.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_card_target.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/media_pipeline.dart';

const _site = 'https://meta.example';
const _letter = '/letter_avatar_proxy/v4/letter/r/a587f6/{size}.png';
const _uploaded = '/user_avatar/meta.example/reader/{size}/91_2.png';
const _second = '/user_avatar/meta.example/reader/{size}/92_2.png';

String _at(String template, int size) =>
    '$_site${template.replaceAll('{size}', '$size')}';

final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  late SiteLifecycle lifecycle;
  late OwnAvatarOverrides overrides;
  late int notifications;

  setUp(() {
    lifecycle = SiteLifecycle();
    overrides = OwnAvatarOverrides();
    notifications = 0;
    overrides.addListener(() => notifications++);
    addTearDown(overrides.dispose);
  });

  void replace(String previous, String current, {String username = 'Reader'}) =>
      overrides.record(
        _site,
        lifecycle.capture(_site),
        username: username,
        previous: previous,
        current: current,
      );

  test('a replaced picture is redrawn at the size its row was read at', () {
    replace(_letter, _uploaded);

    expect(notifications, 1);
    for (final size in [45, 90, 240]) {
      expect(
        overrides.urlFor(_site, 'reader', _at(_letter, size)),
        _at(_uploaded, size),
      );
    }
    expect(
      overrides.urlFor(_site, 'READER', _at(_letter, 90)),
      _at(_uploaded, 90),
      reason: 'a row may spell the name as the site first sent it',
    );
  });

  test('another person, another picture and another site are left alone', () {
    replace(_letter, _uploaded);

    expect(
      overrides.urlFor(_site, 'rival', _at(_letter, 90)),
      _at(_letter, 90),
      reason: 'a letter avatar is shared by everyone with its letter and color',
    );
    expect(
      overrides.urlFor(_site, 'reader', _at(_second, 90)),
      _at(_second, 90),
      reason: 'a row read after a later change is newer than this record',
    );
    expect(
      overrides.urlFor(_site, 'reader', '$_site/uploads/flair.png'),
      '$_site/uploads/flair.png',
    );
    expect(
      overrides.urlFor('https://other.example', 'reader', _at(_letter, 90)),
      _at(_letter, 90),
    );
    expect(overrides.urlFor(_site, 'reader', null), isNull);
    expect(overrides.urlFor(_site, null, _at(_letter, 90)), _at(_letter, 90));
  });

  test('each change follows the one before, and going back is not a loop', () {
    replace(_letter, _uploaded);
    replace(_uploaded, _second);

    expect(
      overrides.urlFor(_site, 'reader', _at(_letter, 90)),
      _at(_second, 90),
    );
    expect(
      overrides.urlFor(_site, 'reader', _at(_uploaded, 90)),
      _at(_second, 90),
    );

    replace(_second, _letter);

    expect(
      overrides.urlFor(_site, 'reader', _at(_letter, 90)),
      _at(_letter, 90),
    );
    expect(
      overrides.urlFor(_site, 'reader', _at(_second, 90)),
      _at(_letter, 90),
    );
    expect(notifications, 3);
  });

  test('a cdn template is matched in the form it was resolved to', () {
    const cdn = '//cdn.example/user_avatar/meta.example/reader/{size}/9_2.png';
    replace(cdn, _uploaded);

    expect(
      overrides.urlFor(
        _site,
        'reader',
        'https://cdn.example/user_avatar/meta.example/reader/120/9_2.png',
      ),
      _at(_uploaded, 120),
    );
  });

  test('a change that changed nothing, or is unknown, records nothing', () {
    replace(_letter, _letter);
    overrides
      ..record(
        _site,
        lifecycle.capture(_site),
        username: 'reader',
        previous: null,
        current: _uploaded,
      )
      ..record(
        _site,
        lifecycle.capture(_site),
        username: 'reader',
        previous: _letter,
        current: null,
      );

    expect(notifications, 0);
    expect(
      overrides.urlFor(_site, 'reader', _at(_letter, 90)),
      _at(_letter, 90),
    );
  });

  test('a change accepted for a retired session is ignored', () {
    final stale = lifecycle.capture(_site);
    lifecycle.invalidate(_site);

    overrides.record(
      _site,
      stale,
      username: 'reader',
      previous: _letter,
      current: _uploaded,
    );

    expect(notifications, 0);
    expect(
      overrides.urlFor(_site, 'reader', _at(_letter, 90)),
      _at(_letter, 90),
    );
  });

  test('an account change clears the site and leaves the others', () {
    const other = 'https://other.example';
    replace(_letter, _uploaded);
    overrides.record(
      other,
      lifecycle.capture(other),
      username: 'reader',
      previous: _letter,
      current: _uploaded,
    );
    notifications = 0;

    overrides.accountChanged(_site);

    expect(notifications, 1);
    expect(
      overrides.urlFor(_site, 'reader', _at(_letter, 90)),
      _at(_letter, 90),
    );
    expect(
      overrides.urlFor(
        other,
        'reader',
        '$other${_letter.replaceAll('{size}', '90')}',
      ),
      '$other${_uploaded.replaceAll('{size}', '90')}',
    );

    overrides.forget(_site);
    expect(notifications, 1, reason: 'nothing was held to forget');
  });

  test('a new account on the site does not inherit the last one\'s record', () {
    replace(_letter, _uploaded);
    replace(_letter, _second, username: 'rival');

    expect(
      overrides.urlFor(_site, 'reader', _at(_letter, 90)),
      _at(_letter, 90),
    );
    expect(
      overrides.urlFor(_site, 'rival', _at(_letter, 90)),
      _at(_second, 90),
    );
    expect(
      overrides.urlFor(_site, 'rival', _at(_uploaded, 90)),
      _at(_uploaded, 90),
    );
  });

  testWidgets(
    'a loaded row of the reader redraws alone when their picture changes',
    (tester) async {
      final requested = <String>[];
      installTestMediaPipeline(
        client: MockClient((request) async {
          requested.add('${request.url}');
          return http.Response.bytes(
            _pixel,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      const user = DiscourseUser(id: 7, username: 'Reader');
      final controller = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.example').copyWith(user: user),
        ]),
        api: FakeDiscourseApi(user: user),
        authenticator: FakeAuthenticator()..keys[_site] = 'key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(controller.dispose);
      await tester.runAsync(controller.load);

      Widget row(String username) => UserCardTarget.avatar(
        key: ValueKey(username),
        username: username,
        siteUrl: _site,
        child: AvatarImage(
          url: _at(_letter, 90),
          size: 45,
          fallback: const SizedBox.shrink(),
        ),
      );
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Column(
              children: [
                row('reader'),
                row('rival'),
                AvatarImage(
                  key: const ValueKey('unowned'),
                  url: _at(_letter, 90),
                  size: 45,
                  fallback: const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(requested, [_at(_letter, 90)]);

      var shellNotifications = 0;
      void count() => shellNotifications++;
      controller.addListener(count);
      addTearDown(() => controller.removeListener(count));
      final rebuilt = <Element>{};
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        rebuilt.add(element);
        previous?.call(element, builtOnce);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);

      controller.ownAvatars.record(
        _site,
        controller.lifecycle.capture(_site),
        username: 'Reader',
        previous: _letter,
        current: _uploaded,
      );
      await tester.pump();
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      debugOnRebuildDirtyWidget = previous;

      expect(requested, [_at(_letter, 90), _at(_uploaded, 90)]);
      expect(shellNotifications, 0);
      final own = tester.element(
        find.descendant(
          of: find.byKey(const ValueKey('reader')),
          matching: find.byType(AvatarImage),
        ),
      );
      expect(rebuilt.where((element) => element.widget is AvatarImage), [
        own,
      ], reason: 'the other person and the unowned picture keep theirs');

      controller.ownAvatars.accountChanged(_site);
      await tester.pump();
      expect(
        requested,
        hasLength(2),
        reason: 'the row is drawn again from the picture it was read with',
      );
    },
  );
}
