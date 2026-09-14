import 'package:flutter/material.dart';

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
    final enabled = TickerMode.valuesOf(context).enabled;
    final identity = (
      shell?.videoThumbnails,
      shell?.lifecycle.capture(siteUrl).session,
      siteUrl,
      widget.source,
      enabled,
    );
    if (_identity == identity) return;
    _identity = identity;
    _request?.dispose();
    _request = enabled
        ? shell?.videoThumbnails.acquire(siteUrl: siteUrl, url: widget.source)
        : null;
  }

  @override
  void dispose() {
    _request?.dispose();
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
        image: imageForCover(
          context,
          MemoryImage(bytes),
          logicalSize: widget.size,
        ),
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    },
  );
}
