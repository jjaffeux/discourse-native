import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'nested_replies_bulk.dart';
import 'nested_replies_data.dart';
import 'nested_replies_reader.dart';
import 'nested_replies_services.dart';

final class NestedRepliesPlugin
    implements
        SitePlugin,
        IsolateTopicDecoderPlugin,
        SiteSettingsPlugin<NestedRepliesSettings>,
        PluginSiteFeature,
        TopicRecordPlugin<NestedTopicData>,
        TopicReaderPlugin,
        TopicMapActionPlugin,
        PostMenuPlugin,
        TopicListHeaderPlugin,
        TopicListTitlePlugin {
  const NestedRepliesPlugin();

  @override
  String get name => nestedRepliesPluginId.value;
  @override
  SitePlugin Function()? get isolateTopicDecoderFactory =>
      NestedRepliesPlugin.new;
  @override
  PluginDataKey<NestedTopicData> get record => nestedRepliesTopicKey;
  @override
  PluginDataPersistenceCodec<NestedRepliesSettings> get siteSettingsCodec =>
      const NestedRepliesSettingsCodec();
  @override
  NestedRepliesSettings readSiteSettings(
    Map<String, dynamic> json,
    String siteUrl,
  ) => NestedRepliesSettings.fromJson(json);
  @override
  bool siteFeatureEnabled(PluginData siteSettings) =>
      siteSettings.get(nestedRepliesSettingsKey)?.enabled == true;
  @override
  NestedTopicData? readTopic(
    Map<String, dynamic> json,
    String siteUrl, {
    TopicRecordDecodeContext context = const TopicRecordDecodeContext.partial(),
  }) {
    return NestedTopicData.fromContext(json, context);
  }

  @override
  bool readsTopic(TopicReaderProbe probe) =>
      (probe.config.plugins.get(nestedRepliesSettingsKey) ??
              const NestedRepliesSettings())
          .allowsTopic(
            probe.topic.plugins.get(nestedRepliesTopicKey),
            privateMessage: probe.topic.privateMessage,
          );

  NestedRepliesServices _service(BuildContext context) =>
      PluginUiScope.require(context, nestedRepliesServiceKey);

  @override
  Widget buildTopicReader(BuildContext context, PluginTopicReader reader) {
    final service = _service(context);
    service.activatePluginSite(reader.siteUrl, connected: reader.isConnected);
    final settings = service.settingsFor(reader.siteUrl);
    return NestedRepliesReader(
      key: ValueKey((reader, settings)),
      reader: reader,
      api: service.api,
      settings: settings,
      memory: service.memory,
    );
  }

  @override
  TopicMapActionContribution topicMapActions(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) {
    final service = _service(context);
    final settings = service.settingsFor(siteUrl);
    final feature = topic.plugins.get(nestedRepliesTopicKey);
    if (settings.enabled == false || topic.privateMessage) {
      return TopicMapActionContribution.none;
    }
    return TopicMapActionContribution(
      actions: [
        if (settings.enabled == true && service.staffFor(siteUrl))
          DButton(
            size: DButtonSize.chip,
            variant: DButtonVariant.tool,
            icon: const DIcon(DIcons.reply),
            label: Text(appL10n.nestedRepliesSettings),
            onPressed: () =>
                unawaited(service.showSettings(context, siteUrl, topic.id)),
          ),
        if (feature?.enabled == true && feature?.hasActivityLog == true)
          DButton(
            size: DButtonSize.chip,
            variant: DButtonVariant.tool,
            label: Text(appL10n.nestedRepliesActivity),
            onPressed: () =>
                unawaited(service.showActivity(context, siteUrl, topic.id)),
          ),
      ],
    );
  }

  @override
  PostMenuContribution postMenu(PostMenuContext menu) {
    final topic = menu.topic;
    final post = menu.post;
    final data = post.plugins.get(nestedRepliesPostKey);
    final service = _service(menu.buildContext);
    if (topic == null ||
        topic.privateMessage ||
        !topic.canEdit ||
        menu.currentUser?.staff != true ||
        !service.staffFor(menu.siteUrl) ||
        post.postNumber <= 1 ||
        data == null ||
        (data.replyToPostNumber != null && data.replyToPostNumber != 1) ||
        topic.plugins.get(nestedRepliesTopicKey)?.enabled != true ||
        service.settingsFor(menu.siteUrl).enabled == false) {
      return PostMenuContribution.none;
    }
    final pinned =
        topic.plugins
            .get(nestedRepliesTopicKey)
            ?.pinnedPostIds
            ?.contains(post.id) ==
        true;
    final label = pinned
        ? appL10n.nestedRepliesUnpin
        : appL10n.nestedRepliesPin;
    return PostMenuContribution(
      rebuildOn: service,
      entries: [
        PostAction(
          icon: DIcons.thumbtack,
          label: label,
          tooltip: label,
          enabled: !service.pinBusy(menu.siteUrl, topic.id),
          placement: PostActionPlacement.overflow,
          onInvoke: () => unawaited(
            service.togglePin(
              menu.buildContext,
              menu.siteUrl,
              topic.id,
              post.id,
            ),
          ),
        ),
      ],
    );
  }

  @override
  List<Widget> topicListHeaderActions(
    BuildContext context,
    String siteUrl,
    ContentRoute route,
  ) => route.isMessages || route.isTopic
      ? const []
      : [
          NestedRepliesBulkActions(
            controller: _service(context).bulk,
            siteUrl: siteUrl,
          ),
        ];

  @override
  Widget? decorateTopicListTitle(
    BuildContext context,
    String siteUrl,
    Topic topic,
    Widget title,
  ) => NestedRepliesBulkTitle(
    controller: _service(context).bulk,
    siteUrl: siteUrl,
    topic: topic,
    title: title,
  );
}

final class NestedRepliesPostPlugin
    implements
        SitePlugin,
        IsolateTopicDecoderPlugin,
        PostRecordPlugin<NestedPostData> {
  const NestedRepliesPostPlugin();
  @override
  String get name => nestedRepliesPluginId.value;
  @override
  SitePlugin Function()? get isolateTopicDecoderFactory =>
      NestedRepliesPostPlugin.new;
  @override
  PluginDataKey<NestedPostData> get record => nestedRepliesPostKey;
  @override
  NestedPostData? readPost(Map<String, dynamic> json, String siteUrl) =>
      json.containsKey('direct_reply_count') ||
          json.containsKey('total_descendant_count') ||
          json.containsKey('deleted_post_placeholder') ||
          json.containsKey('ignored_post_placeholder') ||
          json.containsKey('reply_to_post_number')
      ? NestedPostData.fromJson(json)
      : null;
  @override
  NestedPostData? mergeAfterPostEdit(
    NestedPostData? held,
    NestedPostData? incoming,
  ) => held ?? incoming;
}
