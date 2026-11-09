import 'package:discourse_native/discourse_chat.dart';
import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

@immutable
final class AiChatMessageData {
  const AiChatMessageData(this.model);
  final String model;
  @override
  bool operator ==(Object other) =>
      other is AiChatMessageData && model == other.model;
  @override
  int get hashCode => model.hashCode;
}

final class AiChatMessageContribution
    implements ChatMessageContribution<AiChatMessageData> {
  const AiChatMessageContribution();
  @override
  PluginDataKey<AiChatMessageData> get key =>
      const PluginDataKey(owner: 'discourse-ai', name: 'chat-message');
  @override
  AiChatMessageData? decode(Map<String, dynamic> json, String siteUrl) {
    final model = jsonText(json['ai_llm_name']);
    return model == null ? null : AiChatMessageData(model);
  }

  @override
  Widget buildHeader(BuildContext context, AiChatMessageData data) => DTooltip(
    message: context.l10n.aiChatModel(data.model),
    child: DBadge(
      size: DBadgeSize.compact,
      variant: DBadgeVariant.secondary,
      child: Text(data.model),
    ),
  );
}
