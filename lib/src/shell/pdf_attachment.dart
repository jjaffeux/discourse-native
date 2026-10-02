import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../data/site_pdf_thumbnail_repository.dart';
import '../data/site_thumbnail_repository.dart';
import 'open_link.dart';
import 'shell_scope.dart';
import 'site_url.dart';

/// First-page artwork; the Native attachment owns its bounds and decoration.
class PdfThumbnail extends StatefulWidget {
  const PdfThumbnail({super.key, required this.url, required this.siteUrl});

  final String? url;
  final String? siteUrl;

  @override
  State<PdfThumbnail> createState() => _PdfThumbnailState();
}

class _PdfThumbnailState extends State<PdfThumbnail> {
  Object? _identity;
  ThumbnailRequest? _request;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateRequest();
  }

  @override
  void didUpdateWidget(PdfThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateRequest();
  }

  void _updateRequest() {
    final shell = ShellScope.maybeIdentityOf(context);
    final source = widget.url == null
        ? null
        : Uri.tryParse(resolveSiteUrl(widget.url!, widget.siteUrl));
    final enabled = TickerMode.valuesOf(context).enabled;
    final siteUrl = widget.siteUrl;
    final identity = (
      shell?.pdfThumbnails,
      siteUrl == null ? null : shell?.lifecycle.capture(siteUrl).session,
      siteUrl,
      source,
      enabled,
    );
    if (_identity == identity) return;
    _identity = identity;
    _request?.dispose();
    _request =
        enabled && siteUrl != null && source != null && source.hasAuthority
        ? shell?.pdfThumbnails.acquire(siteUrl: siteUrl, url: source)
        : null;
  }

  @override
  void dispose() {
    _request?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    key: ObjectKey(_request),
    future: _request?.result,
    builder: (context, snapshot) {
      const fallback = Center(child: Icon(Icons.picture_as_pdf_outlined));
      final bytes = snapshot.data;
      if (bytes == null) return fallback;
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => fallback,
      );
    },
  );
}

class PdfAttachment extends StatelessWidget {
  const PdfAttachment({
    super.key,
    required this.filename,
    required this.url,
    required this.siteUrl,
    this.onPressed,
    this.selected = false,
    this.size = DAttachmentSize.regular,
  });

  final String filename;
  final String? url;
  final String? siteUrl;
  final VoidCallback? onPressed;
  final bool selected;
  final DAttachmentSize size;

  @override
  Widget build(BuildContext context) => DAttachment(
    size: size,
    backgroundColor: selected
        ? Theme.of(context).colorScheme.primary.withValues(alpha: .18)
        : null,
    children: [
      DAttachmentMedia(
        variant: DAttachmentMediaVariant.image,
        semanticLabel: context.l10n.previewOf(filename),
        child: PdfThumbnail(url: url, siteUrl: siteUrl),
      ),
      DAttachmentContent(children: [DAttachmentTitle(child: Text(filename))]),
      if (onPressed != null)
        DAttachmentTrigger(
          semanticLabel: filename,
          isLink: true,
          onPressed: onPressed,
        ),
    ],
  );
}

Widget? pdfAttachmentWidgetBuilder(dom.Element element, {String? siteUrl}) {
  if (element.localName != 'a' || !element.classes.contains('attachment')) {
    return null;
  }
  final href = element.attributes['href'];
  if (href == null || !isPdfAttachment(element.text, href)) return null;
  final url = resolveSiteUrl(href, siteUrl);
  final source = Uri.tryParse(url);
  if (source == null || !{'http', 'https'}.contains(source.scheme)) return null;
  return Builder(
    builder: (context) => PdfAttachment(
      filename: element.text.trim(),
      url: url,
      siteUrl: siteUrl,
      onPressed: () => openLink(context, url, siteUrl: siteUrl),
    ),
  );
}
