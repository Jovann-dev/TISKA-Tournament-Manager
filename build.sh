#!/bin/bash
set -e

# Install Flutter SDK in the build environment
if [ ! -d "$PWD/flutter" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$PWD/flutter"
fi

export PATH="$PATH:$PWD/flutter/bin"

flutter config --enable-web
flutter pub get
flutter build web --release
