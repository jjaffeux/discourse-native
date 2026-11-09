import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
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
        ContentMobileDockPlugin,
        TopicPropertiesPlugin,
        TopicListMetadataPlugin,
        TopicMenuPlugin,
        TopicPropertiesRebuildPlugin {
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
  BoardMemberships? readTopic(
    Map<String, dynamic> json,
    String siteUrl, {
    TopicRecordDecodeContext context = const TopicRecordDecodeContext.partial(),
  }) => json.containsKey('board_memberships')
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
              mobileNavigationLabel: context.l10n.boardsTitle,
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
  bool hidesMobileDock(BuildContext context, ContentRoute route) =>
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
    BoardMemberships? memberships, {
    Widget? leading,
  }) {
    // Every topic row asks, and most topics are on no board, so the scopes
    // are only looked up for a topic that is.
    final values = memberships?.values ?? const <BoardMembership>[];
    if (values.isEmpty) return const [];
    final controller = PluginUiScope.require(context, boardsControllerKey);
    if (!controller.enabled(site)) return const [];
    final navigation = PluginUiScope.require(context, boardsNavigationKey);
    return [
      for (final membership in values)
        DButton(
          variant: DButtonVariant.primary,
          size: DButtonSize.chip,
          onPressed: () => navigation.openMembership(site, membership),
          icon: leading,
          label: Text(
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
  ) => _memberships(
    context,
    siteUrl,
    topic.plugins.get(boardsMembershipKey),
    // A topic row has no section label naming these pills, unlike the
    // topic's properties, so each carries the Boards mark instead.
    leading: const DIcon(boardsIcon),
  );
  @override
  List<TopicPropertySection> topicProperties(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) {
    final memberships = topic.plugins.get(boardsMembershipKey);
    final entries = memberships?.values ?? const <BoardMembership>[];
    final directMembership =
        entries.map((entry) => entry.boardId).toSet().length == 1
        ? entries.first
        : null;
    final navigation = PluginUiScope.require(context, boardsNavigationKey);
    final values = _memberships(context, siteUrl, memberships);
    return values.isEmpty
        ? const []
        : [
            TopicPropertySection(
              label: context.l10n.boardsTitle,
              values: values,
              compactAction: TopicPropertyHeaderAction(
                key: const ValueKey('boards-topic-header'),
                icon: const DIcon(boardsIcon),
                label: directMembership?.name ?? context.l10n.boardsTitle,
                onSelected: directMembership == null
                    ? null
                    : (_) =>
                          navigation.openMembership(siteUrl, directMembership),
              ),
            ),
          ];
  }

  @override
  Listenable? topicPropertiesRebuildOn(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) => PluginUiScope.require(context, boardsControllerKey);

  @override
  List<TopicMenuAction> topicMenuActions(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) {
    final controller = PluginUiScope.require(context, boardsControllerKey);
    if (!controller.enabled(siteUrl) ||
        controller.siteState.currentUserFor(siteUrl) == null) {
      return const [];
    }
    final boards = controller.eligibleBoards(siteUrl, topic.id);
    if (boards == null) {
      unawaited(controller.loadEligibleBoards(siteUrl, topic.id));
      return const [];
    }
    if (boards.isEmpty) return const [];
    return [
      TopicMenuAction(
        key: const ValueKey('boards-add-topic'),
        label: context.l10n.boardsAddToBoard,
        icon: boardsIcon,
        onSelected: (context) =>
            unawaited(_chooseBoard(context, siteUrl, topic.id, controller)),
      ),
    ];
  }

  Future<void> _chooseBoard(
    BuildContext context,
    String site,
    int topicId,
    BoardsController controller,
  ) async {
    try {
      final navigation = PluginUiScope.require(
        context,
        boardsNavigationKey,
      ).host;
      final tab = navigation.activeTabId;
      final route = navigation.currentContent;
      final lease = controller.requests.capture(site);
      final revision = controller.accountRevision(site);
      final boards = await controller.loadEligibleBoards(
        site,
        topicId,
        force: true,
      );
      if (!context.mounted ||
          !controller.sourceCurrent(site, lease, revision) ||
          navigation.currentSite?.url != site ||
          navigation.activeTabId != tab ||
          !identical(navigation.currentContent, route) ||
          boards.isEmpty) {
        return;
      }
      await addTopicToBoard(context, controller, site, topicId, boards);
    } catch (error) {
      if (context.mounted) {
        DToast.show(
          context,
          failureText(error, fallback: appL10n.boardsLoadFailed),
        );
      }
    }
  }
}
