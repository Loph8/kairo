#!/bin/sh
# One-time import of the iOS app from the Loph8/golden-hour clone into ios/.
set -e
SRC="$HOME/golden-hour-loph8"
DEST="$HOME/golden-hour/ios"
mkdir -p "$DEST"
cd "$SRC"
cp -R App Shared Widget Sources Tests Config docs Package.swift project.yml .gitignore "$DEST/"
echo "Copied into $DEST:"
ls "$DEST"
