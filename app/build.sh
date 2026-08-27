#!/bin/bash
# Script to build Flutter web app on Render or other CI environments

# Exit on error
set -e

# Download Flutter
git clone https://github.com/flutter/flutter.git -b stable

# Add flutter to path
export PATH="$PATH:`pwd`/flutter/bin"

# Enable web
flutter config --enable-web

# Get dependencies
flutter pub get

# Build web app
# You should set API_BASE to your backend's URL in the Render environment variables
# e.g., API_BASE=https://my-backend.onrender.com
if [ -z "$API_BASE" ]; then
  flutter build web --release
else
  flutter build web --release --dart-define=API_BASE="$API_BASE"
fi

# The static files will be in build/web/
