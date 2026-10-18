import 'dart:async';
import 'dart:collection';

import '../data/site_lifecycle.dart';

/// Visibility permits playback; becoming visible never starts it.
abstract interface class ReaderMediaEndpoint {
  Future<void> setPlaybackVisible(bool visible);
  void retire();
}

final class ReaderMediaAttachment {
  ReaderMediaAttachment._(
    this._owner,
    this.source,
    this._endpoint,
    this._account,
    this._exclusiveVideo,
  );

  final ReaderMediaActivity _owner;
  final Object source;
  final ReaderMediaEndpoint _endpoint;
  final SiteLease? _account;
  final bool _exclusiveVideo;
  final _pending = Queue<bool>();
  bool? _requested;
  bool _draining = false;
  bool _issuing = false;
  bool _latePlaying = false;

  bool get isCurrent =>
      identical(_owner.attachment, this) &&
      !_owner._disposed &&
      (_account?.isCurrent ?? true);

  bool get mayPlay => isCurrent && _owner._allowed;

  void _enqueue(bool visible, {bool force = false}) {
    if (!isCurrent || (!force && _requested == visible)) return;
    _requested = visible;
    _pending.add(visible);
    if (!_draining) unawaited(_drain());
  }

  Future<void> _drain() async {
    _draining = true;
    try {
      while (isCurrent && _pending.isNotEmpty) {
        final visible = _pending.removeFirst() && mayPlay;
        try {
          _issuing = true;
          final completion = _endpoint.setPlaybackVisible(visible);
          _issuing = false;
          await completion;
        } on Object {
          // Platform views can detach while a visibility command is pending.
        } finally {
          _issuing = false;
        }
        if (_latePlaying) {
          _latePlaying = false;
          if (isCurrent && !mayPlay) _pending.add(false);
        }
      }
    } finally {
      _draining = false;
    }
  }
}

/// Owns activity for one retained reader surface and its current source.
final class ReaderMediaActivity {
  ReaderMediaAttachment? _attachment;
  bool _foreground = true;
  bool _rowVisible = true;
  bool _geometryVisible = true;
  ReaderMediaAttachment? _fullscreen;
  bool _fullscreenVisible = false;
  bool _disposed = false;
  static ReaderMediaAttachment? _playingVideo;

  ReaderMediaAttachment? get attachment => _attachment;

  bool get _allowed =>
      _foreground &&
      ((_rowVisible && _geometryVisible) ||
          (identical(_fullscreen, _attachment) && _fullscreenVisible));

  bool get mayStart => !_disposed && _allowed;

  ReaderMediaAttachment attach({
    required Object source,
    required ReaderMediaEndpoint endpoint,
    SiteLease? account,
    bool exclusiveVideo = false,
  }) {
    retire();
    final attachment = ReaderMediaAttachment._(
      this,
      source,
      endpoint,
      account,
      exclusiveVideo,
    );
    _attachment = attachment;
    attachment._enqueue(attachment.mayPlay);
    return attachment;
  }

  void present({
    required bool foreground,
    required bool rowVisible,
    required bool geometryVisible,
  }) {
    _foreground = foreground;
    _rowVisible = rowVisible;
    _geometryVisible = geometryVisible;
    _synchronize();
  }

  void fullscreen(ReaderMediaAttachment attachment, {required bool visible}) {
    if (!attachment.isCurrent) return;
    _fullscreen = attachment;
    _fullscreenVisible = visible;
    _synchronize();
  }

  void endFullscreen(ReaderMediaAttachment attachment) {
    if (!identical(_fullscreen, attachment)) return;
    _fullscreen = null;
    _fullscreenVisible = false;
    _synchronize();
  }

  void _synchronize() {
    final attachment = _attachment;
    if (attachment == null) return;
    if (!attachment.isCurrent) {
      retire();
      return;
    }
    if (!attachment.mayPlay) _releaseVideo(attachment);
    attachment._enqueue(attachment.mayPlay);
  }

  void refresh(ReaderMediaAttachment attachment) {
    if (!attachment.isCurrent) return;
    attachment._enqueue(attachment.mayPlay, force: true);
  }

  bool claimPlay(ReaderMediaAttachment attachment) {
    if (!attachment.mayPlay) return false;
    if (attachment._exclusiveVideo && !identical(_playingVideo, attachment)) {
      final previous = _playingVideo;
      _playingVideo = attachment;
      previous?._enqueue(false, force: true);
    }
    return true;
  }

  void playbackChanged(ReaderMediaAttachment attachment, bool playing) {
    if (!attachment.isCurrent) return;
    if (!playing) {
      _releaseVideo(attachment);
    } else if (attachment.mayPlay) {
      claimPlay(attachment);
    } else if (!attachment._issuing) {
      if (attachment._draining) {
        attachment._latePlaying = true;
      } else {
        attachment._enqueue(false, force: true);
      }
    }
  }

  static void _releaseVideo(ReaderMediaAttachment attachment) {
    if (identical(_playingVideo, attachment)) _playingVideo = null;
  }

  void retire() {
    final attachment = _attachment;
    _attachment = null;
    _fullscreen = null;
    _fullscreenVisible = false;
    if (attachment == null) return;
    _releaseVideo(attachment);
    attachment._pending.clear();
    attachment._endpoint.retire();
  }

  void dispose() {
    _disposed = true;
    retire();
  }
}
