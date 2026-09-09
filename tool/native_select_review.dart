import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/invites_api.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/assign/assign_services.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group_view.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/assign/assignment_sheet.dart';
import 'package:discourse_native/src/plugins/chat/chat_browse_channels_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_info_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_preferences.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_editor.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_sheet.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_editor.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_sheet.dart';
import 'package:discourse_native/src/shell/bookmark_ui.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/group_page.dart';
import 'package:discourse_native/src/shell/invite_list.dart';
import 'package:discourse_native/src/shell/invites_controller.dart';
import 'package:discourse_native/src/shell/preferences_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_status_editor.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test/support/bundled_plugins.dart';
import '../test/support/fakes.dart';
import 'native_select_voice_fixture.dart';

const _site = 'https://native-select.invalid';

/// Local-only native review entrypoint mounting the actual migrated owners.
Future<void> main() => startNativeSelectReview();

Future<void> startNativeSelectReview({Widget Function(Widget)? wrap}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // This executable deliberately uses the package’s in-memory test backend.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await initializeDateFormatting('en');
  LocalDateEnvironment.instance.ensureDatabase();
  final user = DiscourseUser(
    admin: true,
    staff: true,
    canInviteToForum: true,
    plugins: PluginData.none.withValue(
      chatCurrentUserDataKey,
      const ChatCurrentUser(canChat: true),
    ),
    id: 7,
    username: 'fixture',
    status: const UserStatus(description: 'Working', emoji: 'house'),
  );
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance(
        'native-select.invalid',
      ).copyWith(user: user, config: const SiteConfig(userStatusEnabled: true)),
    ]),
    api: _ReviewApi(
      user: user,
      chatChannelsBySite: const {
        _site: ChatChannels(
          public: [
            ChatChannel(
              id: 1,
              title: 'Fixture channel',
              canModerate: true,
              kind: ChatChannelKind.category,
              membership: ChatMembership(following: true),
            ),
            ChatChannel(
              id: 2,
              title: 'Destination channel',
              kind: ChatChannelKind.category,
              membership: ChatMembership(following: true),
            ),
          ],
          direct: [],
        ),
      },
      chatMessagesByKey: {
        FakeDiscourseApi.chatMessagesKey(1): (
          messages: const [
            ChatMessage(
              id: 1,
              channelId: 1,
              cooked: '<p>Fixture message: use Select then Move.</p>',
              raw: 'Fixture message',
              author: ChatMessageAuthor(
                id: 7,
                username: 'fixture',
                isStaff: true,
              ),
            ),
          ],
          canLoadMorePast: false,
          canLoadMoreFuture: false,
          targetMessageId: null,
        ),
      },
      chatBrowsePagesByKey: {
        FakeDiscourseApi.chatBrowseKey(): const ChatChannelBrowsePage(
          channels: [],
          hasMore: false,
        ),
      },
      feeds: const {'/latest.json': <Topic>[]},
      siteConfigs: const {_site: SiteConfig(userStatusEnabled: true)},
    ),
    authenticator: FakeAuthenticator()..keys[_site] = 'fixture-only',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final app = _Review(shell: shell);
  runApp(wrap?.call(app) ?? app);
}

class _Review extends StatefulWidget {
  const _Review({required this.shell});
  final ShellController shell;
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool _dark = false;
  bool _rtl = false;
  bool _large = false;
  bool _editable = true;
  UserPreferences _preferences = const UserPreferences(
    chatSeparateSidebarMode: ChatSeparateSidebarPreference.fullscreen,
  );
  Future<void> _page(BuildContext context, String title, Widget child) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(title)),
            body: ContentAlignmentScope(
              controller: widget.shell.appSettings,
              child: child,
            ),
          ),
        ),
      );

  List<Widget> _fixtures(BuildContext context) => [
    DButton(
      label: const Text('Preferences'),
      onPressed: () => _page(
        context,
        'Actual Preferences',
        const PreferencesPage(siteUrl: _site),
      ),
    ),
    DButton(
      label: const Text('Group management'),
      onPressed: () async {
        var route = GroupRoute.detail(
          'review',
          section: GroupRoute.manage,
          subsection: GroupRoute.membership,
        );
        await _page(
          context,
          'Actual Group management',
          StatefulBuilder(
            builder: (context, update) => GroupPage(
              siteUrl: _site,
              route: route,
              registry: widget.shell.plugins.registry,
              data: const GroupPageData(
                detail: GroupDetail(
                  group: Group(
                    id: 1,
                    name: 'review',
                    canAdminGroup: true,
                    canEditGroup: true,
                  ),
                ),
                isAdmin: true,
                loaded: true,
              ),
              onOpenMember: (_, _) {},
              onSelectRoute: (next) => update(() => route = next),
              onSaveManage: (_) async => true,
            ),
          ),
        );
      },
    ),
    DButton(
      label: const Text('Bookmark editor'),
      onPressed: () => showBookmarkEditor(
        context: context,
        controller: widget.shell.bookmarkTarget(BookmarkTargetType.post),
        siteUrl: _site,
        topicId: 1,
        bookmark: const Bookmark(
          id: 1,
          bookmarkableId: 1,
          bookmarkableType: 'Post',
        ),
      ),
    ),
    DButton(
      label: const Text('Invites'),
      onPressed: () async {
        final invites =
            InvitesController(
                api: InvitesApi(_ReviewApi()),
                credentials: widget.shell.authenticator,
                instance: widget.shell.currentInstance!,
                lifecycle: widget.shell.lifecycle,
              )
              ..loaded = true
              ..canSeeDetails = true;
        await _page(
          context,
          'Actual Invites',
          ListenableBuilder(
            listenable: invites,
            builder: (_, _) => InviteList(controller: invites, onManage: () {}),
          ),
        ).whenComplete(invites.dispose);
      },
    ),
    DButton(
      label: const Text('Poll composer'),
      onPressed: () => showPollComposerSheet(
        context: context,
        draft: PollComposerDraft.newPoll(name: 'poll', defaultPublic: false),
        maximumOptions: 20,
        isStaff: true,
        isPublished: false,
      ),
    ),
    DButton(
      label: const Text('Local Dates composer'),
      onPressed: () => showLocalDateComposerSheet(
        context: context,
        draft: LocalDateComposerDraft.newDate(
          now: DateTime(2026, 9, 9, 10),
          timezone: 'Etc/UTC',
          environment: LocalDateEnvironment.instance,
        ),
        siteFormats: const [],
      ),
    ),
    DButton(
      label: const Text('Event composer'),
      onPressed: () => _page(
        context,
        'Actual Event composer',
        EventComposerSheet(
          settings: const EventSettings(enabled: true),
          timezone: 'Etc/UTC',
          isCurrent: () => true,
        ),
      ),
    ),
    DButton(
      label: const Text('Assignment editor'),
      onPressed: () => _page(
        context,
        'Actual Assignment editor',
        AssignmentEditor(
          loadSuggestions: () async => AssignmentSuggestions(
            users: const [AssignmentUser(id: 7, username: 'fixture')],
          ),
          searchAssignees: (_, _) async => const [],
          save: (_, {note, status}) async => null,
          statusesEnabled: true,
          statuses: const ['New', 'Waiting', 'Done'],
        ),
      ),
    ),
    DButton(
      label: const Text('Assigned topics'),
      onPressed: () => _page(
        context,
        'Actual Assigned topics',
        PluginUiScope.own(
          assignPluginId,
          const AssignedGroupView(
            siteUrl: _site,
            groupName: 'review',
            subsection: null,
          ),
        ),
      ),
    ),
    DButton(
      label: const Text('Chat browse'),
      onPressed: () => _page(
        context,
        'Actual Chat browse',
        PluginUiScope.own(
          chatPluginId,
          const ChatBrowseChannelsView(siteUrl: _site),
        ),
      ),
    ),
    DButton(
      label: const Text('Chat move messages'),
      onPressed: () async {
        await widget.shell.pluginSession
            .require(chatControllerService)
            .loadChannels(_site);
        widget.shell.pluginSession.require(chatShellService).openChannel(1);
        if (!context.mounted) return;
        await _page(
          context,
          'Actual Chat messages',
          PluginUiScope.own(chatPluginId, const ChatChannelView(channelId: 1)),
        );
      },
    ),
    DButton(
      label: const Text('Chat notifications'),
      onPressed: () => _page(
        context,
        'Actual Chat notifications',
        PluginUiScope.own(
          chatPluginId,
          Builder(
            builder: (context) {
              final chat = PluginUiScope.require(
                context,
                chatControllerService,
              );
              return FutureBuilder<void>(
                future: chat.loadChannels(_site),
                builder: (context, snapshot) => ChatChannelInfoView(
                  siteUrl: _site,
                  channelId: 1,
                  tab: ChatChannelInfoTab.settings,
                  chat: chat,
                ),
              );
            },
          ),
        ),
      ),
    ),
    DButton(
      label: const Text('Voice devices, roles and quality'),
      onPressed: () => _page(
        context,
        'Actual Voice — simulated media',
        const NativeSelectVoiceFixture(),
      ),
    ),
  ];

  @override
  void dispose() {
    widget.shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: widget.shell,
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
      home: Scaffold(
        body: Builder(
          builder: (context) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Native Select Review 89bf — local data'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DButton(
                        label: const Text('Styleguide'),
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const ComponentStyleguidePage(),
                          ),
                        ),
                      ),
                      DButton(
                        label: const Text('Actual status editor'),
                        onPressed: () =>
                            showUserStatusEditor(context, siteUrl: _site),
                      ),
                      DButton(
                        label: Text(_dark ? 'Light theme' : 'Dark theme'),
                        onPressed: () => setState(() => _dark = !_dark),
                      ),
                      DButton(
                        label: Text(_rtl ? 'LTR' : 'RTL'),
                        onPressed: () => setState(() => _rtl = !_rtl),
                      ),
                      DButton(
                        label: Text(_large ? '100% text' : '200% text'),
                        onPressed: () => setState(() => _large = !_large),
                      ),
                      DButton(
                        label: Text(
                          _editable
                              ? 'Disable chat editing'
                              : 'Enable chat editing',
                        ),
                        onPressed: () => setState(() => _editable = !_editable),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Wrap(spacing: 8, runSpacing: 8, children: _fixtures(context)),
                  const SizedBox(height: 24),
                  chatUserPreferenceSection(
                    PluginUserPreferenceContext(
                      siteUrl: _site,
                      preferences: _preferences,
                      siteSettings: PluginData.none.withValue(
                        chatSettingsDataKey,
                        const ChatSettings(),
                      ),
                      currentUserData: PluginData.none.withValue(
                        chatCurrentUserDataKey,
                        const ChatCurrentUser(canChat: true),
                      ),
                      currentUserIsAdmin: false,
                      editable: _editable,
                      onEdit: (edit) =>
                          setState(() => _preferences = edit(_preferences)),
                    ),
                  )!.content,
                  const SizedBox(height: 16),
                  Text(
                    'Accepted chat preference: ${_preferences.chatSeparateSidebarMode.name}',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ReviewApi extends FakeDiscourseApi {
  _ReviewApi({
    super.user,
    super.feeds,
    super.siteConfigs,
    super.chatChannelsBySite,
    super.chatBrowsePagesByKey,
    super.chatMessagesByKey,
  });
  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final route = Uri.parse(path).path;
    if (route.endsWith('/invited.json')) {
      return {
        'invites': <Object>[],
        'can_see_invite_details': true,
        'counts': {'pending': 0, 'expired': 0, 'redeemed': 0},
      };
    }
    if (route.startsWith('/assign/members/')) {
      return {'members': <Object>[], 'total_rows': 0};
    }
    if (route.startsWith('/topics/group-topics-assigned/')) {
      return {
        'topic_list': {'topics': <Object>[]},
        'users': <Object>[],
      };
    }
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
