#!/bin/bash
set -e

# Install Flutter outside the repo so Netlify does not scan the downloaded SDK cache
FLUTTER_DIR="${FLUTTER_DIR:-/tmp/flutter}"
if [ ! -d "$FLUTTER_DIR" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

flutter config --enable-web
flutter pub get
flutter build web --release
