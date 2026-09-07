import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/post.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../plugin_api/site_plugin_api.dart';
import 'alert_data.dart';
import 'alert_links.dart';
import 'alert_tables.dart';

const alertSiteStateService = PluginServiceKey<PluginSiteStateHost>(
  owner: prometheusAlertReceiverPluginId,
  name: 'site-state',
);
const alertQuoteService = PluginServiceKey<PluginPostQuoteHost>(
  owner: prometheusAlertReceiverPluginId,
  name: 'post-quote',
);
const alertEmojiService = PluginServiceKey<PluginEmojiHost>(
  owner: prometheusAlertReceiverPluginId,
  name: 'emoji',
);

final class PrometheusAlertReceiverPlugin
    implements
        SitePlugin,
        TopicRecordPlugin<AlertData>,
        SiteSettingsPlugin<AlertLinkSettings>,
        PostDecorationPlugin {
  const PrometheusAlertReceiverPlugin();

  @override
  String get name => prometheusAlertReceiverPluginId.value;

  @override
  PluginDataKey<AlertData> get record => alertDataKey;

  @override
  AlertData? readTopic(Map<String, dynamic> json, String siteUrl) =>
      AlertData.decode(json);

  @override
  PluginDataPersistenceCodec<AlertLinkSettings> get siteSettingsCodec =>
      const AlertLinkSettingsCodec();

  @override
  AlertLinkSettings readSiteSettings(
    Map<String, dynamic> json,
    String siteUrl,
  ) => AlertLinkSettings.decode(json);

  @override
  List<Widget> postDecorations(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
    Post post,
  ) {
    final data = topic.plugins.get(alertDataKey);
    if (post.postNumber != 1 || data == null || data.alerts.isEmpty) {
      return const [];
    }
    final sites = PluginUiScope.maybe(context, alertSiteStateService);
    final quote = PluginUiScope.maybe(context, alertQuoteService);
    final emoji = PluginUiScope.maybe(context, alertEmojiService);
    return [
      AlertTables(
        key: ValueKey((siteUrl, topic.id, 'prometheus-alerts')),
        data: data,
        siteUrl: siteUrl,
        emojiUrl: emoji == null
            ? null
            : (name) => emoji.resolveUrl(siteUrl, name),
        settings:
            sites?.siteConfigFor(siteUrl).plugins.get(alertLinkSettingsKey) ??
            const AlertLinkSettings(),
        onQuote: quote != null && topic.canCreatePost
            ? (alert) =>
                  unawaited(quote.open(siteUrl, post.id, alert.quoteContents))
            : null,
      ),
    ];
  }
}
