import 'dart:async';

import 'package:discourse_native/src/data/bookmark_reminder_store.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/data/recent_destinations_store.dart';
import 'package:discourse_native/src/data/topic_recommendations_tab_store.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/data/user_directory_column_width_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/emoji_usage.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_proofreading_preferences.dart';
import 'package:discourse_native/src/plugins/voice/voice_preferences.dart';
import 'package:discourse_native/src/shell/forum_settings_controller.dart';
import 'package:discourse_native/src/shell/global_search_models.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/site_appearance_fixtures.dart';

const _siteUrl = 'https://meta.discourse.org';
const _publicConfig = SiteConfig(minPersonalMessagePostLength: 10);

final class _AccountFeedApi extends FakeDiscourseApi {
  _AccountFeedApi(this.firstGate)
    : super(
        user: DiscourseUser(
          id: 2,
          username: 'account-b',
          doNotDisturbUntil: DateTime.utc(2040),
        ),
      );

  final Completer<void> firstGate;
  int requests = 0;

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    requests++;
    if (requests == 1) {
      await firstGate.future;
      return const TopicList(
        topics: [Topic(id: 1, title: 'Private to A', slug: 'private-a')],
      );
    }
    return const TopicList(
      topics: [Topic(id: 2, title: 'Visible to B', slug: 'visible-b')],
    );
  }
}

final class _GatedAuthenticator extends FakeAuthenticator {
  _GatedAuthenticator(this.gate);

  final Completer<void> gate;
  final started = Completer<void>();

  @override
  Future<UserApiCredentials> authorize(String siteUrl) async {
    connected.add(siteUrl);
    started.complete();
    await gate.future;
    return const UserApiCredentials(
      key: 'new-account-key',
      apiVersion: 4,
      push: false,
    );
  }
}

final class _GatedAuthFailureAuthenticator extends FakeAuthenticator {
  _GatedAuthFailureAuthenticator(this.gate);

  final Completer<void> gate;
  final started = Completer<void>();

  @override
  Future<UserApiCredentials> authorize(String siteUrl) async {
    connected.add(siteUrl);
    started.complete();
    await gate.future;
    throw const UserApiAuthException(UserApiAuthFailure.launchFailed);
  }
}

final class _GatedCurrentUserApi extends FakeDiscourseApi {
  _GatedCurrentUserApi(this.currentUserGate);

  final Completer<void> currentUserGate;
  final started = Completer<void>();
  final List<String> revokedKeys = [];

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    started.complete();
    await currentUserGate.future;
    throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
  }

  @override
  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    revokedKeys.add(apiKey);
  }
}

final class _ConnectRaceAppearanceApi extends FakeDiscourseApi {
  _ConnectRaceAppearanceApi({
    required this.initialAnonymousAppearance,
    required this.racingAnonymousAppearance,
    required this.accountAppearance,
  });

  final SiteAppearance initialAnonymousAppearance;
  final SiteAppearance racingAnonymousAppearance;
  final SiteAppearance accountAppearance;
  final initialAppearanceStarted = Completer<void>();
  final currentUserStarted = Completer<void>();
  final finishCurrentUser = Completer<void>();
  final racingAppearanceStarted = Completer<void>();
  final finishRacingAppearance = Completer<void>();
  final accountAppearanceStarted = Completer<void>();
  final List<({String? apiKey, String? clientId})> targetAppearanceRequests =
      [];
  final List<String?> targetAppearanceUsernames = [];
  int _anonymousAppearanceRequests = 0;

  @override
  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) async {
    if (siteUrl != _siteUrl) return null;
    targetAppearanceRequests.add((apiKey: apiKey, clientId: clientId));
    targetAppearanceUsernames.add(username);

    if (apiKey != null) {
      if (!accountAppearanceStarted.isCompleted) {
        accountAppearanceStarted.complete();
      }
      return accountAppearance;
    }

    _anonymousAppearanceRequests++;
    if (_anonymousAppearanceRequests == 1) {
      initialAppearanceStarted.complete();
      return initialAnonymousAppearance;
    }

    if (!racingAppearanceStarted.isCompleted) {
      racingAppearanceStarted.complete();
    }
    await finishRacingAppearance.future;
    return racingAnonymousAppearance;
  }

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    currentUserStarted.complete();
    await finishCurrentUser.future;
    return const DiscourseUser(id: 2, username: 'account-b');
  }
}

final class _RollbackAppearanceApi extends FakeDiscourseApi {
  _RollbackAppearanceApi({
    required this.authenticator,
    required this.signedOutAppearance,
    required this.accountAppearance,
  });

  final FakeAuthenticator authenticator;
  final SiteAppearance signedOutAppearance;
  final SiteAppearance accountAppearance;
  final initialAppearanceStarted = Completer<void>();
  final revocationStarted = Completer<void>();
  final finishRevocation = Completer<void>();
  final List<({String? apiKey, bool credentialsDiscarded})> appearanceRequests =
      [];

  @override
  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) async {
    appearanceRequests.add((
      apiKey: apiKey,
      credentialsDiscarded:
          authenticator.disconnected.contains(siteUrl) &&
          !authenticator.keys.containsKey(siteUrl),
    ));
    if (!initialAppearanceStarted.isCompleted) {
      initialAppearanceStarted.complete();
    }
    return apiKey == null ? signedOutAppearance : accountAppearance;
  }

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
  }

  @override
  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    if (!revocationStarted.isCompleted) revocationStarted.complete();
    await finishRevocation.future;
  }
}

final class _DisconnectAppearanceApi extends FakeDiscourseApi {
  _DisconnectAppearanceApi({
    required this.signedOutAppearance,
    required this.accountAppearance,
  });

  final SiteAppearance signedOutAppearance;
  final SiteAppearance accountAppearance;
  final initialAppearanceStarted = Completer<void>();
  final signedOutAppearanceStarted = Completer<void>();
  final List<({String? apiKey, String? clientId})> appearanceRequests = [];
  final List<({String? apiKey, String? clientId})> configRequests = [];
  final List<({String? apiKey, String? clientId})> customEmojiRequests = [];

  @override
  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) async {
    appearanceRequests.add((apiKey: apiKey, clientId: clientId));
    if (appearanceRequests.length == 1) {
      initialAppearanceStarted.complete();
    } else if (!signedOutAppearanceStarted.isCompleted) {
      signedOutAppearanceStarted.complete();
    }
    return apiKey == null ? signedOutAppearance : accountAppearance;
  }

  @override
  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    configRequests.add((apiKey: apiKey, clientId: clientId));
    return const SiteConfig.unknown();
  }

  @override
  Future<Map<String, String>> customEmojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    customEmojiRequests.add((apiKey: apiKey, clientId: clientId));
    return const {};
  }
}

final class _DisconnectRaceAppearanceApi extends FakeDiscourseApi {
  _DisconnectRaceAppearanceApi({
    required this.initialAccountAppearance,
    required this.racingAccountAppearance,
    required this.signedOutAppearance,
  });

  final SiteAppearance initialAccountAppearance;
  final SiteAppearance racingAccountAppearance;
  final SiteAppearance signedOutAppearance;
  final initialAppearanceStarted = Completer<void>();
  final revocationStarted = Completer<void>();
  final finishRevocation = Completer<void>();
  final racingAppearanceStarted = Completer<void>();
  final finishRacingAppearance = Completer<void>();
  final signedOutAppearanceStarted = Completer<void>();
  final List<({String? apiKey, String? clientId})> targetAppearanceRequests =
      [];
  int _accountAppearanceRequests = 0;

  @override
  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) async {
    if (siteUrl != _siteUrl) return null;
    targetAppearanceRequests.add((apiKey: apiKey, clientId: clientId));
    if (apiKey == null) {
      if (!signedOutAppearanceStarted.isCompleted) {
        signedOutAppearanceStarted.complete();
      }
      return signedOutAppearance;
    }

    _accountAppearanceRequests++;
    if (_accountAppearanceRequests == 1) {
      initialAppearanceStarted.complete();
      return initialAccountAppearance;
    }
    if (!racingAppearanceStarted.isCompleted) {
      racingAppearanceStarted.complete();
    }
    await finishRacingAppearance.future;
    return racingAccountAppearance;
  }

  @override
  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    if (!revocationStarted.isCompleted) revocationStarted.complete();
    await finishRevocation.future;
  }
}

final class _GatedRevocationApi extends FakeDiscourseApi {
  _GatedRevocationApi(this.firstGate)
    : super(user: const DiscourseUser(id: 2, username: 'account-b'));

  final Completer<void> firstGate;
  final firstStarted = Completer<void>();
  final List<String> revokedKeys = [];

  @override
  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    revokedKeys.add(apiKey);
    if (revokedKeys.length != 1) return;
    firstStarted.complete();
    await firstGate.future;
  }
}

final class _UnreachableRevocationApi extends FakeDiscourseApi {
  _UnreachableRevocationApi()
    : super(user: const DiscourseUser(id: 7, username: 'reader'));

  @override
  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
  }
}

final class _GatedTopicApi extends FakeDiscourseApi {
  _GatedTopicApi(this._requestGate);

  final Completer<void> _requestGate;
  final started = Completer<void>();

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) async {
    started.complete();
    await _requestGate.future;
    return topicPayload(id: id, title: 'First site title');
  }
}

final class _GatedAccountHealingApi extends FakeDiscourseApi {
  _GatedAccountHealingApi(this.accountGate);

  final Completer<void> accountGate;
  final started = Completer<void>();

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    started.complete();
    await accountGate.future;
    return const DiscourseUser(id: 42, username: 'account-a');
  }
}

final class _RecordingInstanceStore extends FakeInstanceStore {
  _RecordingInstanceStore(super.instances);

  final List<List<DiscourseInstance>> snapshots = [];

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    snapshots.add(List.of(instances));
    await super.save(instances);
  }
}

final class _CurrentUserObserverModule implements PluginModule {
  const _CurrentUserObserverModule(this.observers);

  final List<PluginCurrentUserObserver> observers;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('current-user-observer-test'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession(
      (_, _) => PluginSessionContribution(
        lifecycle: _TestPluginSessionLifecycle(),
        capabilities: observers,
      ),
      requires: const [],
    );
  }
}

final class _TestPluginSessionLifecycle extends PluginSessionLifecycle {}

final class _RequestHostModule implements PluginModule {
  final host = Completer<PluginRequestHost>();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('request-host-test'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession((bindings, _) {
      if (!host.isCompleted) {
        host.complete(bindings.require(corePluginRequestPort));
      }
      return PluginSessionContribution(
        lifecycle: _TestPluginSessionLifecycle(),
      );
    }, requires: const [corePluginRequestPort]);
  }
}

final class _ThrowingCurrentUserObserver implements PluginCurrentUserObserver {
  const _ThrowingCurrentUserObserver(this.calls);

  final List<String> calls;

  @override
  void pluginCurrentUserRefreshed(String siteUrl) {
    calls.add('throwing:$siteUrl');
    throw StateError('observer failed');
  }
}

final class _RecordingCurrentUserObserver implements PluginCurrentUserObserver {
  _RecordingCurrentUserObserver(this.calls);

  final List<String> calls;
  final called = Completer<String>();

  @override
  void pluginCurrentUserRefreshed(String siteUrl) {
    calls.add('recording:$siteUrl');
    if (!called.isCompleted) called.complete(siteUrl);
  }
}

final class _GatedInstanceStore extends FakeInstanceStore {
  _GatedInstanceStore(super.instances, this.gate);

  final Completer<void> gate;
  final Completer<void> loadStarted = Completer<void>();
  int loadCount = 0;

  @override
  Future<List<DiscourseInstance>> load() async {
    loadCount++;
    if (!loadStarted.isCompleted) loadStarted.complete();
    await gate.future;
    return super.load();
  }
}

final class _FailingConnectedSaveStore extends FakeInstanceStore {
  _FailingConnectedSaveStore(super.instances);

  int saveAttempts = 0;
  bool failedConnectedSnapshot = false;

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    saveAttempts++;
    if (!failedConnectedSnapshot && instances.any((item) => item.isConnected)) {
      failedConnectedSnapshot = true;
      throw StateError('preferences unavailable');
    }
    await super.save(instances);
  }
}

final class _FailingRemovalSaveStore extends FakeInstanceStore {
  _FailingRemovalSaveStore(super.instances);

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    if (!instances.any((item) => item.url == _siteUrl)) {
      throw StateError('preferences unavailable');
    }
    await super.save(instances);
  }
}

/// Writes a snapshot without the target site at once, but acknowledges it
/// only after [releaseRemoval].
final class _HeldRemovalSaveStore extends FakeInstanceStore {
  _HeldRemovalSaveStore(super.instances);

  final removalHeld = Completer<void>();
  final releaseRemoval = Completer<void>();

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    await super.save(instances);
    if (!removalHeld.isCompleted &&
        !instances.any((item) => item.url == _siteUrl)) {
      removalHeld.complete();
      await releaseRemoval.future;
    }
  }
}

/// Keeps one value of every preference that core, Voice and Discourse AI keep
/// per forum, through the stores that keep them; the shell's own where it
/// holds what they read.
Future<void> _keepSitePreferences(ShellController shell, String siteUrl) async {
  await const BookmarkReminderStore().write(
    siteUrl,
    'Reader.Name',
    DateTime.utc(2030),
  );
  await shell.emojiPickerStore.writeSkinTone(
    siteUrl: siteUrl,
    tone: EmojiSkinTone.t3,
  );
  await shell.emojiPickerStore.trackEmoji(
    siteUrl: siteUrl,
    context: CoreEmojiUsageContexts.topic,
    emoji: 'tada',
  );
  await shell.forumSettings.setThemeMode(siteUrl, AppThemeMode.dark);
  await shell.forumSettings.setThemes(
    siteUrl,
    ForumThemePreferences.preset('dracula'),
  );
  await shell.sidebarSections.write(
    siteUrl: siteUrl,
    sectionId: 'community',
    collapsed: true,
  );
  await shell.topicSidebar.write(siteUrl: siteUrl, collapsed: true);
  await const TopicRecommendationsTabStore().write(
    siteUrl: siteUrl,
    sourceId: coreSuggestedTopicRecommendationSourceId,
  );
  await const UserDirectoryColumnWidthStore().write(
    siteUrl: siteUrl,
    widths: UserDirectoryColumnWidths(const {'likes_received': 120}),
  );
  const voice = SharedPreferencesVoicePreferences();
  await voice.writeCameraEnabled(siteUrl, 7, true);
  await voice.writeParticipantVolume(siteUrl, 3, 8, 0.5);
  await const AiProofreadingPreferenceStore().write(
    siteUrl: siteUrl,
    userId: 7,
    enabled: true,
  );
}

/// Every stored key that names [siteUrl].
Future<Set<String>> _storedPreferencesOf(String siteUrl) async => {
  for (final key in (await SharedPreferences.getInstance()).getKeys())
    if (key.contains(Uri.encodeComponent(siteUrl))) key,
};

/// Once [holdResponses] is set, the target site's category and client-settings
/// responses wait for [releaseResponses].
final class _HeldPublicPresentationApi extends FakeDiscourseApi {
  _HeldPublicPresentationApi()
    : super(
        categoryList: [
          TopicCategory.fromJson(const {
            'id': 12,
            'name': 'Plants',
            'slug': 'plants',
            'color': '00aa44',
          }),
        ],
        siteConfigs: const {_siteUrl: _publicConfig},
      );

  bool holdResponses = false;
  final categoriesHeld = Completer<void>();
  final releaseResponses = Completer<void>();

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async {
    if (holdResponses && siteUrl == _siteUrl) {
      if (!categoriesHeld.isCompleted) categoriesHeld.complete();
      await releaseResponses.future;
    }
    return super.loadCategories(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      page: page,
    );
  }

  @override
  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    if (holdResponses && siteUrl == _siteUrl) await releaseResponses.future;
    return super.siteConfig(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}

const _refusedKey = 'refused-account-key';

/// Fails every account read made with [_refusedKey] with [readFailure]; a key
/// issued by signing in again reads the account normally.
final class _FailingAccountReadApi extends FakeDiscourseApi {
  _FailingAccountReadApi(this.readFailure, {this.failureGate});

  final SiteLookupException readFailure;
  final Completer<void>? failureGate;
  final failedReadStarted = Completer<void>();
  final List<String> failedReads = [];

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    if (apiKey == _refusedKey) {
      if (!failedReadStarted.isCompleted) failedReadStarted.complete();
      await failureGate?.future;
      failedReads.add(siteUrl);
      throw readFailure;
    }
    return super.currentUser(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}

/// Records the credential each feed, topic and search read carried.
final class _CredentialRecordingApi extends FakeDiscourseApi {
  _CredentialRecordingApi()
    : super(
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'Topic', slug: 'topic')],
        },
        topics: {
          7: topicPayload(
            id: 7,
            title: 'Topic',
            posts: const [
              Post(
                id: 70,
                postNumber: 1,
                username: 'author',
                cooked: '<p>Body</p>',
                canLike: true,
              ),
            ],
          ),
        },
      );

  final List<String?> feedKeys = [];
  final List<String?> topicKeys = [];
  final List<String?> searchKeys = [];
  final List<String?> searchClientIds = [];

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) {
    feedKeys.add(apiKey);
    return super.topicList(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) {
    topicKeys.add(apiKey);
    return super.topic(
      siteUrl: siteUrl,
      slug: slug,
      id: id,
      postNumber: postNumber,
      summary: summary,
      apiKey: apiKey,
      clientId: clientId,
      abortTrigger: abortTrigger,
    );
  }

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    if (!Uri.parse(path).path.startsWith('/search')) {
      return super.pluginGetJson(
        siteUrl: siteUrl,
        path: path,
        apiKey: apiKey,
        clientId: clientId,
      );
    }
    searchKeys.add(apiKey);
    searchClientIds.add(clientId);
    return <String, dynamic>{};
  }
}

/// A platform whose push registration never answers: an Apple notification
/// permission prompt left open, or APNs out of reach.
final class _UnansweredClientIdAuthenticator extends FakeAuthenticator {
  int clientIdReads = 0;

  @override
  Future<String> clientId() {
    clientIdReads++;
    return Completer<String>().future;
  }
}

final class _HeldCredentialDeleteAuthenticator extends FakeAuthenticator {
  final deletionStarted = Completer<void>();
  final finishDeletion = Completer<void>();

  @override
  Future<void> disconnect(String siteUrl) async {
    deletionStarted.complete();
    await finishDeletion.future;
    await super.disconnect(siteUrl);
  }
}

/// Answers every key read with what storage held when it was asked. Reads
/// asked while [hold] is in force wait for its release, like a platform read
/// that has already found nothing and whose answer is still on its way back.
final class _HeldKeyReadAuthenticator extends FakeAuthenticator {
  Completer<void>? _hold;
  int heldReads = 0;
  Completer<void>? authorizeGate;
  final authorizeStarted = Completer<void>();

  Completer<void> hold() => _hold = Completer<void>();

  void stopHolding() => _hold = null;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    final hold = _hold;
    if (hold != null) heldReads++;
    final answer = await super.apiKeyFor(siteUrl);
    await hold?.future;
    return answer;
  }

  @override
  Future<UserApiCredentials> authorize(String siteUrl) async {
    if (!authorizeStarted.isCompleted) authorizeStarted.complete();
    await authorizeGate?.future;
    return super.authorize(siteUrl);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('instance initialization', () {
    test(
      'waits for the initial stored snapshot before adding a site',
      () async {
        final gate = Completer<void>();
        final stored = instance('stored.example.com');
        final added = instance('added.example.com');
        final instanceStore = _GatedInstanceStore([stored], gate);
        final shell = ShellController(
          instanceStore: instanceStore,
          api: FakeDiscourseApi(),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        final loading = shell.load();
        await instanceStore.loadStarted.future;
        final adding = shell.addInstance(added);
        await Future<void>.delayed(Duration.zero);

        expect(instanceStore.loadCount, 1);
        expect(instanceStore.saveCount, 0);
        expect(shell.instances, isEmpty);

        gate.complete();
        await Future.wait([loading, adding]);

        expect(shell.instances, [stored, added]);
        expect(await instanceStore.load(), [stored, added]);
      },
    );
  });

  group('account refresh isolation', () {
    test(
      'keeps a stale account response from replacing the new account feed',
      () async {
        final firstGate = Completer<void>();
        final api = _AccountFeedApi(firstGate);
        final oldAccount = instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 1, username: 'account-a'));
        final authenticator = FakeAuthenticator()
          ..keys[_siteUrl] = 'account-a-key';
        final shell = ShellController(
          instanceStore: FakeInstanceStore([oldAccount]),
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        await Future<void>.delayed(Duration.zero);
        expect(api.requests, 1);

        await shell.connectCurrentInstance();
        await Future<void>.delayed(Duration.zero);
        expect(shell.currentInstance?.user?.username, 'account-b');
        expect(shell.doNotDisturb.stateFor(_siteUrl).until, DateTime.utc(2040));
        expect(shell.currentFeed?.topicIds, [2]);

        firstGate.complete();
        await Future<void>.delayed(Duration.zero);

        expect(shell.currentFeed?.topicIds, [2]);
        expect(shell.store.read<Topic>(_siteUrl, 1), isNull);
        expect(shell.store.read<Topic>(_siteUrl, 2)?.title, 'Visible to B');
      },
    );

    test(
      'prevents a reentrant disconnect from persisting healed account metadata',
      () async {
        final gate = Completer<void>();
        final api = _GatedAccountHealingApi(gate);
        final connected = instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(username: 'account-a'));
        final store = _RecordingInstanceStore([connected]);
        final authenticator = FakeAuthenticator()
          ..keys[_siteUrl] = 'account-a-key';
        final shell = ShellController(
          instanceStore: store,
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        var disconnectStarted = false;
        Future<void>? disconnecting;
        final listenerRan = Completer<void>();
        shell.addListener(() {
          if (disconnectStarted || shell.currentInstance?.user?.id != 42) {
            return;
          }
          disconnectStarted = true;
          disconnecting = shell.disconnectCurrentInstance();
          listenerRan.complete();
        });

        await shell.load();
        await api.started.future;
        gate.complete();
        await listenerRan.future;
        await disconnecting;
        await Future<void>.delayed(Duration.zero);

        expect(
          store.snapshots.where(
            (snapshot) => snapshot.any((item) => item.user?.id == 42),
          ),
          isEmpty,
        );
        expect((await store.load()).single.user, isNull);
      },
    );

    test(
      'reports and isolates a throwing plugin current-user observer',
      () async {
        final diagnostics = await DiagnosticsController.create(
          persistence: MemoryDiagnosticsPersistence(),
          sessionId: 'current-user-observer-isolation',
        );
        final diagnosticsBinding = DiagnosticsSink.install(diagnostics);
        final calls = <String>[];
        final recordingObserver = _RecordingCurrentUserObserver(calls);
        final plugins = PluginInstaller.install(
          PluginManifest([
            _CurrentUserObserverModule([
              _ThrowingCurrentUserObserver(calls),
              recordingObserver,
            ]),
          ]),
        );
        const freshUser = DiscourseUser(id: 42, username: 'fresh-account');
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            instance('meta.discourse.org').copyWith(
              user: const DiscourseUser(id: 42, username: 'stored-account'),
            ),
          ]),
          api: FakeDiscourseApi(
            user: freshUser,
            feeds: const {'/latest.json': []},
          ),
          authenticator: FakeAuthenticator()..keys[_siteUrl] = 'account-key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          plugins: plugins,
        );
        addTearDown(() async {
          shell.dispose();
          await Future<void>.delayed(Duration.zero);
          await plugins.close();
          diagnosticsBinding.close();
          await diagnostics.close();
        });

        await shell.load();
        expect(await recordingObserver.called.future, _siteUrl);
        await Future<void>.delayed(Duration.zero);

        expect(shell.freshCurrentUserFor(_siteUrl)?.username, 'fresh-account');
        expect(calls, ['throwing:$_siteUrl', 'recording:$_siteUrl']);
        final event = diagnostics.events
            .whereType<ErrorDiagnosticEvent>()
            .singleWhere(
              (candidate) =>
                  candidate.operation == 'plugins.session.currentUserRefreshed',
            );
        expect(event.source, 'shell');
        expect(event.severity, DiagnosticSeverity.warning);
        expect(event.handled, isTrue);
        expect(event.degraded, isTrue);
      },
    );

    test(
      'restores old metadata without ever pairing it with a replacement key',
      () async {
        final currentUserGate = Completer<void>();
        final api = _GatedCurrentUserApi(currentUserGate);
        final oldAccount = instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 1, username: 'account-a'));
        final store = FakeInstanceStore([oldAccount]);
        final authenticator = FakeAuthenticator(
          credentials: const UserApiCredentials(
            key: 'account-b-key',
            apiVersion: 4,
            push: false,
          ),
        )..keys[_siteUrl] = 'account-a-key';
        final shell = ShellController(
          instanceStore: store,
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        final connecting = shell.connectCurrentInstance();
        await api.started.future;

        expect(shell.currentInstance?.user, isNull);
        expect((await store.load()).single.user, isNull);
        expect(authenticator.keys[_siteUrl], 'account-a-key');

        currentUserGate.complete();
        await connecting;

        expect(shell.currentInstance?.user?.username, 'account-a');
        expect((await store.load()).single.user?.username, 'account-a');
        expect(authenticator.keys[_siteUrl], 'account-a-key');
        expect(api.revokedKeys, ['account-b-key']);
        expect(shell.connectError, isNotNull);
      },
    );
  });

  group('appearance isolation', () {
    for (final anonymousAppearanceCompletesBeforeConnect in [true, false]) {
      test(
        anonymousAppearanceCompletesBeforeConnect
            ? 'replaces an anonymous appearance completed before account lookup finishes'
            : 'rejects an anonymous appearance completed after account lookup finishes',
        () async {
          const otherSite = 'https://other.example.com';
          final initialAnonymousAppearance = siteAppearance(
            accent: const Color(0xFF112233),
          );
          final racingAnonymousAppearance = siteAppearance(
            accent: const Color(0xFF0066BB),
          );
          final accountAppearance = siteAppearance(
            accent: const Color(0xFFAA2200),
          );
          final store = FakeInstanceStore([
            instance(
              'meta.discourse.org',
            ).copyWith(appearance: initialAnonymousAppearance),
            instance('other.example.com'),
          ]);
          final authenticator = FakeAuthenticator(
            credentials: const UserApiCredentials(
              key: 'account-b-key',
              apiVersion: 4,
              push: false,
            ),
          );
          final api = _ConnectRaceAppearanceApi(
            initialAnonymousAppearance: initialAnonymousAppearance,
            racingAnonymousAppearance: racingAnonymousAppearance,
            accountAppearance: accountAppearance,
          );
          addTearDown(() {
            if (!api.finishCurrentUser.isCompleted) {
              api.finishCurrentUser.complete();
            }
            if (!api.finishRacingAppearance.isCompleted) {
              api.finishRacingAppearance.complete();
            }
          });
          final shell = ShellController(
            instanceStore: store,
            api: api,
            authenticator: authenticator,
            drafts: FakeDraftStore(),
            trackers: FakeSiteTracker.reset(),
          );
          addTearDown(shell.dispose);

          await shell.load();
          await api.initialAppearanceStarted.future;
          await Future<void>.delayed(Duration.zero);
          expect(shell.currentSiteAppearance, initialAnonymousAppearance);

          final connecting = shell.connectCurrentInstance();
          await api.currentUserStarted.future;

          // Re-entering the target while account lookup is held open starts a
          // public appearance request because the pending instance is signed out.
          shell.selectInstance(1);
          expect(shell.currentInstance?.url, otherSite);
          shell.selectInstance(0);
          await api.racingAppearanceStarted.future;

          if (anonymousAppearanceCompletesBeforeConnect) {
            api.finishRacingAppearance.complete();
            await Future<void>.delayed(Duration.zero);
            await Future<void>.delayed(Duration.zero);
            expect(shell.currentSiteAppearance, racingAnonymousAppearance);
            api.finishCurrentUser.complete();
          } else {
            api.finishCurrentUser.complete();
            await api.accountAppearanceStarted.future;
            api.finishRacingAppearance.complete();
          }

          await connecting;
          await api.accountAppearanceStarted.future;
          for (
            var attempt = 0;
            attempt < 10 && shell.currentSiteAppearance != accountAppearance;
            attempt++
          ) {
            await Future<void>.delayed(Duration.zero);
          }

          expect(shell.currentInstance?.user?.username, 'account-b');
          expect(shell.currentSiteAppearance, accountAppearance);
          expect((await store.load()).first.appearance, accountAppearance);
          expect(api.targetAppearanceRequests, [
            (apiKey: null, clientId: null),
            (apiKey: null, clientId: null),
            (apiKey: 'account-b-key', clientId: 'test-client'),
          ]);
          expect(api.targetAppearanceUsernames, [null, null, 'account-b']);
        },
      );
    }

    test(
      'never exposes an authorized but uncommitted key to appearance',
      () async {
        final signedOutAppearance = siteAppearance();
        final accountAppearance = siteAppearance(
          accent: const Color(0xFFAA2200),
        );
        final stored = instance(
          'meta.discourse.org',
        ).copyWith(appearance: signedOutAppearance);
        final store = FakeInstanceStore([stored]);
        final authenticator = FakeAuthenticator(
          credentials: const UserApiCredentials(
            key: 'discarded-account-key',
            apiVersion: 4,
            push: false,
          ),
        );
        final api = _RollbackAppearanceApi(
          authenticator: authenticator,
          signedOutAppearance: signedOutAppearance,
          accountAppearance: accountAppearance,
        );
        final shell = ShellController(
          instanceStore: store,
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        await api.initialAppearanceStarted.future;
        await Future<void>.delayed(Duration.zero);
        expect(api.appearanceRequests, [
          (apiKey: null, credentialsDiscarded: false),
        ]);

        final connecting = shell.connectCurrentInstance();
        await api.revocationStarted.future;
        await Future<void>.delayed(Duration.zero);

        // Authorization exists remotely, but the account lookup failed before
        // the coordinator committed it to local private storage.
        expect(authenticator.keys[_siteUrl], isNull);
        expect(
          api.appearanceRequests.every((request) => request.apiKey == null),
          isTrue,
        );

        api.finishRevocation.complete();
        await connecting;
        await Future<void>.delayed(Duration.zero);

        expect(authenticator.keys[_siteUrl], isNull);
        expect(api.appearanceRequests, isNotEmpty);
        expect(
          api.appearanceRequests.every((request) => request.apiKey == null),
          isTrue,
        );
        expect(shell.currentSiteAppearance, signedOutAppearance);
        expect((await store.load()).single.appearance, signedOutAppearance);
        expect(shell.connectError, isNotNull);
      },
    );

    test(
      'does not retry appearance anonymously after a failed private connection',
      () async {
        final stored = instance(
          'meta.discourse.org',
        ).copyWith(loginRequired: true);
        final store = FakeInstanceStore([stored]);
        final authenticator = FakeAuthenticator(
          credentials: const UserApiCredentials(
            key: 'discarded-account-key',
            apiVersion: 4,
            push: false,
          ),
        );
        final api = _RollbackAppearanceApi(
          authenticator: authenticator,
          signedOutAppearance: siteAppearance(),
          accountAppearance: siteAppearance(accent: const Color(0xFFAA2200)),
        );
        addTearDown(() {
          if (!api.finishRevocation.isCompleted) {
            api.finishRevocation.complete();
          }
        });
        final shell = ShellController(
          instanceStore: store,
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        await Future<void>.delayed(Duration.zero);
        expect(api.appearanceRequests, isEmpty);

        final connecting = shell.connectCurrentInstance();
        await api.revocationStarted.future;
        api.finishRevocation.complete();
        await connecting;
        await Future<void>.delayed(Duration.zero);

        expect(authenticator.keys[_siteUrl], isNull);
        expect(api.appearanceRequests, isEmpty);
        expect(shell.connectError, isNotNull);
      },
    );

    test(
      'does not authenticate signed-out appearance with an undeleted key',
      () async {
        final signedOutAppearance = siteAppearance();
        final accountAppearance = siteAppearance(
          accent: const Color(0xFFAA2200),
        );
        final stored = instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 7, username: 'account'));
        final store = FakeInstanceStore([stored]);
        final authenticator = FakeAuthenticator(
          disconnectFailure: StateError('keychain unavailable'),
        )..keys[_siteUrl] = 'orphaned-account-key';
        final api = _DisconnectAppearanceApi(
          signedOutAppearance: signedOutAppearance,
          accountAppearance: accountAppearance,
        );
        final shell = ShellController(
          instanceStore: store,
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        await api.initialAppearanceStarted.future;
        await Future<void>.delayed(Duration.zero);
        expect(api.appearanceRequests, [
          (apiKey: 'orphaned-account-key', clientId: 'test-client'),
        ]);
        expect(api.configRequests, [
          (apiKey: 'orphaned-account-key', clientId: 'test-client'),
        ]);
        expect(api.customEmojiRequests, [
          (apiKey: 'orphaned-account-key', clientId: 'test-client'),
        ]);

        expect(await shell.disconnectInstance(_siteUrl), isTrue);
        await api.signedOutAppearanceStarted.future;
        await Future<void>.delayed(Duration.zero);

        // The keychain failure deliberately leaves the key behind. Instance
        // identity, rather than key presence alone, must prevent it reaching the
        // forum document once the account has been signed out.
        expect(authenticator.keys[_siteUrl], 'orphaned-account-key');
        expect(shell.currentInstance?.user, isNull);
        expect(api.appearanceRequests.first, (
          apiKey: 'orphaned-account-key',
          clientId: 'test-client',
        ));
        expect(
          api.appearanceRequests
              .skip(1)
              .every((request) => request.apiKey == null),
          isTrue,
        );
        expect(api.configRequests.first, (
          apiKey: 'orphaned-account-key',
          clientId: 'test-client',
        ));
        expect(
          api.configRequests.skip(1).every((request) => request.apiKey == null),
          isTrue,
        );
        expect(api.customEmojiRequests.first, (
          apiKey: 'orphaned-account-key',
          clientId: 'test-client',
        ));
        expect(
          api.customEmojiRequests
              .skip(1)
              .every((request) => request.apiKey == null),
          isTrue,
        );
        expect(shell.currentSiteAppearance, signedOutAppearance);
        expect((await store.load()).single.appearance, signedOutAppearance);
        expect(api.revoked, [_siteUrl]);
      },
    );

    test(
      'blocks account appearance reads as soon as disconnect starts',
      () async {
        const otherSite = 'https://other.example.com';
        final initialAccountAppearance = siteAppearance(
          accent: const Color(0xFF112233),
        );
        final signedOutAppearance = siteAppearance(
          accent: const Color(0xFF0066BB),
        );
        final store = FakeInstanceStore([
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(id: 7, username: 'account')),
          instance('other.example.com'),
        ]);
        final authenticator = FakeAuthenticator()
          ..keys[_siteUrl] = 'account-key';
        final api = _DisconnectRaceAppearanceApi(
          initialAccountAppearance: initialAccountAppearance,
          racingAccountAppearance: siteAppearance(
            accent: const Color(0xFFAA2200),
          ),
          signedOutAppearance: signedOutAppearance,
        );
        addTearDown(() {
          if (!api.finishRevocation.isCompleted) {
            api.finishRevocation.complete();
          }
        });
        final shell = ShellController(
          instanceStore: store,
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        await api.initialAppearanceStarted.future;
        await Future<void>.delayed(Duration.zero);

        final disconnecting = shell.disconnectInstance(_siteUrl);
        await api.revocationStarted.future;
        shell.selectInstance(1);
        expect(shell.currentInstance?.url, otherSite);
        shell.selectInstance(0);
        await api.signedOutAppearanceStarted.future;

        expect(api.racingAppearanceStarted.isCompleted, isFalse);
        expect(
          api.targetAppearanceRequests
              .skip(1)
              .every((request) => request.apiKey == null),
          isTrue,
        );

        api.finishRevocation.complete();
        expect(await disconnecting, isTrue);
        await Future<void>.delayed(Duration.zero);

        expect(authenticator.keys[_siteUrl], isNull);
        expect(shell.currentInstance?.user, isNull);
        expect(shell.currentSiteAppearance, signedOutAppearance);
        expect(
          (await store.load())
              .firstWhere((instance) => instance.url == _siteUrl)
              .appearance,
          signedOutAppearance,
        );
      },
    );
  });

  group('stored key isolation', () {
    // Apple keeps Keychain items when the app is deleted, but the instance
    // list goes with it, so a re-added forum is signed out while its old key
    // is still readable. A failed deletion during sign-out leaves the same
    // state behind.
    for (final connected in [false, true]) {
      final account = connected ? 'a connected' : 'a signed-out';
      final carried = connected ? 'carry its key' : 'stay anonymous';
      test('$account forum\'s feed, topic, search and like $carried', () async {
        final stored = instance('meta.discourse.org');
        final authenticator = FakeAuthenticator()
          ..keys[_siteUrl] = 'stored-account-key';
        final api = _CredentialRecordingApi();
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            connected
                ? stored.copyWith(
                    user: const DiscourseUser(id: 7, username: 'account'),
                  )
                : stored,
          ]),
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);
        final expectedKey = connected ? 'stored-account-key' : null;

        await shell.load();
        await pumpEventQueue();
        expect(api.feedKeys, isNotEmpty);
        expect(api.feedKeys, everyElement(expectedKey));

        shell.openTopic(const Topic(id: 7, title: 'Topic', slug: 'topic'));
        await pumpEventQueue();
        expect(api.topicKeys, isNotEmpty);
        expect(api.topicKeys, everyElement(expectedKey));

        shell.globalSearch
          ..configure(
            siteUrl: _siteUrl,
            capabilities: GlobalSearchCapabilities.fromSite(
              shell.siteConfigFor(_siteUrl),
              shell.currentInstance?.user,
            ),
          )
          ..setQuery('stored account')
          ..submit();
        await pumpEventQueue();
        expect(api.searchKeys, isNotEmpty);
        expect(api.searchKeys, everyElement(expectedKey));
        expect(
          api.searchClientIds,
          everyElement(connected ? 'test-client' : null),
        );

        final post = shell.store.read<Post>(_siteUrl, 70)!;
        expect(post.canToggleLike, isTrue);
        expect(
          await shell.toggleLike(post, siteUrl: _siteUrl),
          connected
              ? isNull
              : const WriteException(WriteFailure.forbidden).message,
        );
        expect(api.liked, connected ? [70] : isEmpty);
        expect(shell.store.read<Post>(_siteUrl, 70)?.liked, connected);
        expect(shell.currentInstance?.isConnected, connected);
        expect(authenticator.keys[_siteUrl], 'stored-account-key');
      });
    }
  });

  group('signed-out client id', () {
    // Reading the client id asks Apple platforms for a push registration,
    // which raises the notification permission prompt and can wait out the
    // whole registration timeout. The site ignores the id without a key.
    test(
      'adding a public forum reads it without waiting for a client id',
      () async {
        final authenticator = _UnansweredClientIdAuthenticator();
        final api = _CredentialRecordingApi();
        final requestHost = _RequestHostModule();
        final plugins = PluginInstaller.install(PluginManifest([requestHost]));
        final shell = ShellController(
          instanceStore: FakeInstanceStore(),
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          plugins: plugins,
        );
        addTearDown(() async {
          shell.dispose();
          await Future<void>.delayed(Duration.zero);
          await plugins.close();
        });

        await shell.load();
        expect(await shell.addInstance(instance('meta.discourse.org')), isTrue);
        await pumpEventQueue();

        expect(shell.currentInstance?.url, _siteUrl);
        expect(api.feedKeys, [null]);
        expect(FakeSiteTracker.built.map((tracker) => tracker.siteUrl), [
          _siteUrl,
        ]);

        shell.globalSearch
          ..configure(
            siteUrl: _siteUrl,
            capabilities: GlobalSearchCapabilities.fromSite(
              shell.siteConfigFor(_siteUrl),
              shell.currentInstance?.user,
            ),
          )
          ..setQuery('public forum')
          ..submit();
        await pumpEventQueue();
        expect(api.searchKeys, [null]);
        expect(api.searchClientIds, [null]);

        final requests = await requestHost.host.future;
        final credentials = requests.credentialsFor(_siteUrl);
        await pumpEventQueue();
        expect(authenticator.clientIdReads, 0);
        expect((await credentials).apiKey, isNull);
        expect((await credentials).clientId, isEmpty);
      },
    );
  });

  group('refused account key', () {
    ShellController refusingShell(
      _FailingAccountReadApi api,
      FakeInstanceStore store,
      FakeAuthenticator authenticator,
    ) {
      final shell = ShellController(
        instanceStore: store,
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);
      return shell;
    }

    DiscourseInstance connected() => instance(
      'meta.discourse.org',
    ).copyWith(user: const DiscourseUser(id: 7, username: 'account'));

    test('signs the forum out and offers to sign in again', () async {
      final api = _FailingAccountReadApi(
        const ApiKeyRejectedException(_siteUrl),
      );
      final store = FakeInstanceStore([connected()]);
      final authenticator = FakeAuthenticator()..keys[_siteUrl] = _refusedKey;
      final shell = refusingShell(api, store, authenticator);

      await shell.load();
      await pumpEventQueue();

      expect(api.failedReads, isNotEmpty);
      expect(shell.currentInstance?.user, isNull);
      expect((await store.load()).single.user, isNull);
      expect(authenticator.keys[_siteUrl], isNull);
      // Nothing sent with a refused key can revoke it.
      expect(api.revoked, isEmpty);
      expect(
        shell.connectError,
        'meta.discourse.org no longer accepts this sign-in. '
        'Sign in again to continue.',
      );

      await shell.connectCurrentInstance();

      expect(shell.currentInstance?.user?.username, 'joffreyj');
      expect(authenticator.keys[_siteUrl], 'api-key');
      expect(shell.connectError, isNull);
    });

    test('a refusal landing after signing in again is ignored', () async {
      final failureGate = Completer<void>();
      final api = _FailingAccountReadApi(
        const ApiKeyRejectedException(_siteUrl),
        failureGate: failureGate,
      );
      final store = FakeInstanceStore([connected()]);
      final authenticator = FakeAuthenticator()..keys[_siteUrl] = _refusedKey;
      final shell = refusingShell(api, store, authenticator);

      await shell.load();
      await api.failedReadStarted.future;
      await shell.connectCurrentInstance();
      expect(shell.currentInstance?.user?.username, 'joffreyj');

      failureGate.complete();
      await pumpEventQueue();

      expect(api.failedReads, isNotEmpty);
      expect(shell.currentInstance?.user?.username, 'joffreyj');
      expect((await store.load()).single.user?.username, 'joffreyj');
      expect(authenticator.keys[_siteUrl], 'api-key');
      expect(shell.connectError, isNull);
    });

    final kept = <String, SiteLookupException>{
      'an unreachable site': const SiteLookupException(
        SiteLookupFailure.unreachable,
        _siteUrl,
        statusCode: 503,
      ),
      'a refusal from something other than Discourse':
          const SiteLookupException(
            SiteLookupFailure.notDiscourse,
            _siteUrl,
            statusCode: 403,
          ),
    };
    for (final MapEntry(key: name, value: failure) in kept.entries) {
      test('keeps the account through $name', () async {
        final api = _FailingAccountReadApi(failure);
        final store = FakeInstanceStore([connected()]);
        final authenticator = FakeAuthenticator()..keys[_siteUrl] = _refusedKey;
        final shell = refusingShell(api, store, authenticator);

        await shell.load();
        await pumpEventQueue();

        expect(api.failedReads, isNotEmpty);
        expect(shell.currentInstance?.user?.username, 'account');
        expect((await store.load()).single.user?.username, 'account');
        expect(authenticator.keys[_siteUrl], _refusedKey);
        expect(authenticator.disconnected, isEmpty);
        expect(shell.connectError, isNull);
      });
    }
  });

  group('missing account key', () {
    // Preferences and private storage come back apart: an iPhone set up from
    // another device's unencrypted backup gets the rail but not its Keychain
    // items, and Linux's private storage file can be lost on its own.
    const missingKeyError =
        'The sign-in for meta.discourse.org is no longer saved on this '
        'device. Sign in again to continue.';

    ShellController keylessShell(
      FakeInstanceStore store,
      FakeAuthenticator authenticator, {
      FakeDiscourseApi? api,
    }) {
      final shell = ShellController(
        instanceStore: store,
        api: api ?? FakeDiscourseApi(),
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);
      return shell;
    }

    DiscourseInstance connected() => instance(
      'meta.discourse.org',
    ).copyWith(user: const DiscourseUser(id: 7, username: 'account'));

    Future<DiscourseUser?> storedUser(FakeInstanceStore store) async =>
        (await store.load())
            .singleWhere((instance) => instance.url == _siteUrl)
            .user;

    test('signs the forum out and offers to sign in again', () async {
      final api = FakeDiscourseApi();
      final store = FakeInstanceStore([connected()]);
      final authenticator = FakeAuthenticator();
      final shell = keylessShell(store, authenticator, api: api);

      await shell.load();
      await pumpEventQueue();

      expect(shell.currentInstance?.user, isNull);
      expect(await storedUser(store), isNull);
      expect(authenticator.disconnected, [_siteUrl]);
      expect(api.revoked, isEmpty);
      expect(shell.connectError, missingKeyError);

      await shell.connectCurrentInstance();

      expect(shell.currentInstance?.user?.username, 'joffreyj');
      expect((await storedUser(store))?.username, 'joffreyj');
      expect(authenticator.keys[_siteUrl], 'api-key');
      expect(shell.connectError, isNull);
    });

    final unreadable = <String, Object>{
      'a locked Keychain': PlatformException(
        code: 'Unexpected security result code',
        details: -25308,
      ),
      'an undecodable private storage file': const FormatException(
        'Invalid private storage format',
      ),
    };
    for (final MapEntry(key: name, value: failure) in unreadable.entries) {
      test('keeps the account through $name', () async {
        final store = FakeInstanceStore([connected()]);
        final authenticator = FakeAuthenticator(apiKeyFailure: failure);
        final shell = keylessShell(store, authenticator);

        await shell.load();
        await pumpEventQueue();

        expect(shell.currentInstance?.user?.username, 'account');
        expect((await storedUser(store))?.username, 'account');
        expect(authenticator.disconnected, isEmpty);
        expect(shell.connectError, isNull);
      });
    }

    test('leaves a signed-out forum without a key alone', () async {
      final store = FakeInstanceStore([instance('meta.discourse.org')]);
      final authenticator = FakeAuthenticator();
      final shell = keylessShell(store, authenticator);

      await shell.load();
      await pumpEventQueue();

      expect(shell.currentInstance?.url, _siteUrl);
      expect(authenticator.disconnected, isEmpty);
      expect(shell.connectError, isNull);
    });

    // Selecting the forum refreshes its account, and every key read that
    // selection asks is held: each has found no key and not yet answered.
    Future<
      ({ShellController shell, FakeInstanceStore store, Completer<void> held})
    >
    selectHeld(_HeldKeyReadAuthenticator authenticator) async {
      final store = FakeInstanceStore([
        instance('try.discourse.org'),
        connected(),
      ]);
      final shell = keylessShell(store, authenticator);
      await shell.load();
      await pumpEventQueue();
      expect(shell.currentInstance?.url, 'https://try.discourse.org');

      final held = authenticator.hold();
      shell.selectInstance(1);
      authenticator.stopHolding();
      expect(shell.currentInstance?.url, _siteUrl);
      expect(authenticator.heldReads, isPositive);
      return (shell: shell, store: store, held: held);
    }

    test('a sign-in stored while an empty read is held keeps it', () async {
      final authenticator = _HeldKeyReadAuthenticator();
      final (:shell, :store, :held) = await selectHeld(authenticator);

      await shell.connectCurrentInstance();
      expect(authenticator.keys[_siteUrl], 'api-key');

      held.complete();
      await pumpEventQueue();

      expect(shell.currentInstance?.user?.username, 'joffreyj');
      expect((await storedUser(store))?.username, 'joffreyj');
      expect(authenticator.keys[_siteUrl], 'api-key');
      expect(authenticator.disconnected, isEmpty);
      expect(shell.connectError, isNull);
    });

    test(
      'an empty read answering during sign-in leaves the forum to it',
      () async {
        final authenticator = _HeldKeyReadAuthenticator()
          ..authorizeGate = Completer<void>();
        final (:shell, :store, :held) = await selectHeld(authenticator);

        final signingIn = shell.connectCurrentInstance();
        await authenticator.authorizeStarted.future;
        held.complete();
        await pumpEventQueue();
        expect(shell.currentInstance?.user?.username, 'account');

        authenticator.authorizeGate!.complete();
        await signingIn;

        expect(shell.currentInstance?.user?.username, 'joffreyj');
        expect((await storedUser(store))?.username, 'joffreyj');
        expect(authenticator.keys[_siteUrl], 'api-key');
        expect(authenticator.disconnected, isEmpty);
        expect(shell.connectError, isNull);
      },
    );
  });

  group('connection and removal operations', () {
    test(
      'remove a site despite signed-out presentation replacement during local disconnection',
      () async {
        const otherSite = 'https://other.example.com';
        final initialAccountAppearance = siteAppearance(
          accent: const Color(0xFF112233),
        );
        final signedOutAppearance = siteAppearance(
          accent: const Color(0xFF0066BB),
        );
        final connected = instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 7, username: 'account'));
        final store = FakeInstanceStore([
          connected,
          instance('other.example.com'),
        ]);
        final authenticator = _HeldCredentialDeleteAuthenticator()
          ..keys[_siteUrl] = 'account-key';
        final api = _DisconnectRaceAppearanceApi(
          initialAccountAppearance: initialAccountAppearance,
          racingAccountAppearance: siteAppearance(
            accent: const Color(0xFFAA2200),
          ),
          signedOutAppearance: signedOutAppearance,
        );
        addTearDown(() {
          if (!authenticator.finishDeletion.isCompleted) {
            authenticator.finishDeletion.complete();
          }
          if (!api.finishRevocation.isCompleted) {
            api.finishRevocation.complete();
          }
        });
        final shell = ShellController(
          instanceStore: store,
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        await api.initialAppearanceStarted.future;
        await Future<void>.delayed(Duration.zero);

        final removing = shell.removeInstance(connected);
        await authenticator.deletionStarted.future;
        shell.selectInstance(1);
        shell.selectInstance(0);
        await api.signedOutAppearanceStarted.future;

        // This anonymous response replaces the immutable signed-out instance
        // while removeInstance still holds the object supplied by its caller.
        await Future<void>.delayed(Duration.zero);
        expect(shell.currentSiteAppearance, signedOutAppearance);
        expect(api.racingAppearanceStarted.isCompleted, isFalse);

        authenticator.finishDeletion.complete();
        expect(await removing.timeout(const Duration(seconds: 1)), isTrue);
        expect(api.finishRevocation.isCompleted, isFalse);
        expect(authenticator.keys[_siteUrl], isNull);
        expect(shell.instances.map((instance) => instance.url), [otherSite]);
        expect((await store.load()).map((instance) => instance.url), [
          otherSite,
        ]);

        // Re-adding the URL in the same process must keep using public colors.
        expect(await shell.addInstance(instance('meta.discourse.org')), isTrue);
        await api.signedOutAppearanceStarted.future;
        await Future<void>.delayed(Duration.zero);

        expect(api.targetAppearanceRequests.first, (
          apiKey: 'account-key',
          clientId: 'test-client',
        ));
        expect(
          api.targetAppearanceRequests
              .skip(1)
              .every((request) => request.apiKey == null),
          isTrue,
        );
        expect(shell.currentSiteAppearance, signedOutAppearance);

        api.finishRevocation.complete();
        await pumpEventQueue();
        expect(shell.instances.map((instance) => instance.url), [
          otherSite,
          _siteUrl,
        ]);
        expect(authenticator.keys[_siteUrl], isNull);
        expect(shell.currentSiteAppearance, signedOutAppearance);
      },
    );

    test(
      'forget a removed public forum and drop its signed-out reload',
      () async {
        const otherSite = 'https://other.example.com';
        final forumTabs = FakeForumTabStore();
        final api = _HeldPublicPresentationApi();
        addTearDown(() {
          if (!api.releaseResponses.isCompleted) {
            api.releaseResponses.complete();
          }
        });
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            instance('other.example.com'),
            instance('meta.discourse.org'),
          ]),
          forumTabs: forumTabs,
          api: api,
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        // The selected forum is last on the rail, so its removal leaves no
        // forum at the old selection index.
        shell.selectInstance(1);
        // Settle the initial activation so only the removal's reload is held.
        await pumpEventQueue();
        api.holdResponses = true;

        expect(
          await shell.removeInstance(shell.instanceFor(_siteUrl)!),
          isTrue,
        );
        // The final signed-out phase re-activated the selected public forum
        // before the rail dropped it.
        expect(api.categoriesHeld.isCompleted, isTrue);

        api.releaseResponses.complete();
        await pumpEventQueue();

        expect(shell.instances.map((instance) => instance.url), [otherSite]);
        expect(shell.currentInstance?.url, otherSite);
        expect(shell.workspaceFor(_siteUrl), isNull);
        expect(forumTabs.workspaces.map((workspace) => workspace.siteUrl), [
          otherSite,
        ]);
        expect(shell.categoryFeedFor(_siteUrl).loaded, isFalse);
        expect(shell.filterCategoriesFor(_siteUrl), isEmpty);
        expect(shell.siteConfigFor(_siteUrl), const SiteConfig.unknown());

        expect(await shell.addInstance(instance('meta.discourse.org')), isTrue);
        await pumpEventQueue();

        expect(shell.workspaceFor(_siteUrl), isNotNull);
        expect(shell.categoryFeedFor(_siteUrl).loaded, isTrue);
        expect(
          shell.filterCategoriesFor(_siteUrl).map((category) => category.id),
          [12],
        );
        expect(shell.siteConfigFor(_siteUrl), _publicConfig);
      },
    );

    for (final removeSelected in [true, false]) {
      test('restore a ${removeSelected ? 'selected' : 'background'} forum '
          'whose removal cannot be saved', () async {
        const otherSite = 'https://other.example.com';
        final store = _FailingRemovalSaveStore([
          instance('meta.discourse.org'),
          instance('other.example.com'),
        ]);
        final shell = ShellController(
          instanceStore: store,
          api: _HeldPublicPresentationApi(),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        if (!removeSelected) shell.selectInstance(1);

        expect(
          await shell.removeInstance(shell.instanceFor(_siteUrl)!),
          isFalse,
        );

        expect(shell.instances.map((instance) => instance.url), [
          _siteUrl,
          otherSite,
        ]);
        expect(
          shell.currentInstance?.url,
          removeSelected ? _siteUrl : otherSite,
        );
        expect((await store.load()).map((instance) => instance.url), [
          _siteUrl,
          otherSite,
        ]);

        // The restored forum reloads under a live lifecycle, not the one
        // retired when the removal forgot its state.
        if (!removeSelected) shell.selectInstance(0);
        await pumpEventQueue();

        expect(shell.workspaceFor(_siteUrl), isNotNull);
        expect(shell.categoryFeedFor(_siteUrl).loaded, isTrue);
        expect(
          shell.filterCategoriesFor(_siteUrl).map((category) => category.id),
          [12],
        );
      });
    }

    test(
      "forget every account's Start page visits of a removed forum",
      () async {
        const otherSite = 'https://other.example.com';
        final persistence = MemoryRecentDestinationsPersistence();
        await (RecentDestinationsStore(persistence: persistence)..remember(
              _siteUrl,
              'user:former',
              ContentRoute.topic(
                topicId: 3,
                slug: 'handover',
                title: 'Handover notes',
              ),
            ))
            .save();
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            instance(
              'meta.discourse.org',
            ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
            instance('other.example.com'),
          ]),
          api: FakeDiscourseApi(),
          authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
          drafts: FakeDraftStore(),
          recentDestinations: RecentDestinationsStore(persistence: persistence),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        shell.pushContent(
          ContentRoute.topic(
            topicId: 7,
            slug: 'contract-renewal',
            title: 'Contract renewal',
          ),
        );
        shell.selectInstance(1);
        shell.pushContent(
          ContentRoute.topic(topicId: 8, slug: 'eight', title: 'Eight'),
        );
        await pumpEventQueue();
        expect(persistence.value, contains('Contract renewal'));

        expect(
          await shell.removeInstance(shell.instanceFor(_siteUrl)!),
          isTrue,
        );
        await pumpEventQueue();

        final reloaded = RecentDestinationsStore(persistence: persistence);
        await reloaded.load();
        for (final account in ['user:reader', 'user:former', 'anonymous']) {
          expect(reloaded.hasVisits(_siteUrl, account), isFalse);
        }
        expect(reloaded.topicsFor(otherSite, 'anonymous').single.topicId, 8);
        expect(persistence.value, isNot(contains('Contract renewal')));
        expect(persistence.value, isNot(contains('Handover notes')));
      },
    );

    test(
      'keep the Start page visits of a forum whose removal cannot be saved',
      () async {
        final persistence = MemoryRecentDestinationsPersistence();
        final shell = ShellController(
          instanceStore: _FailingRemovalSaveStore([
            instance('meta.discourse.org'),
            instance('other.example.com'),
          ]),
          api: FakeDiscourseApi(),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          recentDestinations: RecentDestinationsStore(persistence: persistence),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        shell.pushContent(
          ContentRoute.topic(topicId: 7, slug: 'seven', title: 'Seven'),
        );
        await pumpEventQueue();

        expect(
          await shell.removeInstance(shell.instanceFor(_siteUrl)!),
          isFalse,
        );
        await pumpEventQueue();

        expect(shell.recentTopicsFor(_siteUrl).single.topicId, 7);
        final reloaded = RecentDestinationsStore(persistence: persistence);
        await reloaded.load();
        expect(reloaded.topicsFor(_siteUrl, 'anonymous').single.topicId, 7);
      },
    );

    test(
      'keep the Start page visits of a forum re-added while its removal saves',
      () async {
        final persistence = MemoryRecentDestinationsPersistence();
        final store = _HeldRemovalSaveStore([
          instance('meta.discourse.org'),
          instance('other.example.com'),
        ]);
        addTearDown(() {
          if (!store.releaseRemoval.isCompleted) {
            store.releaseRemoval.complete();
          }
        });
        final shell = ShellController(
          instanceStore: store,
          api: FakeDiscourseApi(),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          recentDestinations: RecentDestinationsStore(persistence: persistence),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        final removing = shell.removeInstance(shell.instanceFor(_siteUrl)!);
        await store.removalHeld.future;

        expect(await shell.addInstance(instance('meta.discourse.org')), isTrue);
        // The current page is remembered again on every notification, so the
        // earlier visit is the one a stale forget would lose.
        shell.pushContent(
          ContentRoute.topic(topicId: 9, slug: 'nine', title: 'Nine'),
        );
        shell.pushContent(
          ContentRoute.topic(topicId: 10, slug: 'ten', title: 'Ten'),
        );
        store.releaseRemoval.complete();
        expect(await removing, isTrue);
        await pumpEventQueue();

        List<int?> topicIds(List<ContentRoute> routes) => [
          for (final route in routes) route.topicId,
        ];
        expect(topicIds(shell.recentTopicsFor(_siteUrl)), [10, 9]);
        final reloaded = RecentDestinationsStore(persistence: persistence);
        await reloaded.load();
        expect(topicIds(reloaded.topicsFor(_siteUrl, 'anonymous')), [10, 9]);
      },
    );

    group('stored preferences', () {
      const otherSite = 'https://other.example.com';

      setUp(
        () => SharedPreferences.setMockInitialValues({
          for (final site in [_siteUrl, otherSite])
            SharedPreferencesAiProofreadingPreferencePersistence.siteWideKeys
                    .of(site):
                true,
        }),
      );

      ShellController storedPreferencesShell(InstanceStore instanceStore) {
        final shell = ShellController(
          instanceStore: instanceStore,
          api: FakeDiscourseApi(),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          forumSettingsStore: ForumSettingsStore(),
          trackers: FakeSiteTracker.reset(),
          plugins: PluginInstaller.install(bundledPluginManifest),
        );
        addTearDown(shell.dispose);
        return shell;
      }

      test('a removed forum leaves none of its preferences', () async {
        final shell = storedPreferencesShell(
          FakeInstanceStore([
            instance('meta.discourse.org'),
            instance('other.example.com'),
          ]),
        );
        await shell.load();
        await _keepSitePreferences(shell, _siteUrl);
        await _keepSitePreferences(shell, otherSite);
        final kept = await _storedPreferencesOf(otherSite);
        expect(await _storedPreferencesOf(_siteUrl), hasLength(11));
        expect(kept, hasLength(11));

        expect(
          await shell.removeInstance(shell.instanceFor(_siteUrl)!),
          isTrue,
        );
        await pumpEventQueue();

        expect(await _storedPreferencesOf(_siteUrl), isEmpty);
        expect(await _storedPreferencesOf(otherSite), kept);
        // What was read goes too, so the forum added again starts as new.
        expect(shell.topicSidebar.collapsedFor(_siteUrl), isNull);
        expect(
          shell.sidebarSections.collapsedFor(
            siteUrl: _siteUrl,
            sectionId: 'community',
          ),
          isNull,
        );
        expect(shell.forumSettings.themeModeFor(_siteUrl), AppThemeMode.system);
        expect(
          shell.forumSettings.themesFor(_siteUrl),
          ForumThemePreferences.defaults,
        );
        expect(
          shell.emojiPickerStore.skinToneFor(siteUrl: _siteUrl),
          EmojiSkinTone.neutral,
        );
        expect(shell.topicSidebar.collapsedFor(otherSite), isTrue);
        expect(
          shell.emojiPickerStore.skinToneFor(siteUrl: otherSite),
          EmojiSkinTone.t3,
        );
      });

      test('a forum whose removal cannot be saved keeps them', () async {
        final shell = storedPreferencesShell(
          _FailingRemovalSaveStore([
            instance('meta.discourse.org'),
            instance('other.example.com'),
          ]),
        );
        await shell.load();
        await _keepSitePreferences(shell, _siteUrl);
        final kept = await _storedPreferencesOf(_siteUrl);

        expect(
          await shell.removeInstance(shell.instanceFor(_siteUrl)!),
          isFalse,
        );
        await pumpEventQueue();

        expect(await _storedPreferencesOf(_siteUrl), kept);
        expect(shell.topicSidebar.collapsedFor(_siteUrl), isTrue);
      });

      test('a forum re-added while its removal saves keeps them', () async {
        final store = _HeldRemovalSaveStore([
          instance('meta.discourse.org'),
          instance('other.example.com'),
        ]);
        addTearDown(() {
          if (!store.releaseRemoval.isCompleted) {
            store.releaseRemoval.complete();
          }
        });
        final shell = storedPreferencesShell(store);
        await shell.load();
        await _keepSitePreferences(shell, _siteUrl);
        final kept = await _storedPreferencesOf(_siteUrl);

        final removing = shell.removeInstance(shell.instanceFor(_siteUrl)!);
        await store.removalHeld.future;
        expect(await shell.addInstance(instance('meta.discourse.org')), isTrue);
        store.releaseRemoval.complete();
        expect(await removing, isTrue);
        await pumpEventQueue();

        expect(await _storedPreferencesOf(_siteUrl), kept);
      });

      for (final rail in [
        [instance('other.example.com')],
        <DiscourseInstance>[],
      ]) {
        test(
          rail.isEmpty
              ? "an empty rail keeps every forum's preferences"
              : 'a restart drops the preferences of forums off the rail',
          () async {
            final previous = storedPreferencesShell(
              FakeInstanceStore([
                instance('meta.discourse.org'),
                instance('other.example.com'),
              ]),
            );
            await previous.load();
            await _keepSitePreferences(previous, _siteUrl);
            await _keepSitePreferences(previous, otherSite);
            await previous.forumSettings.setThemeMode(
              ForumSettingsController.homeSite,
              AppThemeMode.dark,
            );
            final removed = await _storedPreferencesOf(_siteUrl);
            final kept = await _storedPreferencesOf(otherSite);
            final home = await _storedPreferencesOf(
              ForumSettingsController.homeSite,
            );
            expect(home, isNotEmpty);

            final restored = storedPreferencesShell(FakeInstanceStore(rail));
            await restored.load();

            expect(
              await _storedPreferencesOf(_siteUrl),
              rail.isEmpty ? removed : isEmpty,
            );
            expect(await _storedPreferencesOf(otherSite), kept);
            expect(
              await _storedPreferencesOf(ForumSettingsController.homeSite),
              home,
            );
          },
        );
      }
    });

    for (final removeSelected in [true, false]) {
      test('remove the tabs of a ${removeSelected ? 'selected' : 'background'} '
          'forum whose removal the site cannot confirm', () async {
        const otherSite = 'https://other.example.com';
        final forumTabs = FakeForumTabStore();
        final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            instance(
              'meta.discourse.org',
            ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
            instance('other.example.com'),
          ]),
          forumTabs: forumTabs,
          api: _UnreachableRevocationApi(),
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        shell.pushContent(
          ContentRoute.topic(topicId: 7, slug: 'seven', title: 'Seven'),
        );
        shell.createTab();
        shell.pushContent(
          ContentRoute.topic(topicId: 8, slug: 'eight', title: 'Eight'),
        );
        if (!removeSelected) shell.selectInstance(1);
        await pumpEventQueue();
        List<String> tabIds(ForumWorkspace? workspace) => [
          for (final tab in workspace?.tabs ?? const <ForumTab>[]) tab.id,
        ];
        ForumWorkspace? persisted() => forumTabs.workspaces
            .where((workspace) => workspace.siteUrl == _siteUrl)
            .singleOrNull;
        final tabs = tabIds(shell.workspaceFor(_siteUrl));
        expect(tabs, hasLength(2));
        expect(tabIds(persisted()), tabs);

        expect(
          await shell.removeInstance(shell.instanceFor(_siteUrl)!),
          isTrue,
        );
        await pumpEventQueue();

        expect(shell.instanceFor(_siteUrl), isNull);
        expect(shell.currentInstance?.url, otherSite);
        expect(shell.workspaceFor(_siteUrl), isNull);
        expect(persisted(), isNull);
        expect(authenticator.keys[_siteUrl], isNull);
        expect((await shell.instanceStore.load()).map((item) => item.url), [
          otherSite,
        ]);
      });
    }

    test(
      'roll back the account and key after a connected-profile save fails',
      () async {
        final stored = instance('meta.discourse.org');
        final store = _FailingConnectedSaveStore([stored]);
        final authenticator = FakeAuthenticator();
        final api = FakeDiscourseApi(
          user: const DiscourseUser(id: 2, username: 'account-b'),
        );
        final shell = ShellController(
          instanceStore: store,
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        await shell.connectCurrentInstance();

        expect(shell.currentInstance?.user, isNull);
        expect((await store.load()).single.user, isNull);
        expect(authenticator.keys[_siteUrl], isNull);
        expect(store.failedConnectedSnapshot, isTrue);
        expect(store.saveAttempts, greaterThanOrEqualTo(3));
        expect(api.revoked, [_siteUrl]);
        expect(shell.connectError, isNotNull);
      },
    );

    test(
      'discard a key that lands after its site is removed during browser auth',
      () async {
        final connectGate = Completer<void>();
        final authenticator = _GatedAuthenticator(connectGate);
        final stored = instance('meta.discourse.org');
        final api = FakeDiscourseApi();
        final shell = ShellController(
          instanceStore: FakeInstanceStore([stored]),
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        final connecting = shell.connectCurrentInstance();
        await authenticator.started.future;
        await shell.removeInstance(stored);

        connectGate.complete();
        await connecting;

        expect(shell.instances, isEmpty);
        expect(authenticator.keys[_siteUrl], isNull);
        expect(authenticator.disconnected, [_siteUrl]);
        expect(api.revoked, [_siteUrl]);
        expect(shell.connectError, isNull);
      },
    );

    test(
      'keep connection progress and errors with the site being connected',
      () async {
        final gate = Completer<void>();
        final authenticator = _GatedAuthFailureAuthenticator(gate);
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            instance('meta.discourse.org'),
            instance('other.example.com'),
          ]),
          api: FakeDiscourseApi(),
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        final connecting = shell.connectCurrentInstance();
        await authenticator.started.future;

        expect(shell.connecting, isTrue);
        shell.selectInstance(1);
        expect(shell.connecting, isFalse);
        expect(shell.connectError, isNull);

        gate.complete();
        await connecting;

        expect(shell.instanceIndex, 1);
        expect(shell.connecting, isFalse);
        expect(shell.connectError, isNull);

        shell.selectInstance(0);
        expect(shell.connectError, contains('Could not open'));
      },
    );

    test(
      'preserve a newer connection after an older disconnect completes',
      () async {
        final firstRevocation = Completer<void>();
        final api = _GatedRevocationApi(firstRevocation);
        final oldAccount = instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 1, username: 'account-a'));
        final authenticator = FakeAuthenticator(
          credentials: const UserApiCredentials(
            key: 'account-b-key',
            apiVersion: 4,
            push: false,
          ),
        )..keys[_siteUrl] = 'account-a-key';
        final shell = ShellController(
          instanceStore: FakeInstanceStore([oldAccount]),
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        final disconnecting = shell.disconnectCurrentInstance();
        await api.firstStarted.future;

        await shell.connectCurrentInstance();
        expect(shell.currentInstance?.user?.username, 'account-b');
        expect(authenticator.keys[_siteUrl], 'account-b-key');

        firstRevocation.complete();
        await disconnecting;

        expect(shell.currentInstance?.user?.username, 'account-b');
        expect(authenticator.keys[_siteUrl], 'account-b-key');
        expect(api.revokedKeys, ['account-a-key', 'account-a-key']);
        expect(authenticator.disconnected, isEmpty);
      },
    );
  });

  group('route isolation', () {
    test(
      "prevents an off-screen topic from retitling another site's route",
      () async {
        final gate = Completer<void>();
        final api = _GatedTopicApi(gate);
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            instance('meta.discourse.org'),
            instance('other.example.com'),
          ]),
          api: api,
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        shell.pushContent(
          ContentRoute.topic(
            topicId: 7,
            slug: 'first',
            title: 'First placeholder',
          ),
        );
        final loading = shell.loadTopic(7, 'first');
        await api.started.future;

        shell.selectInstance(1);
        shell.pushContent(
          ContentRoute.topic(
            topicId: 7,
            slug: 'second',
            title: 'Second site title',
          ),
        );

        gate.complete();
        await loading;

        expect(shell.currentContent?.title, 'Second site title');
        expect(
          shell.store.read<TopicDetail>('https://meta.discourse.org', 7)?.title,
          'First site title',
        );
      },
    );
  });
}
