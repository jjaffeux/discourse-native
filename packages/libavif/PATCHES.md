# Local patches

This directory vendors the published `libavif` 0.1.1 package from
<https://pub.dev/api/archives/libavif-0.1.1.tar.gz>.

- Archive SHA-256: `e96c31379cd472786133085ec18b977c79d3965a1a339bf283447e7b85955268`
- Upstream source: <https://github.com/dartgfx/libavif>

The published archive is the baseline. The codec implementations and their
licenses are unchanged. The local differences are listed below.

## Windows native build paths

Cargo's native build output nests CMake, Meson, and compiler output directories.
MSVC fails to create dav1d object files when those paths exceed its path limit,
even with the application checked out at `D:\s`.

On Windows, `native/build.rs` places CMake output under the user's temporary
directory. A hash of Cargo's full `OUT_DIR` separates projects and build
configurations. Library discovery searches this same directory. Cargo still
owns the bridge build and final native asset. Other platforms retain their
original CMake output directory.
Cargo also tracks the Windows static archives so clearing temporary files
invalidates the cached build script and rebuilds them.

## Windows static-library names

Meson produces `libdav1d.a` on every platform. `native/build.rs` discovers that
archive on Windows too, then copies it to `dav1d.lib` for Cargo's existing MSVC
static-library lookup. The codec source and CMake imported target remain unchanged.

## Standalone dependency resolution

`pubspec.yaml` omits `resolution: workspace` because this package is a path
dependency of the application rather than a member of the upstream workspace.
