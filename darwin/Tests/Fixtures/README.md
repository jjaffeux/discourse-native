These tiny synthetic H.264 clips exercise native thumbnail decoding and display
rotation. They contain FFmpeg's test pattern, with no application or user data.

Regenerate from the repository root:

```sh
ffmpeg -f lavfi -i testsrc2=size=96x64:rate=5 -t 0.4 -c:v libx264 -pix_fmt yuv420p -movflags +faststart -an -y darwin/Tests/Fixtures/thumbnail.mp4
ffmpeg -display_rotation 90 -i darwin/Tests/Fixtures/thumbnail.mp4 -c copy -y darwin/Tests/Fixtures/thumbnail-rotated.mp4
swift test --package-path darwin
```
