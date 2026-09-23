import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import '../open_link.dart';

/// Cooked iframe markup has already passed the forum's iframe allowlist.
/// Rebuild from its URL and dimensions; never execute srcdoc, event handlers,
/// arbitrary script tags, or other attributes supplied by the post.
class EmbeddedOneboxData {
  const EmbeddedOneboxData({
    required this.uri,
    required this.externalUri,
    required this.title,
    required this.height,
    this.width,
  });

  final Uri uri;
  final Uri externalUri;
  final String title;
  final double height;
  final double? width;

  static EmbeddedOneboxData? from(dom.Element element, {String? siteUrl}) {
    final isScript = element.localName == 'script';
    if (element.localName != 'iframe' && !isScript) return null;
    var uri = oneboxHttpUri(element.attributes['src'], siteUrl: siteUrl);
    if (uri == null || uri.scheme != 'https') return null;
    var externalUri =
        oneboxHttpUri(
          element.attributes['data-original-href'],
          siteUrl: siteUrl,
        ) ??
        uri;
    if (isScript) {
      // Core's only script onebox is Asciinema. Its bootstrap creates this
      // iframe; translate that exact format instead of executing the script.
      if (uri.origin != 'https://asciinema.org' ||
          !RegExp(r'^/a/[A-Za-z0-9_-]+\.js$').hasMatch(uri.path)) {
        return null;
      }
      externalUri = Uri.https(
        uri.host,
        uri.path.substring(0, uri.path.length - 3),
      );
      uri = externalUri.replace(path: '${externalUri.path}/iframe');
    }
    // DEmbed uses the provider origin for its host document. Twitch verifies
    // that origin against parent; the forum's hostname is not the native host.
    if (const {'player.twitch.tv', 'clips.twitch.tv'}.contains(uri.host)) {
      uri = uri.replace(
        queryParameters: {
          ...uri.queryParametersAll,
          'parent': [uri.host],
          'autoplay': ['false'],
        },
      );
    }
    for (
      dom.Element? parent = element.parent;
      parent != null;
      parent = parent.parent
    ) {
      final original = oneboxHttpUri(
        parent.attributes['data-onebox-src'],
        siteUrl: siteUrl,
      );
      if (original != null) {
        externalUri = original;
        break;
      }
    }
    final title = element.attributes['title']?.trim();
    return EmbeddedOneboxData(
      uri: uri,
      externalUri: externalUri,
      title: title != null && title.isNotEmpty
          ? title
          : isScript
          ? 'Asciinema recording'
          : '${uri.host} embed',
      width: _dimension(element, 'width'),
      height: (_dimension(element, 'height') ?? 400).clamp(120, 2000),
    );
  }

  static double? _dimension(dom.Element element, String name) {
    final style = RegExp(
      '(?:^|;)\\s*$name\\s*:\\s*([0-9.]+)px\\s*(?:;|\$)',
    ).firstMatch(element.attributes['style'] ?? '')?.group(1);
    final value = double.tryParse(element.attributes[name] ?? style ?? '');
    return value != null && value.isFinite && value > 0 ? value : null;
  }
}

Uri? oneboxHttpUri(String? value, {String? siteUrl}) {
  if (value == null || value.trim().isEmpty) return null;
  final source = value.trim();
  var uri = Uri.tryParse(source.startsWith('//') ? 'https:$source' : source);
  if (uri == null) return null;
  if (!uri.hasScheme && siteUrl != null) {
    uri = Uri.tryParse(siteUrl)?.resolveUri(uri);
  }
  if (uri == null ||
      !const {'https', 'http'}.contains(uri.scheme) ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

Widget? embeddedOneboxWidgetBuilder(dom.Element element, {String? siteUrl}) {
  final data = EmbeddedOneboxData.from(element, siteUrl: siteUrl);
  if (data == null) return null;
  return EmbeddedOnebox(key: ValueKey(data.uri), data: data, siteUrl: siteUrl);
}

/// Providers only load after activation, keeping long topics inexpensive.
class EmbeddedOnebox extends StatefulWidget {
  const EmbeddedOnebox({super.key, required this.data, this.siteUrl});
  final EmbeddedOneboxData data;
  final String? siteUrl;

  @override
  State<EmbeddedOnebox> createState() => _EmbeddedOneboxState();
}

class _EmbeddedOneboxState extends State<EmbeddedOnebox> {
  bool _activated = false;

  @override
  void didUpdateWidget(EmbeddedOnebox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.uri != widget.data.uri) _activated = false;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: (data.width ?? 690).clamp(240, 900),
          ),
          child: _activated
              ? DEmbed(
                  uri: data.uri,
                  origins: {data.uri.origin},
                  title: data.title,
                  externalUri: data.externalUri,
                  height: data.height,
                  onOpenLink: (uri) => unawaited(
                    openLink(context, uri.toString(), siteUrl: widget.siteUrl),
                  ),
                )
              : DCard(
                  children: [
                    DCardHeader(title: Text(data.title)),
                    DCardContent(
                      child: Wrap(
                        spacing: DSpacing.controlGap,
                        children: [
                          DButton(
                            label: const Text('Load embed'),
                            onPressed: () => setState(() => _activated = true),
                          ),
                          DButton(
                            variant: DButtonVariant.outline,
                            label: const Text('Open in browser'),
                            onPressed: () => unawaited(
                              openLink(
                                context,
                                data.externalUri.toString(),
                                siteUrl: widget.siteUrl,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
