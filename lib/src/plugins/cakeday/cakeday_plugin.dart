import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'cakeday_controller.dart';
import 'cakeday_data.dart';
import 'cakeday_decoration.dart';
import 'cakeday_directory.dart';
import 'cakeday_navigation.dart';
import 'cakeday_preferences.dart';

final class CakedayPlugin
    implements
        SitePlugin,
        IsolateTopicDecoderPlugin,
        SiteSettingsPlugin<CakedaySettings>,
        PostRecordPlugin<CakedayDates>,
        UserCardRecordPlugin<CakedayDates>,
        UserPreferencesPlugin,
        UserPreferenceSectionPlugin,
        CommunitySidebarPlugin,
        ContentPlugin,
        ContentChromePlugin,
        PostAuthorDecorationPlugin,
        UserCardIdentityDecorationPlugin {
  const CakedayPlugin();
  @override
  String get name => cakedayPluginId.value;
  @override
  SitePlugin Function()? get isolateTopicDecoderFactory => CakedayPlugin.new;
  @override
  PluginDataKey<CakedayDates> get record => cakedayDatesKey;
  @override
  PluginDataPersistenceCodec<CakedaySettings> get siteSettingsCodec =>
      const CakedaySettingsCodec();
  @override
  CakedaySettings readSiteSettings(Map<String, dynamic> json, String siteUrl) =>
      CakedaySettings.read(json);
  @override
  CakedayDates? readPost(Map<String, dynamic> json, String siteUrl) =>
      CakedayDates.read(json, post: true);
  @override
  CakedayDates? readUserCard(Map<String, dynamic> json, String siteUrl) =>
      CakedayDates.read(json);
  @override
  CakedayDates? mergeAfterPostEdit(
    CakedayDates? held,
    CakedayDates? incoming,
  ) => incoming;
  @override
  List<UserPreferenceCodec> get userPreferenceCodecs => const [
    CakedayPreferenceCodec(),
  ];
  @override
  PluginUserPreferenceSection? userPreferenceSection(
    BuildContext context,
    PluginUserPreferenceContext preferences,
  ) => cakedayPreferenceSectionFor(context, preferences);
  @override
  Listenable? communitySidebarListenable(BuildContext context) =>
      PluginUiScope.require(context, cakedayControllerKey);
  @override
  List<SidebarDestination> communitySidebarDestinations(BuildContext context) {
    final controller = PluginUiScope.require(context, cakedayControllerKey),
        navigation = PluginUiScope.require(context, cakedayNavigationKey);
    final site = navigation.host.currentSite;
    if (site == null) return const [];
    return [
      for (final kind in CakedayKind.values)
        if (controller.enabled(site.url, kind))
          SidebarDestination(
            id: CakedayQuery(kind, CakedayPeriod.today).id,
            label: kind == CakedayKind.birthdays
                ? context.l10n.cakedayBirthdays
                : context.l10n.cakedayAnniversaries,
            icon: DIcons.cakeCandles,
            onTap: () =>
                navigation.open(CakedayQuery(kind, CakedayPeriod.today)),
          ),
    ];
  }

  @override
  bool ownsContentChrome(BuildContext context, ContentRoute route) =>
      CakedayQuery.parse(route.id) != null;
  @override
  Widget? content(BuildContext context, ContentRoute route) {
    final query = CakedayQuery.parse(route.id);
    if (query == null) return null;
    final navigation = PluginUiScope.require(context, cakedayNavigationKey),
        site = navigation.host.currentSite;
    if (site == null) return null;
    return CakedayDirectory(
      site: site.url,
      query: query,
      controller: PluginUiScope.require(context, cakedayControllerKey),
      navigation: navigation,
    );
  }

  List<Widget> _decorations(
    BuildContext context,
    String site,
    CakedayDates? dates,
    int? userId,
  ) {
    if (dates == null) return const [];
    final controller = PluginUiScope.maybe(context, cakedayControllerKey);
    if (controller == null || controller.celebrations(site, dates).isEmpty) {
      return const [];
    }
    return [
      CakedayDecoration(
        controller: controller,
        site: site,
        dates: dates,
        userId: userId,
      ),
    ];
  }

  CakedayController? _observeDecorations(BuildContext context, String siteUrl) {
    final controller = PluginUiScope.maybe(context, cakedayControllerKey);
    controller?.observeDecorations(siteUrl);
    return controller;
  }

  @override
  Listenable? postAuthorDecorationsListenable(
    BuildContext context,
    String siteUrl,
    Post post,
  ) => _observeDecorations(context, siteUrl);

  @override
  Listenable? userCardIdentityDecorationsListenable(
    BuildContext context,
    String siteUrl,
    UserCard user,
  ) => _observeDecorations(context, siteUrl);

  @override
  List<PostAuthorDecoration> postAuthorDecorations(
    BuildContext context,
    String siteUrl,
    Post post,
  ) => [
    for (final child in _decorations(
      context,
      siteUrl,
      post.plugins.get(cakedayDatesKey),
      post.userId,
    ))
      PostAuthorDecoration(child: child),
  ];
  @override
  List<Widget> userCardIdentityDecorations(
    BuildContext context,
    String siteUrl,
    UserCard user,
  ) => _decorations(
    context,
    siteUrl,
    user.plugins.get(cakedayDatesKey),
    user.id,
  );
}
