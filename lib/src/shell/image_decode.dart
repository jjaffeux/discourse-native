import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

Size? safeImageLayoutSize(double? width, double? height) {
  if (width == null ||
      height == null ||
      !width.isFinite ||
      !height.isFinite ||
      width < 1 ||
      height < 1) {
    return null;
  }

  const maximumWidth = 10000.0;
  const minimumAspectRatio = 1 / 4;
  const maximumAspectRatio = 4.0;
  final ratio = width / height;
  if (!ratio.isFinite || ratio <= 0) return null;
  final safeWidth = width.clamp(1.0, maximumWidth).toDouble();
  final safeRatio = ratio
      .clamp(minimumAspectRatio, maximumAspectRatio)
      .toDouble();
  return Size(safeWidth, safeWidth / safeRatio);
}

Size? parseSafeImageLayoutSize(String? width, String? height) =>
    safeImageLayoutSize(
      double.tryParse(width ?? ''),
      double.tryParse(height ?? ''),
    );

Size? parseSafeImageInformationSize(String? text) {
  if (text == null) return null;
  final dimensions = text.trim().split(' ').first;
  final parts = dimensions.split(RegExp('x|×'));
  if (parts.length != 2) return null;
  return parseSafeImageLayoutSize(parts[0], parts[1]);
}

int imagePhysicalPixels(BuildContext context, double logicalPixels) {
  final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  return math.max(1, (logicalPixels * devicePixelRatio).ceil());
}

/// The physical width to decode an image at when it is drawn [logicalWidth]
/// wide by a layout that can resize continuously.
///
/// Every distinct decode size is its own [ImageCache] entry and a full decode,
/// so a width that followed the layout exactly would decode every visible
/// image again for each pixel of a window resize, divider drag, sidebar toggle
/// or rotation, and keep each result alive. Use [imagePhysicalPixels] for a
/// size that does not follow the layout.
int imageDecodeWidth(BuildContext context, double logicalWidth) =>
    coarseDecodePixels(imagePhysicalPixels(context, logicalWidth));

/// Rounds [physicalPixels] up to one of eight sizes per doubling.
///
/// Keeping the four leading bits bounds the extra width below an eighth of the
/// request at every scale. A fixed step would instead inflate a small
/// thumbnail several times over and still leave dozens of sizes across a
/// desktop-wide drag. Rounding is always up, so a decode is never narrower
/// than the image is drawn.
int coarseDecodePixels(int physicalPixels) {
  final step = 1 << math.max(0, physicalPixels.bitLength - 4);
  return (physicalPixels + step - 1) ~/ step * step;
}

/// The `srcset` source an image drawn on a screen of [devicePixelRatio]
/// should load, or [src] when [srcset] offers no density to choose from.
///
/// Discourse's post processor points an optimized image's `src` at the copy
/// sized for 1x and lists larger copies in `srcset` by density
/// (`responsive_post_image_sizes`, 1.5x and 2x by default), leaving the choice
/// to the browser. Drawing `src` on a 2x screen upscales half the pixels the
/// image needs. This takes the smallest density that covers
/// [devicePixelRatio], or the largest when none does, with [src] standing in
/// for 1x when [srcset] lists no 1x, as it does in a browser.
///
/// The choice follows the screen alone, so a resizing layout never switches
/// source, or cache entry. Width descriptors are chosen by layout width
/// through `sizes` instead, so a [srcset] using them yields [src], as does
/// one with no valid candidate. The URL is returned as written, to be
/// resolved the way [src] is.
String srcsetCandidate({
  required String src,
  required String? srcset,
  required double devicePixelRatio,
}) {
  final densities = srcset == null ? null : _srcsetDensities(srcset);
  if (densities == null) return src;
  if (src.isNotEmpty) densities.putIfAbsent(1, () => src);
  if (densities.isEmpty) return src;
  final ordered = densities.keys.toList()..sort();
  final chosen = ordered.firstWhere(
    (density) => density >= devicePixelRatio - _srcsetDensityTolerance,
    orElse: () => ordered.last,
  );
  return densities[chosen]!;
}

/// How far a density may fall short of the screen's and still be chosen.
/// Common ratios sit exactly on the densities Discourse lists, so without it
/// a 1x screen reported as 1.0000001 would switch to the 1.5x source.
const _srcsetDensityTolerance = 0.01;

final _srcsetPositiveInteger = RegExp(r'^\d*[1-9]\d*$');
final _srcsetFloatingPoint = RegExp(
  r'^-?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][-+]?\d+)?$',
);
final _srcsetTrailingCommas = RegExp(r',+$');

// ASCII whitespace, as the standard defines it.
bool _isSrcsetSpace(int char) =>
    const {0x09, 0x0A, 0x0C, 0x0D, 0x20}.contains(char);

/// The density candidates in [srcset], the first of each density winning, or
/// null when one describes a width.
///
/// Follows the HTML standard's "parse a srcset attribute": a URL runs to the
/// next whitespace, so it may contain commas, and only trailing commas end
/// it. A candidate the standard rejects is skipped.
Map<double, String>? _srcsetDensities(String srcset) {
  final densities = <double, String>{};
  final length = srcset.length;
  var position = 0;
  while (true) {
    while (position < length &&
        (_isSrcsetSpace(srcset.codeUnitAt(position)) ||
            srcset.codeUnitAt(position) == 0x2C)) {
      position++;
    }
    if (position >= length) return densities;

    final start = position;
    while (position < length && !_isSrcsetSpace(srcset.codeUnitAt(position))) {
      position++;
    }
    var url = srcset.substring(start, position);
    final descriptors = <String>[];
    if (url.endsWith(',')) {
      url = url.replaceFirst(_srcsetTrailingCommas, '');
    } else {
      // Whitespace separates descriptors and a comma ends the candidate,
      // except within parentheses.
      final descriptor = StringBuffer();
      var inParentheses = false;
      while (position < length) {
        final char = srcset.codeUnitAt(position++);
        if (inParentheses) {
          descriptor.writeCharCode(char);
          inParentheses = char != 0x29;
        } else if (_isSrcsetSpace(char) || char == 0x2C) {
          if (descriptor.isNotEmpty) {
            descriptors.add(descriptor.toString());
            descriptor.clear();
          }
          if (char == 0x2C) break;
        } else {
          descriptor.writeCharCode(char);
          inParentheses = char == 0x28;
        }
      }
      if (descriptor.isNotEmpty) descriptors.add(descriptor.toString());
    }

    double? density;
    var width = false;
    var height = false;
    var valid = true;
    for (final descriptor in descriptors) {
      final value = descriptor.substring(0, descriptor.length - 1);
      switch (descriptor[descriptor.length - 1]) {
        case 'w'
            when !width &&
                density == null &&
                _srcsetPositiveInteger.hasMatch(value):
          width = true;
        case 'x'
            when !width &&
                !height &&
                density == null &&
                _srcsetFloatingPoint.hasMatch(value):
          density = double.parse(value);
        case 'h'
            when !height &&
                density == null &&
                _srcsetPositiveInteger.hasMatch(value):
          height = true;
        default:
          valid = false;
      }
      if (!valid) break;
    }
    if (!valid || (height && !width)) continue;
    if (width) return null;
    final candidate = density ?? 1;
    if (candidate.isFinite && candidate >= 0) {
      densities.putIfAbsent(candidate, () => url);
    }
  }
}

/// The most source pixels [FittedMemoryImage] decodes.
///
/// A fit bounds the bitmap a decode keeps, not what it allocates on the way:
/// PNG and GIF have no scaled decode, so the whole source is decoded before
/// it is resized, and lossless WebP holds every source pixel while it
/// decodes. A few kilobytes of either can declare hundreds of megapixels.
/// Discourse refuses uploads from 40 megapixels by default
/// (`max_image_megapixels`), and the optimized copies posts draw are far
/// smaller.
const maximumFittedImagePixels = 50 * 1000 * 1000;

/// A [FittedMemoryImage] source whose header declares more than
/// [maximumFittedImagePixels]; none of it was decoded.
final class ImageTooLargeException implements Exception {
  const ImageTooLargeException(this.width, this.height);

  final int width;
  final int height;

  @override
  String toString() =>
      'Image of ${width}x$height pixels exceeds the decode limit';
}

/// Decodes [bytes] to fit within [width] × [height] physical pixels, keeping
/// the aspect ratio and never upscaling: [ResizeImagePolicy.fit] without
/// `allowUpscaling`. A source over [maximumFittedImagePixels] fails with
/// [ImageTooLargeException] instead.
///
/// [ResizeImage] keys its cache entry on the requested bound, so every layout
/// wider than the source decodes the same pixels again under a new key. This
/// provider's key is the bound clamped to the source's own size instead, so
/// all of those layouts share one bitmap. The size is read from the encoded
/// header once per [bytes], before their first key; every later key is
/// synchronous, so a cached bitmap still shows in the frame that asks for it.
@immutable
final class FittedMemoryImage extends ImageProvider<FittedMemoryImage> {
  const FittedMemoryImage(this.bytes, {this.width, this.height})
    : assert(width != null || height != null);

  final Uint8List bytes;
  final int? width;
  final int? height;

  @override
  Future<FittedMemoryImage> obtainKey(ImageConfiguration configuration) =>
      (_sourceSizes[bytes] ??= _readSourceSize(bytes)).then((size) {
        // A fit bound at or beyond the source in a dimension constrains
        // nothing in it, so clamping never changes what the key decodes to.
        final key = FittedMemoryImage(
          bytes,
          width: _clamp(width, size?.$1),
          height: _clamp(height, size?.$2),
        );
        return key == this ? this : key;
      });

  static int? _clamp(int? bound, int? source) =>
      bound == null || source == null ? bound : math.min(bound, source);

  @override
  ImageStreamCompleter loadImage(
    FittedMemoryImage key,
    ImageDecoderCallback decode,
  ) {
    final completer = MultiFrameImageStreamCompleter(
      codec: _decode(key, decode),
      scale: 1,
    );
    completer.addEphemeralErrorListener((_, _) {
      // A synchronous failure can precede ImageCache registering this key.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }

  // Chained rather than awaited: awaiting a SynchronousFuture resumes the
  // awaiting body re-entrantly, and an error it throws after that is reported
  // as uncaught.
  static Future<ui.Codec> _decode(
    FittedMemoryImage key,
    ImageDecoderCallback decode,
  ) {
    final sourceSize = _sourceSizes[key.bytes] ??= _readSourceSize(key.bytes);
    return sourceSize.then((size) => _decodeSource(key, decode, size));
  }

  static Future<ui.Codec> _decodeSource(
    FittedMemoryImage key,
    ImageDecoderCallback decode,
    (int, int)? sourceSize,
  ) async {
    final (width, height) = sourceSize ?? (0, 0);
    if (width * height > maximumFittedImagePixels) {
      throw ImageTooLargeException(width, height);
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(key.bytes);
    return decode(
      buffer,
      getTargetSize: (sourceWidth, sourceHeight) =>
          _fitWithin(sourceWidth, sourceHeight, key.width, key.height),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FittedMemoryImage &&
      identical(other.bytes, bytes) &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(identityHashCode(bytes), width, height);
}

// By identity, as MemoryImage keys are: the site image cache hands every
// widget showing a URL the same bytes.
final _sourceSizes = Expando<Future<(int, int)?>>('encoded image size');

Future<(int, int)?> _readSourceSize(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  (int, int)? size;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    // Reads the header only; no frame is decoded.
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    size = (descriptor.width, descriptor.height);
  } catch (_) {
    // Unreadable bytes keep the requested bound; their decode reports them.
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
  _sourceSizes[bytes] = SynchronousFuture(size);
  return size;
}

ui.TargetImageSize _fitWithin(
  int intrinsicWidth,
  int intrinsicHeight,
  int? maxWidth,
  int? maxHeight,
) {
  // ResizeImage's arithmetic, so a bound decodes to the same size through
  // either provider.
  final aspectRatio = intrinsicWidth / intrinsicHeight;
  var width = intrinsicWidth;
  var height = intrinsicHeight;
  if (maxWidth != null && width > maxWidth) {
    width = maxWidth;
    height = width ~/ aspectRatio;
  }
  if (maxHeight != null && height > maxHeight) {
    height = maxHeight;
    width = (height * aspectRatio).floor();
  }
  return ui.TargetImageSize(
    width: math.max(1, width),
    height: math.max(1, height),
  );
}

ResizeImage memoryImageForLayout(
  BuildContext context,
  Uint8List bytes, {
  required Size logicalSize,
}) {
  return ResizeImage(
    MemoryImage(bytes),
    width: imagePhysicalPixels(context, logicalSize.width),
    height: imagePhysicalPixels(context, logicalSize.height),
    policy: ResizeImagePolicy.fit,
  );
}

ImageProvider<Object> imageForCover(
  BuildContext context,
  ImageProvider<Object> provider, {
  required Size logicalSize,
}) => _CoverImage(
  provider,
  imagePhysicalPixels(context, logicalSize.width),
  imagePhysicalPixels(context, logicalSize.height),
);

@immutable
final class _CoverImage extends ImageProvider<_CoverImageKey> {
  const _CoverImage(this.provider, this.width, this.height);

  final ImageProvider<Object> provider;
  final int width;
  final int height;

  @override
  Future<_CoverImageKey> obtainKey(ImageConfiguration configuration) => provider
      .obtainKey(configuration)
      .then((key) => _CoverImageKey(key, width, height));

  @override
  ImageStreamCompleter loadImage(
    _CoverImageKey key,
    ImageDecoderCallback decode,
  ) {
    final completer = provider.loadImage(key.providerKey, (
      buffer, {
      getTargetSize,
    }) {
      assert(getTargetSize == null);
      return decode(
        buffer,
        getTargetSize: (intrinsicWidth, intrinsicHeight) {
          // Cover needs the larger scale, including pixels outside the crop.
          // One target dimension preserves the poster's own aspect ratio;
          // clamping it avoids decoding an upscale of a small source.
          return key.width * intrinsicHeight >= key.height * intrinsicWidth
              ? ui.TargetImageSize(width: math.min(key.width, intrinsicWidth))
              : ui.TargetImageSize(
                  height: math.min(key.height, intrinsicHeight),
                );
        },
      );
    });
    completer.addEphemeralErrorListener((_, _) {
      // A synchronous failure can precede ImageCache registering this key.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }

  @override
  bool operator ==(Object other) =>
      other is _CoverImage &&
      provider == other.provider &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(provider, width, height);
}

@immutable
final class _CoverImageKey {
  const _CoverImageKey(this.providerKey, this.width, this.height);

  final Object providerKey;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is _CoverImageKey &&
      providerKey == other.providerKey &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(providerKey, width, height);
}
