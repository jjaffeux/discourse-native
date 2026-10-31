import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/widgets.dart';

import 'chat_message.dart';

const chatMessageContributions =
    PluginStaticContributionPoint<ChatMessageContribution<Object>>(
      owner: PluginId('chat'),
      name: 'message-data',
    );

abstract interface class ChatMessageContribution<T extends Object> {
  PluginDataKey<T> get key;
  T? decode(Map<String, dynamic> json, String siteUrl);
  Widget? buildHeader(BuildContext context, T data);
}

typedef ChatMessageDecoder = ChatMessage Function(
  Map<String, dynamic> json,
  String siteUrl,
);

final class ChatMessageCodec {
  ChatMessageCodec(Iterable<ChatMessageContribution<Object>> contributions)
    : contributions = List.unmodifiable(contributions) {
    final keys = <String>{};
    for (final contribution in this.contributions) {
      if (!keys.add(contribution.key.id)) {
        throw ArgumentError(
          'Duplicate Chat message contribution ${contribution.key.id}',
        );
      }
    }
  }

  final List<ChatMessageContribution<Object>> contributions;

  ChatMessage decode(Map<String, dynamic> json, String siteUrl) {
    var data = PluginData.none;
    for (final contribution in contributions) {
      data = data.withValueFor(
        contribution.key,
        contribution.decode(json, siteUrl),
      );
    }
    return ChatMessage.fromJson(json, siteUrl, plugins: data);
  }
}
