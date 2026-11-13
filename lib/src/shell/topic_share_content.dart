import 'package:discourse_native/l10n/strings.dart';

import '../models/site_config.dart';

String topicShareUrl({
  required String siteUrl,
  required int topicId,
  required SiteConfig config,
  String? slug,
  String? username,
}) {
  return config.shareUrl(
    _topicCanonicalUrl(siteUrl: siteUrl, topicId: topicId, slug: slug),
    username: username,
  );
}

String _topicCanonicalUrl({
  required String siteUrl,
  required int topicId,
  String? slug,
}) {
  final origin = siteUrl.endsWith('/')
      ? siteUrl.substring(0, siteUrl.length - 1)
      : siteUrl;
  final topicSlug = slug?.trim().isNotEmpty == true ? slug!.trim() : 'topic';
  return '$origin/t/$topicSlug/$topicId';
}

String postCanonicalUrl({
  required String siteUrl,
  required int topicId,
  required int postNumber,
  String? slug,
}) {
  final topicUrl = _topicCanonicalUrl(
    siteUrl: siteUrl,
    topicId: topicId,
    slug: slug,
  );
  return postNumber > 1 ? '$topicUrl/$postNumber' : topicUrl;
}

String postShareUrl({
  required String siteUrl,
  required int topicId,
  required int postNumber,
  required SiteConfig config,
  String? slug,
  String? username,
}) {
  final url = postCanonicalUrl(
    siteUrl: siteUrl,
    topicId: topicId,
    postNumber: postNumber,
    slug: slug,
  );
  return config.shareUrl(url, username: username);
}

String topicContinuationMarkdown({required String title, required String url}) {
  final escaped = title
      .replaceAll(r'\', r'\\')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]');
  return appL10n.continueTheDiscussionFrom(
    (escaped).toString(),
    (url).toString(),
  );
}
