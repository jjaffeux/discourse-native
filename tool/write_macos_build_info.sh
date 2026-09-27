#!/bin/sh
# Generate the build information displayed by the standard macOS About panel.
set -eu

source_directory=${1:?Source directory required}
resources_directory=${2:?Resources directory required}
configuration=${3:?Build configuration required}

revision=$(git -C "$source_directory" rev-parse --short=12 HEAD 2>/dev/null) || revision=Unavailable
if [ "$revision" != Unavailable ]; then
  if [ -n "$(git -C "$source_directory" status --porcelain --untracked-files=no)" ]; then
    revision="$revision (modified)"
  fi
fi

escape_rtf() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/{/\\{/g; s/}/\\}/g'
}

mkdir -p "$resources_directory"
{
  printf '{\\rtf1\\ansi\n'
  printf '%s build\\line\n' "$(escape_rtf "$configuration")"
  printf 'Commit: %s\\line\n' "$(escape_rtf "$revision")"
  printf 'Built: %s UTC\n' "$(date -u '+%Y-%m-%d %H:%M:%S')"
  printf '}\n'
} > "$resources_directory/Credits.rtf"
