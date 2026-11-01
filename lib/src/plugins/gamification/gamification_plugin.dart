import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'gamification_admin_page.dart';
import 'gamification_controller.dart';
import 'gamification_models.dart';
import 'gamification_navigation.dart';
import 'gamification_page.dart';
import 'gamification_user_score.dart';

final class GamificationPlugin
    implements
        SitePlugin,
        SiteSettingsPlugin<GamificationSettings>,
        UserCardRecordPlugin<GamificationUserScore>,
        CommunitySidebarPlugin,
        ContentPlugin,
        ContentChromePlugin,
        UserCardMetadataPlugin,
        UserProfileMetadataPlugin,
        UserDirectoryColumnLabelPlugin {
  const GamificationPlugin();
  @override
  String get name => 'discourse-gamification';
  @override
  PluginDataPersistenceCodec<GamificationSettings> get siteSettingsCodec =>
      const GamificationSettingsCodec();
  @override
  GamificationSettings? readSiteSettings(
    Map<String, dynamic> json,
    String siteUrl,
  ) => json['discourse_gamification_enabled'] is bool
      ? GamificationSettings(
          enabled: json['discourse_gamification_enabled'] as bool,
        )
      : null;
  @override
  PluginDataKey<GamificationUserScore> get record => gamificationUserScoreKey;
  @override
  GamificationUserScore? readUserCard(
    Map<String, dynamic> json,
    String siteUrl,
  ) => json['gamification_score'] is int
      ? GamificationUserScore(json['gamification_score'] as int)
      : null;
  @override
  Listenable? communitySidebarListenable(BuildContext context) =>
      PluginUiScope.require(context, gamificationControllerKey);
  @override
  List<SidebarDestination> communitySidebarDestinations(BuildContext context) {
    final controller = PluginUiScope.require(
      context,
      gamificationControllerKey,
    );
    final navigation = PluginUiScope.require(
      context,
      gamificationNavigationKey,
    );
    final site = navigation.host.currentSite?.url;
    if (site == null) return const [];
    if (controller.enabled(site)) {
      return [
        SidebarDestination(
          id: 'gamification',
          label: context.l10n.gamificationTitle,
          mobileNavigationLabel: context.l10n.gamificationTitle,
          icon: gamificationIcon,
        ),
      ];
    }
    if (controller.canManage(site)) {
      return [
        SidebarDestination(
          id: 'gamification/admin',
          label: context.l10n.gamificationAdminTitle,
          mobileNavigationLabel: context.l10n.gamificationAdminTitle,
          icon: gamificationIcon,
        ),
      ];
    }
    return const [];
  }

  @override
  bool ownsContentChrome(BuildContext context, ContentRoute route) =>
      GamificationRoute.parse(route.id) != null;
  @override
  Widget? content(BuildContext context, ContentRoute route) {
    final parsed = GamificationRoute.parse(route.id);
    if (parsed == null) return null;
    final navigation = PluginUiScope.require(
      context,
      gamificationNavigationKey,
    );
    final site = navigation.host.currentSite?.url;
    if (site == null) return null;
    final controller = PluginUiScope.require(
      context,
      gamificationControllerKey,
    );
    return parsed.admin
        ? GamificationAdminPage(
            site: site,
            controller: controller,
            initialBoardId: parsed.boardId,
            navigation: navigation,
            create: parsed.create,
          )
        : GamificationPage(
            site: site,
            controller: controller,
            navigation: navigation,
            query: parsed.query,
          );
  }

  List<Widget> _metadata(
    BuildContext context,
    String site,
    UserCard user, [
    VoidCallback? close,
  ]) {
    final score = user.plugins.get(gamificationUserScoreKey);
    if (score == null || score.totalScore == 0) return const [];
    return [
      GamificationUserScoreMetadata(
        controller: PluginUiScope.require(context, gamificationControllerKey),
        site: site,
        score: score,
        navigation: PluginUiScope.require(context, gamificationNavigationKey),
        close: close,
      ),
    ];
  }

  @override
  List<Widget> userCardMetadata(
    BuildContext context,
    String siteUrl,
    UserCard user,
    VoidCallback close,
  ) => _metadata(context, siteUrl, user, close);
  @override
  List<Widget> userProfileMetadata(
    BuildContext context,
    String siteUrl,
    UserCard user,
  ) => _metadata(context, siteUrl, user);
  @override
  String? userDirectoryColumnLabel(
    BuildContext context,
    String siteUrl,
    String columnName,
  ) {
    if (siteUrl.isEmpty || columnName != 'gamification_score') return null;
    return PluginUiScope.require(
          context,
          gamificationControllerKey,
        ).enabled(siteUrl)
        ? context.l10n.gamificationCheers
        : null;
  }
}
