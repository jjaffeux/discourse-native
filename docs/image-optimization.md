# Composer image optimization

The composer prepares uploads before invoking the network uploader. Topic,
private-message, chat, and nested-editor uploads share this boundary, including
files selected through a picker, pasted, or dropped. `ComposerUploadPreparer`
keeps the codec replaceable without changing upload transport or UI.

`ComposerImageOptimizer` uses `image` 4.10.1 in a disposable isolate. One job runs
at a time across composers; files outside the byte limits return before joining
that queue, and network uploads remain concurrent. Inputs and outputs
use app temporary storage rather than passing pixel buffers between isolates.
The controller retains the prepared file through network retries and releases
it on success, removal, cancellation, or disposal.

## Policy

- Respect the site and iOS optimization switches. JPEG/PNG eligibility starts at
  the site's byte threshold (default 524288 bytes).
- Bake EXIF orientation before evaluating dimensions. Strip camera/EXIF and PNG
  text metadata, retaining ICC colour profiles.
- A JPEG output carries its profile in one APP2 segment numbered 1 of 1. The
  encoder cannot split one, so a profile over 65,519 bytes, or a JPEG source's
  profile that spans several segments, is dropped rather than written truncated.
- Expand palette and grayscale PNGs to RGB before encoding. A grayscale PNG's
  gray profile cannot describe the RGB result, so it is dropped.
- Resize only when width exceeds the site's dimension threshold, to its width
  target (both default to 1920). Preserve aspect ratio and never upscale.
- Encode opaque pixels as JPEG and transparent pixels as lossy WebP. Use the
  site's encode quality, falling back to image quality (default 90).
- Require the output extension to be authorized, validate the encoded output's
  dimensions by decoding it, and accept only a smaller result.
- Retain animated PNGs, GIFs, HEIC/JXL, existing WebP, unsupported/corrupt inputs,
  and any file whose preparation fails. Animated-format conversion is deferred.
- The mobile photo picker already exports JPEGs with site width/quality settings.
  These carry `imageOptimizationApplied` to avoid another lossy encode. Its
  existing export behavior differs from byte-threshold-based processing.

The Dart encoder does not reproduce MozJPEG byte for byte, and area averaging
replaces the web worker's Lanczos3 resize filter. Quality numbers are specific to
each codec. Unlike the web JPEG path, larger results are discarded; valid results
below 20 KB are accepted.

## Resource limits and measurement

Inputs above 32 MiB or 16 megapixels retain their originals. Dimensions are read
before constructing decoder buffers: `JpegDecoder.startDecode` itself can allocate
substantial memory. A worker exceeding 30 seconds is terminated. Cancellation also
terminates active encoding and removes temporary files; cancelling a queued job
does not allow subsequent work to overlap the current job.

Build the standalone benchmark in AOT mode and pass local JPEG/PNG paths:

```sh
dart compile exe tool/benchmark_composer_image_optimization.dart -o /tmp/image-bench
/tmp/image-bench photo.jpg screenshot.png
```

The benchmark includes output validation and bypasses the byte eligibility
threshold so small fixtures can exercise encoding. Peak RSS is for the whole
benchmark process, not incremental codec memory.

On the development Mac, a generated 4032×3024 patterned JPEG reduced from
9,200,918 to 588,026 bytes in 1.3 seconds. Discourse's
2032×1312 transparent PNG fixture reduced from 421,730 to 127,564 bytes in 1.2
seconds. Process peak RSS across this run was 348 MiB. These are synthetic/fixture measurements, not physical iOS or Linux
benchmarks. Measure release builds on those devices before raising resource
limits or increasing concurrency.
