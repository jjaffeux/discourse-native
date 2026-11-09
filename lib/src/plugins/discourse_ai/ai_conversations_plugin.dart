import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/widgets.dart';

import 'ai_conversations_data.dart';
import 'ai_conversations_page.dart';
import 'ai_conversations_service.dart';

final class AiConversationsPlugin
    implements
        SitePlugin,
        SiteSettingsPlugin<AiBotSettings>,
        CurrentUserPlugin<AiBotUser>,
        HomepagePlugin,
        PrivateMessageSourcePlugin,
        ContentPageTitlePlugin,
        ContentPlugin {
  const AiConversationsPlugin();
  @override
  String get name => 'discourse-ai';
  @override
  String get homepageId => 'ai-conversations';

  @override
  ContentRoute? homepage(SiteConfig config, DiscourseUser? user) =>
      aiConversationsAvailable(config, user)
      ? AiConversationsService.route
      : null;

  @override
  PluginDataPersistenceCodec<AiBotSettings> get siteSettingsCodec =>
      const AiBotSettingsCodec();
  @override
  AiBotSettings readSiteSettings(Map<String, dynamic> json, String siteUrl) =>
      AiBotSettings(
        enabled:
            json['discourse_ai_enabled'] == true &&
            json['ai_bot_enabled'] == true,
      );
  @override
  PluginDataPersistenceCodec<AiBotUser> get currentUserCodec =>
      const AiBotUserCodec();
  @override
  AiBotUser readCurrentUser(Map<String, dynamic> json, String siteUrl) =>
      AiBotUser.fromWire(json);

  @override
  bool ownsPrivateMessageSource(ContentRoute route) => route.id == homepageId;

  @override
  bool ownsContentPageTitle(BuildContext context, ContentRoute route) =>
      route.id == homepageId;

  @override
  Widget? content(BuildContext context, ContentRoute route) {
    if (route.id != homepageId) return null;
    final service = PluginUiScope.require(context, aiConversationsService);
    final site = service.navigation.currentSite;
    if (site == null) return null;
    return AiConversationsPage(
      key: ValueKey((site.url, service.siteState.currentUserFor(site.url)?.id)),
      siteUrl: site.url,
      service: service,
    );
  }
}
