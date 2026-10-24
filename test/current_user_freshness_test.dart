import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/do_not_disturb.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader', draftCount: 9);

final class _GatedFreshnessApi extends FakeDiscourseApi {
  _GatedFreshnessApi({super.doNotDisturbUntil})
    : super(
        user: _user,
        feeds: const {'/latest.json': []},
        topics: {
          for (var id = 1; id <= 5; id++)
            id: topicPayload(
              id: id,
              title: 'Draft topic $id',
              canCreatePost: true,
              draft: const ComposerDraft(reply: 'Previously saved reply'),
              draftSequence: 4,
            ),
        },
      );

  final started = List.generate(3, (_) => Completer<void>());
  final responses = List.generate(3, (_) => Completer<DiscourseUser>());
  Completer<DateTime>? pauseResponse;
  final pauseStarted = Completer<void>();

  @override
  Future<DateTime> enterDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    required DoNotDisturbDuration duration,
    String? clientId,
  }) {
    if (pauseResponse case final response?) {
      doNotDisturbDurations.add(duration);
      pauseStarted.complete();
      return response.future;
    }
    return super.enterDoNotDisturb(
      siteUrl: siteUrl,
      apiKey: apiKey,
      duration: duration,
      clientId: clientId,
    );
  }

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    final index = currentUserRequests.length;
    currentUserRequests.add(siteUrl);
    started[index].complete();
    return responses[index].future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a fresh account read reconciles a pause changed on another device',
    () async {
      final api = _GatedFreshnessApi(doNotDisturbUntil: DateTime.utc(2040));
      final shell = await _loadShell(api);
      await _completeRead(api, 0, _user);

      expect(
        await shell.doNotDisturb.pause(
          _site,
          DoNotDisturbOption.oneHour.duration,
        ),
        isNull,
      );
      expect(
        shell.currentInstance?.user?.doNotDisturbUntil,
        DateTime.utc(2040),
      );

      await _discardDraft(shell, 1);
      await api.started[1].future;
      final remoteUntil = DateTime.utc(2041);
      await _completeRead(api, 1, _user.withDoNotDisturbUntil(remoteUntil));

      expect(shell.currentInstance?.user?.doNotDisturbUntil, remoteUntil);
      expect(shell.doNotDisturb.stateFor(_site).until, remoteUntil);
      expect(await shell.doNotDisturb.resume(_site), isNull);
      expect(api.doNotDisturbResumes, [_site]);
      expect(shell.currentInstance?.user?.doNotDisturbUntil, isNull);
    },
  );

  test(
    'a later read restores a longer remote pause after local expiry',
    () async {
      var now = DateTime.utc(2030);
      final localUntil = now.add(const Duration(minutes: 30));
      final api = _GatedFreshnessApi();
      final shell = await _loadShell(
        api,
        clock: () => now,
        user: _user.withDoNotDisturbUntil(localUntil),
      );
      await _completeRead(api, 0, _user.withDoNotDisturbUntil(localUntil));
      now = now.add(const Duration(minutes: 31));
      shell.doNotDisturb.checkExpirations();
      _expectPause(shell, null);

      await _discardDraft(shell, 1);
      await api.started[1].future;
      final remoteUntil = now.add(const Duration(hours: 2));
      await _completeRead(api, 1, _user.withDoNotDisturbUntil(remoteUntil));
      _expectPause(shell, remoteUntil);
      expect(await shell.doNotDisturb.resume(_site), isNull);
      expect(api.doNotDisturbResumes, [_site]);
      _expectPause(shell, null);
    },
  );

  test(
    'an equal live event protects an older read while later reads reconcile',
    () async {
      final localUntil = DateTime.utc(2040);
      final api = _GatedFreshnessApi();
      final shell = await _loadShell(
        api,
        user: _user.withDoNotDisturbUntil(localUntil),
      );
      shell.doNotDisturb.applyMessage(_site, {
        'ends_at': localUntil.toIso8601String(),
      });
      await _completeRead(api, 0, _user);
      _expectPause(shell, localUntil);

      await _discardDraft(shell, 1);
      await api.started[1].future;
      await _completeRead(api, 1, _user);
      _expectPause(shell, null);
    },
  );

  for (final succeeds in [true, false]) {
    test(
      'a write ${succeeds ? 'success' : 'failure'} protects an older read',
      () async {
        final localUntil = DateTime.utc(2030);
        final confirmedUntil = DateTime.utc(2040);
        final api = _GatedFreshnessApi()..pauseResponse = Completer<DateTime>();
        final shell = await _loadShell(
          api,
          user: _user.withDoNotDisturbUntil(localUntil),
        );
        final pause = shell.doNotDisturb.pause(
          _site,
          DoNotDisturbOption.oneHour.duration,
        );
        await api.pauseStarted.future;
        _settlePause(api, succeeds, confirmedUntil);
        expect(await pause, succeeds ? isNull : 'Not saved');
        final heldUntil = succeeds ? confirmedUntil : localUntil;
        await _completeRead(api, 0, _user);
        _expectPause(shell, heldUntil);

        await _discardDraft(shell, 1);
        await api.started[1].future;
        await _completeRead(api, 1, _user);
        _expectPause(shell, null);
      },
    );

    for (final settlesBeforeRead in [true, false]) {
      test(
        'a read begun during a ${succeeds ? 'successful' : 'failed'} write stays stale ${settlesBeforeRead ? 'after' : 'before'} settlement',
        () async {
          final localUntil = DateTime.utc(2030);
          final confirmedUntil = DateTime.utc(2040);
          final api = _GatedFreshnessApi()
            ..pauseResponse = Completer<DateTime>();
          final shell = await _loadShell(
            api,
            user: _user.withDoNotDisturbUntil(localUntil),
          );
          await _completeRead(api, 0, _user.withDoNotDisturbUntil(localUntil));
          final pause = shell.doNotDisturb.pause(
            _site,
            DoNotDisturbOption.oneHour.duration,
          );
          await api.pauseStarted.future;
          await _discardDraft(shell, 1);
          await api.started[1].future;
          if (!settlesBeforeRead) {
            await _completeRead(api, 1, _user);
            _expectPause(shell, localUntil);
          }
          _settlePause(api, succeeds, confirmedUntil);
          expect(await pause, succeeds ? isNull : 'Not saved');
          final heldUntil = succeeds ? confirmedUntil : localUntil;
          if (settlesBeforeRead) await _completeRead(api, 1, _user);
          _expectPause(shell, heldUntil);

          await _discardDraft(shell, 2);
          await api.started[2].future;
          await _completeRead(api, 2, _user);
          _expectPause(shell, null);
        },
      );
    }
  }

  test(
    'disconnect retires both a pending DND write and its account read',
    () async {
      final api = _GatedFreshnessApi()..pauseResponse = Completer<DateTime>();
      final shell = await _loadShell(api);
      final pause = shell.doNotDisturb.pause(
        _site,
        DoNotDisturbOption.oneHour.duration,
      );
      await api.pauseStarted.future;
      expect(await shell.disconnectInstance(_site), isTrue);
      api.pauseResponse!.complete(DateTime.utc(2040));
      expect(await pause, isNull);
      await _completeRead(
        api,
        0,
        _user.withDoNotDisturbUntil(DateTime.utc(2041)),
      );
      expect(shell.currentInstance?.user, isNull);
      expect(shell.doNotDisturb.stateFor(_site).until, isNull);
      expect(shell.doNotDisturb.stateFor(_site).saving, isFalse);
    },
  );

  test(
    'unlisted draft discards share a freshness replay and publish its count',
    () async {
      final api = _GatedFreshnessApi();
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(user: _user),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[_site] = 'account-key',
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        initialRootMode: ShellRootMode.forum,
      );
      addTearDown(shell.dispose);
      await shell.load();
      await api.started[0].future;

      Future<void> discard(int id) async {
        shell.pushContent(
          ContentRoute.topic(
            topicId: id,
            slug: 'draft-$id',
            title: 'Draft topic $id',
          ),
        );
        await shell.loadTopic(id, 'draft-$id');
        shell.openReply();
        final composer = shell.visibleComposer!;
        expect(await shell.finishComposerDraftRestore(composer), isTrue);
        expect(await shell.discardComposer(composer), isNull);
        await Future<void>.delayed(Duration.zero);
      }

      for (var id = 1; id <= 3; id++) {
        await discard(id);
      }
      expect(api.currentUserRequests, hasLength(1));
      expect(shell.draftList.feedFor(_site).loaded, isFalse);
      api.responses[0].complete(_user);
      await api.started[1].future;
      expect(api.currentUserRequests, hasLength(2));

      await discard(4);
      await discard(5);
      api.responses[1].complete(_user.withDraftCount(6));
      await api.started[2].future;
      expect(api.currentUserRequests, hasLength(3));
      api.responses[2].complete(_user.withDraftCount(2));
      await Future<void>.delayed(Duration.zero);
      expect(api.userDraftsDeleted, hasLength(5));
      expect(shell.currentInstance?.user?.draftCount, 2);
      expect(shell.draftCountFor(_site), 2);
      expect(api.currentUserRequests, hasLength(3));
    },
  );
}

Future<ShellController> _loadShell(
  _GatedFreshnessApi api, {
  DiscourseUser user = _user,
  DateTime Function()? clock,
}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'account-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    initialRootMode: ShellRootMode.forum,
    clock: clock,
  );
  addTearDown(shell.dispose);
  addTearDown(() {
    final pause = api.pauseResponse;
    if (pause != null && !pause.isCompleted) pause.complete(DateTime.utc(2040));
    for (final response in api.responses) {
      if (!response.isCompleted) response.complete(_user);
    }
  });
  await shell.load();
  await api.started[0].future;
  return shell;
}

Future<void> _completeRead(
  _GatedFreshnessApi api,
  int index,
  DiscourseUser user,
) async {
  api.responses[index].complete(user);
  await Future<void>.delayed(Duration.zero);
}

void _expectPause(ShellController shell, DateTime? until) {
  expect(shell.currentInstance?.user?.doNotDisturbUntil, until);
  expect(shell.doNotDisturb.stateFor(_site).until, until);
}

void _settlePause(_GatedFreshnessApi api, bool succeeds, DateTime until) {
  if (succeeds) {
    api.pauseResponse!.complete(until);
  } else {
    api.pauseResponse!.completeError(
      const WriteException(WriteFailure.validation, errors: ['Not saved']),
    );
  }
}

Future<void> _discardDraft(ShellController shell, int id) async {
  shell.pushContent(
    ContentRoute.topic(
      topicId: id,
      slug: 'draft-$id',
      title: 'Draft topic $id',
    ),
  );
  await shell.loadTopic(id, 'draft-$id');
  shell.openReply();
  final composer = shell.visibleComposer!;
  expect(await shell.finishComposerDraftRestore(composer), isTrue);
  expect(await shell.discardComposer(composer), isNull);
}
