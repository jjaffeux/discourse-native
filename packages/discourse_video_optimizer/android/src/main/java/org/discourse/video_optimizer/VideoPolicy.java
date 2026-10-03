package org.discourse.video_optimizer;

/** Geometry and validation shared by the encoder and its native tests. */
final class VideoPolicy {
  final int width;
  final int height;
  final int bitrate;

  VideoPolicy(int width, int height) {
    if (width <= 0 || height <= 0 || Math.max(width, height) > 8192) {
      throw new IllegalArgumentException("Unsupported video dimensions");
    }
    double scale = Math.min(1.0,
        Math.min(1920.0 / Math.max(width, height), 1080.0 / Math.min(width, height)));
    this.width = Math.max(2, (int) (width * scale) / 2 * 2);
    this.height = Math.max(2, (int) (height * scale) / 2 * 2);
    // About 5 Mbps at 1080p. Smaller frames need less bitrate.
    bitrate = Math.max(500_000, (int) (5_000_000L * this.width * this.height / (1920 * 1080)));
  }

  static boolean validOutput(int sourceWidth, int sourceHeight, long sourceDurationUs,
      int sourceAudioTracks, int width, int height, long durationUs, int audioTracks) {
    return width > 0 && height > 0 && sourceWidth > 0 && sourceHeight > 0
        && sourceDurationUs > 0 && Math.abs(durationUs - sourceDurationUs) <= 250_000
        && sourceAudioTracks == audioTracks
        && width <= sourceWidth + 2 && height <= sourceHeight + 2
        && Math.max(width, height) <= 1920 && Math.min(width, height) <= 1080
        && Math.abs((double) width / height - (double) sourceWidth / sourceHeight) < 0.02;
  }
}
