#!/bin/bash
# Recreate generated application resources from source.
set -euo pipefail
cd "$(dirname "$0")/.."
(
  cd integrations/editor
  npm ci --ignore-scripts
  npm run build
)
flutter pub get
dart run tool/generate_app_version.dart
