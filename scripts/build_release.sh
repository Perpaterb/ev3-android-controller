#!/usr/bin/env bash
# Builds a signed Play Store App Bundle (.aab) for BrickLogic and copies it
# into ./releases/ with the version number in the file name.
#
# Usage:  ./scripts/build_release.sh
# Requires android/key.properties to exist (see BUILD.md).
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f android/key.properties ]]; then
  echo "ERROR: android/key.properties not found." >&2
  echo "Create it from android/key.properties.example — see BUILD.md." >&2
  exit 1
fi

# Read "version: 1.0.0+1" from pubspec.yaml → name=1.0.0, code=1.
version_line="$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}')"
version_name="${version_line%%+*}"
version_code="${version_line##*+}"
echo "Building BrickLogic ${version_name} (build ${version_code})…"

flutter build appbundle --release \
  --build-name="${version_name}" \
  --build-number="${version_code}"

mkdir -p releases
out="releases/bricklogic-${version_name}-${version_code}.aab"
cp build/app/outputs/bundle/release/app-release.aab "$out"

echo
echo "Done → ${out}"
echo "Upload this .aab to the Google Play Console."
