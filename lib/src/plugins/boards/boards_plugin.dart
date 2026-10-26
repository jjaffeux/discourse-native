import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'board_move_dialog.dart';
import 'boards_controller.dart';
import 'boards_data.dart';
import 'boards_navigation.dart';
import 'boards_page.dart';

final class BoardsPlugin
    implements
        SitePlugin,
        IsolateTopicDecoderPlugin,
        IconCatalogPlugin,
        SiteSettingsPlugin<BoardsSettings>,
        TopicRecordPlugin<BoardMemberships>,
        CommunitySidebarPlugin,
        ContentPlugin,
        ContentChromePlugin,
        ContentMobilePageSheetPlugin,
        TopicPropertiesPlugin,
        TopicListMetadataPlugin,
        TopicMapActionPlugin {
  const BoardsPlugin();
  @override
  String get name => 'boards';
  @override
  SitePlugin Function()? get isolateTopicDecoderFactory => BoardsPlugin.new;
  @override
  PluginIconCatalog get iconCatalog => const PluginIconCatalog(
    owner: boardsPluginId,
    entries: {'boards': boardsIcon},
  );
  @override
  PluginDataKey<BoardMemberships> get record => boardsMembershipKey;
  @override
  BoardMemberships? readTopic(Map<String, dynamic> json, String siteUrl) =>
      json.containsKey('board_memberships')
      ? BoardMemberships.decode(json['board_memberships'])
      : null;
  @override
  PluginDataPersistenceCodec<BoardsSettings> get siteSettingsCodec =>
      const BoardsSettingsCodec();
  @override
  BoardsSettings readSiteSettings(Map<String, dynamic> json, String siteUrl) =>
      BoardsSettings(enabled: json['boards_enabled'] == true);
  @override
  Listenable? communitySidebarListenable(BuildContext context) =>
      PluginUiScope.require(context, boardsControllerKey);
  @override
  List<SidebarDestination> communitySidebarDestinations(BuildContext context) {
    final controller = PluginUiScope.require(context, boardsControllerKey);
    final navigation = PluginUiScope.require(context, boardsNavigationKey);
    final site = navigation.host.currentSite;
    return site != null && controller.enabled(site.url)
        ? [
            SidebarDestination(
              id: 'boards',
              label: context.l10n.boardsTitle,
              icon: boardsIcon,
            ),
          ]
        : const [];
  }

  @override
  bool ownsContentChrome(BuildContext context, ContentRoute route) =>
      BoardsRoute.parse(route.id) != null;
  @override
  bool usesMobilePageSheet(BuildContext context, ContentRoute route) =>
      BoardsRoute.parse(route.id)?.boardId != null;
  @override
  Widget? content(BuildContext context, ContentRoute route) {
    final parsed = BoardsRoute.parse(route.id);
    if (parsed == null) return null;
    final navigation = PluginUiScope.require(context, boardsNavigationKey);
    final site = navigation.host.currentSite;
    if (site == null) return null;
    return BoardsPage(
      site: site.url,
      route: parsed,
      controller: PluginUiScope.require(context, boardsControllerKey),
      navigation: navigation,
    );
  }

  List<Widget> _memberships(
    BuildContext context,
    String site,
    BoardMemberships? memberships,
  ) {
    final controller = PluginUiScope.require(context, boardsControllerKey);
    if (!controller.enabled(site)) return const [];
    final navigation = PluginUiScope.require(context, boardsNavigationKey);
    return [
      for (final membership in memberships?.values ?? const <BoardMembership>[])
        DBadge.action(
          onPressed: () => navigation.openMembership(site, membership),
          child: Text(
            membership.columnTitle.isEmpty
                ? membership.name
                : '${membership.name} · ${membership.columnTitle}',
          ),
        ),
    ];
  }

  @override
  List<Widget> topicListMetadata(
    BuildContext context,
    String siteUrl,
    Topic topic,
  ) => _memberships(context, siteUrl, topic.plugins.get(boardsMembershipKey));
  @override
  List<TopicPropertySection> topicProperties(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) {
    final values = _memberships(
      context,
      siteUrl,
      topic.plugins.get(boardsMembershipKey),
    );
    return values.isEmpty
        ? const []
        : [
            TopicPropertySection(
              label: context.l10n.boardsTitle,
              values: values,
            ),
          ];
  }

  @override
  TopicMapActionContribution topicMapActions(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) {
    final controller = PluginUiScope.require(context, boardsControllerKey);
    if (!controller.enabled(siteUrl) ||
        controller.siteState.currentUserFor(siteUrl) == null) {
      return TopicMapActionContribution.none;
    }
    return TopicMapActionContribution(
      actions: [
        DButton(
          label: Text(context.l10n.boardsAddTopic),
          onPressed: () =>
              unawaited(_chooseBoard(context, siteUrl, topic.id, controller)),
        ),
      ],
    );
  }

  Future<void> _chooseBoard(
    BuildContext context,
    String site,
    int topicId,
    BoardsController controller,
  ) async {
    try {
      final lease = controller.requests.capture(site);
      final boards = await controller.loadDirectory(site, topicId: topicId);
      if (!context.mounted || !lease.isCurrent || !controller.enabled(site)) {
        return;
      }
      await addTopicToBoard(context, controller, site, topicId, boards);
    } catch (error) {
      if (context.mounted) DToast.show(context, error.toString());
    }
  }
}
