import 'dart:typed_data';

typedef ThumbnailGenerator = ThumbnailRequest Function(Uri source);

/// One consumer's interest in a thumbnail. Release it when the preview leaves
/// the tree; shared work is cancelled only after the last consumer leaves.
final class ThumbnailRequest {
  ThumbnailRequest(this.result, this._release);

  final Future<Uint8List?> result;
  final void Function() _release;
  bool _released = false;

  void dispose() {
    if (_released) return;
    _released = true;
    _release();
  }
}
