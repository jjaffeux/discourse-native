import 'dart:async';

import 'package:discourse_native/discourse_plugin_reader.dart'
    show HtmlBodyMountingNotification, HtmlBodyTiming;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Whether a chat row's HTML builds after the frame that first builds the
/// row, and the height the row holds until then.
typedef ChatBodyStaging = ({bool followsFrame, double? reservedHeight});

const ChatBodyStaging chatBodyAtOnce = (
  followsFrame: false,
  reservedHeight: null,
);

/// Decides how a row first built at [row] stages its body.
///
/// The transcript is reversed: row 0 is the present, at the bottom, and higher
/// rows reach into history. A row entering from the history edge during a
/// user scroll lies beyond the visible rows, so its body landing a frame later
/// grows away from them. A row entering from the present edge sits below the
/// visible rows, which its late body would push up; it is staged only when the
/// list measured it before, and holds that height until the body lands.
/// Programmatic positioning, jumps and live arrivals build at once.
ChatBodyStaging chatBodyStagingFor({
  required int row,
  required ScrollDirection direction,
  required (int, int)? visibleRange,
  required (double, bool isEstimated) Function(int row) extentForIndex,
}) {
  if (visibleRange case (final first, final last)) {
    switch (direction) {
      case ScrollDirection.reverse when row > last:
        return (followsFrame: true, reservedHeight: null);
      case ScrollDirection.forward when row < first:
        if (extentForIndex(row) case (final extent, false)) {
          return (followsFrame: true, reservedHeight: extent);
        }
      case _:
    }
  }
  return chatBodyAtOnce;
}

/// Latches [staging] for the lifetime of a chat row, so rebuilds and live
/// edits keep the timing the row first mounted with.
class ChatMessageBodyStaging extends StatefulWidget {
  const ChatMessageBodyStaging({
    super.key,
    required this.staging,
    required this.child,
  });

  /// Read once, when the row first builds.
  final ChatBodyStaging staging;
  final Widget child;

  @override
  State<ChatMessageBodyStaging> createState() => _ChatMessageBodyStagingState();
}

class _ChatMessageBodyStagingState extends State<ChatMessageBodyStaging> {
  late final bool _followsFrame;
  double? _reservedHeight;
  final _pending = <Future<void>>{};

  @override
  void initState() {
    super.initState();
    _followsFrame = widget.staging.followsFrame;
    _reservedHeight = widget.staging.reservedHeight;
    // A row whose bodies all built in its first frame reports nothing to wait
    // for; it must not keep the hold.
    if (_reservedHeight != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _release());
    }
  }

  void _release() {
    if (!mounted || _pending.isNotEmpty || _reservedHeight == null) return;
    // The landed body was measured at this height before, so releasing the
    // hold moves nothing unless the message changed meanwhile.
    setState(() => _reservedHeight = null);
  }

  bool _track(HtmlBodyMountingNotification notification) {
    final completion = notification.completion;
    _pending.add(completion);
    unawaited(
      completion.whenComplete(() {
        _pending.remove(completion);
        _release();
      }),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final body = HtmlBodyTiming(
      followsFrame: _followsFrame,
      child: widget.child,
    );
    final reserved = _reservedHeight;
    if (!_followsFrame) return body;
    return NotificationListener<HtmlBodyMountingNotification>(
      onNotification: _track,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: reserved ?? 0),
        child: body,
      ),
    );
  }
}
