// Local-data review only. No real accounts, settings or network clients.
import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/aggregate_preferences_store.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_info_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_editor.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_sheet.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_editor.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_sheet.dart';
import 'package:discourse_native/src/plugins/voice/voice_diagnostics_view.dart';
import 'package:discourse_native/src/plugins/voice/voice_report_exporter.dart';
import 'package:discourse_native/src/shell/app_settings_page.dart';
import 'package:discourse_native/src/shell/group_page.dart';
import 'package:discourse_native/src/shell/preferences_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/bundled_plugins.dart';
import '../test/support/chat_shell.dart';
import '../test/support/fakes.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LocalDateEnvironment.instance.ensureDatabase();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const SwitchReviewApp());
}

class SwitchReviewApp extends StatefulWidget {
  const SwitchReviewApp({super.key});
  @override
  State<SwitchReviewApp> createState() => _SwitchReviewAppState();
}

class _SwitchReviewAppState extends State<SwitchReviewApp> {
  final _shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
    appSettingsStore: AppSettingsStore(
      persistence: MemoryAppSettingsPersistence(),
    ),
  );
  bool _dark = false;
  bool _rtl = false;
  bool _large = false;
  @override
  void dispose() {
    _shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: _shell,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(_large ? 2 : 1)),
        child: Directionality(
          textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Switch review — local data')),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DButton(
                    label: const Text('Light / Dark'),
                    onPressed: () => setState(() => _dark = !_dark),
                  ),
                  DButton(
                    label: const Text('LTR / RTL'),
                    onPressed: () => setState(() => _rtl = !_rtl),
                  ),
                  DButton(
                    label: const Text('100% / 200%'),
                    onPressed: () => setState(() => _large = !_large),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              DButton(
                label: const Text('Open styleguide'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ComponentStyleguidePage(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DButton(
                label: const Text('Settings — memory persistence'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const Dialog(
                    child: SizedBox(
                      width: 720,
                      height: 640,
                      child: AppSettingsModal(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DButton(
                label: const Text('Preferences — fake account'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _AccountFixture(chat: false),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DButton(
                label: const Text('Chat settings — fake account'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _AccountFixture(chat: true),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DButton(
                label: const Text('Poll — local draft'),
                onPressed: () async {
                  final result = await showPollComposerSheet(
                    context: context,
                    draft: PollComposerDraft.newPoll(
                      name: 'poll',
                      defaultPublic: false,
                    ),
                    maximumOptions: 20,
                    isStaff: true,
                    isPublished: false,
                  );
                  if (context.mounted && result != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Local poll: ${result.type.name}'),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              DButton(
                label: const Text('Local date — local draft'),
                onPressed: () async {
                  final result = await showLocalDateComposerSheet(
                    context: context,
                    draft: LocalDateComposerDraft.newDate(
                      now: DateTime(2026, 9, 9, 12),
                      timezone: 'Etc/UTC',
                      environment: LocalDateEnvironment.instance,
                    ),
                    siteFormats: const [],
                  );
                  if (context.mounted && result != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Local date: ${result.type.name}'),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              DButton(
                label: const Text('Group management — local updates'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _GroupFixture(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DButton(
                label: const Text('Voice diagnostics — fake capture'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _VoiceFixture(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _GroupFixture extends StatefulWidget {
  const _GroupFixture();
  @override
  State<_GroupFixture> createState() => _GroupFixtureState();
}

class _GroupFixtureState extends State<_GroupFixture> {
  var _route = GroupRoute.detail(
    'review',
    section: GroupRoute.manage,
    subsection: GroupRoute.membership,
  );
  String _saved = 'No changes saved';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_saved)),
    body: GroupPage(
      siteUrl: 'https://review.invalid',
      route: _route,
      registry: PluginRegistry.empty,
      data: const GroupPageData(
        detail: GroupDetail(
          group: Group(
            id: 9,
            name: 'review',
            fullName: 'Local Review',
            canAdminGroup: true,
            canSeeMembers: true,
          ),
        ),
        loaded: true,
        isAdmin: true,
        smtpEnabled: true,
      ),
      onSelectRoute: (route) => setState(() => _route = route),
      onOpenMember: (context, member) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(member.username))),
      onSaveManage: (update) async {
        setState(
          () => _saved =
              'Saved ${update.subsection}: ${jsonEncode(update.values)}',
        );
        return true;
      },
    ),
  );
}

class _VoiceFixture extends StatefulWidget {
  const _VoiceFixture();
  @override
  State<_VoiceFixture> createState() => _VoiceFixtureState();
}

class _VoiceFixtureState extends State<_VoiceFixture>
    implements VoiceReportExporter {
  final _state = ValueNotifier(
    const VoiceDiagnosticsUiState(
      enabled: false,
      retainedBytes: 0,
      droppedRecords: 0,
      truncated: false,
    ),
  );
  final _events = ValueNotifier(<Map<String, Object?>>[]);
  void _capture(bool enabled) {
    _state.value = VoiceDiagnosticsUiState(
      enabled: enabled,
      captureId: 'local-switch-review',
      retainedBytes: 0,
      droppedRecords: 0,
      truncated: false,
    );
  }

  @override
  void dispose() {
    _state.dispose();
    _events.dispose();
    super.dispose();
  }

  @override
  String get actionLabel => 'Preview local export';
  @override
  Future<VoiceReportExportOutcome> export(
    String report, {
    Rect? sharePositionOrigin,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Local export'),
        content: Text(report),
        actions: [
          DButton(
            label: const Text('Close'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
    return VoiceReportExportOutcome.saved;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fake Voice capture')),
    body: VoiceDiagnosticsView(
      stateListenable: _state,
      eventsListenable: _events,
      readState: () => _state.value,
      readEvents: () => _events.value,
      startCapture: () async => _capture(true),
      stopCapture: () async => _capture(false),
      clear: () async {
        _events.value = [];
      },
      buildJsonReport: () async => jsonEncode(_events.value),
      exporter: this,
    ),
  );
}

const _site = 'https://review.invalid';
const _user = DiscourseUser(id: 7, username: 'local', staff: true);
const _channel = ChatChannel(
  id: 9,
  title: 'Local review',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true),
);

class _AccountFixture extends StatefulWidget {
  const _AccountFixture({required this.chat});
  final bool chat;
  @override
  State<_AccountFixture> createState() => _AccountFixtureState();
}

class _AccountFixtureState extends State<_AccountFixture> {
  late final ShellController _shell;
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    _shell = ShellController(
      plugins: installedPlugins,
      instanceStore: FakeInstanceStore([
        const DiscourseInstance(url: _site, title: 'Local review', user: _user),
      ]),
      api: _AccountApi(),
      authenticator: FakeAuthenticator()..keys[_site] = 'local-fake-key',
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
      aggregatePreferences: AggregatePreferencesStore.memory(),
    );
    unawaited(_load());
  }

  Future<void> _load() async {
    await _shell.load();
    if (widget.chat) await _shell.chat.loadChannels(_site);
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: _shell,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.chat ? 'Local Chat settings' : 'Local preferences'),
      ),
      body: !_ready
          ? const Center(child: DSpinner())
          : widget.chat
          ? PluginUiScope.own(
              chatPluginId,
              ChatChannelInfoView(
                siteUrl: _site,
                channelId: 9,
                tab: ChatChannelInfoTab.settings,
                chat: _shell.chat,
              ),
            )
          : const PreferencesPage(siteUrl: _site),
    ),
  );
}

class _AccountApi extends FakeDiscourseApi {
  _AccountApi()
    : super(
        user: _user,
        userPreferences: const UserPreferences(
          username: 'local',
          canEdit: true,
        ),
        chatChannelsBySite: {
          _site: const ChatChannels(public: [_channel]),
        },
        chatChannelsById: {9: _channel},
      );
  @override
  Future<ChatChannel> updateChatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? name,
    String? slug,
    String? description,
    bool? threadingEnabled,
    String? clientId,
  }) async {
    final channel = await super.updateChatChannel(
      siteUrl: siteUrl,
      apiKey: apiKey,
      channelId: channelId,
      threadingEnabled: threadingEnabled,
    );
    return channel.withThreadingEnabled(
      threadingEnabled ?? channel.threadingEnabled,
    );
  }
}
