#!/bin/sh
set -eu

source_dir=$1
resources_dir=$2
configuration=$3

# AppKit reads Credits.rtf from the app bundle when opening About Discourse.
# Stamp it during every native build, before Xcode signs the bundle. The
# version/build number remain the Flutter-provided values in Info.plist.
revision=$(git -C "$source_dir" rev-parse --short=12 HEAD 2>/dev/null || true)
if [ -n "$revision" ]; then
  if ! git -C "$source_dir" diff --quiet HEAD --; then
    revision="$revision (modified)"
  fi
else
  revision="Unavailable"
fi
built_at=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

# Xcode configuration names can contain characters with meaning in RTF.
configuration=$(printf '%s' "$configuration" | sed 's/[\\{}]/\\&/g')
mkdir -p "$resources_dir"
cat > "$resources_dir/Credits.rtf" <<EOF
{\rtf1\ansi\deff0{\fonttbl{\f0 Helvetica;}}
\qc\f0\fs22
$configuration build\line
Commit: $revision\line
Built: $built_at
}
EOF
