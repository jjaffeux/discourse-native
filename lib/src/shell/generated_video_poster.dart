import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/site_video_thumbnail_repository.dart';
import 'image_decode.dart';
import 'shell_scope.dart';

/// Account-owned image data for the existing video preview. This never mounts
/// a platform video player, and hidden panes release their extraction requests.
class GeneratedVideoPoster extends StatefulWidget {
  const GeneratedVideoPoster({
    super.key,
    required this.source,
    required this.siteUrl,
    required this.size,
  });

  final Uri source;
  final String? siteUrl;
  final Size size;

  @override
  State<GeneratedVideoPoster> createState() => _GeneratedVideoPosterState();
}

class _GeneratedVideoPosterState extends State<GeneratedVideoPoster> {
  Object? _identity;
  VideoThumbnailRequest? _request;
  bool _enabled = true;
  bool _hasPoster = false;
  bool _viewportCheckScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateRequest();
  }

  @override
  void didUpdateWidget(GeneratedVideoPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateRequest();
  }

  void _updateRequest() {
    final shell = ShellScope.maybeIdentityOf(context);
    final siteUrl = widget.siteUrl ?? widget.source.origin;
    _enabled = TickerMode.valuesOf(context).enabled;
    final identity = (
      shell?.videoThumbnails,
      shell?.lifecycle.capture(siteUrl).session,
      siteUrl,
      widget.source,
      _enabled,
    );
    if (_identity == identity) return;
    _identity = identity;
    _releaseRequest();
    _hasPoster = false;
    _scheduleViewportCheck();
  }

  void _releaseRequest() {
    final request = _request;
    _request = null;
    request?.dispose();
  }

  void _scheduleViewportCheck() {
    if (_viewportCheckScheduled || !_enabled || _hasPoster) return;
    _viewportCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportCheckScheduled = false;
      if (!mounted || !_enabled || _hasPoster) return;
      if (_inViewport()) {
        if (_request == null) {
          final shell = ShellScope.maybeIdentityOf(context);
          final request = shell?.videoThumbnails.acquire(
            siteUrl: widget.siteUrl ?? widget.source.origin,
            url: widget.source,
          );
          if (request != null) {
            setState(() => _request = request);
            request.result.then((bytes) {
              if (mounted && identical(_request, request) && bytes != null) {
                _hasPoster = true;
              }
            }).ignore();
          }
        }
      } else if (_request != null) {
        setState(_releaseRequest);
      }
      // Observe ancestor layout and scrolling on natural frames without
      // requesting frames for previews that remain outside the viewport.
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
    // A new request must not retain the previous video's completed snapshot.
    key: ObjectKey(_request),
    future: _request?.result,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (bytes == null) return const SizedBox.shrink();
      return Image(
        image: memoryImageForCover(context, bytes, logicalSize: widget.size),
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    },
  );
}
