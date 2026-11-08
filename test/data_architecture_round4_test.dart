import 'dart:async';
import 'dart:io';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/data/application_cooking.dart';
import 'package:discourse_native/src/data/current_user_refresh.dart';
import 'package:discourse_native/src/data/discourse_request_coordinator.dart';
import 'package:discourse_native/src/data/request_intent.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/foundation/private_file_staging.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _site = 'https://forum.example';
const _user = DiscourseUser(id: 1, username: 'reader');

ComposerUploadFile _file() => ComposerUploadFile(
  name: 'image.png',
  length: () async => 3,
  openRead: () => Stream.value([1, 2, 3]),
);

void main() {
  test('prepared upload disposal is admitted before release reentry', () async {
    late final PreparedComposerUpload upload;
    Future<void>? joined;
    var releases = 0;
    upload = PreparedComposerUpload(
      _file(),
      release: () {
        releases++;
        if (releases == 1) joined = upload.dispose();
        return Future.value();
      },
    );
    final first = upload.dispose();
    await Future.wait([first, joined!]);
    expect(releases, 1);
    expect(joined, same(first));
  });

  test(
    'prepared upload synchronous cleanup failure settles one shared future',
    () async {
      final error = StateError('release failed');
      var releases = 0;
      final upload = PreparedComposerUpload(
        _file(),
        release: () {
          releases++;
          throw error;
        },
      );
      Future<void>? first;
      expect(() {
        first = upload.dispose();
      }, returnsNormally);
      await expectLater(first, throwsA(same(error)));
      final second = upload.dispose();
      await expectLater(second, throwsA(same(error)));
      expect(second, same(first));
      expect(releases, 1);
    },
  );

  test(
    'normal cooking rejects context-retired work before service admission',
    () async {
      final plugins = PluginInstaller.install(const PluginManifest([]));
      final service = _CookingService();
      final app = ApplicationCooking(
        plugins: plugins.cookingPlugins,
        service: service,
      );
      addTearDown(app.dispose);
      addTearDown(plugins.close);
      final request = app.request(
        siteUrl: _site,
        accountId: '1',
        raw: 'old',
        config: const SiteConfig.unknown(),
      );
      app.contextChanged(_site);
      expect(app.isCurrent(request), isFalse);
      expect((await app.cook(request)).failure, CookingFailure.stale);
      expect(service.calls, 0);
    },
  );

  test(
    'normal cooking retains the result admitted before context retirement',
    () async {
      final plugins = PluginInstaller.install(const PluginManifest([]));
      final service = _CookingService()..gate = Completer<CookingResult>();
      final app = ApplicationCooking(
        plugins: plugins.cookingPlugins,
        service: service,
      );
      addTearDown(app.dispose);
      addTearDown(plugins.close);
      final request = app.request(
        siteUrl: _site,
        accountId: '1',
        raw: 'accepted',
        config: const SiteConfig.unknown(),
      );
      final pending = app.cook(request);
      app.contextChanged(_site);
      final accepted = CookingResult(html: '<p>accepted</p>');
      service.gate!.complete(accepted);
      expect(await pending, same(accepted));
      expect(service.calls, 1);
    },
  );

  test(
    'ordinary interactive refresh joins promote the admitted request only',
    () async {
      final coordinator = DiscourseRequestCoordinator(
        maxConcurrentPerOrigin: 1,
      );
      addTearDown(coordinator.close);
      final release = Completer<http.Response>();
      final blocker = coordinator.run(
        Uri.parse('$_site/blocker'),
        () => release.future,
      );
      final order = <String>[];
      final competitor = RequestIntent.background().run(
        () => coordinator.run(Uri.parse('$_site/background'), () async {
          order.add('background');
          return http.Response('{}', 200);
        }),
      );
      final refresh = CurrentUserRefresh(
        lease: SiteLifecycle().capture(_site),
        read: () async {
          await coordinator.run(Uri.parse('$_site/current'), () async {
            order.add('refresh');
            return http.Response('{}', 200);
          });
          return _user;
        },
      );
      addTearDown(refresh.retire);
      final background = RequestIntent.background();
      final original = background.run(() => refresh.request());
      final joined = refresh.request();
      release.complete(http.Response('{}', 200));
      await Future.wait([blocker, competitor, original, joined]);
      expect(order, ['refresh', 'background']);
      expect(background.isInteractive, isFalse);
    },
  );

  test(
    'forced refresh replay retains its callers intent independently',
    () async {
      final firstResult = Completer<DiscourseUser?>();
      final intents = <RequestIntent>[];
      final refresh = CurrentUserRefresh(
        lease: SiteLifecycle().capture(_site),
        read: () {
          intents.add(RequestIntent.current);
          return intents.length == 1 ? firstResult.future : Future.value(_user);
        },
      );
      addTearDown(refresh.retire);
      final first = RequestIntent.background().run(() => refresh.request());
      final forcedBackground = RequestIntent.background();
      final forced = forcedBackground.run(() => refresh.request(force: true));
      final interactive = refresh.request(force: true);
      firstResult.complete(_user);
      await Future.wait([first, forced, interactive]);
      expect(intents, hasLength(2));
      expect(intents.first.isInteractive, isFalse);
      expect(intents.last.isInteractive, isTrue);
      expect(forcedBackground.isInteractive, isFalse);
    },
  );

  test(
    'ordinary refresh adoption leaves a forced background replay unchanged',
    () async {
      final firstResult = Completer<DiscourseUser?>();
      final intents = <RequestIntent>[];
      final refresh = CurrentUserRefresh(
        lease: SiteLifecycle().capture(_site),
        read: () {
          intents.add(RequestIntent.current);
          return intents.length == 1 ? firstResult.future : Future.value(_user);
        },
      );
      addTearDown(refresh.retire);
      final background = RequestIntent.background();
      final first = background.run(() => refresh.request());
      final forcedBackground = RequestIntent.background();
      final forced = forcedBackground.run(() => refresh.request(force: true));
      final joined = refresh.request();
      firstResult.complete(_user);
      await Future.wait([first, forced, joined]);
      expect(intents.map((intent) => intent.isInteractive), [true, false]);
      expect(background.isInteractive, isFalse);
      expect(forcedBackground.isInteractive, isFalse);
    },
  );

  test(
    'private staging owns the accepted share payload and cleans it up',
    () async {
      final parent = await Directory.systemTemp.createTemp('round4-share-');
      addTearDown(() => parent.delete(recursive: true));
      final submitted = [1, 2, 3];
      final sharing = withStagedPrivateFile(
        parent,
        submitted,
        prefix: 'share-',
        filename: 'report.bin',
        use: (file) => file.readAsBytes(),
      );
      submitted[0] = 99;
      expect(await sharing, [1, 2, 3]);
      expect(parent.listSync(), isEmpty);
    },
  );
}

final class _CookingService implements CookingServicePort {
  int calls = 0;
  Completer<CookingResult>? gate;
  @override
  Future<bool> start() async => true;
  @override
  Future<CookingResult> cook(CookingRequest request) {
    calls++;
    return gate?.future ?? Future.value(CookingResult(html: request.raw));
  }

  @override
  Future<CookingResult> cookTransient(
    CookingRequest request, {
    required Future<void> abortTrigger,
  }) => cook(request);
  @override
  void invalidate() {}
  @override
  Future<void> dispose() async {}
}
