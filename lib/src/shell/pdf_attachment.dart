import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:html/dom.dart' as dom;

import '../data/site_lifecycle.dart';
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
  ({
    SitePdfThumbnailRepository repository,
    SiteLease lease,
    String siteUrl,
    Uri source,
  })?
  _configuration;
  bool _enabled = true;
  bool _hasArtwork = false;
  bool _viewportCheckScheduled = false;

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
    _enabled = TickerMode.valuesOf(context).enabled;
    final siteUrl = widget.siteUrl;
    final lease = siteUrl == null ? null : shell?.lifecycle.capture(siteUrl);
    final identity = (
      shell?.pdfThumbnails,
      lease?.session,
      siteUrl,
      source,
      _enabled,
    );
    if (_identity == identity) return;
    _identity = identity;
    _releaseRequest();
    _hasArtwork = false;
    _configuration =
        shell != null &&
            lease != null &&
            siteUrl != null &&
            source != null &&
            source.hasAuthority
        ? (
            repository: shell.pdfThumbnails,
            lease: lease,
            siteUrl: siteUrl,
            source: source,
          )
        : null;
    _scheduleViewportCheck();
  }

  void _releaseRequest() {
    final request = _request;
    _request = null;
    request?.dispose();
  }

  void _scheduleViewportCheck() {
    final configuration = _configuration;
    if (_viewportCheckScheduled ||
        !_enabled ||
        _hasArtwork ||
        configuration == null ||
        !configuration.lease.isCurrent) {
      return;
    }
    _viewportCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportCheckScheduled = false;
      final configuration = _configuration;
      if (!mounted ||
          !_enabled ||
          _hasArtwork ||
          configuration == null ||
          !configuration.lease.isCurrent) {
        return;
      }
      if (_inViewport()) {
        if (_request == null) {
          final request = configuration.repository.acquire(
            siteUrl: configuration.siteUrl,
            url: configuration.source,
          );
          setState(() => _request = request);
          request.result.then((bytes) {
            if (mounted &&
                identical(_request, request) &&
                configuration.lease.isCurrent &&
                bytes != null) {
              _hasArtwork = true;
            }
          }).ignore();
        }
      } else if (_request != null) {
        setState(_releaseRequest);
      }
      // Observe layout and scrolling without requesting idle frames.
      _scheduleViewportCheck();
    });
  }

  bool _inViewport() {
    final source = context.findRenderObject();
    if (source is! RenderBox || !source.attached || !source.hasSize) {
      return false;
    }
    final view = View.of(context);
    var viewport = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    RenderObject child = source;
    for (var parent = child.parent; parent != null; parent = child.parent) {
      if (!parent.paintsChild(child)) return false;
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        viewport = viewport.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(null), clip),
        );
      }
      if (parent is RenderAbstractViewport && parent is RenderBox) {
        viewport = viewport.intersect(
          MatrixUtils.transformRect(
            parent.getTransformTo(null),
            parent.paintBounds,
          ),
        );
      }
      child = parent;
    }
    if (!viewport.isFinite || viewport.isEmpty) return false;
    final bounds = MatrixUtils.transformRect(
      source.getTransformTo(null),
      source.paintBounds,
    );
    return bounds.isFinite && !bounds.isEmpty && bounds.overlaps(viewport);
  }

  @override
  void dispose() {
    _releaseRequest();
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
