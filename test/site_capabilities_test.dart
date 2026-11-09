import 'dart:async';

import 'package:discourse_native/src/data/site_message_bus_bootstrap.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');
const _canCreateTag = TopicComposerCapabilities(canCreateTag: true);
const _catalog = SitePostActionCatalog(
  postFlags: [
    PostFlagType(
      id: 3,
      nameKey: 'off_topic',
      name: 'Off-Topic',
      description: '<p>Not relevant to the discussion.</p>',
      appliesTo: ['Post'],
      system: true,
    ),
  ],
);

typedef _CapabilityRead = ({
  String apiKey,
  Completer<TopicComposerCapabilities> answer,
});

final class _GatedCapabilitiesApi extends FakeDiscourseApi {
  _GatedCapabilitiesApi() : super(user: _user);

  final reads = <_CapabilityRead>[];

  @override
  Future<TopicComposerCapabilities> topicComposerCapabilities({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    final read = (
      apiKey: apiKey,
      answer: Completer<TopicComposerCapabilities>(),
    );
    reads.add(read);
    return read.answer.future;
  }
}

Future<ShellController> _loadShell(
  FakeDiscourseApi api, {
  FakeAuthenticator? authenticator,
}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org', user: _user),
    ]),
    api: api,
    authenticator: authenticator ?? (FakeAuthenticator()..keys[_site] = 'key'),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  await pumpEventQueue();
  return shell;
}

void main() {
  test('overlapping composer reads ask once and share its answer', () async {
    final api = _GatedCapabilitiesApi();
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);

    final first = shell.prepareTopicTagEditor(_site);
    await pumpEventQueue();
    final second = shell.prepareTopicTagEditor(_site);
    await pumpEventQueue();

    final overlappingReads = api.reads.length;
    // ignore: avoid_print
    print(
      'PERF_PROOF site-capabilities-owner '
      'overlapping_reads=$overlappingReads',
    );
    for (final read in api.reads) {
      read.answer.complete(_canCreateTag);
    }

    expect(overlappingReads, 1);
    expect((await first).canCreateTag, isTrue);
    expect((await second).canCreateTag, isTrue);
  });

  test('removing a forum forgets all of its capabilities', () async {
    final api = FakeDiscourseApi(
      user: _user,
      categoryPostActionCatalog: _catalog,
      composerCapabilities: _canCreateTag,
      messageBusBootstrapResult: SiteMessageBusBootstrap(
        currentUser: _user,
        currentUserState: null,
        topicTrackingState: null,
        topicTrackingLastIds: const {},
        notificationChannelPosition: null,
        serverPluginNames: const {'discourse-bbcode-color'},
      ),
    );
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);
    await shell.prepareTopicTagEditor(_site);
    expect(shell.supportsComposerColors(_site), isTrue);
    expect(shell.postFlagTypesFor(_site), _catalog.postFlags);
    expect(shell.topicComposerCapabilities(_site).canCreateTag, isTrue);

    await shell.removeInstance(shell.currentInstance!);
    await pumpEventQueue();

    final retained =
        shell.supportsComposerColors(_site) ||
        shell.postFlagTypesFor(_site).isNotEmpty ||
        shell.topicComposerCapabilities(_site).canCreateTag;
    // ignore: avoid_print
    print(
      'PERF_PROOF site-capabilities-owner '
      'retained_after_remove=${retained ? 1 : 0}',
    );
    expect(retained, isFalse);
  });

  test('a read a retired account started cannot publish', () async {
    final api = _GatedCapabilitiesApi();
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);
    final retired = shell.prepareTopicTagEditor(_site);
    await pumpEventQueue();

    shell.lifecycle.invalidate(_site);
    api.reads.single.answer.complete(_canCreateTag);
    await retired;

    expect(shell.topicComposerCapabilities(_site).canCreateTag, isFalse);
  });

  test('a new account at the same URL gets its own read', () async {
    final api = _GatedCapabilitiesApi();
    final authenticator = FakeAuthenticator()..keys[_site] = 'old-key';
    final shell = await _loadShell(api, authenticator: authenticator);
    addTearDown(shell.dispose);
    final retired = shell.prepareTopicTagEditor(_site);
    await pumpEventQueue();

    shell.lifecycle.invalidate(_site);
    authenticator.keys[_site] = 'next-key';
    final successor = shell.prepareTopicTagEditor(_site);
    await pumpEventQueue();

    expect(api.reads.map((read) => read.apiKey), ['old-key', 'next-key']);

    api.reads.first.answer.complete(_canCreateTag);
    await retired;
    final joined = shell.prepareTopicTagEditor(_site);
    await pumpEventQueue();

    expect(
      api.reads,
      hasLength(2),
      reason:
          "the retired read's late settlement left the successor's in place",
    );
    expect(shell.topicComposerCapabilities(_site).canCreateTag, isFalse);

    api.reads.last.answer.complete(
      const TopicComposerCapabilities(maxTagLength: 9),
    );

    expect((await successor).maxTagLength, 9);
    expect((await joined).maxTagLength, 9);
  });

  test('a failed read leaves the site free to ask again', () async {
    final api = _GatedCapabilitiesApi();
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);
    final failed = shell.prepareTopicTagEditor(_site);
    await pumpEventQueue();

    api.reads.single.answer.completeError(StateError('offline'));
    expect((await failed).canCreateTag, isFalse);

    final retry = shell.prepareTopicTagEditor(_site);
    await pumpEventQueue();

    expect(api.reads, hasLength(2));
    api.reads.last.answer.complete(_canCreateTag);
    expect((await retry).canCreateTag, isTrue);
  });
}
