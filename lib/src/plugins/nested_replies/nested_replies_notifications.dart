import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/l10n/strings.dart';

ResolvedNotification? nestedReplyNotification(
  PluginNotificationPresentationContext context, {
  required bool available,
}) {
  if (!available || context.notification.typeId.value != 2) return null;
  final notification = context.notification;
  final bucket = notification.data['reply_to_post_number'];
  final count = notification.data['consolidated_count'];
  final topic = notification.topicId;
  if (bucket is! int ||
      bucket < 1 ||
      count is! int ||
      count <= 1 ||
      topic == null ||
      topic <= 0) {
    return null;
  }
  final slug = Uri.encodeComponent(
    notification.slug.isEmpty ? 'topic' : notification.slug,
  );
  final base = '/t/$slug/$topic';
  final path = bucket == 1 ? base : '$base/$bucket';
  final fallback = context.fallback.presentation;
  final phrase = bucket == 1
      ? appL10n.nestedRepliesNotificationTopic(count)
      : appL10n.nestedRepliesNotificationPost(count);
  return ResolvedNotification(
    path: '$path?sort=new&collapse_replies=true',
    presentation: NotificationPresentation(
      icon: fallback.icon,
      phrase: phrase,
      actor: fallback.actor,
      menuLead: phrase,
      subject: fallback.subject,
    ),
  );
}
