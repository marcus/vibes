#!/usr/bin/env bash
set -euo pipefail

SOURCE_ICON="${1:?usage: set-app-icon.sh SOURCE_ICON}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CANONICAL_ICON="$ROOT_DIR/assets/icon.png"
APPICONSET_DIR="$ROOT_DIR/client/Vibes/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "Missing source icon: $SOURCE_ICON" >&2
  exit 1
fi

sips -s format png "$SOURCE_ICON" --out "$CANONICAL_ICON" >/dev/null
"$ROOT_DIR/scripts/generate-client-app-icon.sh" "$CANONICAL_ICON" "$APPICONSET_DIR"

echo "Updated app icon from $SOURCE_ICON"
