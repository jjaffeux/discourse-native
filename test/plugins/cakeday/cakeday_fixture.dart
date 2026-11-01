import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugin_api/emoji_preferences.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_api.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_controller.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_data.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_navigation.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

const cakedaySite = 'https://forum.example/community';
const birthdayQuery = CakedayQuery(CakedayKind.birthdays, CakedayPeriod.today);
Map<String, dynamic> celebration(int id, {String date = '1992-11-01'}) => {
  'id': id,
  'username': 'member$id',
  'name': 'Member $id',
  'title': 'Community member',
  'cakedate': date,
};
Map<String, dynamic> page(
  List<Map<String, dynamic>> rows, {
  int? total,
  String? next,
  CakedayKind kind = CakedayKind.birthdays,
}) => {
  kind.name: rows,
  'total_rows_${kind.name}': total ?? rows.length,
  'load_more_${kind.name}': ?next,
};

final class CakedayFixture {
  CakedayFixture({
    bool connected = true,
    bool enabled = true,
    bool birthdays = true,
    PluginApiTransport? actualTransport,
  }) {
    user = connected ? const DiscourseUser(id: 7, username: 'reader') : null;
    config = TrackedConfig(
      SiteConfig(
        emojiEnabled: false,
        plugins: PluginData.none.withValue(
          cakedaySettingsKey,
          CakedaySettings(enabled: enabled, birthdays: birthdays),
        ),
      ),
    );
    requests = PluginTestRequestHost(
      apiKeys: {
        if (connected) cakedaySite: 'key',
        if (connected) 'https://second.example': 'second-key',
      },
    );
    transport = RecordingPluginTransport();
    controller = CakedayController(
      api: CakedayApi(actualTransport ?? transport),
      requests: requests,
      siteState: PluginSiteStateHost(
        currentUserFor: (_) => user,
        siteConfigFor: (_) => config.value,
        siteConfigListenableFor: (_) => config,
      ),
      timezone: PluginTimezoneHost(
        readerTimezone: ([zone]) => zone ?? 'UTC',
        location: (name) =>
            name == 'Pacific/Kiritimati' ? tz.getLocation(name!) : tz.UTC,
        timezoneNames: () => ['UTC'],
        changes: timezoneChanges,
      ),
      emoji: PluginEmojiHost(
        preferences: _EmojiPreferences(),
        siteConfigFor: (_) => config.value,
        loadCatalog: (_, {refresh = false}) async => null,
        loadSearchAliases: (_, {refresh = false}) async => null,
        resolveUrl: (site, name) => '$site/emoji/$name.png',
      ),
      clock: () => clock,
    );
    navigation = CakedayNavigation(routes, controller);
  }
  DiscourseUser? user;
  DateTime clock = DateTime(2026, 11, 1, 12);
  late final TrackedConfig config;
  final timezoneChanges = TrackedChanges();
  late final PluginTestRequestHost requests;
  late final RecordingPluginTransport transport;
  late final CakedayController controller;
  final routes = CakedayRoutes();
  late final CakedayNavigation navigation;
  void dispose() {
    controller.dispose();
    config.dispose();
    timezoneChanges.dispose();
  }
}

final class CakedayRoutes implements PluginRouteNavigationHost {
  final List<ContentRoute> pushed = [];
  @override
  List<PluginRouteSite> get sites => const [
    PluginRouteSite(url: cakedaySite, title: 'Community', isConnected: true),
  ];
  @override
  PluginRouteSite? get currentSite => sites.first;
  @override
  String? get activeTabId => 'tab';
  @override
  ContentRoute? get currentContent => pushed.lastOrNull;
  @override
  void selectInstance(int index) {}
  @override
  void pushContent(ContentRoute route) => pushed.add(route);
  @override
  void replaceCurrentContent(ContentRoute route) {
    if (pushed.isNotEmpty) pushed.removeLast();
    pushed.add(route);
  }

  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    bool highlight = false,
  }) {}
}

final class _EmojiPreferences implements EmojiPreferenceStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class TrackedConfig extends ValueNotifier<SiteConfig> {
  TrackedConfig(super.value);
  final _listeners = <VoidCallback>{};
  int get listenerCount => _listeners.length;
  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    super.removeListener(listener);
  }
}

final class TrackedChanges extends ChangeNotifier {
  final _listeners = <VoidCallback>{};
  int get listenerCount => _listeners.length;
  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    super.removeListener(listener);
  }
}
