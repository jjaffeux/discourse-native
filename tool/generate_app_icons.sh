#!/usr/bin/env bash
#
# Regenerates every platform's app icon from assets/logo_mark.svg.
#
# The source is the Discourse mark — the speech bubble and its four arcs, with
# neither the dark container nor the wordmark — sitting on the app's purple.
# Rendering from vector rather than from a PNG master means the 16px Finder
# icon and the 1024px App Store icon come from the same geometry, and the thin
# arcs survive the small sizes.
#
# Requires ImageMagick and librsvg (`brew install imagemagick librsvg`).
# oxipng, if installed, is used to shrink the output; it is optional.
#
#   ./tool/generate_app_icons.sh
#
# Android, Windows and Linux are not scaffolded yet. Their icons are written to
# the paths the Flutter templates expect, so `flutter create --platforms=...`
# drops its scaffolding around them — but that command also rewrites the
# template's own placeholder icons, so re-run this script afterwards.
#
set -euo pipefail

cd "$(dirname "$0")/.."

SRC="assets/logo_mark.svg"

# The background runs corner to corner, top left to bottom right:
# hsl(263deg, 44%, 35%) to hsl(263deg, 44%, 25%).
BG_FROM="#503281"
BG_TO="#39245C"

# How much of a full-bleed square the mark covers. Everything else is derived
# from this so the mark looks the same size whichever platform you are on.
MARK_RATIO="0.62"

[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
command -v rsvg-convert >/dev/null || { echo "need rsvg-convert (brew install librsvg)" >&2; exit 1; }
command -v magick >/dev/null || { echo "need magick (brew install imagemagick)" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- masters ----------------------------------------------------------------
#
# Each master is rendered once at 1024 and every real icon is a Lanczos
# downscale of it. Going through one large raster rather than re-rendering the
# vector per size is what keeps the arcs smooth at 16px: at that scale a direct
# vector render puts a sub-pixel-wide arc on a pixel grid and it breaks up.

render_mark() { # <px> <out>
  rsvg-convert -w "$1" -h "$1" "$SRC" -o "$2"
}

# Paints the diagonal background. Two-point `barycentric` puts BG_FROM exactly
# on the first coordinate and BG_TO exactly on the second and interpolates
# linearly along that line, which is the definition of the gradient we want —
# and, unlike `gradient:` plus a rotate, it does not crop the square.
#
# The coordinates are given rather than assumed to be the corners because the
# Android layer needs its endpoints inside the canvas; barycentric extrapolates
# past them without clipping.
gradient() { # <size> <x0,y0> <x1,y1> <out>
  magick -size "${1}x${1}" xc: \
    -sparse-color barycentric "$2 $BG_FROM $3 $BG_TO" -depth 8 "$4"
}

MARK=1024
render_mark "$MARK" "$WORK/mark.png"

# Full-bleed square, opaque: iOS, Android's legacy launcher icon, Windows,
# Linux. The platforms that round the corners do it themselves.
gradient 1024 "0,0" "1023,1023" "$WORK/square_bg.png"
magick "$WORK/square_bg.png" \
  \( "$WORK/mark.png" -resize "$(echo "1024 * $MARK_RATIO" | bc)x" \) \
  -gravity center -composite -alpha remove -alpha off -depth 8 "$WORK/square.png"

# macOS keeps transparent margins and carries its own rounded-rect plate,
# following Apple's 1024pt grid: 824pt artwork inset, 185.4pt corner radius.
# The mark is sized against the plate, not the canvas, so it matches iOS, and
# so is the gradient — it runs corner to corner of the plate, not of the canvas
# the plate floats in.
#
# The mask is drawn on opaque black rather than on transparency so the rounded
# corners keep their antialiasing: on `xc:none` the soft edge lives in the
# alpha channel, and `-alpha off` would throw exactly that away.
gradient 824 "0,0" "823,823" "$WORK/plate_bg.png"
magick -size 1024x1024 xc:black \
  -fill white -draw "roundrectangle 100,100 924,924 185,185" \
  -alpha off "$WORK/plate_mask.png"
magick -size 1024x1024 xc:none "$WORK/plate_bg.png" -gravity center -composite \
  "$WORK/plate_mask.png" -alpha off -compose CopyOpacity -composite \
  \( "$WORK/mark.png" -resize "$(echo "824 * $MARK_RATIO" | bc)x" \) \
  -gravity center -compose Over -composite -depth 8 "$WORK/plate.png"

# Android adaptive icons hand the system a 108dp layer and show only the middle
# 72dp of it, so the mark has to be sized against that 72dp viewport to end up
# looking like it does everywhere else. 0.62 of 72 out of 108 is 0.41.
ADAPTIVE_RATIO="$(echo "scale=4; $MARK_RATIO * 72 / 108" | bc)"
magick -size 1024x1024 xc:none \
  \( "$WORK/mark.png" -resize "$(echo "1024 * $ADAPTIVE_RATIO" | bc)x" \) \
  -gravity center -composite -depth 8 "$WORK/adaptive_fg.png"

# The background layer is cropped to that same 72dp viewport, so the gradient
# is anchored to the viewport's corners — 170.67 and 853.33 on a 1024 layer —
# and left to run off the edges. Anchoring it to the full 108dp layer instead
# would show only the middle two thirds of the ramp, and Android would end up
# with a visibly flatter background than every other platform.
gradient 1024 "170.67,170.67" "853.33,853.33" "$WORK/adaptive_bg.png"

# Themed (monochrome) Android icons are the same layer flattened to its
# silhouette; the launcher tints it to whatever the wallpaper palette says.
magick "$WORK/adaptive_fg.png" -alpha extract \
  \( +clone -fill white -colorize 100 \) +swap \
  -alpha off -compose CopyOpacity -composite -depth 8 "$WORK/adaptive_mono.png"

# --- helpers ----------------------------------------------------------------

# Downscales a master. Lanczos over the default so the arcs stay crisp.
#
# `-depth 8` is not cosmetic. Homebrew's ImageMagick is a Q16 build, so a canvas
# it invents itself (`-size … xc:`) is 16 bits per channel and it writes 16-bit
# PNGs all the way down. Nothing here needs that precision, it doubles every
# file, and Xcode's actool quietly drops some of the representations rather than
# compiling them into AppIcon.icns.
emit() { # <master> <px> <dest>
  mkdir -p "$(dirname "$3")"
  magick "$1" -filter Lanczos -resize "${2}x${2}" -depth 8 -strip "$3"
}

emit_opaque() { # <master> <px> <dest>
  emit "$1" "$2" "$3"
  magick "$3" -background "$BG_FROM" -alpha remove -alpha off -depth 8 "$3"
}

# --- iOS (iPhone + iPad) ----------------------------------------------------
#
# Full-bleed and opaque: an alpha channel here is an App Store rejection, and
# the system draws the rounded mask itself.

IOS_SET="ios/Runner/Assets.xcassets/AppIcon.appiconset"

while read -r size name; do
  emit_opaque "$WORK/square.png" "$size" "$IOS_SET/$name"
done <<'EOF'
20    Icon-App-20x20@1x.png
40    Icon-App-20x20@2x.png
60    Icon-App-20x20@3x.png
29    Icon-App-29x29@1x.png
58    Icon-App-29x29@2x.png
87    Icon-App-29x29@3x.png
40    Icon-App-40x40@1x.png
80    Icon-App-40x40@2x.png
120   Icon-App-40x40@3x.png
120   Icon-App-60x60@2x.png
180   Icon-App-60x60@3x.png
76    Icon-App-76x76@1x.png
152   Icon-App-76x76@2x.png
167   Icon-App-83.5x83.5@2x.png
1024  Icon-App-1024x1024@1x.png
EOF

# --- macOS ------------------------------------------------------------------

MACOS_SET="macos/Runner/Assets.xcassets/AppIcon.appiconset"

for size in 16 32 64 128 256 512 1024; do
  emit "$WORK/plate.png" "$size" "$MACOS_SET/app_icon_${size}.png"
done

# --- Android ----------------------------------------------------------------
#
# Skipped unless the platform is really scaffolded. Testing for the Gradle
# project rather than the directory, because writing icons into a bare
# android/ leaves something that looks like a platform and builds nothing —
# which is exactly the state this repo was in before the test was added.
if [ -f android/settings.gradle ] || [ -f android/settings.gradle.kts ]; then

ANDROID_RES="android/app/src/main/res"

while read -r density size; do
  emit_opaque "$WORK/square.png" "$size" "$ANDROID_RES/mipmap-$density/ic_launcher.png"
done <<'EOF'
mdpi     48
hdpi     72
xhdpi    96
xxhdpi   144
xxxhdpi  192
EOF

# The adaptive layers are 108dp squares, so they are 2.25x the launcher icon
# at every density. The background is a bitmap rather than a colour resource
# because a colour cannot hold a gradient.
while read -r density size; do
  emit "$WORK/adaptive_bg.png"   "$size" "$ANDROID_RES/mipmap-$density/ic_launcher_background.png"
  emit "$WORK/adaptive_fg.png"   "$size" "$ANDROID_RES/mipmap-$density/ic_launcher_foreground.png"
  emit "$WORK/adaptive_mono.png" "$size" "$ANDROID_RES/mipmap-$density/ic_launcher_monochrome.png"
done <<'EOF'
mdpi     108
hdpi     162
xhdpi    216
xxhdpi   324
xxxhdpi  432
EOF

mkdir -p "$ANDROID_RES/mipmap-anydpi-v26"

cat > "$ANDROID_RES/mipmap-anydpi-v26/ic_launcher.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/generate_app_icons.sh -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
EOF

# Left over from when the background was a flat colour.
rm -f "$ANDROID_RES/values/ic_launcher_background.xml"
rmdir "$ANDROID_RES/values" 2>/dev/null || true

fi

# Play Store listing icon: 512x512, no transparency. Outside the gate above —
# it is a store listing asset that lives in assets/, not Android platform code.
emit_opaque "$WORK/square.png" 512 "assets/store/play_store_512.png"

# --- Windows ----------------------------------------------------------------
#
# One .ico carrying every size Explorer, the taskbar and Alt-Tab ask for. The
# frames are packed by hand because ImageMagick stores them as raw BMP, which
# makes the 256px frame alone ~260KB — and this file is linked into the .exe as
# a resource. Windows has read PNG-compressed frames since Vista and Flutter
# needs Windows 10, so every frame goes in as PNG.

# Gated on the CMake project for the same reason as Android above.
if [ -f windows/CMakeLists.txt ]; then

WINDOWS_RES="windows/runner/resources"
mkdir -p "$WINDOWS_RES"

ico_frames=()
for size in 16 24 32 48 64 128 256; do
  emit_opaque "$WORK/square.png" "$size" "$WORK/win_$size.png"
  ico_frames+=("$WORK/win_$size.png")
done
command -v oxipng >/dev/null && oxipng -q -o 4 --strip safe "${ico_frames[@]}"

python3 - "$WINDOWS_RES/app_icon.ico" "${ico_frames[@]}" <<'PY'
import struct, sys

dest, srcs = sys.argv[1], sys.argv[2:]
frames = []
for path in srcs:
    data = open(path, 'rb').read()
    # PNG signature, then the IHDR width/height at a fixed offset.
    width, height = struct.unpack('>II', data[16:24])
    frames.append((width, height, data))

offset = 6 + 16 * len(frames)
directory, payload = b'', b''
for width, height, data in frames:
    directory += struct.pack('<BBBBHHII',
                             width % 256, height % 256, 0, 0, 1, 32,
                             len(data), offset)
    payload += data
    offset += len(data)

with open(dest, 'wb') as out:
    out.write(struct.pack('<HHH', 0, 1, len(frames)) + directory + payload)
PY

fi

# --- Linux ------------------------------------------------------------------
#
# Laid out the way freedesktop wants it installed, so packaging just copies the
# tree into /usr/share/icons/. The scalable entry is the real vector, which is
# what GNOME and KDE prefer when they have it.

LINUX_ICONS="linux/icons/hicolor"

for size in 16 24 32 48 64 128 256 512; do
  emit_opaque "$WORK/square.png" "$size" \
    "$LINUX_ICONS/${size}x${size}/apps/org.discourse.native.png"
done

mkdir -p "$LINUX_ICONS/scalable/apps"
{
  echo '<!-- Generated by tool/generate_app_icons.sh from assets/logo_mark.svg -->'
  echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">'
  echo '  <defs>'
  echo '    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">'
  printf '      <stop offset="0" stop-color="%s"/>\n' "$BG_FROM"
  printf '      <stop offset="1" stop-color="%s"/>\n' "$BG_TO"
  echo '    </linearGradient>'
  echo '  </defs>'
  echo '  <rect width="512" height="512" fill="url(#bg)"/>'
  # 0.62 of 512 is 317.44, centred, and the mark's own viewBox rescales into it.
  echo '  <svg x="97.28" y="97.28" width="317.44" height="317.44" viewBox="17 16.35 70.4 70.4">'
  grep '<path' "$SRC" | sed 's/^  /    /'
  echo '  </svg>'
  echo '</svg>'
} > "$LINUX_ICONS/scalable/apps/org.discourse.native.svg"

# --- shrink -----------------------------------------------------------------

if command -v oxipng >/dev/null; then
  shrink=(
    "$IOS_SET"/*.png
    "$MACOS_SET"/*.png
    assets/store/play_store_512.png
    "$LINUX_ICONS"/*/apps/*.png
  )
  # Only if the Android block ran; under `set -u` an unset ANDROID_RES is fatal,
  # and the glob would not have expanded to anything either way.
  if [ -n "${ANDROID_RES:-}" ]; then
    shrink+=("$ANDROID_RES"/mipmap-*/*.png)
  fi
  oxipng -q -o 4 --strip safe "${shrink[@]}"
else
  echo "note: oxipng not installed, PNGs left unoptimized" >&2
fi

did=(iOS macOS Linux)
if [ -n "${ANDROID_RES:-}" ]; then did+=(Android); fi
if [ -n "${WINDOWS_RES:-}" ]; then did+=(Windows); fi
echo "Regenerated icons for ${did[*]}"
