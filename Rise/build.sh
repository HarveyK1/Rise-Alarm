#!/bin/bash
# Builds an unsigned Rise.ipa inside WSL Ubuntu and puts it in the repo folder.
# Run it with the repo folder as the working directory (see README); no paths are hardcoded.
set -euo pipefail
. /root/.local/share/swiftly/env.sh

REPO="$PWD"
[ -f "$REPO/Rise/Package.swift" ] || { echo "Run this from the repo folder (the one containing Rise/)."; exit 1; }

# Build on Ubuntu's own disk: much faster than compiling straight off the Windows drive.
rsync -a --delete --exclude .build --exclude xtool "$REPO/Rise/" /root/Rise/
cd /root/Rise
xtool dev build --ipa --configuration "${1:-release}"
cp "$(find xtool -name '*.ipa' -newer Package.swift | head -1)" "$REPO/Rise.ipa"
echo "IPA: $REPO/Rise.ipa"
