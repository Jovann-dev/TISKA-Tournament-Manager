#!/bin/bash
set -euo pipefail

# Install Flutter outside the repo so Netlify does not scan the downloaded SDK cache
FLUTTER_DIR="${FLUTTER_DIR:-/tmp/flutter}"
FLUTTER_VERSION="3.47.4"
if [ ! -d "$FLUTTER_DIR" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" "$FLUTTER_DIR"
fi
if [ "$(git -C "$FLUTTER_DIR" describe --tags --exact-match)" != "$FLUTTER_VERSION" ]; then
  echo "Flutter SDK cache does not match $FLUTTER_VERSION; clear FLUTTER_DIR and rebuild." >&2
  exit 1
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

flutter config --enable-web
flutter pub get
flutter analyze --no-fatal-infos lib test
flutter test
flutter build web --release
