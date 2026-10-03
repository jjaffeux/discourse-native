package org.discourse.video_optimizer;

import static org.junit.Assert.*;
import org.junit.Test;

public final class VideoPolicyTest {
  @Test public void capsLandscapeAndPortraitWithoutUpscaling() {
    VideoPolicy landscape = new VideoPolicy(3840, 2160);
    assertEquals(1920, landscape.width);
    assertEquals(1080, landscape.height);
    VideoPolicy portrait = new VideoPolicy(2160, 3840);
    assertEquals(1080, portrait.width);
    assertEquals(1920, portrait.height);
    VideoPolicy small = new VideoPolicy(640, 480);
    assertEquals(640, small.width);
    assertEquals(480, small.height);
    VideoPolicy square = new VideoPolicy(2048, 2048);
    assertEquals(1080, square.width);
    assertEquals(1080, square.height);
  }

  @Test public void rejectsAudioLossTruncationAndWrongOrientation() {
    assertTrue(VideoPolicy.validOutput(2160, 3840, 10_000_000, 1, 1080, 1920, 10_000_000, 1));
    assertFalse(VideoPolicy.validOutput(2160, 3840, 10_000_000, 1, 1080, 1920, 10_000_000, 0));
    assertFalse(VideoPolicy.validOutput(2160, 3840, 10_000_000, 1, 1080, 1920, 5_000_000, 1));
    assertFalse(VideoPolicy.validOutput(2160, 3840, 10_000_000, 1, 1920, 1080, 10_000_000, 1));
    assertFalse(VideoPolicy.validOutput(640, 480, 10_000_000, 0, 1440, 1080, 10_000_000, 0));
  }

  @Test(expected = IllegalArgumentException.class)
  public void rejectsInvalidDimensions() { new VideoPolicy(0, 100); }
}
