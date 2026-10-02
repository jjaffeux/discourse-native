import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'ai_conversations_data.dart';
import 'ai_conversations_plugin.dart';

const aiConversationsService = PluginServiceKey<AiConversationsService>(
  owner: PluginId('discourse-ai'),
  name: 'conversations',
);

final class AiConversation {
  const AiConversation({
    required this.id,
    required this.title,
    required this.slug,
    this.starred = false,
  });
  final int id;
  final String title;
  final String slug;
  final bool starred;
}

final class AiConversationPage {
  const AiConversationPage({
    required this.conversations,
    required this.page,
    required this.hasMore,
  });
  final List<AiConversation> conversations;
  final int page;
  final bool hasMore;

  factory AiConversationPage.fromJson(
    Map<String, dynamic> json,
    int requestedPage,
  ) {
    if (json['conversations'] is! List || json['meta'] is! Map) {
      throw FormatException(appL10n.aiConversationsLoadFailed);
    }
    final meta = jsonObject(json['meta']);
    return AiConversationPage(
      conversations: [
        for (final row in jsonObjects(json['conversations']))
          if (jsonInt(row['id']) > 0)
            AiConversation(
              id: jsonInt(row['id']),
              title: jsonText(row['title']) ?? '',
              slug: jsonText(row['slug']) ?? 'conversation',
              starred: row['ai_conversation_starred'] == true,
            ),
      ],
      page: jsonIntOrNull(meta['page']) ?? requestedPage,
      hasMore: meta['has_more'] == true,
    );
  }
}

final class AiConversationsUnavailable implements Exception {
  const AiConversationsUnavailable();
}

final class AiConversationsService implements PluginLinkHandler {
  const AiConversationsService({
    required this.transport,
    required this.requests,
    required this.siteState,
    required this.navigation,
    required this.topicLists,
  });
  final PluginApiTransport transport;
  final PluginRequestHost requests;
  final PluginSiteStateHost siteState;
  final PluginRouteNavigationHost navigation;
  final PluginTopicListNavigationHost topicLists;

  bool available(String siteUrl) =>
      navigation.currentSite?.isConnected == true &&
      navigation.currentSite?.url == siteUrl &&
      aiConversationsAvailable(
        siteState.siteConfigFor(siteUrl),
        siteState.currentUserFor(siteUrl),
      );

  Future<AiConversationPage?> load(String siteUrl, {int page = 0}) async {
    final lease = requests.capture(siteUrl);
    if (!available(siteUrl)) throw const AiConversationsUnavailable();
    final credentials = await requests.credentialsFor(siteUrl);
    if (!lease.isCurrent) return null;
    if (credentials.apiKey == null || !available(siteUrl)) {
      throw const AiConversationsUnavailable();
    }
    try {
      final json = await transport.pluginGetJson(
        siteUrl: siteUrl,
        path: '/discourse-ai/ai-bot/conversations.json?page=$page',
        apiKey: credentials.apiKey,
        clientId: credentials.clientId,
      );
      if (!lease.isCurrent) return null;
      if (!available(siteUrl)) throw const AiConversationsUnavailable();
      return AiConversationPage.fromJson(json, page);
    } on SiteLookupException catch (error) {
      if (error.statusCode == 403 || error.statusCode == 404) {
        throw const AiConversationsUnavailable();
      }
      rethrow;
    }
  }

  void open(String siteUrl, AiConversation conversation) {
    if (!available(siteUrl)) return;
    navigation.pushContent(
      ContentRoute.topic(
        topicId: conversation.id,
        slug: conversation.slug,
        title: conversation.title,
      ),
    );
    navigation.openTopicPost(
      siteUrl: siteUrl,
      topicId: conversation.id,
      postNumber: 1,
    );
  }

  @override
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
  }) async {
    final uri = Uri.tryParse(resolveSiteUrl(url, navigation.currentSite?.url));
    if (uri == null) return false;
    final index = navigation.sites.indexWhere((site) => site.serves(uri));
    if (index < 0) return false;
    final site = navigation.sites[index];
    if (site.pathWithin(uri) != '/discourse-ai/ai-bot/conversations' ||
        !site.isConnected ||
        !aiConversationsAvailable(
          siteState.siteConfigFor(site.url),
          siteState.currentUserFor(site.url),
        )) {
      return false;
    }
    if (navigation.currentSite?.url != site.url) {
      navigation.selectInstance(index);
    }
    if (navigation.currentContent?.id != 'ai-conversations') {
      navigation.pushContent(AiConversationsPlugin.route);
    }
    return true;
  }

  void openForum(String siteUrl) {
    if (navigation.currentSite?.url != siteUrl) return;
    final fallback = ContentRoute.homepage(
      siteState.siteConfigFor(siteUrl),
      connected: navigation.currentSite?.isConnected == true,
    );
    if (fallback.id == 'all-categories') {
      navigation.pushContent(fallback);
    } else {
      topicLists.openTopicList(
        ContentRoute(
          id: fallback.id,
          title: fallback.title,
          icon: fallback.icon,
          feedPath: fallback.feedPath ?? '/latest.json',
        ),
      );
    }
  }
}
