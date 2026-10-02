import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../diagnostics/diagnostics_controller.dart';
import '../../foundation/uri_path.dart';
import '../../foundation/uri_query.dart';
import '../open_link.dart';

const _redditOrigins = {
  'https://embed.reddit.com',
  'https://sh.reddit.com',
  // Cooked posts from older Discourse versions retain this embed host.
  'https://www.redditmedia.com',
};
final _redditName = RegExp(r'^[A-Za-z0-9_-]+$');
final _redditId = RegExp(r'^[A-Za-z0-9]+$');

class RedditOneboxData {
  const RedditOneboxData({
    required this.embedUri,
    required this.linkUri,
    required this.title,
    required this.height,
  });

  final Uri embedUri;
  final Uri linkUri;
  final String title;
  final double height;

  Uri embedUriFor(Brightness brightness) {
    final parameters = Map<String, dynamic>.of(
      validUriQueryParameters(embedUri),
    )..remove('theme');
    if (brightness == Brightness.dark) parameters['theme'] = 'dark';
    return embedUri.replace(queryParameters: parameters);
  }

  /// Reddit can fill in or change the title slug while keeping the same post.
  bool allowsNavigation(Uri uri) {
    final source = tryUriPathSegments(embedUri);
    final destination = tryUriPathSegments(uri);
    if (source == null || destination == null) return false;
    String? part(List<String> path, int index) =>
        index < path.length && path[index].isNotEmpty
        ? path[index].toLowerCase()
        : null;
    return destination.length >= 4 &&
        destination.length <= 7 &&
        [
          0,
          1,
          2,
          3,
          5,
        ].every((index) => part(source, index) == part(destination, index)) &&
        (destination.length < 7 || destination.last.isEmpty);
  }

  static RedditOneboxData? from(dom.Element element) {
    if (element.localName != 'iframe' ||
        !element.classes.contains('reddit-onebox')) {
      return null;
    }
    final source = element.attributes['src']?.trim();
    if (source == null) return null;
    final uri = Uri.tryParse(
      source.startsWith('//') ? 'https:$source' : source,
    );
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !_redditOrigins.contains(uri.origin)) {
      return null;
    }
    final segments = tryUriPathSegments(uri);
    if (segments == null) return null;
    final path = List.of(segments);
    if (path.isNotEmpty && path.last.isEmpty) path.removeLast();
    if (path.length < 4 ||
        path.length > 6 ||
        !const {'r', 'user'}.contains(path[0]) ||
        !_redditName.hasMatch(path[1]) ||
        path[2] != 'comments' ||
        !_redditId.hasMatch(path[3]) ||
        (path.length == 6 && !_redditId.hasMatch(path[5])) ||
        path.any((part) => part.contains('/') || part.contains('\\'))) {
      return null;
    }
    final comment = path.length == 6;
    final parsedHeight = double.tryParse(element.attributes['height'] ?? '');
    final height =
        parsedHeight != null && parsedHeight.isFinite && parsedHeight > 0
        ? parsedHeight.clamp(120.0, 2000.0)
        : comment
        ? 300.0
        : 500.0;
    return RedditOneboxData(
      embedUri: uri,
      linkUri: Uri(
        scheme: 'https',
        host: 'www.reddit.com',
        pathSegments: segments,
      ),
      title: appL10n.reddit(
        (comment).toString(),
        (path[0]).toString(),
        (path[1]).toString(),
      ),
      height: height,
    );
  }
}

Widget? redditOneboxWidgetBuilder(dom.Element element, {String? siteUrl}) {
  final data = RedditOneboxData.from(element);
  if (data == null) return null;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Builder(
          builder: (context) => DEmbed(
            uri: data.embedUriFor(Theme.of(context).brightness),
            presentation: DEmbedPresentation.provider,
            origins: _redditOrigins,
            externalUri: data.linkUri,
            title: data.title,
            height: data.height,
            openLabel: appL10n.openOnReddit,
            resizeMessageType: 'resize.embed',
            canNavigate: data.allowsNavigation,
            onOpenLink: (uri) =>
                unawaited(openLink(context, uri.toString(), siteUrl: siteUrl)),
            onError: (error, stackTrace) => DiagnosticsSink.current.reportError(
              error,
              stackTrace,
              operation: 'reddit.embed.load',
              source: 'platform',
              severity: DiagnosticSeverity.warning,
              handled: true,
              degraded: true,
            ),
          ),
        ),
      ),
    ),
  );
}
