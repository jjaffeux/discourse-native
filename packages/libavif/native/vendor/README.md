# Vendored native source

`libavif/` contains the build, headers, and library sources from libavif
1.4.2, released at https://github.com/AOMediaCodec/libavif/releases/tag/v1.4.2.

Only the decoder library sources are retained. Applications, tests, and
unrelated third-party source trees are excluded.

`libavif/ext/dav1d/` contains dav1d 1.5.4 from tag `1.5.4`, commit
`54706fc6bc0cdecab7e9593974a4039cc038fca7`. libavif's local-codec build owns
its static Meson/Ninja build for the target selected by the Dart native-assets
hook. The upstream dav1d BSD-2-Clause license is retained as
`libavif/ext/dav1d/COPYING`.

`libavif/ext/libyuv/` contains libyuv commit
`644251f252a84bf8ce91ff0aca86a9b16b069ab8`, the exact revision pinned by
libavif 1.4.2. libavif's local-dependency build compiles it for accelerated
YUV-to-RGBA conversion without fetching source during application builds. The
upstream BSD-3-Clause license is retained as `libavif/ext/libyuv/LICENSE`.
