#!/usr/bin/env sh
#
# Registers this extracted bundle with the desktop: a launcher entry pointing at
# wherever you put it, plus the icon theme tree.
#
# Everything goes under $XDG_DATA_HOME (~/.local/share by default), so this needs
# no root and touches nothing outside your account. Safe to re-run -- an update
# that replaces the bundle in place keeps working, and one that moves it just
# needs this run again.

set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_ID="org.discourse.native"
BINARY="discourse_native"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

if [ ! -x "$HERE/$BINARY" ]; then
  echo "error: $HERE/$BINARY is missing or not executable." >&2
  echo "Run this from inside the extracted bundle." >&2
  exit 1
fi

mkdir -p "$DATA/applications" "$DATA/icons"

# Exec= is parsed as a command line rather than as an ordinary path. Quote the
# executable so a bundle extracted below a directory containing whitespace or
# shell punctuation still launches. The desktop-entry format applies its own
# string escaping before command-line unquoting: literal backslashes need four
# backslashes, dollars and backticks need two, and percent starts a field code.
DESKTOP_EXEC="$({
  printf '%s' "$HERE/$BINARY" |
    sed \
      -e 's/\\/\\\\\\\\/g' \
      -e 's/"/\\\\"/g' \
      -e 's/`/\\\\`/g' \
      -e 's/\$/\\\\$/g' \
      -e 's/%/%%/g'
})"

# Write the one generated field without interpolating the path into a sed
# program. Besides handling `&` and `|` literally, a temporary file keeps a
# failed reinstall from truncating the launcher's last good copy.
DESKTOP_FILE="$DATA/applications/$APP_ID.desktop"
DESKTOP_TMP="$(mktemp "$DATA/applications/.$APP_ID.XXXXXX")"
trap 'rm -f "$DESKTOP_TMP"' EXIT HUP INT TERM
while IFS= read -r LINE || [ -n "$LINE" ]; do
  if [ "$LINE" = 'Exec=@EXEC@' ]; then
    printf 'Exec="%s"\n' "$DESKTOP_EXEC"
  else
    printf '%s\n' "$LINE"
  fi
done < "$HERE/data/desktop/$APP_ID.desktop" > "$DESKTOP_TMP"
chmod 644 "$DESKTOP_TMP"
mv "$DESKTOP_TMP" "$DESKTOP_FILE"
DESKTOP_TMP=''
trap - EXIT HUP INT TERM

cp -r "$HERE/data/desktop/icons/hicolor" "$DATA/icons/"

# Both are best-effort: the entry is already valid without them, they just make
# it show up without a re-login.
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DATA/applications" || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$DATA/icons/hicolor" || true
fi

echo "Installed $APP_ID."
echo "  launcher: $DATA/applications/$APP_ID.desktop"
echo "  binary:   $HERE/$BINARY"
