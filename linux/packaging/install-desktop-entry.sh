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

# The only substitution: Exec= has to name this copy, not the one it was built
# from. Anchored to the whole line so a path containing @EXEC@ cannot confuse it.
sed "s|^Exec=@EXEC@$|Exec=$HERE/$BINARY|" \
  "$HERE/data/desktop/$APP_ID.desktop" > "$DATA/applications/$APP_ID.desktop"
chmod 644 "$DATA/applications/$APP_ID.desktop"

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
