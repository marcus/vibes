#!/usr/bin/env bash
set -euo pipefail

SOURCE_ICON="${1:?usage: generate-client-app-icon.sh SOURCE_ICON APPICONSET_DIR}"
APPICONSET_DIR="${2:?usage: generate-client-app-icon.sh SOURCE_ICON APPICONSET_DIR}"

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "Missing source app icon: $SOURCE_ICON" >&2
  exit 1
fi

mkdir -p "$APPICONSET_DIR"

generate_icon() {
  local pixels="$1"
  local filename="$2"

  sips -s format png -z "$pixels" "$pixels" "$SOURCE_ICON" --out "$APPICONSET_DIR/$filename" >/dev/null
}

generate_icon 16 "app-icon-generated-16x16@1x.png"
generate_icon 32 "app-icon-generated-16x16@2x.png"
generate_icon 32 "app-icon-generated-32x32@1x.png"
generate_icon 64 "app-icon-generated-32x32@2x.png"
generate_icon 128 "app-icon-generated-128x128@1x.png"
generate_icon 256 "app-icon-generated-128x128@2x.png"
generate_icon 256 "app-icon-generated-256x256@1x.png"
generate_icon 512 "app-icon-generated-256x256@2x.png"
generate_icon 512 "app-icon-generated-512x512@1x.png"
generate_icon 1024 "app-icon-generated-512x512@2x.png"

cat > "$APPICONSET_DIR/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "app-icon-generated-16x16@1x.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "app-icon-generated-16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "app-icon-generated-32x32@1x.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "app-icon-generated-32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "app-icon-generated-128x128@1x.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "app-icon-generated-128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "app-icon-generated-256x256@1x.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "app-icon-generated-256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "app-icon-generated-512x512@1x.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "app-icon-generated-512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
